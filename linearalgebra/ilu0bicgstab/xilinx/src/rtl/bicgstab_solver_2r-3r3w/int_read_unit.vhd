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

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library xpm;
    use xpm.vcomponents.all;

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.rw_pkg.all;
    use work.wm_pkg.all;

-- The int_read_unit handles all interaction between the sparstition unit and the 
-- URAM vector memory, in which vector X is stored.
-- Since it handles the reads of the vector partition values, it contains memories 
-- into which the vector partition values of the next color can be read while 
-- computations on the current color occur. It also contains logic to allow the 
-- fast-forwarding for the ILU0 result of the current color into that memory.
-- It is instantiated by the sparstition unit. 

entity int_read_unit is
    port ( 
        clk            : in std_logic;
        reset          : in std_logic;
        do_read_vect   : in std_logic;
        do_read_L      : in std_logic;
        do_read_U      : in std_logic;
        do_transfer    : in std_logic;
        is_L_fs        : in std_logic;
        is_U_bs        : in std_logic;
        spmvp_reset    : in std_logic;
        arow_size      : in mat_size;
        col_size       : in mat_size;
        read_line      : in cacheline;
        read_fields    : in field_array(1 downto 0);
        field_re       : in std_logic_vector(1 downto 0);
        P_indices_wr_addr : in unsigned(COL_INDEX_WIDTH downto 0);
        P_indices_we   : in std_logic_vector(0 downto 0);
        P_read_done    : in std_logic;
        read_interrupt : in std_logic;
        wb_elem        : in element;
        read_P         : out read_P_type;
        vect_vals_done : out std_logic;
        LU_done        : out std_logic;
        transfer_done  : out std_logic;
        X_P_line       : out cacheline;
        P_valid        : out std_logic;
        X_valid        : out std_logic
        ; found_ilu0_fifo_overflow : out std_logic
    );
end int_read_unit;

architecture behavioral of int_read_unit is

    COMPONENT blk_mem_temp_X_P_vect
        PORT (
            clka : IN STD_LOGIC;
            wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
            addra : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
            dina : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
            douta : OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
            clkb : IN STD_LOGIC;
            web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
            addrb : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
            dinb : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
            doutb : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
        );
    END COMPONENT;

    signal r, q : int_read_int;
    signal p_inds_in  : std_logic_vector( (DMA_DATA_WIDTH/32 * VECTOR_ADDR_WIDTH) - 1 downto 0); -- -- 32=elements are integers
    signal p_inds_out : std_logic_vector( (2 * VECTOR_ADDR_WIDTH) - 1 downto 0);  -- 2=number of write ports of the vector mem
    signal unused_read_signal : field;
    
    signal ilu0_fifo_in, ilu0_fifo_out : std_logic_vector(FIELD_WIDTH + ROW_INDEX_WIDTH - 1 downto 0);
    signal ilu0_fifo_full, ilu0_fifo_empty : std_logic;
    signal ilu0_fifo_almost_empty : std_logic;
   
begin

pii: for g in 0 to 15 generate
        p_inds_in(VECTOR_ADDR_WIDTH * (g + 1) - 1 downto VECTOR_ADDR_WIDTH * g) <= read_line(32 * g + VECTOR_ADDR_WIDTH - 1 downto 32 * g);
    end generate; 

-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: blk_mem_p_indices
p_inds_mem : xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => COL_INDEX_WIDTH - integer(ceil(log2(real(DMA_DATA_WIDTH/32)))),  -- 32=elements are integers
        ADDR_WIDTH_B => COL_INDEX_WIDTH - integer(ceil(log2(real(2)))),  -- 2=number of write ports of the vector mem
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => DMA_DATA_WIDTH/32 * VECTOR_ADDR_WIDTH,  -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "block",     -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => P_INDS_MEM_SIZE_BITS,  -- size in bits
        MESSAGE_CONTROL => 1,
        READ_DATA_WIDTH_B => 2 * VECTOR_ADDR_WIDTH, -- 2=number of write ports of the vector mem
        READ_LATENCY_B => 2,
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => DMA_DATA_WIDTH/32 * VECTOR_ADDR_WIDTH,
        WRITE_MODE_B => "no_change"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        ena => bit_1,
        addra => std_logic_vector(P_indices_wr_addr(COL_INDEX_WIDTH - 1 downto integer(ceil(log2(real(DMA_DATA_WIDTH/32)))))),
        dina => p_inds_in,
        wea => P_indices_we,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.P_inds_addr(COL_INDEX_WIDTH - 1 downto integer(ceil(log2(real(2)))))),
        doutb => p_inds_out,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );

