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

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.spmvp_pkg.all;

-- This unit is the SpMV pipeline, the unit that performs the SpMV calculations
-- It consists of the multiplicant replication buffer, a series of parallel 
-- multiplier IP cores, an Select-Adder Tree built from multiple tree_stage units, 
-- NRs_fifo units and an NR2offset unit to provide the New row data, a reduce unit
-- built from reduce_stage units, and a write_merge unit.
-- This unit is instantiated by the sparstitioning unit.

entity spmvp is
    port( 
        clk             : in std_logic;
        reset           : in std_logic;
        last_val        : in std_logic;
        X_P_line        : in cacheline;
        multiplicant_we : in std_logic;
        in_vals         : in field_array(mult_range);
        in_col_indices  : in col_index_array(mult_range);
        in_NRs          : in offset_array(mult_range);
        in_valid        : in std_logic;
        res_elems       : out elem_array(SPMVP_OUTPUT_NUM - 1 downto 0);
        done_up_to_addr : out row_index;
        done            : out std_logic
        ; found_merge_overflow : out std_logic
		; merge_overflow : out std_logic_vector(15 downto 0)
		; found_reduce_overflow : out std_logic
		; lost_value     : out std_logic_vector(SPMVP_OUTPUT_NUM - 1 downto 0)
    );
end spmvp;

architecture behavioural of spmvp is

    constant ZERO_FIELD : field := (others => '0');

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
    
    component FP_multiplier is
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
        
    signal r, q : spmvp_int;
    signal re   : spmvp_ext;
    
    signal mrb_debug_error : std_logic_vector(0 downto 0);
    signal debug_X_P_line_fields : field_array(NUM_FIELDS_PER_LINE - 1 downto 0);
    
begin

debug_X_P: for l in 0 to NUM_FIELDS_PER_LINE - 1 generate
        debug_X_P_line_fields(l) <= index(X_P_line, l, FIELD_WIDTH);
    end generate;
        
m_buff: entity work.multiplicant_replication_buffer
        port map(
            clk        => clk,
            reset      => reset,
            in_line    => X_P_line,
            we         => multiplicant_we,
            read_addrs => in_col_indices,
            in_vals    => in_vals,
            in_valid   => in_valid,
            read_outs  => re.multiplicants,
            out_vals   => re.delayed_vals,
            out_valid  => re.delayed_valid,
            debug_error => mrb_debug_error
        );
        
mults: for g in 0 to MULT_NUM - 1 generate
    mult: FP_multiplier 
            port map(
                aclk                 => clk,
                s_axis_a_tvalid      => re.delayed_valid,
                s_axis_a_tdata       => re.delayed_vals(g),
                s_axis_b_tvalid      => re.delayed_valid,
                s_axis_b_tdata       => re.multiplicants(g),
                m_axis_result_tvalid => re.mult_valids(g),
                m_axis_result_tdata  => re.tree_stage_values(0)(g)
            );
    end generate;

re.tree_stage_valids(0) <= re.mult_valids(0);

mult_NR_fifo: entity work.NRs_fifo
        generic map(
            DELAY             => MULT_DELAY
        )
        port map(
            clk     => clk,
            reset   => reset,
            inputs  => in_NRs,
            outputs => re.tree_stage_NRs(0)
        );

NR_fifos: for stage in 0 to MULT_DEPTH - 2 generate
    NR_fifo: entity work.NRs_fifo
            generic map(
                DELAY             => ADD_DELAY
            )
            port map(
                clk     => clk,
                reset   => reset,
                inputs  => re.tree_stage_NRs(stage),
                outputs => re.tree_stage_NRs(stage + 1),
                out_flags => re.tree_stage_NR_flags(stage)
            );

    end generate;
    
NR_offset: entity work.NR2offset
        port map(
            clk      => clk,
            reset    => reset,
            inputs   => re.tree_stage_NRs(MULT_DEPTH - 1),
            out_NRs  => re.tree_stage_NR_flags(MULT_DEPTH - 1),
            offsets  => re.tree_stage_offsets
        );
    
tree_stgs: for stage in 0 to MULT_DEPTH - 1 generate 
    tree_stg: entity work.tree_stage
            generic map(
                STAGE_NUM        => stage
            )
            port map(
                clk         => clk,
                reset       => reset,
                in_valid    => re.tree_stage_valids(stage),
                in_values   => re.tree_stage_values(stage),
                add_connect => r.connect_to_add(stage),
                out_valid   => re.tree_stage_valids(stage + 1),
                out_values  => re.tree_stage_values(stage + 1)
            );
    end generate;

red_stg0: entity work.reduce_stage
        port map(
            clk       => clk,
            reset     => reset,
            last_val  => r.last_val(1),
            add_elem  => r.reduce_in_elem,
            add_val   => r.reduce_in_val,
            next_elem => re.reduce_out_elems(0),
            next_val  => re.reduce_out_vals(0)
        );

