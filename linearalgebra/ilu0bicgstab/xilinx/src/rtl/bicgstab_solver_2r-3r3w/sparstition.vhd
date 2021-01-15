--  Copyright 2020 Equinor ASA
--
--  This file is part of the Open Porous Media project (OPM).
--
--  OPM is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  OPM is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with OPM.  If not, see <http://www.gnu.org/licenses/>.

library xpm;
    use xpm.vcomponents.all;

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_misc.all;

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.rw_pkg.all;
    use work.sparstition_pkg.all;

-- This unit performs all matrix operations. It consists of the spmv, ILU0, 
-- ext_read, int_read and write unit, and is instantiated by the solver unit. 
-- It runs the SpMV pipeline once for every color, while controlling the reads
-- and writes so that the correct data is where it needs to be when the SpMV 
-- is started. 

entity sparstition is
    generic (
        SIM_DEBUG: natural := 0;
        WRITE_ILU0_RESULTS: boolean := false
    );
    port (
        clk         : in std_logic;
        reset       : in std_logic;
        start       : in std_logic;
        apply_ILU0  : in std_logic;
        sizes       : in sparstition_sizes;
        addresses   : in sparstition_addresses;

        reads       : in reads_in_array(NUM_DDR_READ_PORTS - 1 downto 0);

        read_fields : in field_array(NUM_DDR_READ_PORTS - 1 downto 0);
        field_re    : in std_logic_vector(NUM_DDR_READ_PORTS - 1 downto 0);
        write_ready : in std_logic;
        L_done      : out std_logic;
        done        : out std_logic;
        read0_rq    : out read_request_type;
        read1_rq    : out read_request_type;
        read_ack    : out std_logic_vector(NUM_DDR_READ_PORTS - 1 downto 0);
        read_ready  : out std_logic_vector(NUM_DDR_READ_PORTS - 1 downto 0);

        read_P      : out read_P_type;
        write_rq    : out write_request_type;
        write_line  : out write_line_type;
        write_field : out write_field_type
        ; debug_line : out write_line_type
        ; debug_encoded_state : out std_logic_vector(7 downto 0)
    );
end sparstition;

architecture behavioral of sparstition is       

    signal r, q : sparstition_int;
    signal re : sparstition_ext;
    
    signal read_valids, read_dones : std_logic_vector(1 downto 0);
    signal spmvp_NRs : std_logic_vector(MULT_NUM - 1 downto 0);
    signal is_L_fs : std_logic;
    signal row_mem_in, arow_mem_in, col_mem_in, val_mem_in : std_logic_vector(127 downto 0);
    
    signal nnz_vals_fifo_out : std_logic_vector(FIELD_WIDTH * MULT_NUM - 1 downto 0);
    signal col_inds_fifo_in  : std_logic_vector(NUM_COL_INDS_PER_LINE * COL_INDEX_WIDTH - 1 downto 0);
    signal col_inds_fifo_out : std_logic_vector(COL_INDEX_WIDTH * MULT_NUM - 1 downto 0);
	signal NRs_fifo_in       : cacheline;
    signal NRs_fifo_out      : std_logic_vector(OFFSET_WIDTH * MULT_NUM - 1 downto 0);

    signal nnz_read_ready : std_logic;
    signal ci_read_ready  : std_logic;
    signal nr_read_ready  : std_logic;
    
    signal P_read_done  : std_logic;
    
begin

    read_valids <= reads(1).valid & reads(0).valid;
    read_dones  <= reads(1).done & reads(0).done;
    read_ready <= (nr_read_ready AND ci_read_ready) & nnz_read_ready;
    is_L_fs <= bool2sl(r.LU_state = L_fs);

eru: entity work.ext_read_unit
    port map(
        clk            => clk,
        reset          => reset,
        read_sizes     => r.ext_read_control(0),
        read_vect      => r.ext_read_control(1),
        read_spm       => r.ext_read_control(2),
        is_L_fs        => is_L_fs,
        is_U_bs        => r.is_U_bs,
        sizes          => sizes,
        addresses      => addresses,
        read_valids    => read_valids,
        read_dones     => read_dones,
        color_sizes    => r.current_color_sizes,
        read0_rq       => read0_rq,
        read1_rq       => read1_rq,
        read_ack       => read_ack,
        sizes_done     => re.read_dones(0),
        vect_vals_done => re.read_dones(1),
        mat_vals_done  => re.read_dones(2),
        diag_done      => re.read_dones(3),
        write_enables  => re.read_wes,
        write_addrs    => re.read_wr_addrs
    );

    P_read_done <= re.read_dones(1) AND bool2sl(r.current_ext_read = EXT_READ_VECT_INDS);

