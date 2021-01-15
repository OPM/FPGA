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
    use work.wm_pkg.all;

-- The split2 unit sorts two streams of input elements by bit [COMPARE_INDEX] in their 
-- address. In other words: it makes sure all incoming elements with a 0 in the 
-- COMPARE_INDEX-th bit of their address are outputted by the even_elem output port, 
-- and all incoming elements with a 1 in the COMPARE_INDEX-th bit of their address 
-- are outputted by the odd_elem output port. 
-- This unit is instantiated multiple times by the write_merge unit described further 
-- down in this file.

entity split2 is
    generic(
        COMPARE_INDEX : integer := 0  
    );
    port(
        clk       : in std_logic;
        reset     : in std_logic;
        in_done   : in std_logic_vector(1 downto 0);
        in_elems  : in elem_array(1 downto 0);
        even_elem : out element;
        odd_elem  : out element;
        done      : out std_logic_vector(1 downto 0)
        ; overflow : out std_logic
    );
end entity split2;
    
architecture behavioural of split2 is

    signal r, q : split2_int;
--    signal re   : wm_fifo_out_type;
    
begin

logic_proc: process(in_elems, in_done, r)--, re)
        variable v : split2_int;
        variable sel, unsel : integer range 1 downto 0;
        variable write_index, read_index : integer range SPLIT_BUFFER_SIZE - 1 downto 0;
    begin
        v := r;
        
        -- default assignments
        v.even_elem.valid := '0';
        v.odd_elem.valid := '0';
        write_index := to_integer(r.write_addr(SPLIT_BUFFER_DEPTH - 1 downto 0));
        read_index := to_integer(r.read_addr(SPLIT_BUFFER_DEPTH - 1 downto 0));
        
        v.overflow := bool2sl(r.write_addr - r.read_addr > SPLIT_BUFFER_SIZE);
        v.done := bool2sl(in_done = "11") AND bool2sl(r.write_addr = r.read_addr) AND NOT(r.eo_elems(0).valid) AND NOT(r.eo_elems(1).valid) AND NOT(r.even_elem.valid) AND NOT(r.odd_elem.valid); --re.empty AND bool2sl(r.fifo.push = "0000")
        
        -- choose elements to operate on:
        v.eo_elems := in_elems;
        if in_elems(0).valid = '0' then
			-- if the first incoming valus is not valid and the second one is not valid either, 
			-- or does not share the COMPARE_INDEX address bit with the top element from the fifo,
			-- pull that value and put it into eo_elems(0)
            if r.stored_elem(read_index).addr(COMPARE_INDEX) /= in_elems(1).addr(COMPARE_INDEX) OR in_elems(1).valid = '0' then
                v.eo_elems(0) := r.stored_elem(read_index);
                if r.stored_elem(read_index).valid = '1' then
                    v.stored_elem(read_index).valid := '0';
                    v.read_addr := r.read_addr + 1;
                end if;
            end if;
        elsif in_elems(1).valid = '0' then
			-- if the second incoming valus is not valid and the first one does not share the 
			-- COMPARE_INDEX address bit with the top element from the fifo,
			-- pull that value and put it into eo_elems(1)
            if r.stored_elem(read_index).addr(COMPARE_INDEX) /= in_elems(0).addr(COMPARE_INDEX) then
                v.eo_elems(1) := r.stored_elem(read_index);
                if r.stored_elem(read_index).valid = '1' then
                    v.stored_elem(read_index).valid := '0';
                    v.read_addr := r.read_addr + 1;
                end if;
            end if;
        else
			-- otherwise, if both incoming valid elements share the same COMPARE_INDEX address bit,
			-- store one of them in the fifo and try if a value from the fifo fits in its place
			-- otherwise, send both input elements into eo-elems
            if in_elems(0).addr(COMPARE_INDEX) = in_elems(1).addr(COMPARE_INDEX) then
                sel := to_integer(r.out_sel);
                unsel := to_integer(r.out_sel + 1);
                v.stored_elem(write_index) := in_elems(unsel);
                v.write_addr := r.write_addr + 1;
                if r.stored_elem(read_index).addr(COMPARE_INDEX) /= in_elems(sel).addr(COMPARE_INDEX) then
                    v.eo_elems(unsel) := r.stored_elem(read_index);
                    if r.stored_elem(read_index).valid = '1' then
                        v.stored_elem(read_index).valid := '0';
                        v.read_addr := r.read_addr + 1;
                    end if;
                 else
                    v.eo_elems(unsel).valid := '0';
                end if;
            end if; 
        end if; 
        v.out_sel := NOT(r.out_sel);
        
        -- select one even and one odd addressed element from eo_elems
        if (r.eo_elems(0).addr(COMPARE_INDEX) = '0' AND r.eo_elems(0).valid = '1') OR (r.eo_elems(1).addr(COMPARE_INDEX) = '1' AND r.eo_elems(1).valid = '1') then
            v.even_elem := r.eo_elems(0);
            v.odd_elem := r.eo_elems(1);
        else
            v.even_elem := r.eo_elems(1);
            v.odd_elem := r.eo_elems(0);
        end if;
        
        --assign output signals:
        even_elem <= r.even_elem;
        odd_elem  <= r.odd_elem;
        done      <= r.done & r.done;
        overflow  <= r.overflow;
        
        q <= v;
    end process;

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= SPLIT2_INT_INIT;
            else
                r <= q;
            end if;        
        end if;
    end process;

