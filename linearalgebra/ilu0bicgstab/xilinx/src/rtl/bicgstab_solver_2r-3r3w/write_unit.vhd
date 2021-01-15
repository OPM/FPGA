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
    use ieee.std_logic_misc.all;
    use ieee.numeric_std.all;
    
-- synthesis translate_off
use std.textio.all;
use IEEE.std_logic_textio.all;
-- synthesis translate_on

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.rw_pkg.all;

-- This unit writes the result of the SpMV pipeline into the correct memories or sending it to 
-- the correct units. Since the SpMv pipeline does not produce it results in order, a part of 
-- the task of this unit is accumulating the results, keeping track of up to which address all 
-- spmv calculations have been done, and then sending the results u to that address to the 
-- correct locations. For the spMV calculation, this location is to a write port that connects 
-- to the HBM memory, but during the ILU0 application, this location is the ILU0 unit. The 
-- results of the ILU0 unit also briefly pass through this unit to be accumulated into cachelines
-- and for their addresses which are local to the color to be translated into addresses that are 
-- the actual indices of the complete ILU0 result vector.
-- This unit is instantiated by the sparsetition unit.

entity write_unit is
    generic (
        SIM_DEBUG: natural := 0;
        WRITE_ILU0_RESULTS : boolean
    );
    port (
        clk             : in std_logic;
        reset           : in std_logic;
        start           : in std_logic;
        write_batches   : in std_logic;
        is_U            : in std_logic;
        rows_num        : in mat_size;
        actual_row_size : in mat_size;
        do_reset        : in std_logic;
        flush           : in std_logic;
        new_color       : in std_logic;
        spmvp_res       : in elem_array(SPMVP_OUTPUT_NUM - 1 downto 0);
        done_up_to_addr : in row_index;
        spmvp_done      : in std_logic;
        ilu0_res        : in element;
        ilu0_done       : in std_logic;
        ilu0_input      : out element;
        ilu0_last_val   : out std_logic;
        write_ready     : in std_logic;
        write_line      : out write_line_type;
        write_field     : out write_field_type;
        ready           : out std_logic;
        done            : out std_logic
        ; found_overflow : out std_logic
        ; overflow      : out std_logic_vector(7 downto 0)
    );
end write_unit;

architecture behavioral of write_unit is

    signal r, q : write_int;
    
    type spmvp_res_we_type is array(SPMVP_OUTPUT_NUM - 1 downto 0) of std_logic_vector(0 downto 0);
    type spmvp_res_lines_type is array(SPMVP_OUTPUT_NUM - 1 downto 0) of std_logic_vector(DMA_DATA_WIDTH/SPMVP_OUTPUT_NUM - 1 downto 0);
    signal spmvp_res_wes   : spmvp_res_we_type;
    signal spmvp_res_lines : spmvp_res_lines_type;
    signal spmvp_res_line      : cacheline;
    signal debug_res_fields    : field_array(MULT_NUM -1 downto 0);

begin

