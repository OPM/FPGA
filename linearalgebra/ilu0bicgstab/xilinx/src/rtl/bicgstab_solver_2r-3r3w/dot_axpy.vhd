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
    use ieee.std_logic_misc.all;

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.dot_axpy_pkg.all;

-- This unit performs one dot product, norm calculation or axpy operation. 
-- The start_op input signal selects between its different modes
-- This unit uses a dot_reduce unit to control the final adder in the dot 
-- product state to reduce all results of the adder tree into a single value.
-- Two of these units are instantiated in the vector_ops unit

entity dot_axpy is
    port (
        clk          : in std_logic;
        reset        : in std_logic;
        start_op     : in std_logic_vector(2 downto 0);
        last_val     : in std_logic;
        input_vect1  : in field_array(mult_range);
        input_valid1 : in std_logic;
        input_vect2  : in field_array(mult_range);
        input_valid2 : in std_logic;
        scaling_factor : in field;
        writing_ready : in std_logic;
        vect1_ready  : out std_logic;
        vect2_ready  : out std_logic;
        dot_output   : out field;
        axpy_output  : out field_array(mult_range);
        axpy_valid   : out std_logic_vector(mult_range);
        done         : out std_logic
        ; debug_encoded_state : out std_logic_vector(1 downto 0)
    );
end dot_axpy;

architecture behavioral of dot_axpy is

    component FP_adder_blocking is
        port(
            aclk                 : in std_logic;
            s_axis_a_tvalid      : in std_logic;
            s_axis_a_tready      : out std_logic;
            s_axis_a_tdata       : in field;
            s_axis_b_tvalid      : in std_logic;
            s_axis_b_tready      : out std_logic;
            s_axis_b_tdata       : in field;
            m_axis_result_tvalid : out std_logic;
            m_axis_result_tready : in std_logic;
            m_axis_result_tdata  : out field
        );
    end component;
    
    component FP_multiplier_blocking is
        port(
            aclk                 : in std_logic;
            s_axis_a_tvalid      : in std_logic;
            s_axis_a_tready      : out std_logic;
            s_axis_a_tdata       : in field;
            s_axis_b_tvalid      : in std_logic;
            s_axis_b_tready      : out std_logic;
            s_axis_b_tdata       : in field;
            m_axis_result_tvalid : out std_logic;
            m_axis_result_tready : in std_logic;
            m_axis_result_tdata  : out field
        );
    end component;

    signal r  : dot_axpy_int := DOT_AXPY_INT_INIT;
    signal q  : dot_axpy_int := DOT_AXPY_INT_INIT;
    signal re : dot_axpy_ext := DOT_AXPY_EXT_INIT;