end architecture behavioural;

----------------------------------------------------------------------------------------

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
    use work.wm_pkg.all;

-- This unit merges two streams of occasionally valid input element into a single 
-- stream of elements. It does this by storing both incoming streams in FIFOs. 
-- If only one FIFO is non-empty, it pulls from that FIFO alone, but if both FIFOs 
-- are non-empty, the unit will pull from them in a round-robin fashion to not give 
-- preference to one over the other.
-- This unit is instantiated multiple times by the write_merge unit described further 
-- down in this file.

entity merge2 is
    port(
        clk       : in std_logic;
        reset     : in std_logic;
        in_done   : in std_logic_vector(1 downto 0);
        in_elems  : in elem_array(1 downto 0);
        out_elem  : out element;
        done      : out std_logic
        ; overflow : out std_logic_vector(1 downto 0)
    );
end entity merge2;

architecture behavioural of merge2 is
    
    signal r, q : merge2_int;
    signal re  : wm_fifo_out_array(1 downto 0);
    
begin

-- xpm_fifo_sync: Synchronous FIFO
-- Xilinx Parameterized Macro, version 2018.3
-- Replaces the IP: fifo_dist_mem_element
fifos: for g in 0 to 1 generate
fifo : xpm_fifo_sync
    generic map (
        DOUT_RESET_VALUE => "0",
        ECC_MODE => "no_ecc",
        FIFO_MEMORY_TYPE => "distributed",  -- "auto", "block", "distributed", "ultra"
        FIFO_READ_LATENCY => 0,       -- must be 0 if READ_MODE = "fwft"
        FIFO_WRITE_DEPTH => 64,      -- must be a power of two
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
        wr_en => r.fifos(g).push(0),
        wr_ack => open,
        din => r.fifos(g).data,
        rd_en => r.fifos(g).pull,
        dout => re(g).data,
        data_valid => open,
        empty => re(g).empty,
        almost_empty => re(g).almost_empty,
        prog_empty => open,
        full => re(g).full,
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
end generate;

logic_proc: process(in_elems, in_done, r, re)
        variable v : merge2_int;
        variable sel, unsel : integer range 1 downto 0;
    begin
        v      := r;
        
        -- default assignments
        v.out_elem.valid  := '0';

        v.done := re(0).empty AND re(1).empty AND bool2sl(r.fifos(0).push = "0000") AND bool2sl(r.fifos(1).push = "0000") AND bool2sl(in_done = "11");
        for l in 0 to 1 loop
            v.fifos(l).pull       := '0';
            v.overflow(l) := re(l).full AND r.fifos(l).push(0);
			-- store incoming elements in the fifos
            v.fifos(l).data  := std_logic_vector(in_elems(l).addr) & in_elems(l).field;
            v.fifos(l).push(0)  := in_elems(l).valid;
            v.fifos(l).push(3 downto 1) := r.fifos(l).push(2 downto 0);
        end loop;
              
        -- Delay the write-through one cycle to give the fifo time to update
        sel := to_integer(r.fifo_sel);
        unsel := to_integer(r.fifo_sel + 1);
		-- pull from the fifos in a round-robin fashion
        if re(sel).almost_empty = '0' OR (re(sel).empty = '0' AND r.fifos(sel).pull = '0') then
            v.fifos(sel).pull := '1';
        else
            v.fifos(unsel).pull := NOT(re(unsel).almost_empty) OR (NOT(re(unsel).empty) AND NOT(r.fifos(unsel).pull));
        end if;
        
		-- Connect fifo outputs to output ports
        if r.fifos(0).pull = '1' then
            v.out_elem := fifo_data2element(re(0), r.fifos(0).pull);
        elsif r.fifos(1).pull = '1' then
            v.out_elem := fifo_data2element(re(1), r.fifos(1).pull);
        end if;
        
        v.fifo_sel := r.fifo_sel + 1;
        q <= v;
    end process;
    
    out_elem  <= r.out_elem;
    done      <= r.done;
    overflow <= r.overflow;
    
clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= MERGE2_INT_INIT;
            else
                r <= q;
            end if;        
        end if;
    end process;
end architecture behavioural;

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;
    use ieee.std_logic_misc.all;

library xpm;
    use xpm.vcomponents.all;

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.wm_pkg.all;

-- This unit merges the results of the Selective adder tree and reduce unit, and merges 
-- them into a number of outputs that can be written to the cyclically partitioned BRAM 
-- of the write unit. To this enc, each of the SPMVP_OUTPUT_NUM output elements has a 
-- set value of the log2(SPMVP_OUTPUT_NUM) least significant bits of their address. 
-- The design goal of this unit was to output as many elements as possible every clock 
-- cycle to try to prevent the FIFOs in this unit from overflowing.
-- This unit first merges the NUM_MULTS-1 result elements of the adder tree into 
-- SPMVP_OUTPUT_NUM elements using merge2 units, and then it sorts those elements based 
-- on the least significant bits of their addresses using split2 units. Finally, FIFOs 
-- are used to register the split2 results so a reduce unit result with the same least 
-- significant bits in its address can be given priority over it into the write unit.
-- This unit is instantiated by the spmv unit.

entity write_merge is
    port(
        clk        : in std_logic;
        reset      : in std_logic;
        last_val   : in std_logic;
        in_elems   : in elem_array(MULT_NUM - 1 downto 0);
        out_elems  : out elem_array(SPMVP_OUTPUT_NUM - 1 downto 0);
        done       : out std_logic
        ; overflow : out std_logic_vector(15 downto 0)
        ; found_overflow : out std_logic
    );
end write_merge;

architecture behavioral of write_merge is
        
    signal r, q : write_merge_int;
    signal re   : write_merge_ext;
    
    signal in_dones : std_logic_vector(1 downto 0);
    
begin

fifos: for g in 0 to 3 generate
    -- xpm_fifo_sync: Synchronous FIFO
    -- Xilinx Parameterized Macro, version 2018.3
    -- Replaces the IP: fifo_dist_mem_element
    fifo : xpm_fifo_sync
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
            wr_en => r.fifos(g).push(0),
            wr_ack => open,
            din => r.fifos(g).data,
            rd_en => r.fifos(g).pull,
            dout => re.fifos(g).data,
            data_valid => open,
            empty => re.fifos(g).empty,
            almost_empty => re.fifos(g).almost_empty,
            prog_empty => open,
            full => re.fifos(g).full,
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
    end generate;

logic_proc: process(in_elems, last_val, r, re)
        variable v : write_merge_int;
    begin
        v      := r;
        
        -- default assignments
        v.next_elem.valid := '0';
        v.found_overflow := '0';
        v.overflow  := (others => '0');
        
        --compute done
        v.done :=  bool2sl(re.split_dones(1) = "1111");
        
        for l in 0 to SPMVP_OUTPUT_NUM - 1  loop
            v.fifos(l).pull := '0';
            v.done := v.done AND re.fifos(l).empty AND bool2sl(r.fifos(l).push = "0000");
        end loop;
        
        -- gather overflow signals
        if or_reduce(re.merge_overflows(0)) = '1' then
            v.found_overflow := '1';
            v.overflow(5 downto 0) := re.merge_overflows(0)(5 downto 0);
        end if;
        
        if or_reduce(re.split_overflows(0)(1 downto 0)) = '1' then
            v.found_overflow := '1';
            v.overflow(9 downto 8) := re.split_overflows(0)(1 downto 0);
        end if;
        
        if or_reduce(re.split_overflows(1)(1 downto 0)) = '1' then
            v.found_overflow := '1';
            v.overflow(11 downto 10) := re.split_overflows(1)(1 downto 0);
        end if;
        
        for l in 0 to SPMVP_OUTPUT_NUM - 1  loop
            if r.fifos(l).push(0) = '1' AND re.fifos(l).full = '1' then
                v.found_overflow := '1';
                v.overflow(12 + l) := '1';
            end if;
            -- control fifo inputs
            v.fifos(l).data    := std_logic_vector(re.split_out_elems(1)(l).addr) & re.split_out_elems(1)(l).field;
            v.fifos(l).push(0) := re.split_out_elems(1)(l).valid;
            v.fifos(l).push(3 downto 1) := r.fifos(l).push(2 downto 0);
            v.fifos(l).pull := NOT(re.fifos(l).almost_empty) OR (NOT(re.fifos(l).empty) AND NOT(r.fifos(l).pull));
        end loop;
        
        -- substitute one potential fifo output with the merge unit input (negate the pull from that fifo)
        if in_elems(MULT_NUM - 1).valid = '1' then
            v.next_elem := in_elems(MULT_NUM - 1);
            v.fifos(to_integer(in_elems(MULT_NUM - 1).addr(1 downto 0))).pull := '0';
        end if;
        for l in 0 to SPMVP_OUTPUT_NUM - 1  loop
            if r.next_elem.valid = '1' AND to_integer(r.next_elem.addr(1 downto 0)) = l then
                v.out_elems(l) := r.next_elem;
            else
                v.out_elems(l) := fifo_data2element(re.fifos(l), r.fifos(l).pull);
            end if; 
        end loop;

        q <= v;
    end process;
    
    in_dones <= last_val & last_val;
    
    -- The first merge stage has an odd number of input, so one input goes straight to the outputs
    re.merge_elems(0)(0) <= in_elems(0);
    re.merge_dones(0)(0) <= last_val;
    
    merge_stage0: for g in 0 to MULT_NUM/2 - 2 generate
        merge: entity work.merge2 port map(
            clk      => clk,
            reset    => reset,
            in_done  => in_dones,
            in_elems => in_elems(g*2 + 2 downto g * 2 + 1),
            out_elem => re.merge_elems(0)(g + 1),
            done     => re.merge_dones(0)(g+1),
            overflow => re.merge_overflows(0)(g*2 + 1 downto g * 2)
        );
    end generate;

    merge_stages_n0: for s in 1 to NUM_MERGE_STAGES - 1 generate
        merge_stage: for g in 0 to MULT_NUM/(2**(s+1)) - 1 generate
            merge: entity work.merge2 port map(
                clk      => clk,
                reset    => reset,
                in_done  => in_dones,
                in_elems => re.merge_elems(s-1)(g*2 + 2 downto g * 2 + 1),
                out_elem => re.merge_elems(s)(g + 1),
                done     => re.merge_dones(s)(g+1),
                overflow => re.merge_overflows(s)(g*2 + 1 downto g * 2)
            );
        end generate;
    end generate;
    
    stage_ins: for g in 0 to SPMVP_OUTPUT_NUM-1 generate
        re.split_in_elems(0)(g) <= re.merge_elems(NUM_MERGE_STAGES-1)(g);
        re.split_ready(0)(g) <= re.merge_dones(NUM_MERGE_STAGES-1)(g);
        stage_n0_ins: for s in 1 to NUM_SPLIT_STAGES - 1 generate
            re.split_in_elems(s)(g) <= re.split_out_elems(s-1)(sorting_connection(g, s-1, NUM_SPLIT_STAGES, false));
            re.split_ready(s)(g) <= re.split_dones(s-1)(sorting_connection(g, s-1, NUM_SPLIT_STAGES, false));
        end generate;
    end generate;
    
    split_stages:for s in 0 to NUM_SPLIT_STAGES - 1 generate
        split_stage: for g in 0 to SPMVP_OUTPUT_NUM/2 - 1  generate
            split: entity work.split2 generic map(
                COMPARE_INDEX => NUM_SPLIT_STAGES - 1 - s
            )port map(
                clk       => clk,
                reset     => reset,
                in_done   => re.split_ready(s)(2 * g + 1 downto 2 * g),
                in_elems  => re.split_in_elems(s)(2 * g + 1 downto 2 * g),
                even_elem => re.split_out_elems(s)(2 * g),
                odd_elem  => re.split_out_elems(s)(2 * g + 1),
                done      => re.split_dones(s)(2 * g + 1 downto 2 * g),
                overflow  => re.split_overflows(s)(g)
            );
        end generate;
    end generate;
    
    out_elems <= r.out_elems;
    done      <= r.done;
    overflow  <= r.overflow;
    found_overflow <= r.found_overflow;
    
clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= WRITE_MERGE_INT_INIT;
            else
                r <= q;
            end if;        
        end if;
    end process;
        
end architecture behavioral;