iru: entity work.int_read_unit
    port map(
        clk            => clk,
        reset          => reset,
        do_read_vect   => r.int_read_control(0),
        do_read_L      => r.int_read_control(1),
        do_read_U      => r.int_read_control(2),
        do_transfer    => r.int_read_control(3),
        is_L_fs        => is_L_fs,
        is_U_bs        => r.is_U_bs,
        spmvp_reset    => r.spmvp_reset,
        arow_size      => r.current_color_sizes.arow,
        col_size       => r.current_color_sizes.col,
        read_line      => r.read1_line,
        read_fields    => read_fields,
        field_re       => field_re,
        P_indices_wr_addr => re.read_wr_addrs.P_indices,
        P_indices_we   => re.read_wes.P_indices,
        P_read_done    => P_read_done,
        read_interrupt => re.read_interrupt,
        wb_elem        => re.ilu0_out_elem,
        read_P         => read_P,
        vect_vals_done => re.int_read_dones(0),
        LU_done        => re.int_read_dones(1),
        transfer_done  => re.int_read_dones(2),
        X_P_line       => re.X_P_line,
        P_valid        => re.P_we,
        X_valid        => re.X_we
        , found_ilu0_fifo_overflow => re.found_ilu0_fifo_overflow
    );
    
split_line: for g in 0 to 3 generate
        row_mem_in(g * 32 + 31 downto g * 32) <= r.read0_line((4 * g) * 32 + 31 downto (4 * g) * 32);
        arow_mem_in(g * 32 + 31 downto g * 32) <= r.read0_line((4 * g + 1) * 32 + 31 downto (4 * g + 1) * 32);
        col_mem_in(g * 32 + 31 downto g * 32) <= r.read0_line((4 * g + 2) * 32 + 31 downto (4 * g + 2) * 32);
        val_mem_in(g * 32 + 31 downto g * 32) <= r.read0_line((4 * g + 3) * 32 + 31 downto (4 * g + 3) * 32);
    end generate;

-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: blk_mem_color_sizes
row_size_mem : xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => 6,
        ADDR_WIDTH_B => 8,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => 128,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "block",     -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => 2**8*32,           -- size in bits
        MESSAGE_CONTROL => 1,
        READ_DATA_WIDTH_B => 32,
        READ_LATENCY_B => 2,
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => 128,
        WRITE_MODE_B => "no_change"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        ena => bit_1,
        addra => std_logic_vector(re.read_wr_addrs.color_sizes(MAX_COLORS_DEPTH - 1 downto CPS_PER_LINE_DEPTH)),
        dina => row_mem_in,
        wea => re.read_wes.color_sizes,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.current_color), -- NOTE: hardcoded size: max no. of row per color < 2048
        doutb => re.color_sizes_row,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );
        
-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: blk_mem_color_sizes
arow_size_mem : xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => 6,
        ADDR_WIDTH_B => 8,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => 128,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "block",     -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => 2**8*32,           -- size in bits
        MESSAGE_CONTROL => 1,
        READ_DATA_WIDTH_B => 32,
        READ_LATENCY_B => 2,
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => 128,
        WRITE_MODE_B => "no_change"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        ena => bit_1,
        addra => std_logic_vector(re.read_wr_addrs.color_sizes(MAX_COLORS_DEPTH - 1 downto CPS_PER_LINE_DEPTH)),
        dina => arow_mem_in,
        wea => re.read_wes.color_sizes,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.current_color), -- NOTE: hardcoded size: max no. of row per color < 2048
        doutb => re.color_sizes_arow,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );
        
-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: blk_mem_color_sizes
col_size_mem : xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => 6,
        ADDR_WIDTH_B => 8,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => 128,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "block",     -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => 2**8*32,           -- size in bits
        MESSAGE_CONTROL => 1,
        READ_DATA_WIDTH_B => 32,
        READ_LATENCY_B => 2,
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => 128,
        WRITE_MODE_B => "no_change"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        ena => bit_1,
        addra => std_logic_vector(re.read_wr_addrs.color_sizes(MAX_COLORS_DEPTH - 1 downto CPS_PER_LINE_DEPTH)),
        dina => col_mem_in,
        wea => re.read_wes.color_sizes,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.next_color), -- NOTE: hardcoded size: max no. of row per color < 2048
        doutb => re.color_sizes_col,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );
        