begin

    mults: for g in 0 to MULT_NUM - 1 generate
        mult: component FP_multiplier_blocking port map(
            aclk                 => clk,
            s_axis_a_tvalid      => q.mults_valid(g)(0),
            s_axis_a_tready      => re.mults_ready(g)(0),
            s_axis_a_tdata       => q.mults_in(g)(0),
            s_axis_b_tvalid      => q.mults_valid(g)(1),
            s_axis_b_tready      => re.mults_ready(g)(1),
            s_axis_b_tdata       => q.mults_in(g)(1),
            m_axis_result_tvalid => re.mults_done(g),
            m_axis_result_tready => q.mults_ready(g),
            m_axis_result_tdata  => re.mults_out(g)
        );
    end generate;

    adds: for g in 0 to MULT_NUM - 1 generate
        add: component FP_adder_blocking port map(
            aclk                 => clk,
            s_axis_a_tvalid      => q.adds_valid(g)(0),
            s_axis_a_tready      => re.adds_ready(g)(0),
            s_axis_a_tdata       => q.adds_in(g)(0),
            s_axis_b_tvalid      => q.adds_valid(g)(1),
            s_axis_b_tready      => re.adds_ready(g)(1),
            s_axis_b_tdata       => q.adds_in(g)(1),
            m_axis_result_tvalid => re.adds_done(g),
            m_axis_result_tready => q.adds_ready(g),
            m_axis_result_tdata  => re.adds_out(g)
        );
    end generate;

    red: entity work.dot_reduce port map(
        clk      => clk,
        enable   => r.reduce_enable,
        data_in  => re.adds_out(MULT_NUM - 2),
        valid_in => re.adds_done(MULT_NUM - 2),
        last_val => r.reduce_last_val,
        result   => re.reduce_result,
        done     => re.reduce_done,
        
        add_inputs => re.reduce_add_data,
        add_valid  => re.reduce_add_valid,
        add_result => re.adds_out(MULT_NUM - 1),
        add_done   => re.adds_done(MULT_NUM - 1)
    );

    logic: process(r, re, start_op, input_vect1, input_valid1, input_vect2, input_valid2, last_val, scaling_factor, writing_ready)
        variable v : dot_axpy_int;
        variable in_offset, out_offset : natural;
        variable vect1_ready_var : std_logic;
        variable vect2_ready_var : std_logic;
    begin
        v := r;
        v.axpy_valid := (others => '0');
        v.done := '0';
        case r.state is
            when idle =>
				-- in the idle state, the dot_axpy unit is always ready to receive new input data
                vect1_ready_var := '1';
                vect2_ready_var := '1';
                v.last_val_set := '0'; 
                --v.adds_in := (others => (others => (others => '0')));
                v.adds_valid := (others => "00");
                v.reduce_enable := '0';
                v.last_val_set := '0';
                v.last_val_count := (others => '0');
                v.mults_ready := (others => '1');
                v.adds_ready := (others => '1');
                v.is_norm := '0';
                -- the start_op is one-hot, and decides between axpy, dot and norm operations
                if start_op(2) = '1' then
                    v.state := axpy;
                elsif start_op(0) = '1' then
                    v.state := dot;
                elsif start_op(1) = '1' then
                    v.is_norm := '1';
                    v.state := dot;
                end if;
            when dot =>
				-- The dot product has no ouput that can be not-ready, so the adders and multipliers can also always be ready
                v.mults_ready := (others => '1');
                v.adds_ready := (others => '1');
                v.reduce_enable := '1';
                -- connect to reduce block: the final adder is connected to the reducer unit
                v.adds_in(MULT_NUM - 1)    := re.reduce_add_data;
                v.adds_valid(MULT_NUM - 1) := re.reduce_add_valid;
                
                vect1_ready_var := '1';
                vect2_ready_var := '1';
                for l in 0 to MULT_NUM - 1 loop
                    vect1_ready_var := vect1_ready_var AND re.mults_ready(l)(0);
                    vect2_ready_var := vect2_ready_var AND re.mults_ready(l)(1);
                    -- forward input signals to output to be used by other dot_axpy unit
                    v.axpy_res(l)    := input_vect1(l);
                    v.axpy_valid(l)  := input_valid1;
                end loop;
                -- When the reducer unit is done, the entire dot product is.
                if re.reduce_done = '1' then
                    v.state := idle;
                    v.reduce_enable := '0';
                    v.adds_valid := (others => "00");
                    v.mults_valid := (others => "00");
                    --v.adds_in := (others => (others => (others => '0')));
                    v.done := '1';
                end if;
                
                if last_val = '1' then
                    v.last_val_set := '1';
                end if;

                if v.last_val_set = '1' AND r.last_val_count < REDUCE_TREE_DELAY AND writing_ready = '1' then
                    v.last_val_count := r.last_val_count + 1;
                end if;
                
                -- connect multipliers to inputsignals and first level of adder tree
                for l in 0 to MULT_NUM - 1 loop
                    v.mults_in(l)(0)           := input_vect1(l);
                    v.mults_valid(l)(0)        := input_valid1;
					-- A norm is just a dot where the first input vector is multiplied with itself
                    if r.is_norm = '1' then
                        v.mults_in(l)(1)           := input_vect1(l);
                        v.mults_valid(l)(1)        := input_valid1;
                    else 
                        v.mults_in(l)(1)           := input_vect2(l);
                        v.mults_valid(l)(1)        := input_valid2;
                    end if;
                    v.adds_in(l/2)(l mod 2)    := re.mults_out(l);
                    v.adds_valid(l/2)(l mod 2) := re.mults_done(l);
                end loop;
                -- build adder tree
                for l in 0 to MULT_DEPTH - 2 loop
                    in_offset  := MULT_NUM - 2**(l + 1);
                    out_offset := MULT_NUM - 2**(l + 2);
                    for k in 0 to 2**l-1 loop
                        v.adds_in(in_offset+k)(0)    := re.adds_out(out_offset + 2 * k);
                        v.adds_valid(in_offset+k)(0) := re.adds_done(out_offset + 2 * k);
                        v.adds_in(in_offset+k)(1)    := re.adds_out(out_offset + 2 * k + 1);
                        v.adds_valid(in_offset+k)(1) := re.adds_done(out_offset + 2 * k + 1);
                    end loop;
                end loop;
            when axpy =>
				-- The adder results are written to the output, and the multiplier results go into the adders
				-- connect the ready signals accordingly:
                for l in 0 to MULT_NUM - 1 loop
                    v.adds_ready(l) := writing_ready;
                    v.mults_ready(l) := re.adds_ready(l)(0);
                end loop;
                vect1_ready_var := '1';
                vect2_ready_var := '1';
                for l in 0 to MULT_NUM - 1 loop
                    vect1_ready_var := vect1_ready_var AND and_reduce(re.mults_ready(l));
                    vect2_ready_var := vect2_ready_var AND re.adds_ready(l)(1);
                end loop;
				-- set multiplier inputs: use either the incoming values or values stored during the previous stall as on input
				-- and the scaling factor as the other input
                for l in 0 to MULT_NUM - 1 loop
                    v.mults_valid(l) := "00";
                    v.mults_in(l)(1) := scaling_factor;
                    if re.mults_ready(0)(0) = '1' then
                        if input_valid1 = '1' then 
                            v.mults_valid(l) := "11";
                            v.mults_in(l)(0) := input_vect1(l);
                        elsif r.stored_val = '1' then
                            v.mults_valid(l) := "11";
                            v.stored_val := '0';
                        end if ;
                    else
						-- if a stall starts, store the values that were about to enter the multipliers:
                        if input_valid1 = '1' then 
                            v.stored_val := '1';
                            v.mults_in(l)(0) := input_vect1(l);
                        end if;
                    end if;