temp_x_p : blk_mem_temp_X_P_vect
        PORT MAP (
            clka  => clk,
            wea   => r.X_P_we(0 downto 0),
            addra => std_logic_vector(r.temp_X_P_addr1(col_index_range)),
            dina  => r.X_P_in_fields(0),
            douta => X_P_line,
            clkb  => clk,
            web   => r.X_P_we(1 downto 1),
            addrb => std_logic_vector(r.temp_X_P_addr2(col_index_range)),
            dinb  => r.X_P_in_fields(1),
            doutb => unused_read_signal
        );

ilu0_fifo_in <= wb_elem.field & std_logic_vector(wb_elem.addr(row_index_range));

-- xpm_fifo_sync: Synchronous FIFO
-- Xilinx Parameterized Macro, version 2019.1
-- Replaces the IP: fifo_dist_ilu0_res
nnz_fifo : xpm_fifo_sync
    generic map (
        DOUT_RESET_VALUE => "0",
        ECC_MODE => "no_ecc",
        FIFO_MEMORY_TYPE => "distributed",  -- "auto", "block", "distributed", "ultra"
        FIFO_READ_LATENCY => 0,       -- must be 0 if READ_MODE = "fwft"
        FIFO_WRITE_DEPTH => 16,       -- must be a power of two
        FULL_RESET_VALUE => 0,
        PROG_EMPTY_THRESH => 5,
        PROG_FULL_THRESH => 6,
        RD_DATA_COUNT_WIDTH => 1,
        READ_DATA_WIDTH => FIELD_WIDTH + ROW_INDEX_WIDTH, -- Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1,4:1 and 2:1
        READ_MODE => "fwft",          -- "std": standard read mode; "fwft": First-Word-Fall-Through read mode
        SIM_ASSERT_CHK => 1,
        USE_ADV_FEATURES => "0800",   -- enable almost_empty flag
        WAKEUP_TIME => 0,
        WR_DATA_COUNT_WIDTH => 1,
        WRITE_DATA_WIDTH => FIELD_WIDTH + ROW_INDEX_WIDTH
    )
    port map (
        sleep => bit_0,
        rst => reset,
        wr_rst_busy => open,
        rd_rst_busy => open,
        wr_clk => clk,
        wr_en => wb_elem.valid,
        wr_ack => open,
        din => ilu0_fifo_in,
        rd_en => r.ilu0_fifo_pull,
        dout => ilu0_fifo_out,
        data_valid => open,
        empty => ilu0_fifo_empty,
        almost_empty => ilu0_fifo_almost_empty,
        prog_empty => open,
        full => ilu0_fifo_full,
        almost_full => open,
        prog_full => open,
        overflow => open,
        underflow => open,
        rd_data_count => open,
        wr_data_count => open,
        injectdbiterr => bit_0,
        injectsbiterr => bit_0,
        sbiterr => open,
        dbiterr => open
    );

