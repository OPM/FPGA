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
    use work.constants.all;
    use work.types.all;
    use work.functions.all;

-- This unit contains of the memories in which the vector partition of the color 
-- that is being worked on is stored multiple times, once for each 2 multiplier 
-- units. It also contains registers to delay the non-zero values of the matrix, 
-- while the column indices are used as addresses to read from the vector partition memories.
-- This unit is instantiated by the SpMV unit.

entity multiplicant_replication_buffer is
    port (
        clk        : in std_logic;
        reset      : in std_logic;
        in_line    : in cacheline;
        we         : in std_logic;
        read_addrs : in col_index_array(mult_range);
        in_vals    : in field_array(mult_range);
        in_valid   : in std_logic;
        read_outs  : out field_array(mult_range);
        out_vals   : out field_array(mult_range);
        out_valid  : out std_logic;
        debug_error : out std_logic_vector(0 downto 0) 
    );
end multiplicant_replication_buffer;

architecture behavioral of multiplicant_replication_buffer is

    constant FIELDS_PER_LINE : natural := DMA_DATA_WIDTH / FIELD_WIDTH;

    component blk_mem_ilu0_multiplicant_vector
        port (
            clka  : in std_logic;
            wea   : in std_logic_vector(0 downto 0);
            addra : in std_logic_vector(col_index_range);
            dina  : in cacheline;
            douta : out field;
            clkb  : in std_logic;
            web   : in std_logic_vector(0 downto 0);
            addrb : in std_logic_vector(col_index_range);
            dinb  : in field;
            doutb : out field
        );
    end component;

    type delay_vals_type is array(SPMV_X_LOOKUP_LATENCY - 1 downto 0) of field_array(mult_range);
    
    type mult_repl_buff_int is record
        delayed_vals       : delay_vals_type;
        delayed_valid      : std_logic_vector(SPMV_X_LOOKUP_LATENCY - 1 downto 0);
        delay_write_addr   : unsigned(1 downto 0);
        delay_read_addr    : unsigned(1 downto 0);
        we                 : std_logic_vector(0 downto 0);
        read_reg           : cacheline;
        write_addr         : column_index;
        addr1              : col_index_array(MULT_NUM / 2 - 1 downto 0);
        addr2              : col_index_array(MULT_NUM / 2 - 1 downto 0);
    end record;

constant MULT_REPL_BUFF_INT_INIT : mult_repl_buff_int := (
	(others => (others => (others => '0'))), -- delayed_vals
	(others => '0'),   -- delayed_valid
	to_unsigned(SPMV_X_LOOKUP_LATENCY - 1, 2), -- delay_write_addr
	(others => '0'),   -- delay_read_addr
	"0",               -- we
	(others => '0'),   -- line_reg
	(others => '0'),   -- write_addr
	(others => (others => '0')),   -- addr1
	(others => (others => '0'))    -- addr2
);

    signal r, q        : mult_repl_buff_int;
    signal unused_in_field : field;
    signal unused_we : std_logic_vector(0 downto 0);

begin

buffs: for g in 0 to MULT_NUM / 2 - 1 generate
    buff:  blk_mem_ilu0_multiplicant_vector
        port map(
            clka  => clk,
            wea   => r.we,
            addra => std_logic_vector(r.addr1(g)),
            dina  => r.read_reg,
            douta => read_outs(2 * g),
            clkb  => clk,
            web   => unused_we,
            addrb => std_logic_vector(r.addr2(g)),
            dinb  => unused_in_field,
            doutb => read_outs(2 * g + 1)
        );
    
    -- The xpm_memory below was tried, but does not work, as this macro does not support different read and write widths on the same port
    -- The above IP core must be used until this support is added (if ever) 
    
    -- xpm_memory_sdpram: True Dual Port RAM
    -- Xilinx Parameterized Macro, version 2019.2
    -- Replaces the IP: blk_mem_ilu0_multiplicant_vector