--                    v.mults_valid(l) := input_valid1 & input_valid1;
					-- set adder inputs and result signals:
					-- TODO: why are the adder inputs that come from the input ports not buffered in case of a stall like the multplier inputs are?
                    v.adds_in(l)(0)  := re.mults_out(l);
                    v.adds_valid(l)  := input_valid2 & re.mults_done(l);
                    v.adds_in(l)(1)  := input_vect2(l);
                    v.axpy_res(l)    := re.adds_out(l);
                    v.axpy_valid(l)  := re.adds_done(l) AND writing_ready;
                end loop;
                
                if last_val = '1' then
                    v.last_val_set := '1';
                end if;

                if v.last_val_set = '1' AND r.last_val_count < AXPY_DELAY AND writing_ready = '1' then -- causes issues(?): AND vect2_ready_var = '1'   --commit:9b2b07fc: used in ddr3 and later
                ---if v.last_val_set = '1' AND r.last_val_count < REDUCE_TREE_DELAY AND writing_ready = '1' then --commit:bdf44d0f: used in ddr0-2
                    v.last_val_count := r.last_val_count + 1;
                end if;
                
                if r.axpy_last_val = '1' then
                    v.state       := idle;
                    v.done        := '1';
                    --v.adds_in     := (others => (others => (others => '0')));
                    v.adds_valid  := (others => "00");
                    v.mults_valid := (others => "00");
					-- Explicitly empty the final adder, since it may be used by the reduce unit during the next do operation
                    v.adds_valid(MULT_NUM - 1) := "11";
                end if;
            when others =>
                -- must set variables to avoid latches --commit:9b2b07fc: used since ddr0
                vect1_ready_var := '1';
                vect2_ready_var := '1';
                v.state := idle;
        end case;
        
        v.axpy_last_val := bool2sl(r.last_val_count >= AXPY_DELAY);
        v.reduce_last_val := bool2sl(r.last_val_count >= REDUCE_TREE_DELAY);

        q <= v;
        
        -- assign output signals
        dot_output  <= re.reduce_result;
        axpy_output <= r.axpy_res;
        
        done        <= r.done;
        for l in 0 to MULT_NUM - 1 loop
            axpy_valid(l) <= r.axpy_valid(l);
        end loop;
        vect1_ready <= vect1_ready_var;
        vect2_ready <= vect2_ready_var;
        
        debug_encoded_state <= dot_axpy_state_encoding(r.state);
    end process;

reg: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= DOT_AXPY_INT_INIT;
            else
                r <= q;
            end if;
        end if;  
    end process;

end behavioral;