-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: blk_mem_color_sizes
val_size_mem : xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => 6,
        ADDR_WIDTH_B => 8,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => 128,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "block",     -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => 2**8*32,           -- size in bits
        MESSAGE_CONTROL => 1,
        READ_DATA_WIDTH_B => 32,
        READ_LATENCY_B => 2,
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => 128,
        WRITE_MODE_B => "no_change"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        ena => bit_1,
        addra => std_logic_vector(re.read_wr_addrs.color_sizes(MAX_COLORS_DEPTH - 1 downto CPS_PER_LINE_DEPTH)),
        dina => val_mem_in,
        wea => re.read_wes.color_sizes,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.current_color), -- NOTE: hardcoded size: max no. of row per color < 2048
        doutb => re.color_sizes_val,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );
        
    re.color_sizes.row  <= unsigned(re.color_sizes_row);
    re.color_sizes.arow <= unsigned(re.color_sizes_arow);
    re.color_sizes.col  <= unsigned(re.color_sizes_col);
    re.color_sizes.val  <= unsigned(re.color_sizes_val);
    
-- xpm_fifo_sync: Synchronous FIFO
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: fifo_nnz_vals
nnz_fifo : xpm_fifo_sync
    generic map (
        DOUT_RESET_VALUE => "0",
        ECC_MODE => "no_ecc",
        FIFO_MEMORY_TYPE => "block",  -- "auto", "block", "distributed", "ultra"
        FIFO_READ_LATENCY => 0,       -- must be 0 if READ_MODE = "fwft"
        -- FIFO_WRITE_DEPTH must be a power of two
        --FIFO_WRITE_DEPTH => 2*READ_BATCH_SIZE/NUM_FIELDS_PER_LINE, --commit:9b2b07fc: used in ddr0
        --FIFO_WRITE_DEPTH => 256, --commit:bdf44d0f: used in ddr1
        FIFO_WRITE_DEPTH => BATCHES_IN_MEMORY*READ_BATCH_SIZE/NUM_FIELDS_PER_LINE, --commit:new: used in ddr2 and later, correct parameterization
        FULL_RESET_VALUE => 0,
        PROG_EMPTY_THRESH => 10,
        --PROG_FULL_THRESH => 2*READ_BATCH_SIZE/NUM_FIELDS_PER_LINE - 5, --commit:9b2b07fc: used in ddr0
        --PROG_FULL_THRESH => 250, --commit:bdf44d0f: used in ddr1
        PROG_FULL_THRESH => BATCHES_IN_MEMORY*READ_BATCH_SIZE/NUM_FIELDS_PER_LINE - 5, --commit:new: used in ddr2 and later, correct parameterization
        RD_DATA_COUNT_WIDTH => 1,
        READ_DATA_WIDTH => DMA_DATA_WIDTH, -- Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1,4:1 and 2:1
        READ_MODE => "fwft",          -- "std": standard read mode; "fwft": First-Word-Fall-Through read mode
        USE_ADV_FEATURES => "080A",   -- enable prog_full, almost_full and almost_empty flags
        WAKEUP_TIME => 0,
        WRITE_DATA_WIDTH => DMA_DATA_WIDTH,
        WR_DATA_COUNT_WIDTH => 1
    )
    port map (
        sleep => bit_0,
        rst => r.spmvp_reset,
        wr_rst_busy => open,
        rd_rst_busy => open,
        wr_clk => clk,
        wr_en => re.read_wes.nnz_vals(0),
        wr_ack => open,
        din => r.read0_line,
        rd_en => r.pull_fifos,
        dout => nnz_vals_fifo_out,
        data_valid => open,
        empty => re.nnz_vals_fifo.empty,
        almost_empty => re.nnz_vals_fifo.almost_empty,
        prog_empty => open,
        full => re.nnz_vals_fifo.full,
        almost_full => open,
        prog_full => re.nnz_vals_fifo.prog_full,
        overflow => open,
        underflow => open,
        rd_data_count => open,
        wr_data_count => open,
        injectdbiterr => bit_0,
        injectsbiterr => bit_0,
        sbiterr => open,
        dbiterr => open
    );
    
    nnz_read_ready <= NOT(re.nnz_vals_fifo.prog_full);
    