red_stgs: for stage in 1  to REDUCE_NUM - 2 generate   
    red_stg: entity work.reduce_stage
            port map(
                clk       => clk,
                reset     => reset,
                last_val  => r.last_val(stage + 1),
                add_elem  => re.reduce_out_elems(stage - 1),
                add_val   => re.reduce_out_vals(stage - 1),
                next_elem => re.reduce_out_elems(stage),
                next_val  => re.reduce_out_vals(stage)
            );
    end generate;
    
last_stg_add: FP_adder
        port map(
            aclk => clk,
            s_axis_a_tvalid      => re.reduce_out_elems(REDUCE_NUM - 2).valid,
            s_axis_a_tdata       => re.reduce_out_elems(REDUCE_NUM - 2).field,
            s_axis_b_tvalid      => re.reduce_out_elems(REDUCE_NUM - 2).valid,
            s_axis_b_tdata       => re.reduce_out_vals(REDUCE_NUM - 2),
            m_axis_result_tvalid => re.reduce_wr(MULT_NUM - 1).valid,
            m_axis_result_tdata  => re.reduce_wr(MULT_NUM - 1).field
        );
        
last_stg_mem: entity work.delay_pipe
        generic map(
            delay => ADD_DELAY,
            delay_depth => ADD_DELAY_DEPTH,
            width => ROW_INDEX_WIDTH
        )
        port map(
            clk      => clk,
            reset    => reset,
            in_data  => std_logic_vector(re.reduce_out_elems(REDUCE_NUM - 2).addr),
            out_data => re.out_addr
        );
    re.reduce_wr(MULT_NUM - 1).addr <= unsigned(re.out_addr);        
    
    re.reduce_wr(MULT_NUM - 2 downto 0)  <= r.direct_wrs(MULT_NUM - 2  downto 0);

wr_merge: entity work.write_merge
        port map(
            clk       => clk,
            reset     => reset,
            last_val  => r.last_val(REDUCE_NUM),
            in_elems  => re.reduce_wr,
            out_elems => re.merge_res,
            done      => re.done
            , found_overflow => found_merge_overflow
            , overflow => merge_overflow
        );  

