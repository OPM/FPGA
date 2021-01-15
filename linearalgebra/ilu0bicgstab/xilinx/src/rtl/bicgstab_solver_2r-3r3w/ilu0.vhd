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

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.sparstition_pkg.all;
    use work.wm_pkg.all;

-- This unit performs the operations that need to be added to the SpMV pipeline
-- in order to have it perform forward and backward substitution needed to apply
-- the ILU0 preconditioner.
-- It receives its input data from the write unit, and sends its outputs to that 
-- unit as well.
-- This unit is instantiated by the sparstition unit.

entity ilu0 is
    port (
        clk             : in std_logic;
        reset           : in std_logic;
        do_diag_mult    : in std_logic;
        read_line       : in cacheline;
        read_fields     : in field_array(1 downto 0);
        read_p          : in std_logic;
        read_diag       : in std_logic_vector(0 downto 0);
        spmvp_res       : in element;
        spmvp_done      : in std_logic;
        read_interrupt  : out std_logic;
        done            : out std_logic;
        write_elem      : out element
    );
end ilu0;

architecture behavioral of ilu0 is
    
    component FP_adder is
        port(
            aclk                 : in std_logic;
            s_axis_a_tvalid      : in std_logic;
            s_axis_a_tdata       : in std_logic_vector(FIELD_WIDTH - 1 downto 0);
            s_axis_b_tvalid      : in std_logic;
            s_axis_b_tdata       : in std_logic_vector(FIELD_WIDTH - 1 downto 0);
            m_axis_result_tvalid : out std_logic;
            m_axis_result_tdata  : out std_logic_vector(FIELD_WIDTH - 1 downto 0)
        );
    end component;
    
    component FP_multiplier is
        port(
            aclk                 : in std_logic;
            s_axis_a_tvalid      : in std_logic;
            s_axis_a_tdata       : in std_logic_vector(FIELD_WIDTH - 1 downto 0);
            s_axis_b_tvalid      : in std_logic;
            s_axis_b_tdata       : in std_logic_vector(FIELD_WIDTH - 1 downto 0);
            m_axis_result_tvalid : out std_logic;
            m_axis_result_tdata  : out std_logic_vector(FIELD_WIDTH - 1 downto 0)
        );
    end component;
        
    component FP_subtracter is
        port(
            aclk                 : in std_logic;
            s_axis_a_tvalid      : in std_logic;
            s_axis_a_tdata       : in std_logic_vector(FIELD_WIDTH - 1 downto 0);
            s_axis_b_tvalid      : in std_logic;
            s_axis_b_tdata       : in std_logic_vector(FIELD_WIDTH - 1 downto 0);
            m_axis_result_tvalid : out std_logic;
            m_axis_result_tdata  : out std_logic_vector(FIELD_WIDTH - 1 downto 0)
        );
    end component;

    signal r, q : ilu0_int;
    signal re : ilu0_ext;
    
    signal long_reg_in, long_reg_out : std_logic_vector(191 downto 0);
    signal fifo_in_data : std_logic_vector(FIFO_DATA_WIDTH - 1 downto 0);
    signal p_in_data : std_logic_vector(FIELD_WIDTH * 2 - 1 downto 0);
    signal p_vect_we : std_logic_vector(0 downto 0);
    
    signal debug_diag_vals : field_array(3 downto 0);
begin
    
ddv: for g in 0 to 3 generate
        debug_diag_vals(g) <= re.diag_vals(64 * (g + 1) - 1 downto g * 64);
    end generate;
    
    fifo_in_data <= std_logic_vector(spmvp_res.addr) & spmvp_res.field;
    