spmvp_res_mems: for g in 0 to SPMVP_OUTPUT_NUM - 1 generate
    spmvp_res_wes(g)(0) <= r.write_elems(g).valid;
    
    -- xpm_memory_sdpram: Simple Dual Port RAM
    -- Xilinx Parameterized Macro, version 2019.2
    -- Replaces the IP: blk_mem_SPMVP_res
    spmvp_res_mem: xpm_memory_sdpram
        generic map (
            ADDR_WIDTH_A => ROW_INDEX_WIDTH - SPMVP_OUTPUT_DEPTH,
            ADDR_WIDTH_B => ROW_INDEX_WIDTH - FIELDS_PER_LINE_DEPTH,
            AUTO_SLEEP_TIME => 0,
            BYTE_WRITE_WIDTH_A => FIELD_WIDTH,       -- set to WRITE_DATA_WIDTH_A for one-bit wea
            CLOCKING_MODE => "common_clock", -- "common_clock", "independent_clock"
            ECC_MODE => "no_ecc",
            MEMORY_INIT_FILE => "none",
            MEMORY_INIT_PARAM => "0",
            MEMORY_OPTIMIZATION => "true",
            MEMORY_PRIMITIVE => "block",     -- "auto", "block", "distributed", "ultra"
            MEMORY_SIZE => MAX_ROW_SIZE / SPMVP_OUTPUT_NUM * FIELD_WIDTH,          -- size in bits
            MESSAGE_CONTROL => 1,
            READ_DATA_WIDTH_B => DMA_DATA_WIDTH / SPMVP_OUTPUT_NUM,
            READ_LATENCY_B => 2,
            READ_RESET_VALUE_B => "0",
            RST_MODE_A => "SYNC",
            RST_MODE_B => "SYNC",
            USE_EMBEDDED_CONSTRAINT => 0,
            USE_MEM_INIT => 0,
            WAKEUP_TIME => "disable_sleep",
            WRITE_DATA_WIDTH_A => FIELD_WIDTH,
            WRITE_MODE_B => "read_first" --no_change, read_first, write_first
        )
        port map (
            sleep => bit_0,
            clka => clk,
            ena => bit_1,
            addra => std_logic_vector(r.write_elems(g).addr(ROW_INDEX_WIDTH - 1 downto SPMVP_OUTPUT_DEPTH)),
            dina => r.write_elems(g).field,
            wea => spmvp_res_wes(g),
            injectsbiterra => bit_0,
            injectdbiterra => bit_0,
            clkb => bit_0, -- common clock, using clka
            rstb => reset,
            enb => bit_1,
            addrb => std_logic_vector(r.spmvp_res_addr(ROW_INDEX_WIDTH - 1 downto 3)), 
            doutb => spmvp_res_lines(g),
            regceb => bit_1,
            sbiterrb => open,
            dbiterrb => open
        );
    
    rl: for h in 0 to NUM_FIELDS_PER_LINE/SPMVP_OUTPUT_NUM - 1 generate
        spmvp_res_line((h * SPMVP_OUTPUT_NUM + g + 1) * FIELD_WIDTH - 1 downto (h * SPMVP_OUTPUT_NUM + g) * FIELD_WIDTH) <= index(spmvp_res_lines(g), h, FIELD_WIDTH);
        debug_res_fields(h * SPMVP_OUTPUT_NUM + g) <= index(spmvp_res_lines(g), h, FIELD_WIDTH);
    end generate;
end generate;

logic_proc: process(flush, start, write_batches, is_U, do_reset, new_color, rows_num, actual_row_size, done_up_to_addr, spmvp_done, spmvp_res_line, write_ready, spmvp_res, ilu0_res, ilu0_done, r)
    variable v : write_int;
    variable line_index : integer;
    variable reset_done : boolean;
    variable spmvp_valid : boolean;
    variable actual_address : row_index;
    variable write_elems_index : integer range SPMVP_OUTPUT_NUM - 1 downto 0;
begin
    v := r;
    
    -- detect overflow
    v.found_overflow := '0';
    v.overflow := (others => '0');
    for l in 0 to SPMVP_OUTPUT_NUM - 1 loop
        if r.write_elems(l).valid = '1' AND r.write_elems(l).addr > r.spmvp_res_addr AND r.write_elems(l).addr - r.spmvp_res_addr > SPMVP_RES_MEM_SIZE then
            v.found_overflow := '1';
            v.overflow(l) := '1';
        end if;
    end loop;

    --default assignments
    v.set_wr_data_valid := '0';
    v.done              := '0';
    v.ilu0_input.valid  := '0';
    v.do_split          := '0';
    
    -- register
    v.next_wr_data_valid := r.set_wr_data_valid;
    v.written_up_to_addr(0) := r.done_up_to_addr;
    v.written_up_to_addr(1) := r.written_up_to_addr(0);
    v.written_up_to_addr(2) := r.written_up_to_addr(1);
    
    v.write_line.valid := '0';
    
    -- do computations   
    
    case r.state is
        when idle =>
            v.flushed := '0';
            v.zero_pad_offset := (others => '0');
            v.done_up_to_addr := (others => '0');
            v.done_rows       := (others => '0');
            v.spmvp_res_addr  := (others => '0');
            v.write_addr      := (others => '0');
            v.ilu0_last_val   := '0';
            
            v.write_line.valid := r.next_wr_data_valid;
            v.write_line.data  := spmvp_res_line;
            
            if do_reset = '1' then
				-- In the U backward substitution, results are written from high addresses to low ones
                if is_U = '1' then
                    v.done_rows := rows_num(vector_addr_range) - 1;
                end if;
                for l in 0 to SPMVP_OUTPUT_NUM - 1 loop
                    if NOT(r.ready = '1') then
                        v.reset_addrs(l) := to_unsigned(0, ROW_INDEX_WIDTH);
                    end if;
                    v.write_elems(l).field := (others => '0');
