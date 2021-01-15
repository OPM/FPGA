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
	use work.constants.all;
	use work.types.all;

package spmvp_pkg is

	-- One-dimensional arrays
    type tree_control_type is array(MULT_DEPTH - 1 downto 0) of std_logic_vector(mult_range);
    type tree_vals_type is array(MULT_DEPTH downto 0) of field_array(mult_range);
    type NRs_type is array(MULT_DEPTH - 1 downto 0) of offset_array(mult_range);
    type NR_flags_type is array(MULT_DEPTH - 1 downto 0) of std_logic_vector(mult_range);
    type add_offsets_type is array(mult_range) of unsigned(MULT_DEPTH + OFFSET_WIDTH - 1 downto 0);
    
    type spmvp_int is record
        offsets_valid      : std_logic_vector(MULT_DELAY + ADD_DELAY * MULT_DEPTH + 1 downto 0);
        addr_calc_NRs      : std_logic_vector(mult_range);
        connect_to_add     : tree_control_type;
        tree_out_addresses : row_index_array(mult_range);
        calc_addrs_NR_flags : std_logic_vector(mult_range);
        tree_out_NR_flags  : std_logic_vector(mult_range);
        tree_out_offsets   : add_offsets_type;
        is_last_val_set    : std_logic;
        last_val_timer     : unsigned(LAST_VAL_TIMER_DEPTH - 1 downto 0);
        last_val           : std_logic_vector(REDUCE_NUM downto 0);
        direct_wrs         : elem_array(MULT_NUM - 2 downto 0);
        reduce_address     : row_index;
        reduce_buff        : element;
        reduce_in_elem     : element;
        reduce_in_val      : field;
        out_addr_buff      : row_index_array(MULT_DEPTH - 2 downto 0);
        reduce_count       : unsigned(REDUCE_NUM downto 0);
		prev_reduce_addr   : row_index;
		found_reduce_overflow : std_logic;
		lost_value         : std_logic_vector(SPMVP_OUTPUT_NUM - 1 downto 0);
    end record;
    
    constant SPMVP_INT_INIT : spmvp_int := (
        (others => '0'),                -- offsets_valid
        (others => '0'),                -- addre_calc_NRs
        (others => (others => '0')),    -- connect_to_add
        (others => (others => '0')),    -- tree_out_addresses
        (others => '0'),                -- valc_addrs_NRs
        (others => '0'),                -- tree_out_NRs
        (others => (others => '0')),    -- tree_out_offsets
        '0',                            -- is_last_val_set
        (others => '0'),                -- last_val_timer
        (others => '0'),                -- last_val
        (others => ELEMENT_INIT),       -- direct_wrs
        (others => '1'),                -- reduce_address
        ELEMENT_INIT,                   -- reduce_buff
        ELEMENT_INIT,                   -- reduce_in_elem
        (others => '0'),                -- reduce_in_val
        (others => (others => '0'))     -- out_addr_buff
        , (others => '0')               -- reduce_count
		, (others => '0')               -- prev_reduce_addr
		, '0'							-- found_reduce_overflow
		, (others => '0')               -- lost_value
    );
    
    type spmvp_ext is record
        multiplicants       : field_array(mult_range);
        mult_valids         : std_logic_vector(mult_range);
        delayed_vals        : field_array(mult_range);
        delayed_valid       : std_logic;
        tree_stage_NRs      : NRs_type;
        tree_stage_NR_flags : NR_flags_type;
        tree_stage_offsets  : add_offsets_type;
        tree_stage_values   : tree_vals_type;
        tree_stage_valids   : std_logic_vector(MULT_DEPTH downto 0);
        -- synthesis translate_off
        overflow            : std_logic_vector(1 downto 0);
        -- synthesis translate_on
        merge_res           : elem_array(SPMVP_OUTPUT_NUM - 1 downto 0);
        reduce_out_elems    : elem_array(REDUCE_NUM - 1 downto 0);
        reduce_out_vals     : field_array(REDUCE_NUM - 2 downto 0);
        out_addr            : std_logic_vector(row_index_range);
        reduce_wr           : elem_array(MULT_NUM - 1 downto 0);
        done                : std_logic;
    end record;

end package;
