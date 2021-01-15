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
    use work.spmvp_pkg.all;
    use work.types.all;

-- This unit produces takes new row offsets as inputs, and produces both 
-- new row flags and total offset values as outputs that will be output 
-- exactly ADD_DELAY cycles after the row offsets they are based on enter 
-- this unit.
-- The new row flags are bits that are 1 if and only if the row offset they 
-- are based on is non-zero. The total offsets values are the combined row 
-- offsets in the clock cycle up and including to that index. 
-- (so, total_offset[0] = NR_offset[0], 
-- total_offset[1] = NR_offset[1] + NR_offset[0], 
-- total_offset[7] = SUM(NR_offsets[7 downto 0], etc.)
-- This unit is instantiated by the SpMV unit.

entity NR2offset is
    port( 
        clk      : in std_logic;
        reset    : in std_logic;
        inputs   : in offset_array(mult_range);
        out_NRs  : out std_logic_vector(MULT_NUM - 1 downto 0);
        offsets  : out add_offsets_type
    );
end NR2offset;

architecture behavioral of NR2offset is
    
    constant NR_DELAY : natural := ADD_DELAY - MULT_DEPTH + 1;
    
    signal write_data : std_logic_vector(OFFSET_WIDTH * MULT_NUM - 1 downto 0);
    signal read_data  : std_logic_vector(OFFSET_WIDTH * MULT_NUM - 1 downto 0);
    
    type stages_type is array(MULT_DEPTH downto 0, mult_range) of unsigned(OFFSET_WIDTH + MULT_DEPTH - 1 downto 0);

    type NR_buffer_type is array(MULT_DEPTH - 1 downto 0) of std_logic_vector(mult_range);
    
    -- add stage types:
    type NR2O_int is record
        push       : std_logic_vector(0 downto 0);
        read_addr  : unsigned(ADD_DELAY_WIDTH - 1 downto 0);
        write_addr : unsigned(ADD_DELAY_WIDTH - 1 downto 0);
        stages     : stages_type;
        NR_buffers : NR_buffer_type;
    end record;
    
    constant NR2O_INT_INIT : NR2O_int :=(
        "0",                         -- push
        (others => '0'),             -- read_addr
        to_unsigned(NR_DELAY - 2, ADD_DELAY_WIDTH),-- write_addr
        (others => (others => (others => '0'))), -- stages
        (others => (others => '0'))  -- NR_buffers
    );
    
    signal q, r : NR2O_int;
    
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
        addra => std_logic_vector(r.write_addr),
        dina => write_data,
        wea => r.push,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.read_addr), -- NOTE: hardcoded size: max no. of row per color < 2048
        doutb => read_data,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open
    );
    
logic_proc: process(read_data, r)
        variable v : NR2O_int;
        variable add_index : integer;
        variable add_range : integer;
    begin
        v := r;
        
        v.push       := "1";
        v.read_addr  := v.read_addr + 1;
        v.write_addr := v.write_addr + 1;
        
		-- the addition of all new row offsets is done in stages, because 8 or 16 additions in a row cannot be done in one cycle.
        -- Generate inputs of the first add stage
        for value in 0 to MULT_NUM - 1 loop
            v.stages(0, value)(offset_range) := unsigned(index(read_data, value, OFFSET_WIDTH));
            -- generate NR row flags
            v.NR_buffers(0)(value) := bool2sl(index(read_data, value, OFFSET_WIDTH) /= ZEROES(offset_range));
        end loop;
        
        -- generate all add stages
        for stage in 0 to MULT_DEPTH - 1 loop
            add_range := 2 ** (stage + 1);
            for value in 0 to MULT_NUM - 1 loop
                add_index := add_range * (value / add_range) + add_range / 2 - 1;
                if ((value mod add_range) > (add_range / 2 - 1)) then
                    v.stages(stage + 1, value)(OFFSET_WIDTH + stage downto 0) := ("0" & r.stages(stage, value)(OFFSET_WIDTH + stage - 1 downto 0)) + ("0" & r.stages(stage, add_index)(OFFSET_WIDTH + stage - 1 downto 0));
                else
                    v.stages(stage + 1, value)(OFFSET_WIDTH + stage downto 0) := "0" & r.stages(stage, value)(OFFSET_WIDTH + stage - 1 downto 0);
                end if;
            end loop;
        end loop;
        
        -- delay NR signals some more
        for stage in 0 to MULT_DEPTH - 2 loop
            v.NR_buffers(stage + 1) := r.NR_buffers(stage);
        end loop;
        
        -- output signals
        for value in 0 to MULT_NUM - 1 loop
            offsets(value) <= r.stages(MULT_DEPTH, value);
        end loop;
        out_NRs <= r.NR_buffers(MULT_DEPTH - 1);
        
        q <= v;
    end process;

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= NR2O_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;

end architecture behavioral;