--                    v.write_elems(l).valid := '1';
                end loop;
                v.state := reset_state;
            end if;

            -- only the spmvp write back can be started without reseting first.
            if start = '1' then
                v.is_U := is_U;
                v.ready := '0';
                for l in 0 to SPMVP_OUTPUT_NUM - 1 loop
                    v.reset_addrs(l) := to_unsigned(l, ROW_INDEX_WIDTH);
                end loop;
                if write_batches = '1' then
                    v.state     := fill_batch;
                end if; 
            end if;
        when reset_state =>
			-- The reset state writes zeroes to all memory locations in the spmvp results
			-- because the SpMV unit may skip addresses, which should be zero-valued results
            v.done_up_to_addr := (others => '0');
            v.spmvp_res_addr  := (others => '0');
            v.write_addr      := (others => '0');
            reset_done := true;
            for l in 0 to SPMVP_OUTPUT_NUM - 1 loop
                v.write_elems(l).field := (others => '0');
                v.write_elems(l).addr := r.reset_addrs(l);
                v.write_elems(l).valid := '1';
                if r.reset_addrs(l) < actual_row_size then
                    v.reset_addrs(l) := r.reset_addrs(l) + SPMVP_OUTPUT_NUM;       
                end if;
                reset_done := reset_done AND r.reset_addrs(l) >= actual_row_size;
            end loop;
            v.ilu0_last_val   := '0';
            v.next_ilu0_addr  := (others => '0');
            v.split_addr      := (others => '0');
            v.ilu0_input.addr := (others => '0');
            if reset_done then
                if start = '1' then
                    v.is_U := is_U;
                    v.ready := '0';
                    for l in 0 to SPMVP_OUTPUT_NUM - 1 loop
                        v.reset_addrs(l) := to_unsigned(l, ROW_INDEX_WIDTH);
                    end loop;
					-- The write batches input signal starts a write of SpMV operation results. 
					-- Otherwise, the write unit will be part of the ILU0 pipeline.
                    if write_batches = '1' then
                        v.state     := fill_batch;
                    else
                        v.state := write_ILU0;
                    end if;
                else
                    v.ready := '1';
                end if;
                
            end if;
        when fill_batch =>
            if new_color = '1' then
                v.done_rows := r.done_up_to_addr;
            end if;
            spmvp_valid := false;
            
            for l in 0 to SPMVP_OUTPUT_NUM - 1 loop
                if flush = '0' then
					-- write the SpMV unit results to the SpMV_res memory
                    actual_address := spmvp_res(l).addr + r.done_rows(row_index_range);
                    write_elems_index := (l + to_integer(r.done_rows(SPMVP_OUTPUT_DEPTH - 1 downto 0))) mod SPMVP_OUTPUT_NUM;
                    v.write_elems(write_elems_index).addr := actual_address;
                    v.write_elems(write_elems_index).field := spmvp_res(l).field;
                    v.write_elems(write_elems_index).valid := spmvp_res(l).valid;
                    spmvp_valid := spmvp_valid OR spmvp_res(l).valid = '1';
                else
					-- zero-pad the values in the SpMV_res memory to make sure the final results make up a full cacheline 
                    actual_address := done_up_to_addr + r.done_rows(row_index_range) + r.zero_pad_offset + to_unsigned(l, SPMVP_OUTPUT_DEPTH);
                    write_elems_index := (l + to_integer(done_up_to_addr(SPMVP_OUTPUT_DEPTH - 1 downto 0) + r.done_rows(SPMVP_OUTPUT_DEPTH - 1 downto 0))) mod SPMVP_OUTPUT_NUM;
                    v.write_elems(write_elems_index).addr := actual_address;
                    v.write_elems(write_elems_index).field := (others => '0');
                    v.write_elems(write_elems_index).valid := '1';
                    if r.zero_pad_offset < NUM_FIELDS_PER_LINE then
                        v.zero_pad_offset := r.zero_pad_offset + SPMVP_OUTPUT_NUM;
                    end if;
                end if;
            end loop;
            
			-- Keep track of up to which address all results have been outputted by the SpMv unit
            if flush = '0' then 
                if spmvp_done = '1' OR spmvp_valid then 
                    v.done_up_to_addr := done_up_to_addr + r.done_rows;
                end if;
            else
                v.done_up_to_addr := done_up_to_addr + r.done_rows + r.zero_pad_offset - 1;
            end if;
            
            -- update up to which row the results are guaranteed to be done
            
            if r.done_up_to_addr >= r.write_addr + WRITE_BATCH_SIZE * NUM_FIELDS_PER_LINE then
                v.write_addr := r.write_addr + WRITE_BATCH_SIZE * NUM_FIELDS_PER_LINE;
                v.state := write_batch;
                v.flushed := flush;
            end if;