--    buff : xpm_memory_tdpram
--        generic map (
--            ADDR_WIDTH_A => 13,
--            ADDR_WIDTH_B => 13,
--            AUTO_SLEEP_TIME => 0,
--            BYTE_WRITE_WIDTH_A => 512,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
--            BYTE_WRITE_WIDTH_B => 64,
--            CASCADE_HEIGHT => 0,
--            CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
--            ECC_MODE => "no_ecc",
--            MEMORY_INIT_FILE => "none",
--            MEMORY_INIT_PARAM => "0",
--            MEMORY_OPTIMIZATION => "true",
--            MEMORY_PRIMITIVE => "block",     -- "auto", "block", "distributed", "ultra"
--            MEMORY_SIZE => 2**13*64,           -- size in bits
--            MESSAGE_CONTROL => 1,
--            READ_DATA_WIDTH_A => 64,
--            READ_DATA_WIDTH_B => 64,
--            READ_LATENCY_A => 2,
--            READ_LATENCY_B => 2,
--            READ_RESET_VALUE_A => "0",
--            READ_RESET_VALUE_B => "0",
--            RST_MODE_A => "SYNC",
--            RST_MODE_B => "SYNC",
--            SIM_ASSERT_CHK => 1,
--            USE_EMBEDDED_CONSTRAINT => 0,
--            USE_MEM_INIT => 0,
--            WAKEUP_TIME => "disable_sleep",
--            WRITE_DATA_WIDTH_A => 512,
--            WRITE_DATA_WIDTH_B => 64,
--            WRITE_MODE_A => "write_first",
--            WRITE_MODE_B => "write_first"
--        )
--        port map (
--            sleep => bit_0,
--            clka => clk,
--            rsta => reset,
--            ena => bit_1,
--            addra => std_logic_vector(r.addr1(g)),
--            dina => r.read_reg,
--            wea => r.we,
--            douta => read_outs(2 * g),
--            regcea => bit_1,
--            sbiterra => open,
--            dbiterra => open,
--            injectsbiterra => bit_0,
--            injectdbiterra => bit_0,
--            clkb => bit_0, -- common clock, using clka
--            rstb => reset,
--            enb => bit_1,
--            addrb => std_logic_vector(r.addr2(g)), -- NOTE: hardcoded size: max no. of row per color < 2048
--            dinb => unused_in_field,
--            web => unused_we,
--            doutb => read_outs(2 * g + 1),
--            regceb => bit_1,
--            sbiterrb => open,
--            dbiterrb => open,
--            injectsbiterrb => bit_0,
--            injectdbiterrb => bit_0
--        );
    end generate;
    
logic_proc: process(r, we, in_line, read_addrs, in_vals, in_valid)
        variable v : mult_repl_buff_int;
    begin
        v := r;
        
        -- default assignments:
        v.read_reg := in_line;

        if r.we = "1" then
            v.write_addr := r.write_addr + NUM_FIELDS_PER_LINE;
        end if;
        
        -- delay input vals and valids by the delay of the buffer
        v.delayed_vals(to_integer(r.delay_write_addr)) := in_vals;
        v.delayed_valid(to_integer(r.delay_write_addr)) := in_valid;
        
        v.delay_write_addr := r.delay_write_addr + 1;
        v.delay_read_addr  := r.delay_read_addr + 1;
        
        -- switch between buffer read and write states
        v.we(0) := we;
        if we = '1' then
            for l in 0 to MULT_NUM / 2 - 1 loop
                v.addr1(l) := v.write_addr;
                v.addr2(l) := v.write_addr;
            end loop;
        else
            for l in 0 to MULT_NUM / 2 - 1 loop
                v.addr1(l) := read_addrs(2 * l);
                v.addr2(l) := read_addrs(2 * l + 1);
            end loop;
        end if;
        
        q <= v;
        
        -- assign output values
        out_vals  <= r.delayed_vals(to_integer(r.delay_read_addr));
        out_valid <= r.delayed_valid(to_integer(r.delay_read_addr));
    end process;

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= MULT_REPL_BUFF_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;

end behavioral;
