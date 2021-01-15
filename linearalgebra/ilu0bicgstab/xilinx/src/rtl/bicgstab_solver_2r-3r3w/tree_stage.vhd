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
    use work.constants.all;
    use work.types.all;
    use work.functions.all;

-- This unit describes one stage of the selective adder tree in the SpMV unit
-- It has MULT_NUM output value, which need the be connected to either the results 
-- of one of its adder outputs, or to the input value corresponding to the output port,
-- delayed by tha dder delay. Its add_connect input bits select which output should be 
-- chosen for each port in each cycle.
-- This unit is instantiated multiple (log2(MULT_NUM)) times by the spmv unit.

entity tree_stage is
    generic(
        STAGE_NUM        : natural
    );
    port ( 
        clk         : in std_logic;
        reset       : in std_logic;
        in_valid    : in std_logic;
        in_values   : in field_array(mult_range);
        add_connect : in std_logic_vector(mult_range);
        out_valid   : out std_logic;
        out_values  : out field_array(mult_range)
    );
end tree_stage;

architecture behavioral of tree_stage is

    constant INS_PER_ADD : natural := 2 ** (STAGE_NUM + 1);
    
    component FP_adder is
        port(
            aclk                 : in std_logic;
            s_axis_a_tvalid      : in std_logic;
            s_axis_a_tdata       : in field;
            s_axis_b_tvalid      : in std_logic;
            s_axis_b_tdata       : in field;
            m_axis_result_tvalid : out std_logic;
            m_axis_result_tdata  : out field
        );
    end component;
    
    type tree_adder_int is record
        out_vals   :  field_array(mult_range);
        read_addr  : unsigned(ADD_DELAY_WIDTH - 1 downto 0);
        write_addr : unsigned(ADD_DELAY_WIDTH - 1 downto 0);
        push       : std_logic_vector(0 downto 0);
        out_valid  : std_logic;
    end record;
    
    constant TREE_ADDER_INT_INIT : tree_adder_int :=(
        (others => (others => '0')), -- out_vals
        (others => '0'),    -- read_addr
        to_unsigned(ADD_DELAY - 2, ADD_DELAY_WIDTH), -- write_addr
        "0",                -- push
        '0'                 -- out_valid
    );

    signal res_valid : std_logic_vector(MULT_NUM / INS_PER_ADD - 1 downto 0);
    signal res_data  : field_array(MULT_NUM / INS_PER_ADD - 1 downto 0);
    signal buff_vals : field_array(MULT_NUM - 1 downto 0);
    
    signal r, q      : tree_adder_int;
    -- This signal cannot be part of the record because it has variable size based on generic
    signal delay_in  : std_logic_vector(MULT_NUM * FIELD_WIDTH - 1 downto 0);
    signal delay_out : std_logic_vector(MULT_NUM * FIELD_WIDTH - 1 downto 0);
begin

adders: for adder in 0 to MULT_NUM / INS_PER_ADD - 1 generate
        constant add_in_index0 : natural := INS_PER_ADD * adder + INS_PER_ADD / 2 - 1;
        constant add_in_index1 : natural := INS_PER_ADD * adder + INS_PER_ADD / 2;
    begin
    add: FP_adder
            port map(
                aclk => clk,
                s_axis_a_tvalid => in_valid,
                s_axis_a_tdata  => in_values(add_in_index0),
                s_axis_b_tvalid => in_valid,
                s_axis_b_tdata  => in_values(add_in_index1 ),
                m_axis_result_tvalid => res_valid(adder),
                m_axis_result_tdata  => res_data(adder)
            );
    end generate;
    
--bram_check: if USE_BRAM_ADD_TREE_FIFO generate
bram_fifos: for g in 0 to MULT_NUM - 1 generate
    -- xpm_memory_sdpram: Simple Dual Port RAM
    -- Xilinx Parameterized Macro, version 2019.2
    -- Replaces the IP: dist_mem_field_delay
    bram_fifo: xpm_memory_sdpram
        generic map (
            ADDR_WIDTH_A => ADD_DELAY_DEPTH,
            ADDR_WIDTH_B => ADD_DELAY_DEPTH,
            AUTO_SLEEP_TIME => 0,
            BYTE_WRITE_WIDTH_A => FIELD_WIDTH,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
            CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
            ECC_MODE => "no_ecc",
            MEMORY_INIT_FILE => "none",
            MEMORY_INIT_PARAM => "0",
            MEMORY_OPTIMIZATION => "true",
            MEMORY_PRIMITIVE => "distributed",     -- "auto", "block", "distributed", "ultra"
            MEMORY_SIZE => 2**ADD_DELAY_DEPTH * FIELD_WIDTH,           -- size in bits
            MESSAGE_CONTROL => 0,
            READ_DATA_WIDTH_B => FIELD_WIDTH,
            READ_LATENCY_B => 2,
            READ_RESET_VALUE_B => "0",
            RST_MODE_A => "SYNC",
            RST_MODE_B => "SYNC",
            USE_EMBEDDED_CONSTRAINT => 0,
            USE_MEM_INIT => 0,
            WAKEUP_TIME => "disable_sleep",
            WRITE_DATA_WIDTH_A => FIELD_WIDTH,
            WRITE_MODE_B => "read_first"
        )
        port map (
            sleep => bit_0,
            clka => clk,
            ena => bit_1,
            addra => std_logic_vector(r.write_addr),
            dina => delay_in(g*64+63 downto g*64),
            wea => r.push,
            injectsbiterra => bit_0,
            injectdbiterra => bit_0,
            clkb => bit_0, -- common clock, using clka
            rstb => reset,
            enb => bit_1,
            addrb => std_logic_vector(r.read_addr), -- NOTE: hardcoded size: max no. of row per color < 2048
            doutb => delay_out(g*64 + 63 downto g * 64),
            regceb => bit_1,
            sbiterrb => open,
            dbiterrb => open
        );
    end generate;
    
bio: for g  in 0 to MULT_NUM - 1 generate
        delay_in((g + 1) * FIELD_WIDTH - 1 downto g * FIELD_WIDTH) <= in_values(g);
        buff_vals(g) <= delay_out((g + 1) * FIELD_WIDTH - 1 downto g * FIELD_WIDTH);
    end generate;

logic_proc: process(r, buff_vals, res_data, add_connect, res_valid)
        variable v : tree_adder_int;
    begin
        v := r;
        v.read_addr  := r.read_addr + 1;
        v.write_addr := r.write_addr + 1;
        v.push       := "1";
        v.out_valid  := and_reduce(res_valid);
        for value in 0 to MULT_NUM - 1 loop
            if add_connect(value) = '1' then
                v.out_vals(value ) := res_data(value/INS_PER_ADD);
            else
                v.out_vals(value) := buff_vals(value);
            end if;
        end loop;
        q <= v;
    end process;    

    out_valid  <= r.out_valid;
    out_values <= r.out_vals;

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= TREE_ADDER_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;

end architecture behavioral;
