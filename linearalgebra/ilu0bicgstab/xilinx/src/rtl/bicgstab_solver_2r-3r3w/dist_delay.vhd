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

-- The purpose of this entity is to delay an input signal by a number of cycles.
-- This is done with a BRAM, and two constantsly updating read/write addresses that are always 
-- as much apart as the delay minus the memory delay.
-- This unit is instantiated by the spmv and ilu0 units.

entity delay_pipe is
    generic( 
        delay : integer;
        delay_depth : integer;
        width : integer
    );
    port (
        clk      : in std_logic;
        reset    : in std_logic;
        in_data  : in std_logic_vector(width - 1 downto 0);
        out_data : out std_logic_vector(width - 1 downto 0)
    );
end delay_pipe;

architecture behavioral of delay_pipe is

    signal we         : std_logic_vector(0 downto 0);
    signal write_addr : unsigned(delay_depth - 1 downto 0);
    signal read_addr  : unsigned(delay_depth - 1 downto 0);
begin

-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2019.2
-- Replaces either IP: dist_mem_field_delay, dist_mem_addr_delay or dist_mem_addr_long_delay
-- depending on which input parameters were chosen
dist_mem: xpm_memory_sdpram
    generic map (
        ADDR_WIDTH_A => delay_depth,
        ADDR_WIDTH_B => delay_depth,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => width,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
        CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "distributed",     -- "auto", "block", "distributed", "ultra"
        MEMORY_SIZE => 2**delay_depth * width,           -- size in bits
        MESSAGE_CONTROL => 0,
        READ_DATA_WIDTH_B => width,
        READ_LATENCY_B => 2,
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => width,
        WRITE_MODE_B => "read_first"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        ena => bit_1,
        addra => std_logic_vector(write_addr),
        dina => in_data,
        wea => we,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(read_addr), -- NOTE: hardcoded size: max no. of row per color < 2048
        doutb => out_data,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );
       
clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                write_addr <= to_unsigned(delay - 2, delay_depth);
                read_addr <= (others => '0');
                we <= "0";
            else
                write_addr <= write_addr + 1;
                read_addr <= read_addr + 1;
                we <= "1";
            end if;
        end if;
    end process;    
        
end behavioral;