-- xpm_fifo_sync: Synchronous FIFO
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: fifo_dist_mem_element
blocking_fifo : xpm_fifo_sync
    generic map (
        DOUT_RESET_VALUE => "0",
        ECC_MODE => "no_ecc",
        FIFO_MEMORY_TYPE => "distributed",  -- "auto", "block", "distributed", "ultra"
        FIFO_READ_LATENCY => 0,       -- must be 0 if READ_MODE = "fwft"
        FIFO_WRITE_DEPTH => 64,       -- must be a power of two
        FULL_RESET_VALUE => 0,
        PROG_EMPTY_THRESH => 10,
        PROG_FULL_THRESH => 10,
        RD_DATA_COUNT_WIDTH => 1,
        READ_DATA_WIDTH => FIFO_DATA_WIDTH, -- Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1,4:1 and 2:1
        READ_MODE => "fwft",          -- "std": standard read mode; "fwft": First-Word-Fall-Through read mode
        USE_ADV_FEATURES => "0808",   -- enable almost_full and almost_empty flags
        WAKEUP_TIME => 0,
        WRITE_DATA_WIDTH => FIFO_DATA_WIDTH,
        WR_DATA_COUNT_WIDTH => 1
    )
    port map (
        sleep => bit_0,
        rst => reset,
        wr_rst_busy => open,
        rd_rst_busy => open,
        wr_clk => clk,
        wr_en => spmvp_res.valid,
        wr_ack => open,
        din => fifo_in_data,
        rd_en => r.fifo_pull(2),
        dout => re.fifo.data,
        data_valid => open,
        empty => re.fifo.empty,
        almost_empty => re.fifo.almost_empty,
        prog_empty => open,
        full => re.fifo.full,
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

p_in_data <= read_fields(1) & read_fields(0);
p_vect_we(0) <= read_p;

-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: blk_mem_p_vector
p_buff : xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => 10,
        ADDR_WIDTH_B => 11,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => 128,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "block",     -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => 131072,           -- size in bits
        MESSAGE_CONTROL => 1,
        READ_DATA_WIDTH_B => 64,
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
        addra => std_logic_vector(r.p_write_addr(ROW_INDEX_WIDTH - 1 downto 1)),
        dina => p_in_data,
        wea => p_vect_we,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => re.fifo.data(FIFO_DATA_WIDTH - 1 downto FIELD_WIDTH), -- NOTE: hardcoded size: max no. of row per color < 2048
        doutb => re.p_value,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );

diag_addr: entity work.delay_pipe
         generic map(
             delay => ADD_DELAY + 2,
             delay_depth => ADD_DELAY_DEPTH,
             width => ROW_INDEX_WIDTH
         )
         port map(
             clk      => clk,
             reset    => reset,
             in_data  => re.fifo.data(FIFO_DATA_WIDTH - 1 downto FIELD_WIDTH),
             out_data => re.diag_read_addr
         );
  
-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: blk_mem_diagonal_block_vector
diag_buff : xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => 10,
        ADDR_WIDTH_B => 11,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => 512,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "block",     -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => 524288,           -- size in bits
        MESSAGE_CONTROL => 1,
        READ_DATA_WIDTH_B => 256,
        READ_LATENCY_B => 2,
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => 512,
        WRITE_MODE_B => "no_change"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        ena => bit_1,
        addra => std_logic_vector(r.diag_write_addr(10 downto 1)),
        dina => read_line,
        wea => read_diag,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.diag_read_addr(10 downto 0)),
        doutb => re.diag_vals,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );

sub: FP_subtracter port map(
        aclk                 => clk,
        s_axis_a_tvalid      => r.sub_valid,
        s_axis_a_tdata       => re.p_value,
        s_axis_b_tvalid      => r.sub_valid,
        s_axis_b_tdata       => r.sub_in,
        m_axis_result_tvalid => re.sub_valid,
        m_axis_result_tdata  => re.sub_res
    );

wad: entity work.delay_pipe
         generic map(
             delay => MULT_DELAY + 2*ADD_DELAY + 3,
             delay_depth => ADD_DELAY_DEPTH + 2,
             width => ROW_INDEX_WIDTH
         )
         port map(
             clk      => clk,
             reset    => reset,
             in_data  => re.diag_read_addr,
             out_data => re.write_addr
         );

mults: for g in 0 to 2 generate 
    mult: FP_multiplier port map(
            aclk                 => clk,
            s_axis_a_tvalid      => r.aggr_valids(2),
            s_axis_a_tdata       => re.diag_vals(64 * (g + 1) - 1 downto 64 * g),
            s_axis_b_tvalid      => r.aggr_valids(2),
            s_axis_b_tdata       => r.aggregates(g),
            m_axis_result_tvalid => re.mult_valid(g),
            m_axis_result_tdata  => re.mult_res(g)
        );
    end generate;
       
add0: FP_adder port map(
         aclk                 => clk,
         s_axis_a_tvalid      => re.mult_valid(0),
         s_axis_a_tdata       => re.mult_res(0),
         s_axis_b_tvalid      => re.mult_valid(1),
         s_axis_b_tdata       => re.mult_res(1),
         m_axis_result_tvalid => re.add0_valid,
         m_axis_result_tdata  => re.add0_res
     );