-- xpm_fifo_sync: Synchronous FIFO
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: fifo_col_inds
ci_fifo : xpm_fifo_sync
    generic map (
        DOUT_RESET_VALUE => "0",
        ECC_MODE => "no_ecc",
        FIFO_MEMORY_TYPE => "block",  -- "auto", "block", "distributed", "ultra"
        FIFO_READ_LATENCY => 0,       -- must be 0 if READ_MODE = "fwft"
        -- FIFO_WRITE_DEPTH must be a power of two
        --FIFO_WRITE_DEPTH => 2*READ_BATCH_SIZE/NUM_ROW_INDS_PER_LINE, --commit:9b2b07fc: used in ddr0
        --FIFO_WRITE_DEPTH => 64, --commit:bdf44d0f: used in ddr1
        FIFO_WRITE_DEPTH => BATCHES_IN_MEMORY*READ_BATCH_SIZE/NUM_ROW_INDS_PER_LINE, --commit:new: used in ddr2 and later, correct parameterization
        FULL_RESET_VALUE => 0,
        PROG_EMPTY_THRESH => 10,
        --PROG_FULL_THRESH => 2*READ_BATCH_SIZE/NUM_ROW_INDS_PER_LINE - 5, --commit:9b2b07fc: used in ddr0
        --PROG_FULL_THRESH => 59, --commit:bdf44d0f: used in ddr1
        PROG_FULL_THRESH => BATCHES_IN_MEMORY*READ_BATCH_SIZE/NUM_ROW_INDS_PER_LINE - 5, --commit:new: used in ddr2 and later, correct parameterization
        RD_DATA_COUNT_WIDTH => 1,
        READ_DATA_WIDTH => COL_INDEX_WIDTH * MULT_NUM, -- Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1,4:1 and 2:1
        READ_MODE => "fwft",          -- "std": standard read mode; "fwft": First-Word-Fall-Through read mode
        USE_ADV_FEATURES => "080A",   -- enable prog_full, almost_full and almost_empty flags
        WAKEUP_TIME => 0,
        WRITE_DATA_WIDTH => COL_INDEX_WIDTH * NUM_ROW_INDS_PER_LINE,
        WR_DATA_COUNT_WIDTH => 1
    )
    port map (
        sleep => bit_0,
        rst => r.spmvp_reset,
        wr_rst_busy => open,
        rd_rst_busy => open,
        wr_clk => clk,
        wr_en => re.read_wes.col_inds(0),
        wr_ack => open,
        din => col_inds_fifo_in,
        rd_en => r.pull_fifos,
        dout => col_inds_fifo_out,
        data_valid => open,
        empty => re.col_inds_fifo.empty,
        almost_empty => re.col_inds_fifo.almost_empty,
        prog_empty => open,
        full => re.col_inds_fifo.full,
        almost_full => open,
        prog_full => re.col_inds_fifo.prog_full,
        overflow => open,
        underflow => open,
        rd_data_count => open,
        wr_data_count => open,
        injectdbiterr => bit_0,
        injectsbiterr => bit_0,
        sbiterr => open,
        dbiterr => open
    );
    
    ci_read_ready <= NOT(re.col_inds_fifo.prog_full);
    
