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

package dot_axpy_pkg is

    constant AXPY_DELAY : integer := ADD_DELAY + MULT_DELAY + 2; --commit:9b2b07fc: used in ddr3 and later
    --constant AXPY_DELAY : integer := ADD_DELAY + 1; --commit:bdf44d0f: used in ddr0-2
    constant REDUCE_TREE_DELAY : integer := MULT_DELAY + MULT_DEPTH * (ADD_DELAY + 1);

    type dot_axpy_state is (idle, dot, axpy);
    
    type dot_axpy_state_encoding_type is array(dot_axpy_state) of std_logic_vector(1 downto 0);
    
    constant dot_axpy_state_encoding : dot_axpy_state_encoding_type :=(
        idle => "00",
        dot => "01",
        axpy => "10"
    ); 

    type op_input_type is array (1 downto 0) of field;

    type ops_inputs_type is array (mult_range) of op_input_type;
    type ops_valids_type is array (mult_range) of std_logic_vector(1 downto 0);

    type dot_axpy_int is record
        state           : dot_axpy_state;
        is_norm         : std_logic;
        stored_val      : std_logic;
        mults_in        : ops_inputs_type;
        mults_valid     : ops_valids_type;
        mults_ready     : std_logic_vector(mult_range);
        adds_in         : ops_inputs_type;
        adds_valid      : ops_valids_type;
        adds_ready      : std_logic_vector(mult_range);
        reduce_enable   : std_logic;
        last_val_set    : std_logic;
        last_val_count  : unsigned(7 downto 0);
        axpy_last_val   : std_logic;
        reduce_last_val : std_logic;
        axpy_res        : field_array(MULT_NUM - 1 downto 0);
        axpy_valid      : std_logic_vector(mult_range);
        done            : std_logic;
    end record;
    
    constant DOT_AXPY_INT_INIT : dot_axpy_int := (
        state       => idle,
        mults_in    => (others => (others => (others => '0'))),
        mults_valid => (others => "00"),
        mults_ready => (others => '0'),
        adds_in     => (others => (others => (others => '0'))),
        adds_valid  => (others => "00"),
        adds_ready  => (others => '0'),
        last_val_count => (others => '0'),
        axpy_res    => (others => (others => '0')),
        axpy_valid  => (others => '0'),
        others      => '0'
    );
    
    type dot_axpy_ext is record
        mults_done       : std_logic_vector(mult_range);
        mults_ready      : ops_valids_type;
        mults_out        : field_array(mult_range);
        adds_done        : std_logic_vector(mult_range);
        adds_ready       : ops_valids_type;
        adds_out         : field_array(mult_range);
        reduce_add_data  : op_input_type;
        reduce_add_valid : std_logic_vector(1 downto 0);
        reduce_result    : field;
        reduce_done      : std_logic;
    end record;
    
    constant DOT_AXPY_EXT_INIT : dot_axpy_ext := (
        mults_done => (others => '0'),
        mults_ready => (others => "00"),
        mults_out => (others => (others => '0')),
        adds_done => (others => '0'),
        adds_ready => (others => "00"),
        adds_out => (others => (others => '0')),
        reduce_add_data => (others => (others => '0')),
        reduce_add_valid => "00",
        reduce_result => (others => '0'),
        reduce_done => '0'
    );
    
    function make_valid (a : in field; valid : in std_logic) return field;
      
    type dr_state is (idle, tree, reduce, done_state); 
      
    type dr_int is record
        state      : dr_state;
        vals_in_add : unsigned(4 downto 0);
        prev_vals_in_add : unsigned(4 downto 0);
        add_inputs : op_input_type;
        add_valid  : std_logic_vector(1 downto 0);
        temp_res   : field;
        temp_valid : std_logic;
        result     : field;
        done       : std_logic;
      end record;

end package;

package body dot_axpy_pkg is

  function make_valid (a : in field; valid : in std_logic) return field is
    variable result : field;
  begin
    if valid = '1' then
      result := a;
    else
      result := (others => '0');
    end if;
    return result;
  end function make_valid;

end package body dot_axpy_pkg;