--            if flush = '1' then
--                v.write_addr := r.done_up_to_addr;
--                v.done_rows  := r.done_up_to_addr;
--                v.state :=  write_batch;
--                v.flushed := '1';
--            end if;
            
            v.write_line.valid := r.next_wr_data_valid;
            v.write_line.data  := spmvp_res_line;
        when write_batch =>
            if new_color = '1' then
                v.done_rows := r.done_up_to_addr;
            end if;
            spmvp_valid := false;
            -- write the SpMV unit results to the SpMV_res memory
            for l in 0 to SPMVP_OUTPUT_NUM - 1 loop
                actual_address := spmvp_res(l).addr + r.done_rows(row_index_range);
                write_elems_index := (l + to_integer(r.done_rows(SPMVP_OUTPUT_DEPTH - 1 downto 0))) mod SPMVP_OUTPUT_NUM;
                v.write_elems(write_elems_index).addr := actual_address;
                v.write_elems(write_elems_index).field := spmvp_res(l).field;
                v.write_elems(write_elems_index).valid := spmvp_res(l).valid;
                spmvp_valid := spmvp_valid OR spmvp_res(l).valid = '1'; 
            end loop;
            -- update up to which row the results are guaranteed to be done
            if spmvp_done = '1' OR spmvp_valid then 
                v.done_up_to_addr := done_up_to_addr + r.done_rows;
            end if;
			-- If the writing of the batch is done, either go back to write another one or finish the write
            if r.spmvp_res_addr >= r.write_addr then
                if v.flushed = '1' then
                    v.done := '1';
                    v.state := idle;
                else
                    v.state := fill_batch;
                end if;
            else
				-- Otherwise, send the data to the write_line (set_wr_data_valid willbecome write_line.valid after 2 cycles (the meory read latency)
                if write_ready = '1' then
                    v.spmvp_res_addr := r.spmvp_res_addr + NUM_FIELDS_PER_LINE;
                    v.set_wr_data_valid := '1';
                end if;
            end if;
            
            v.write_line.valid := r.next_wr_data_valid ;
            v.write_line.data  := spmvp_res_line;
        when write_ILU0 =>
            spmvp_valid := false;
            for l in 0 to SPMVP_OUTPUT_NUM - 1 loop
                spmvp_valid := spmvp_valid OR spmvp_res(l).valid = '1'; 
				-- write the SpMV unit results to the SpMV_res memory
                if spmvp_res(l).valid = '1' then
                    v.write_elems(l).addr := spmvp_res(l).addr ;
                    v.write_elems(l).field := spmvp_res(l).field;
                    v.write_elems(l).valid := spmvp_res(l).valid;
                else
					-- if no SpMV result is received on this port this cycle, already do a reset when possible
                    v.write_elems(l).addr := r.reset_addrs(l);
                    v.write_elems(l).field := (others => '0');
                    if r.reset_addrs(l) + 8 < r.ilu0_input.addr then
                        v.write_elems(l).valid := '1';
                        v.reset_addrs(l) := r.reset_addrs(l) + SPMVP_OUTPUT_NUM;
                    else
                        v.write_elems(l).valid := '0';
                    end if;
                end if;
            end loop;
            
            -- update up to which row the results are guaranteed to be done
            if spmvp_valid then 
                v.done_up_to_addr := done_up_to_addr + to_unsigned(0, VECTOR_ADDR_WIDTH);
            elsif spmvp_done = '1' then
                v.done_up_to_addr := actual_row_size(VECTOR_ADDR_WIDTH - 1 downto 0);
            end if;
            
			-- start read from SpMV_res memory to send to the ILU0 unit, when enough data is available
            if r.written_up_to_addr(2) > r.spmvp_res_addr then
                v.spmvp_res_addr := r.spmvp_res_addr + 1;
                v.do_split       := '1';
                v.split_addr     := r.spmvp_res_addr(ROW_INDEX_WIDTH - 1 downto 0);
            end if;
            
            --v.line_to_split := spmvp_res_line;
            v.next_wr_data_valid := r.do_split;
            v.next_ilu0_addr := r.split_addr;
			
			-- Send data to the ILU0 unit
            v.ilu0_input.field := index(spmvp_res_line, to_integer(r.next_ilu0_addr(FIELDS_PER_LINE_DEPTH - 1 downto 0)), FIELD_WIDTH);
            v.ilu0_input.addr  := r.next_ilu0_addr;
            v.ilu0_input.valid := r.next_wr_data_valid;
            
            if r.ilu0_input.addr = actual_row_size(VECTOR_ADDR_WIDTH - 1 downto 0) - 1 AND r.ilu0_input.valid = '1' AND spmvp_done = '1' then
                v.ilu0_last_val := '1';
            end if;
			-- Handle done signals
            v.done := ilu0_done;
            if flush = '1' then
                v.flushed := '1';
            end if;
            if r.done = '1' then
				-- The flush signal is set only when the currently L_forward_substitution or U_backward substitution is done
                if r.flushed = '1' then
                    v.write_line.valid := r.write_line_filled;
                    v.write_line_filled := '0';
                    v.state := idle;
                else
					-- if the flush was not set, prepare for another set of SpMV results
                    v.flushed := '0';
                    v.state := reset_state;
                    
					-- Update the done_rows count: L does this low-to-high, and U high-to-low
                    if r.is_U = '1' then
                        v.done_rows := r.done_rows - actual_row_size(VECTOR_ADDR_WIDTH - 1 downto 0);
                    else
                        v.done_rows := r.done_rows + actual_row_size(VECTOR_ADDR_WIDTH - 1 downto 0);
                    end if;
                end if;
            end if;
            
            -- The code below is for debugging purposes only. 
            if WRITE_ILU0_RESULTS then
				-- aggregate the ILU0 results into a cacheline, and write this cacheline to the write_line when it is full
                if r.write_field.valid = '1' then
                    line_index := to_integer(r.write_field.addr(2 downto 0));
                    v.write_line.data((line_index + 1) * FIELD_WIDTH - 1 downto line_index * FIELD_WIDTH) := r.write_field.data;
                    if (r.is_U = '1' AND line_index = 0) OR (r.is_U = '0' AND line_index = 7) then
                        v.write_line.valid := '1';
                        v.write_line_filled := '0';
                    else
                        v.write_line_filled := '1';                  
                    end if;
                end if;
            end if;
        when others =>
    end case;

    v.write_field.valid := ilu0_res.valid;
    if r.is_U = '1' then
        v.write_field.addr := r.done_rows - ilu0_res.addr;
    else
        v.write_field.addr  := ilu0_res.addr + r.done_rows;
    end if;
    v.write_field.data  := ilu0_res.field;

    -- connect registers to output ports
    ilu0_last_val <= r.ilu0_last_val;
    ilu0_input  <= r.ilu0_input;
    write_line  <= r.write_line;
    write_field <= r.write_field;
    ready       <= r.ready;
    done        <= r.done;
    found_overflow <= r.found_overflow;
    overflow <= r.overflow;
    
    q <= v;
end process;

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= WRITE_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;

-- synthesis translate_off
-- DEBUG code to print some intermediate results
-- It's placed here in order to be used also when doing co-simulation with SDAccel
print_trans_proc: process(clk)
    variable lineout: line;
    begin
        if rising_edge(clk) and ( or_reduce(std_logic_vector(to_unsigned(SIM_DEBUG,32) and to_unsigned(SIM_DEBUG_WU,32)))='1' ) then
            -- dump ilu0_input
            if (r.ilu0_input.valid = '1') then
                write(lineout,string'("DBGWU: ilu0_input, "));
                write(lineout,string'("time="));
                write(lineout,time'image(now));
                write(lineout,string'(" - addr "));
                write(lineout,to_integer(r.ilu0_input.addr));
                write(lineout,string'(" - 0x "));
                hwrite(lineout,std_logic_vector( r.ilu0_input.field ));
                writeline(output, lineout);
            end if;
            -- dump write_field
            if (r.write_field.valid = '1') then
                write(lineout,string'("DBGWU: write_field, "));
                write(lineout,string'("time="));
                write(lineout,time'image(now));
                write(lineout,string'(" - addr "));
                write(lineout,to_integer(r.write_field.addr));
                write(lineout,string'(" - 0x "));
                hwrite(lineout,std_logic_vector( r.write_field.data ));
                writeline(output, lineout);
            end if;
        end if;
    end process;
-- synthesis translate_on

end behavioral;
