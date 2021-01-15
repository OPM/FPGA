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

library xpm;
    use xpm.vcomponents.all;

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;

-- This unit takes to subsequent input elements of the same address, and adds them together
-- Subsequent elements with different addresses are just passed through
-- The reduction of multiple partial results of the same row in the spmv 
-- is reduced to a single result using multiple of these reduce stages
-- Multiple instance of this unit are instantiated by the SpMV unit

entity reduce_stage is
    port (
        clk       : in std_logic;
        reset     : in std_logic;
        last_val  : in std_logic;
        add_elem  : in element;
        add_val   : field;
        next_elem : out element;
        next_val  : out field
    );
end reduce_stage;

architecture behavioral of reduce_stage is

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

    type reduce_stage_int is record
        push       : std_logic;
        read_addr  : unsigned(ADD_DELAY_DEPTH - 1 downto 0);
        write_addr : unsigned(ADD_DELAY_DEPTH - 1 downto 0);
        prev_addr  : row_index;
        buff_elem  : element;
        next_elem  : element;
        next_val   : field;
    end record;
    
    constant REDUCE_STAGE_INT_INIT : reduce_stage_int :=(
        '0',                 -- push
        (others => '0'),     -- read_addr
        to_unsigned(ADD_DELAY - 2, ADD_DELAY_WIDTH), -- write_addr
        (others => '0'),    -- prev_addr
        ELEMENT_INIT,       -- buff_elem
        ELEMENT_INIT,       -- next_elem
        (others => '0')     -- next_add
    );
    
    type reduce_stage_ext is record
        add_res      : element;
        addr_out     : std_logic_vector(row_index_range);
    end record;
    
    signal q, r       : reduce_stage_int;
    signal re         : reduce_stage_ext;
    signal dist_mem_wea : std_logic_vector(0 downto 0);

begin

add: FP_adder
        port map(
            aclk                 => clk,
            s_axis_a_tvalid      => add_elem.valid,
            s_axis_a_tdata       => add_elem.field,
            s_axis_b_tvalid      => add_elem.valid,
            s_axis_b_tdata       => add_val,
            m_axis_result_tvalid => re.add_res.valid,
            m_axis_result_tdata  => re.add_res.field
        );

    dist_mem_wea(0) <= r.push;

-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2019.2
-- Replaces IP: dist_mem_addr_delay
dist_mem: xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => ADD_DELAY_DEPTH,
        ADDR_WIDTH_B => ADD_DELAY_DEPTH,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => ROW_INDEX_WIDTH, -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "distributed", -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => 2**ADD_DELAY_DEPTH * ROW_INDEX_WIDTH,  -- size in bits
        MESSAGE_CONTROL => 0,
        READ_DATA_WIDTH_B => ROW_INDEX_WIDTH,
        READ_LATENCY_B => 2,
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => ROW_INDEX_WIDTH,
        WRITE_MODE_B => "read_first"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        ena => bit_1,
        addra => std_logic_vector(r.write_addr),
        dina => std_logic_vector(add_elem.addr),
        wea => dist_mem_wea,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.read_addr),
        doutb => re.addr_out,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );

re.add_res.addr <= unsigned(re.addr_out);

logic_proc: process(r, re, last_val)
        variable v : reduce_stage_int;
    begin
        v := r;
        
        -- default assignments
        v.next_elem.valid := '0';

        v.push       := '1';
        v.write_addr := r.write_addr + 1;
        v.read_addr  := r.read_addr + 1;
        
        if re.add_res.valid = '1' then
            v.buff_elem  := re.add_res;
        end if;

        if r.buff_elem.valid = '1' AND (re.add_res.valid = '1' OR last_val = '1') then
            -- if the value coming out of the adder is in the same row as 
            -- the value currently in the buffer: sent them away together
            if re.add_res.addr = r.buff_elem.addr then
                v.buff_elem.valid := '0';
                v.next_elem       := r.buff_elem;
                if re.add_res.valid = '1' then
                    v.next_val := re.add_res.field;
                else
                    v.next_val := (others =>'0');
                end if;
                v.prev_addr       := r.buff_elem.addr;
            else
                -- otherwise, send the buffer value and a zero value into the next reduce stage
                v.next_elem  := r.buff_elem;
                v.next_val  := (others => '0');
            end if;
        end if;
        
        q <= v;
    end process;
    
    next_elem <= r.next_elem;
    next_val  <= r.next_val;
    
clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= REDUCE_STAGE_INT_INIT;
            else
                r <= q;    
            end if;
        end if;
    end process;

end architecture behavioral;