-- xpm_fifo_sync: Synchronous FIFO
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: fifo_NR_offsets
nr_fifo : xpm_fifo_sync
    generic map (
        DOUT_RESET_VALUE => "0",
        ECC_MODE => "no_ecc",
        FIFO_MEMORY_TYPE => "block",  -- "auto", "block", "distributed", "ultra"
        FIFO_READ_LATENCY => 0,       -- must be 0 if READ_MODE = "fwft"
        -- FIFO_WRITE_DEPTH must be a power of two
        --FIFO_WRITE_DEPTH => 2*READ_BATCH_SIZE/NUM_OFFSETS_PER_LINE, --commit:9b2b07fc: used in ddr0
        --FIFO_WRITE_DEPTH => 32, --commit:bdf44d0f: used in ddr1
        FIFO_WRITE_DEPTH => BATCHES_IN_MEMORY*READ_BATCH_SIZE/NUM_OFFSETS_PER_LINE, --commit:new: used in ddr2 and later, correct parameterization
        FULL_RESET_VALUE => 0,
        PROG_EMPTY_THRESH => 10,
        --PROG_FULL_THRESH => 2*READ_BATCH_SIZE/NUM_OFFSETS_PER_LINE - 5, --commit:9b2b07fc: used in ddr0
        --PROG_FULL_THRESH => 27, --commit:bdf44d0f: used in ddr1
        PROG_FULL_THRESH => BATCHES_IN_MEMORY*READ_BATCH_SIZE/NUM_OFFSETS_PER_LINE - 5, --commit:new: used in ddr2 and later, correct parameterization
        RD_DATA_COUNT_WIDTH => 1,
        READ_DATA_WIDTH => OFFSET_WIDTH * MULT_NUM, -- Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1,4:1 and 2:1
        READ_MODE => "fwft",          -- "std": standard read mode; "fwft": First-Word-Fall-Through read mode
        USE_ADV_FEATURES => "080A",   -- enable prog_full, almost_full and almost_empty flags
        WAKEUP_TIME => 0,
        WRITE_DATA_WIDTH => DMA_DATA_WIDTH,
        WR_DATA_COUNT_WIDTH => 1
    )
    port map (
        sleep => bit_0,
        rst => r.spmvp_reset,
        wr_rst_busy => open,
        rd_rst_busy => open,
        wr_clk => clk,
        wr_en => re.read_wes.NRs(0),
        wr_ack => open,
        din => NRs_fifo_in,
        rd_en => r.pull_fifos,
        dout => NRs_fifo_out,
        data_valid => open,
        empty => re.NRs_fifo.empty,
        almost_empty => re.NRs_fifo.almost_empty,
        prog_empty => open,
        full => re.NRs_fifo.full,
        almost_full => open,
        prog_full => re.NRs_fifo.prog_full,
        overflow => open,
        underflow => open,
        rd_data_count => open,
        wr_data_count => open,
        injectdbiterr => bit_0,
        injectsbiterr => bit_0,
        sbiterr => open,
        dbiterr => open
    );
    
    nr_read_ready <= NOT(re.NRs_fifo.prog_full);
    
split_fifo_lines: for g in 0 to MULT_NUM - 1 generate
        re.nnz_vals_fifo_data(g) <= index(nnz_vals_fifo_out, g, FIELD_WIDTH);
        re.col_inds_fifo_data(g) <= unsigned(index(col_inds_fifo_out, g, COL_INDEX_WIDTH));
        re.NRs_fifo_data(g) <= unsigned(index(NRs_fifo_out, g, OFFSET_WIDTH));
    end generate;

spmv_unit: entity work.SpMVP
        port map ( 
            clk             => clk,
            reset           => r.spmvp_reset,
            last_val        => r.spmvp_last_val,
            X_P_line        => re.X_P_line,
            multiplicant_we => re.X_we,
            in_vals         => re.nnz_vals_fifo_data,
            in_col_indices  => re.col_inds_fifo_data,
            in_NRs          => re.NRs_fifo_data,
            in_valid        => r.spmvp_valid(SPMV_FIFO_LATENCY - 1),
            res_elems       => re.spmvp_res,
            done_up_to_addr => re.spmvp_done_up_to_addr,
            done            => re.spmvp_done
            , found_merge_overflow => re.found_merge_overflow
            , merge_overflow => re.merge_overflow
            , found_reduce_overflow => re.found_reduce_overflow
            , lost_value    => re.spmvp_lost_value
        );

wu: entity work.write_unit
        generic map (
            SIM_DEBUG => SIM_DEBUG,
            WRITE_ILU0_RESULTS => WRITE_ILU0_RESULTS
        )
        port map(
            clk             => clk,
            reset           => reset,
            start           => r.write_activate,
            write_batches   => r.is_spmvp,
            is_U            => r.is_U_bs,
            rows_num        => sizes.row_size,
            actual_row_size => r.current_color_sizes.arow,
            do_reset        => r.write_reset,
            flush           => r.write_flush,
            new_color       => r.spmvp_reset,
            spmvp_res       => re.spmvp_res,
            done_up_to_addr => re.spmvp_done_up_to_addr,
            spmvp_done      => re.spmvp_done,
            ilu0_res        => re.ilu0_out_elem,
            ilu0_done       => re.ilu0_done,
            ilu0_input      => re.ilu0_in_elem,
            ilu0_last_val   => re.ilu0_last_val,
            write_ready     => write_ready,
            write_line      => write_line,
            write_field     => write_field,
            ready           => re.write_ready,
            done            => re.write_done
            , found_overflow => re.found_write_overflow
            ,  overflow => re.write_overflow
        );