logic_proc: process(r, re, last_val) -- 
        variable v               : spmvp_int;
        variable current_index   : natural;
        variable add_port2_index : natural;
    begin
        v := r;
        
        v.found_reduce_overflow := '0';      
        
        -- generate offset_valid signal:
        v.offsets_valid := v.offsets_valid(MULT_DELAY + ADD_DELAY * MULT_DEPTH downto 0) & re.delayed_valid;
        
        -- General tree control signals from the NR flags:
        -- NOTE: for this to work, the offsets need to enter this entity one cycle before their associated multiply results
        -- Go over all tree stages
        for stage in 0 to MULT_DEPTH - 1 loop
            -- go over all adders in that stage
            for adder in 0 to MULT_NUM / (2 ** (stage + 1)) - 1 loop
                -- go outward from the vales going into the adder to the values on the edge of the adder's range
                -- connect that value to the adder if all NR between it and the second add in port's are '0'
                add_port2_index := adder * (2 ** (stage + 1)) + (2 ** stage);
                -- values going into the adder:
                v.connect_to_add(stage)(add_port2_index - 1) := NOT(re.tree_stage_NR_flags(stage)(add_port2_index));
                v.connect_to_add(stage)(add_port2_index)     := NOT(re.tree_stage_NR_flags(stage)(add_port2_index));
                for value in 1 to (2 ** stage) - 1 loop
                    -- values before the adder
                    current_index := add_port2_index - value - 1;
                    v.connect_to_add(stage)(current_index)   := v.connect_to_add(stage)(current_index + 1) AND NOT(re.tree_stage_NR_flags(stage)(current_index + 1));
                    -- values after the adder
                    current_index := add_port2_index + value;
                    v.connect_to_add(stage)(current_index)   := v.connect_to_add(stage)(current_index - 1) AND NOT(re.tree_stage_NR_flags(stage)(current_index));
                end loop;
            end loop;
        end loop;
        
        -- update addresses
        for value in 0 to MULT_NUM - 1 loop
            if r.offsets_valid(MULT_DELAY + ADD_DELAY * MULT_DEPTH + 1) = '1' then
                v.tree_out_addresses(value) := r.reduce_address + re.tree_stage_offsets(value);
            else
                v.tree_out_addresses(value) := r.reduce_address;
            end if;
        end loop;
        
        v.reduce_address := v.tree_out_addresses(MULT_NUM - 1);
        
        v.calc_addrs_NR_flags   := re.tree_stage_NR_flags(MULT_DEPTH - 1);
        v.tree_out_NR_flags     := r.calc_addrs_NR_flags;
        v.tree_out_offsets  := re.tree_stage_offsets;
        -- Calculate whether each element is an output signal
        for value in 0 to MULT_NUM - 2 loop
            v.direct_wrs(value).field := re.tree_stage_values(MULT_DEPTH)(value);
            v.direct_wrs(value).addr := r.tree_out_addresses(value);
            v.direct_wrs(value).valid := bool2sl(r.tree_out_NR_flags(value) = '1' AND 
                                                r.tree_out_offsets(value) /= r.tree_out_offsets(MULT_NUM - 1)) AND
                                                re.tree_stage_valids(MULT_DEPTH);
        end loop;
        
        -- Set first reduce buffer behaviour
        if r.tree_out_offsets(MULT_NUM - 1) /= 0 AND re.tree_stage_valids(MULT_DEPTH) = '1' then
            -- if the last tree result is in a different row than the first: store it in the buffer
            v.reduce_buff.field  := re.tree_stage_values(MULT_DEPTH)(MULT_NUM - 1);
            v.reduce_buff.valid := '1';
            v.reduce_buff.addr  := r.tree_out_addresses(MULT_NUM - 1);
        elsif r.tree_out_NR_flags(0) = '0' AND r.reduce_buff.valid = '0' AND re.tree_stage_valids(MULT_DEPTH) = '1'  then -- AND r.last_val(0) = '0'
            -- if the first tree result is in the same row as the previous cycle's last tree result,
            -- and if nothing is currently stored in the buffer AND there is no direct write-through 
            -- of the last val: store that result in the buffer            
            v.reduce_buff.field := re.tree_stage_values(MULT_DEPTH)(MULT_NUM - 1);
            v.reduce_buff.valid := '1';
            v.reduce_buff.addr  := r.tree_out_addresses(MULT_NUM - 1);
        elsif re.tree_stage_valids(MULT_DEPTH) = '1' OR (r.reduce_buff.valid = '1' AND r.last_val(0) = '1') then
            -- else, so if a value will be sent straight through to the reduce unit without needing buffering,
            -- invalidate the buffer
            v.reduce_buff.valid := '0';
        end if;
        
        -- Generate first reduce stage adder input signals
        v.reduce_in_elem := r.reduce_buff;
        v.reduce_in_val  := ZERO_FIELD;
        v.reduce_in_elem.valid := r.reduce_buff.valid AND (re.tree_stage_valids(MULT_DEPTH) OR r.last_val(0));
         
        if r.reduce_buff.valid = '1' AND r.tree_out_NR_flags(0) = '0' AND re.tree_stage_valids(MULT_DEPTH) = '1' then -- Why was this also here? :  OR r.last_val(0) = '1'
            -- if something is stored in the buffer, and the address first element of the 
            -- current cycle matches the address of the last element of the last cycle:
            -- put that value into the reduce stage.
            v.reduce_in_val := re.tree_stage_values(MULT_DEPTH)(0);
        elsif r.reduce_buff.valid = '0' AND (r.tree_out_NR_flags(0) = '0' AND r.tree_out_offsets(MULT_NUM - 1) /= 0) then -- OR r.last_val(0) = '1')
            -- if nothing is stored in the buffer, and a value of a row that ends this cycle is coming in,
            -- send that value straight through to the reduce unit.
            v.reduce_in_elem.field := re.tree_stage_values(MULT_DEPTH)(0);
            v.reduce_in_elem.valid := re.tree_stage_valids(MULT_DEPTH);
            v.reduce_in_elem.addr  := r.tree_out_addresses(0);
        end if;    
        
        -- DEBUG: detect an overflow of the reduce unit.
		if r.reduce_in_elem.valid = '1' then
		    v.prev_reduce_addr := r.reduce_in_elem.addr;
			if r.prev_reduce_addr = r.reduce_in_elem.addr then
				v.reduce_count := r.reduce_count + 1;
			else
				v.reduce_count := to_unsigned(1, REDUCE_NUM + 1);
			end if;
		end if;
		if r.reduce_count > MAX_REDUCE_LINES / 2 then
			v.found_reduce_overflow := '1';
		end if;
        
        -- Set the last_val signals for all reduce stages
        if last_val = '1' then
            v.is_last_val_set := '1';
        end if;
        if r.is_last_val_set = '1' AND r.last_val_timer < LAST_VAL_TIMES(REDUCE_NUM) then 
            v.last_val_timer  := r.last_val_timer + 1;
        end if;
        for l in 0 to REDUCE_NUM loop 
            v.last_val(l)     := bool2sl(r.last_val_timer >= LAST_VAL_TIMES(l));
        end loop;
        
        v.out_addr_buff(0) := re.reduce_wr(MULT_NUM - 1).addr;

        for l in 0 to MULT_DEPTH - 3 loop
            v.out_addr_buff(l + 1) := r.out_addr_buff(l);
        end loop;
        
        if re.done = '1' then
            done_up_to_addr <= r.reduce_address + to_unsigned(1, ROW_INDEX_WIDTH);
        else
            done_up_to_addr <= r.out_addr_buff(MULT_DEPTH - 2);
        end if;
        -- Output signals;
        done <= re.done;
        found_reduce_overflow <= r.found_reduce_overflow;
        
        for l in 0 to SPMVP_OUTPUT_NUM - 1 loop
            if re.merge_res(l).valid = '1' AND re.merge_res(l).addr < r.out_addr_buff(MULT_DEPTH - 2) then
                v.lost_value(l) := '1';
            end if;
        end loop;

        lost_value <= r.lost_value;
        res_elems <= re.merge_res;
        q <= v;    
    end process;

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= SPMVP_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;

end architecture behavioural;