add1: FP_adder port map(
         aclk                 => clk,
         s_axis_a_tvalid      => re.add0_valid,
         s_axis_a_tdata       => re.add0_res,
         s_axis_b_tvalid      => re.add0_valid,
         s_axis_b_tdata       => re.delayed_mult2,
         m_axis_result_tvalid => re.add1_valid,
         m_axis_result_tdata  => re.add1_res
     );

mdp: entity work.delay_pipe
         generic map(
             delay => ADD_DELAY,
             delay_depth => ADD_DELAY_DEPTH,
             width => FIELD_WIDTH
         )
         port map(
             clk      => clk,
             reset    => reset,
             in_data  => re.mult_res(2),
             out_data => re.delayed_mult2
         );

logic_proc: process(r, re, do_diag_mult, read_p, read_fields, read_diag, spmvp_res, spmvp_done)
        variable v : ilu0_int;
    begin
        v := r;
        
        --standard assignments
        v.write_elem.valid := '0';
        v.U_active := do_diag_mult;
        
        -- registers
        v.next_sub_in := re.fifo.data(FIELD_WIDTH - 1 downto 0);
        v.sub_in    := r.next_sub_in;
        v.sub_valid := r.fifo_pull(3);
        v.diag_read_addr := unsigned(re.diag_read_addr);
        v.read_interrupt(15 downto 1) := r.read_interrupt(14 downto 0);
        v.read_interrupt(0) := r.sub_valid;
        
        if spmvp_done = '1' then
            v.spmvp_done := '1';
        end if;
        if r.spmvp_done = '1' AND re.fifo.empty = '1' AND r.done_count < 128 then
            v.done_count := r.done_count + 1;
        end if;
        
        -- control fifo
        if spmvp_res.valid = '1' then
            v.fifo_count := r.fifo_count + 1;           
        end if;
        
        if r.fifo_count >= 3 AND r.fifo_pull(1 downto 0) = "00" then
            v.fifo_pull(2 downto 0) := "111";
            v.fifo_pull(5 downto 3) := r.fifo_pull(4 downto 2);
            v.fifo_count := v.fifo_count - 3;
        else
            v.fifo_pull(0) := '0';
            v.fifo_pull(5 downto 1) := r.fifo_pull(4 downto 0);
        end if;
            
        -- update writing addresses
        if read_p = '1' then
            v.p_write_addr := r.p_write_addr + 2;
        end if;        
        if read_diag = "1" then
            -- read 4 values (1/3 block + 1 empty) for every element in the p vector 
            v.diag_write_addr := r.diag_write_addr + NUM_FIELDS_PER_LINE / 4;
        end if;
        
        -- aggregate subtract results:
        v.aggr_valids(0) := '0';
        v.aggr_valids(2 downto 1) := r.aggr_valids(1 downto 0);
        if re.sub_valid = '1' then
            if r.aggr_count = 2 then
                -- reverse signals going into aggregates, because rows are streaming in in reverse order.
                v.aggregates(0) := re.sub_res;
                v.aggregates(1) := r.next_aggrs(1);
                v.aggregates(2) := r.next_aggrs(0);
                v.aggr_count  := 0;
                if r.U_active = '1' then
                    v.aggr_valids := "111";
                else
                    v.aggr_valids := "000";
                end if;
            else
                v.next_aggrs(r.aggr_count) := re.sub_res;
                v.aggr_count  := r.aggr_count + 1;
            end if;
        end if;
        
        -- choose a result value:
        if r.U_active = '1' then
            v.write_elem.field := re.add1_res;
            v.write_elem.valid := re.add1_valid;
            v.write_elem.addr  := unsigned(re.write_addr);
            v.done             := bool2sl(r.done_count >= MULT_DELAY + 3 * ADD_DELAY + 5);
        else
            v.write_elem.field := re.sub_res;
            v.write_elem.valid := re.sub_valid;
            v.write_elem.addr  := unsigned(re.diag_read_addr);
            v.done             := bool2sl(r.done_count >= ADD_DELAY + 2);
        end if;
        
        q <= v;
    end process;

    -- output signals
    done       <= r.done;
    read_interrupt <= r.read_interrupt(ADD_DELAY - 2);
    write_elem <= r.write_elem;

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= ILU0_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;

end behavioral;
