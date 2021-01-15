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
    use IEEE.math_real.all;

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;

-- This unit delays NR offset values by [delay] cycles. 
-- It does this by constantly increasing both its read and write address
-- and writing its input data into it memory and connecting the memory output to its output
-- while making sure that the difference between its read and write address is always
-- the desired delay minus the memory latency. 
-- Note: this means the desired delay cannot be smaller than the memory delay
-- It also generates new row flags based on the delayed new row offsets. These flags are 1 
-- if and only if the offset is non-zero, and are used to create the control signals of the 
-- adder tree.
-- This unit is instantiated by the spmv unit.

entity NRs_fifo is
    generic(
        delay : natural
    );
    port( 
        clk     : in std_logic;
        reset   : in std_logic;
        inputs  : in offset_array(mult_range);
        outputs : out offset_array(mult_range);
        out_flags : out std_logic_vector(mult_range)
    );
end NRs_fifo;

architecture behavioral of NRs_fifo is
    
    signal push       : std_logic_vector(0 to 0);
    signal read_addr  : unsigned(ADD_DELAY_WIDTH - 1 downto 0);
    signal write_addr : unsigned(ADD_DELAY_WIDTH - 1 downto 0);
    signal write_data : std_logic_vector(OFFSET_WIDTH * MULT_NUM - 1 downto 0);
    signal read_data  : std_logic_vector(OFFSET_WIDTH * MULT_NUM - 1 downto 0);

begin

wd: for g in 0 to MULT_NUM - 1 generate
        write_data(OFFSET_WIDTH * (g + 1) - 1 downto OFFSET_WIDTH * g) <= std_logic_vector(inputs(g));
    end generate;
    
-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2019.2
-- Replaces the IP: dist_mem_NRs_delay
dram_fifo: xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => ADD_DELAY_DEPTH,
        ADDR_WIDTH_B => ADD_DELAY_DEPTH,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => MULT_NUM*OFFSET_WIDTH,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "distributed",     -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => MULT_NUM*OFFSET_WIDTH * 2 ** ADD_DELAY_DEPTH,           -- size in bits
        MESSAGE_CONTROL => 0,
        READ_DATA_WIDTH_B => MULT_NUM*OFFSET_WIDTH,
        READ_LATENCY_B => 2,
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => MULT_NUM*OFFSET_WIDTH,
        WRITE_MODE_B => "read_first"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        ena => bit_1,
        addra => std_logic_vector(write_addr),
        dina => write_data,
        wea => push,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(read_addr), -- NOTE: hardcoded size: max no. of row per color < 2048
        doutb => read_data,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                read_addr  <= (others => '0');
				-- NOTE: hardcoded memory delay of 2 cycles:
                write_addr <= to_unsigned(delay - 2, ADD_DELAY_WIDTH);
                push       <= "0";
                outputs    <= (others => (others => '0'));
                out_flags  <= (others => '0');
            else
                read_addr  <= read_addr + 1;
                write_addr <= write_addr + 1;
                push       <= "1";
                for l in 0 to MULT_NUM - 1 loop
                    outputs(l) <= unsigned(index(read_data, l, OFFSET_WIDTH));
                    out_flags(l) <= bool2sl(unsigned(index(read_data, l, OFFSET_WIDTH)) /= 0);
                end loop;
            end if;
        end if;
    end process;

end architecture behavioral;