ilu0_unit: entity work.ilu0
        port map(
            clk             => clk,
            reset           => r.spmvp_reset,
            do_diag_mult    => r.is_U_bs,
            read_line       => r.read0_line,
            read_fields     => r.read_fields,
            read_p          => re.P_we,
            read_diag       => re.read_wes.block_diag,
            spmvp_res       => re.ilu0_in_elem,
            spmvp_done      => re.ilu0_last_val, 
            write_elem      => re.ilu0_out_elem,
            read_interrupt  => re.read_interrupt,
            done            => re.ilu0_done
        );

logic_proc: process(r, re, field_re, read_fields, start, apply_ilu0, sizes, addresses, reads)
        variable v : sparstition_int;
        variable fifo_index, input_index : integer;
    begin 
        v := r;
        
        --gather debug signals
        v.debug_overflow_bits(0) := re.found_reduce_overflow;
        if re.found_reduce_overflow = '1' then
            v.found_overflow := '1';
        end if;
        v.debug_overflow_bits(4) := re.found_ilu0_fifo_overflow;
        if re.found_ilu0_fifo_overflow = '1' then
            v.found_overflow := '1';
        end if;
        v.debug_overflow_bits(23 downto 8) := re.merge_overflow;
        if re.found_merge_overflow = '1' then
            v.found_overflow := '1';
        end if;
        v.debug_overflow_bits(31 downto 24) := re.write_overflow;
        if re.found_write_overflow = '1' then
            v.found_overflow := '1';
        end if;
        v.debug_overflow_bits(31 + SPMVP_OUTPUT_NUM downto 32) := re.spmvp_lost_value;
        if re.spmvp_lost_value(0) = '1' OR re.spmvp_lost_value(1) = '1' then
            v.found_overflow := '1';
        end if;
        -- default assignments:
        v.write_rq.valid := '0';
        v.int_read_control := (others => '0');
        v.ext_read_control := (others => '0');
        
        v.spmvp_valid(0) := '0';
        v.spmvp_reset    := '0';
        v.pull_fifos     := '0';
        
        v.write_reset    := '0';
        v.write_activate := '0';
        v.write_flush    := '0';
        v.L_done         := '0';
        
        -- register values

        v.read0_line     := reads(0).data;
        v.read1_line     := reads(1).data;
        
        v.read_fields    := read_fields;
        if or_reduce(r.ext_read_control) = '1' then
            v.current_ext_read := r.ext_read_control;
        end if;
        
        v.spmvp_valid(SPMV_FIFO_LATENCY - 1 downto 1) := r.spmvp_valid(SPMV_FIFO_LATENCY - 2 downto 0);
        
        case r.state is
            when idle =>
                v.current_color  := (others => '0');
                v.next_color     := (others => '0');
                v.spmvp_last_val := '0';
                v.done           := '0';
                v.is_U_bs         := '0';
				-- the sparsition unit can be started to do SpMV or apply_ILU0:
                if start = '1' then
                    v.ext_read_control := EXT_READ_SIZES;
                    v.state           := wait_for_sizes_read;
                    if apply_ILU0 = '1' then
                        v.LU_state    := L_fs;
                        v.write_reset := '1';
                    else
                        v.LU_state    := spmvp;
                    end if;
                end if;
            when wait_for_sizes_read =>
				-- Here, all sizes of all colors of a certain matrix are read into the sizes memories
                v.num_colors          := sizes.num_colors;
                v.current_color_sizes := re.color_sizes;
                v.read_done := re.read_dones(0);
                if r.read_done = '1' then
                    v.spmvp_reset     := '1';
					-- The next_color is used to read the column_size, which is used to do the transfer of 
					-- the X vector values of a color. In the spmv and L_fs cases, this is done in parallel with 
					-- the spmv operations of the previous color, so their next_color must be one higher then current_color
					-- However, due to the way the U results are written into the U_bs, this pre-reading of the 
					-- X vector partition is not possible, and the next_color nees to be current_color
                    if r.is_U_bs = '0' then
                        v.next_color      := r.current_color + 1;
                    else
                        v.next_color      := r.current_color;
                    end if;

                    v.read_done       := '0';
                    if r.LU_state = spmvp then
                        v.is_spmvp := '1';
                    else
                        v.is_spmvp := '0';
                    end if;
                    v.int_read_control := INT_READ_VECT_VALS; 
                    v.state := wait_for_first_vector_read;
                    v.ext_read_control := EXT_READ_VECT_INDS; 
                end if;
            when wait_for_first_vector_read => 
				-- In this state, the spmv and L_fs read the X vector partition of the first color
				-- The U_bs needs to do this every color (see above)
				-- the reading of the diagonal values is also done in parallel here in the X_bs case.
                v.spmvp_last_val := '0';
                v.current_color_sizes := re.color_sizes;
                if re.read_dones(3) = '1' then
                    v.diag_read_done := '1';
                end if;
                
                if re.int_read_dones(0) = '1' then
                    if r.is_u_bs = '0' then 
                        v.ext_read_control := EXT_READ_VECT_INDS;
                    end if;
                    v.int_read_control := INT_READ_TRANSFER;
                    v.state := wait_for_transfer;
                end if;
            when wait_for_transfer =>
				-- In this state, the X vector partition read in the state before this one is transfered
				-- into the multiplicant memories of the SpMV unit.
				-- Another external read is done in parallel: a read of the next vector partition indices
				-- when the mode is spmv or L_fs, or a read of the diagonal array if it is U_bs
                v.fifos_read_addr := (others => '0');
                
                v.spmvp_last_val  := '0';
                v.write_done      := '0';
                if re.int_read_dones(2) = '1' then
                    v.int_read_done := '1';
                end if;
                if re.read_dones(1) = '1' then
                    v.read_done := '1';
                end if;
                
                if re.read_dones(3) = '1' then
                    v.diag_read_done := '1';
                end if;
                
                if r.int_read_done = '1' AND (r.read_done = '1' OR r.is_U_bs = '1' OR r.current_color = r.num_colors - 1) then
                    v.read_done       := '0';
                    v.int_read_done   := '0';
                    
                    if r.is_spmvp = '1' then
                        v.write_activate  := '1';
                        v.current_color := r.current_color + 1;
                        v.next_color := r.next_color + 1;
                        v.ext_read_control := EXT_READ_MATRIX;
                        if r.current_color /= r.num_colors - 1 then    
                            v.int_read_control := INT_READ_VECT_VALS;
                        end if;
                        v.state := running;
                    elsif r.is_u_bs = '0' then
						-- Which portion of the X matrix needs to be transfered to the ILU0 unit,
						-- depens on whether it is doing L_fs or U_bs
                        v.ext_read_control := EXT_READ_MATRIX;
                        v.int_read_control := INT_READ_P_VECT_L;
                        v.state := wait_for_P_vector_read;
                    else
                        v.int_read_control := INT_READ_P_VECT_U;
                        v.state := wait_for_P_vector_read;
                    end if;
                end if;
            when wait_for_P_vector_read =>
				-- The ILU0 needs a portion of the X vector to perform its operations
				-- That portion is transfered to the ILU0 unit here
                v.current_color_sizes := re.color_sizes;
                -- catch the done_matrix_read signal, for if the matrix read is very quick
                if re.read_dones(2) = '1' then
                    v.read_done := '1'; 
                end if;
                -- wait for the diag_read_done signal
                if re.read_dones(3) = '1' then
                    v.diag_read_done := '1';
                end if;
                if re.int_read_dones(1) = '1' then 
                    v.int_read_done := '1';
                end if;
                -- Go to next state if P transfer is done, as well as the diags read, if one was started
                if r.int_read_done = '1' AND (r.diag_read_done = '1' OR r.is_u_bs = '0') AND re.write_ready = '1' then
                    v.current_color := r.current_color + 1;
                    v.next_color := r.next_color + 1;
                    v.int_read_done   := '0';
                    v.diag_read_done  := '0';
                    v.write_activate  := '1';
                    -- start a matrix if one wasn't started already 
                    if r.is_u_bs = '1' then
                        v.ext_read_control := EXT_READ_MATRIX;
                        v.read_done := '0';    
                    end if;
                    if r.current_color /= r.num_colors - 1 AND r.is_U_bs = '0' then    
                        v.int_read_control := INT_READ_VECT_VALS;
                    end if;
                    v.state := running;
                end if;
            when running =>
				-- This state runs the SpMV unit (and the ILU0 unit is the mode is not spmv)
				-- Send data into SpMV pipeline if data is available on all fifos:
                if (re.nnz_vals_fifo.almost_empty = '0' OR (r.pull_fifos = '0' AND re.nnz_vals_fifo.empty = '0')) AND 
                        (re.col_inds_fifo.almost_empty = '0' OR (r.pull_fifos = '0' AND re.col_inds_fifo.empty = '0')) AND 
                        (re.NRs_fifo.almost_empty = '0' OR (r.pull_fifos = '0' AND re.NRs_fifo.empty = '0')) then
                    v.pull_fifos := '1';
                    v.fifos_read_addr := r.fifos_read_addr + NUM_FIELDS_PER_LINE;
                    v.spmvp_valid(0) := '1';
                end if;

				-- Set done signals and signals that siganl the ends of inputs
                if re.read_dones(2) = '1' then
                    v.read_done := '1'; 
                end if;
                if re.write_done = '1' then
                    v.write_done := '1';
                end if;
                v.spmvp_last_val :=  r.read_done AND re.nnz_vals_fifo.empty;
                
                if r.current_color = r.num_colors then
                    v.write_flush := re.spmvp_done;
                end if;
                
                if re.int_read_dones(0) = '1' then
                    v.int_read_done := '1';
                end if;
                
                -- criteria for exiting the running state depend on the type of operation that is being done
                if (r.is_spmvp = '1' AND re.spmvp_done = '1' AND (r.int_read_done = '1' OR r.current_color = r.num_colors)) OR (r.is_spmvp = '0' AND r.write_done = '1' AND (r.int_read_done = '1' OR r.current_color = r.num_colors OR r.is_U_bs = '1')) then
                    v.int_read_done := '0';
                    v.read_done       := '0';
                    if r.current_color = r.num_colors then
                        if r.is_spmvp = '1' AND r.write_done = '1' then
                            v.state := finished;
                        end if;
                        if r.is_spmvp = '0' then
                            v.write_done := '0';
                            if r.is_U_bs = '1' then
                                v.state := finished;
                            else
                                --v.read_done       := '0';
                                v.spmvp_reset         := '1';
                                v.current_color := (others => '0');
                                v.state := init_U;
                            end if;
                        end if;
                    else
                        v.write_done := '0';
                        --v.read_done       := '0';

                        v.current_color_sizes := re.color_sizes;
                        v.spmvp_reset         := '1';
                        if r.is_U_bs = '1' then
                            v.ext_read_control     := EXT_READ_VECT_INDS;
                            v.int_read_control := INT_READ_VECT_VALS;
                            v.state := wait_for_first_vector_read;
                        else
                            if r.current_color /= r.num_colors - 1 then 
                                v.ext_read_control     := EXT_READ_VECT_INDS;
                            end if;
                            v.int_read_control     := INT_READ_TRANSFER;
                            v.state := wait_for_transfer;
                        end if;
                    end if;
                end if;
            when init_U =>
				-- This state is here to wait for the solver to start the U_bs
				-- and to do some resets
                v.L_done := '1';
                if start = '1' then
                    v.LU_state         := U_bs;
                    v.is_U_bs          := '1';
                    v.write_reset      := '1';
                    v.current_color  := (others => '0');
                    v.next_color     := (others => '0');
                    v.ext_read_control := EXT_READ_SIZES;
                    v.state := wait_for_sizes_read;
                end if;
            when finished =>
                v.done := '1';
                v.state := idle;
            when others => 

        end case;
        for g in 0 to NUM_COL_INDS_PER_LINE - 1 loop
            col_inds_fifo_in(COL_INDEX_WIDTH * (g + 1) - 1 downto COL_INDEX_WIDTH * g) <=  r.read1_line(2 ** COL_INDEX_DEPTH * g + COL_INDEX_WIDTH - 1 downto 2 ** COL_INDEX_DEPTH * g);
        end loop;
        for g in 0 to NUM_OFFSETS_PER_LINE  - 1 loop
            NRs_fifo_in(OFFSET_WIDTH * (g + 1) - 1 downto OFFSET_WIDTH * g) <=  r.read1_line(OFFSET_WIDTH * (g + 1) - 1 downto OFFSET_WIDTH * g);
        end loop;
        
        L_done      <= r.L_done;
        done        <= r.done;
        write_rq    <= r.write_rq;
        debug_line.data(511 downto 32 + SPMVP_OUTPUT_NUM) <= (others => '0');
        debug_line.data(31 + SPMVP_OUTPUT_NUM downto 0) <= r.debug_overflow_bits;
        debug_line.valid <= r.found_overflow;
        
        debug_encoded_state <= "00" & LU_state_encoding(r.LU_state) & "0" & sparstition_state_encoding(r.state);
        
        q <= v;
    end process;     

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= SPARSTITION_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;

end behavioral;