logic_proc: process(r, read_fields, field_re, spmvp_reset, do_read_vect, do_read_L, do_read_U, do_transfer, is_L_fs, is_U_bs, col_size, arow_size, ilu0_fifo_out, ilu0_fifo_full, ilu0_fifo_empty, ilu0_fifo_almost_empty, P_read_done, P_inds_out, read_interrupt, P_indices_wr_addr, wb_elem)
        variable v : int_read_int;
        variable diag_size : unsigned(READ_RQ_SIZE_WIDTH- 1 downto 0);
    begin
        v := r;
        
        -- detect overflow for debugging
        if ilu0_fifo_full = '1' AND wb_elem.valid = '1' then
            v.ilu0_fifo_overflow := '1';
        end if;
        
        -- default assignments
        v.done              := '0';
        v.transfer_done     := '0';
        v.LU_done           := '0';
        v.read_P_enable     := "00";
        v.next_P_enables(0) := "00";
        v.next_X_valid      := '0';
        v.P_valid           := '0';
        v.ilu0_fifo_pull    := '0';
        
        -- register
        v.X_valid := r.next_X_valid;
        v.prev_col_size := col_size(COL_INDEX_WIDTH downto 0);
        
        if P_read_done = '1' then
            v.ext_read_done := '1';
        end if;
        
        if spmvp_reset = '1' then
            v.ext_read_done := '0';
        end if;
        
        case r.state is  
            when idle =>
				--Even in the idle state, the unit must be ready to store ILU0 results:
                v.X_P_in_fields(1) := read_fields(1);
                v.temp_X_P_addr2 := r.write_addr + 1;
                v.X_P_we(0) := r.ilu0_fifo_pull;
                v.X_P_we(1) := '0';
                v.X_P_in_fields(0) := ilu0_fifo_out(FIELD_WIDTH + ROW_INDEX_WIDTH - 1 downto ROW_INDEX_WIDTH);
                if is_U_bs = '1' then
                    v.temp_X_P_addr1 := r.ilu0_start_addr - unsigned('0' & ilu0_fifo_out(ROW_INDEX_WIDTH - 1 downto 0));
                else
                    v.temp_X_P_addr1 := r.ilu0_start_addr + unsigned('0' & ilu0_fifo_out(ROW_INDEX_WIDTH - 1 downto 0));
                end if;
                v.ilu0_fifo_pull := NOT(ilu0_fifo_almost_empty) OR (NOT(ilu0_fifo_empty) AND NOT(r.ilu0_fifo_pull));

				-- start an operation based on the input start signal:
                if do_transfer = '1' OR r.do_transfer = '1' then
					-- Start a transfer of the X vector partition from the local X_P memory to the SpMV unit
                    if ilu0_fifo_empty = '1' then
                        v.do_transfer := '0';
                        v.temp_X_P_addr1 := (others => '0');
                        v.state := transfer_vect;
                    else
                        v.do_transfer := '1';
                    end if;
                elsif do_read_vect = '1' then 
					-- Start a read of an X vector partition from the URAM into the local X_P memory
                    v.P_inds_addr := (others => '0');
                    v.write_addr := (others => '0');
                    if is_U_bs = '1' then
                        v.ilu0_start_addr := col_size(COL_INDEX_WIDTH downto 0);
                    else
                        v.ilu0_start_addr := col_size(COL_INDEX_WIDTH downto 0) - arow_size(COL_INDEX_WIDTH downto 0);
                    end if;
                    v.next_transfer_size := col_size(COL_INDEX_WIDTH downto 0);
                    v.state       := read_vect_inds;
                elsif do_read_L = '1' then
					-- Starts a transfer of an X vector section from the URAM into the ILU0 unit
					-- (addresses go up from 0 for L_fs)
                    v.temp_X_P_addr1 := (others => '0');
                    v.done_rows := r.done_rows + arow_size(vector_addr_range);
                    v.read_P_addrs(0) := r.done_rows;
                    v.read_P_addrs(1) := r.done_rows + 1;
                    v.state := read_P_vector;
                elsif do_read_U = '1' then
					-- Starts a transfer of an X vector section from the URAM into the ILU0 unit
					-- (addresses go down from row_size for U_bs)
                    v.temp_X_P_addr1 := (others => '0');
                    v.done_rows := r.done_rows - arow_size(vector_addr_range);
                    v.read_P_addrs(0) := r.done_rows - 1;
                    v.read_P_addrs(1) := r.done_rows - 2;
                    v.state := read_U_P_vector;
                end if;
            when read_P_vector =>
				-- Transfer an X vector section from the URAM into the ILU0 unit
				-- (addresses go up from 0 for L_fs)
                if r.read_P_addrs(0) + 2 < r.done_rows then
                    v.read_P_enable := "11";
                end if;
                if r.read_P_enable = "11" then
                    v.read_P_addrs(0) := r.read_P_addrs(0) + 2;
                    v.read_P_addrs(1) := r.read_P_addrs(1) + 2;
                end if;
                -- handle P vector read responses
                if field_re = "11" then
                    v.P_valid := '1';
                    v.temp_X_P_addr1 := r.temp_X_P_addr1 + 2;
                end if;
                if r.temp_X_P_addr1 >= arow_size then
                    v.LU_done := '1';
                    v.state := idle;
                end if;
            when read_U_P_vector =>
				-- Transfer an X vector section from the URAM into the ILU0 unit
				-- (addresses go down from row_size for U_bs)
                if r.read_P_addrs(0) >= r.done_rows + 2 AND NOT(r.read_P_addrs(0)(VECTOR_ADDR_WIDTH - 1 downto VECTOR_ADDR_WIDTH - 2) = "11" AND r.done_rows(VECTOR_ADDR_WIDTH - 1 downto VECTOR_ADDR_WIDTH - 2) = "00") then
                    v.read_P_enable := "11";
                end if;
                if r.read_P_enable = "11" then
                    v.read_P_addrs(0) := r.read_P_addrs(0) - 2;
                    v.read_P_addrs(1) := r.read_P_addrs(1) - 2;
                end if;
                if field_re = "11" then
                    v.P_valid := '1';
                    v.temp_X_P_addr1 := r.temp_X_P_addr1 + 2;
                end if;
                if r.temp_X_P_addr1 >= arow_size then
                    v.LU_done := '1';
                    v.state := idle;
                end if;
            when read_vect_inds =>
                -- use read indices to give actual P vector element read "commands"
                if r.P_inds_addr < P_indices_wr_addr AND NOT(read_interrupt = '1') AND r.P_inds_addr(0) = '0' then
					-- Read from both URAM ports unless the ILU0 results are being read into the X_P memory as well,
                    v.P_inds_addr := r.P_inds_addr + 2;
                    v.next_P_enables(0) := "11";
                elsif r.P_inds_addr < P_indices_wr_addr then
					-- In which case, only read from one URAM port.
                    v.P_inds_addr := r.P_inds_addr + 1;
                    v.next_P_enables(0) := "01";
                end if;
                
                v.next_P_enables(READ_FIFO_LATENCY + 4 downto 1) := r.next_P_enables(READ_FIFO_LATENCY + 3 downto 0);
                v.read_P_enable   := r.next_P_enables(1);
                v.single_uneven_P_inds_addr(0) := r.next_P_enables(0)(0) AND NOT(r.next_P_enables(0)(1)) AND r.P_inds_addr(0);
                v.single_uneven_P_inds_addr(1) := r.single_uneven_P_inds_addr(0);
                
                if r.single_uneven_P_inds_addr(1) = '1' then
                    v.read_P_addrs(0) := unsigned(P_inds_out(2 * VECTOR_ADDR_WIDTH - 1 downto VECTOR_ADDR_WIDTH));
                else
                    v.read_P_addrs(0) := unsigned(P_inds_out(VECTOR_ADDR_WIDTH - 1 downto 0));
                end if;
                v.read_P_addrs(1) := unsigned(P_inds_out(2 * VECTOR_ADDR_WIDTH - 1 downto VECTOR_ADDR_WIDTH));
                
                -- handle P vector read responses
                v.X_vect_we := field_re;
                
                v.X_P_in_fields(0) := read_fields(0);
                v.temp_X_P_addr1 := r.write_addr;
                
                if field_re(0) = '1' then
					-- Only write to the X_P memory if it is known not to be overwriting previously written ILU0 results
                    v.X_P_we(0) := bool2sl(r.write_addr < r.ilu0_start_addr) OR NOT(is_L_fs);
                    v.write_addr := r.write_addr + 1;
                else
                    v.X_P_we(0) := '0';
                end if;
                -- Pull from the ILU0 result fifo when it is not empty and space has been left for its outputs to be written into the X_P memory
                v.ilu0_fifo_pull := (NOT(ilu0_fifo_almost_empty) OR NOT(ilu0_fifo_empty OR r.ilu0_fifo_pull)) AND NOT(r.next_P_enables(INT_VECTOR_MEM_LATENCY + 2)(1));

				-- Write either the data read from the URAM of from the ilu0_res fifo into the second prt of the X_P memory
                if field_re(1) = '1' then
                    v.X_P_in_fields(1) := read_fields(1);
                    v.temp_X_P_addr2 := v.write_addr;
                    v.X_P_we(1) := bool2sl(v.write_addr < r.ilu0_start_addr) OR NOT(is_L_fs);
                    v.write_addr := v.write_addr + 1;
                else
                    v.X_P_in_fields(1) := ilu0_fifo_out(FIELD_WIDTH + ROW_INDEX_WIDTH - 1 downto ROW_INDEX_WIDTH);
                    
                    v.temp_X_P_addr2 := r.ilu0_start_addr + unsigned('0' & ilu0_fifo_out(ROW_INDEX_WIDTH - 1 downto 0));
                  
                    if r.ilu0_fifo_pull = '1' then
                        v.X_P_we(1) := '1';
                    else
                        v.X_P_we(1) := '0';
                    end if;
                end if;

                if r.write_addr >= P_indices_wr_addr AND r.ext_read_done = '1' AND ilu0_fifo_empty = '1' then
                    v.done := '1';
                    v.ext_read_done := '0';
                    v.state := idle;
                end if;
            when transfer_vect =>
				-- Transfer the X vector partition from the local X_P memory to the SpMV unit
                if r.temp_X_P_addr1 < r.next_transfer_size then
                    v.temp_X_P_addr1 := r.temp_X_P_addr1 + NUM_FIELDS_PER_LINE;
                    v.next_X_valid := '1';
                else
                    v.transfer_done := '1';
                    v.state := idle;
                end if;
            when others => 

        end case;
        
        --output signals
        read_P.valids  <= r.read_P_enable;
        read_P.addrs   <= r.read_P_addrs;
        vect_vals_done <= r.done;
        LU_done <= r.LU_done;
        transfer_done <= r.transfer_done;
        X_valid      <= r.X_valid;
        P_valid      <= r.P_valid;
        found_ilu0_fifo_overflow <= r.ilu0_fifo_overflow;
        
        q <= v;
    end process;   

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= INT_READ_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;

end behavioral;
