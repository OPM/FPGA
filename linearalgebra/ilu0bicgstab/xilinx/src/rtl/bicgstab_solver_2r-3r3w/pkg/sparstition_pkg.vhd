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
    use work.rw_pkg.all;
    use work.wm_pkg.all;

package sparstition_pkg is

	type sparstition_state is(
		idle,
        wait_for_sizes_read,
        wait_for_first_vector_read,
        wait_for_transfer,
        wait_for_P_vector_read,
		running,
		init_U,
		finished
	);
	
	type sparsetition_state_encoding_type is array(sparstition_state) of std_logic_vector(2 downto 0);
	
	constant sparstition_state_encoding : sparsetition_state_encoding_type := (
	    idle => "000",
        wait_for_sizes_read => "001",
        wait_for_first_vector_read => "010",
        wait_for_transfer => "011",
        wait_for_P_vector_read => "100",
		running => "101",
		init_U => "110",
		finished => "111"
	);
	
	type sparstition_read_in is record
	   data   : cacheline;
       valid  : std_logic;
       done   : std_logic;
	end record;
	
	type reads_in_array is array(integer range<>) of sparstition_read_in;

	type LU_state_type is(
	   spmvp,
	   l_fs,
	   u_bs
	);
	
	type LU_state_encoding_type is array(LU_state_type) of std_logic_vector(1 downto 0);
	
	constant LU_state_encoding : LU_state_encoding_type := (
	    spmvp => "11",
	    l_fs => "01",
	    u_bs => "10"
	);
	
	-- One-hot encoded constants for the different operations the ext_read and int_read units can perform:
	constant EXT_READ_SIZES     : std_logic_vector(3 downto 0) := "0001";
	constant EXT_READ_VECT_INDS : std_logic_vector(3 downto 0) := "0010";
	constant EXT_READ_MATRIX    : std_logic_vector(3 downto 0) := "0100";
	constant EXT_READ_DIAG      : std_logic_vector(3 downto 0) := "1000";
	constant INT_READ_VECT_VALS : std_logic_vector(3 downto 0) := "0001";
	constant INT_READ_P_VECT_L  : std_logic_vector(3 downto 0) := "0010";
	constant INT_READ_P_VECT_U  : std_logic_vector(3 downto 0) := "0100";
	constant INT_READ_TRANSFER  : std_logic_vector(3 downto 0) := "1000";

	type sparstition_int is record
	    read0_line          : cacheline;
	    read1_line          : cacheline;
	    read_fields         : field_array(1 downto 0);
		state               : sparstition_state;
		LU_state            : LU_state_type;
		
		current_color_sizes : sparstition_color_sizes;
		current_color       : unsigned(MAX_COLORS_DEPTH - 1 downto 0);
		next_color          : unsigned(MAX_COLORS_DEPTH - 1 downto 0);
		num_colors          : unsigned(MAX_COLORS_DEPTH - 1 downto 0);
		pull_fifos          : std_logic;
		fifos_read_addr     : sparstition_counter;
		spmvp_reset         : std_logic;
		ext_read_control    : std_logic_vector(3 downto 0);
	    current_ext_read    : std_logic_vector(3 downto 0);
		int_read_control    : std_logic_vector(3 downto 0);
		spmvp_valid         : std_logic_vector(SPMV_FIFO_LATENCY downto 0);
		spmvp_last_val      : std_logic;
        
        is_spmvp            : std_logic;
        write_activate      : std_logic;
        write_reset         : std_logic;
        write_flush         : std_logic;
        int_read_done       : std_logic;
		read_done           : std_logic;
		diag_read_done      : std_logic;

        write_done          : std_logic;
        is_U_bs             : std_logic;
        ilu0_field          : field;
        ilu0_valid          : std_logic;
        
        L_done              : std_logic;
        done                : std_logic;
        write_rq            : write_request_type;
        
        found_overflow      : std_logic;
        debug_overflow_bits : std_logic_vector(31 + SPMVP_OUTPUT_NUM downto 0);
	end record;
	
	constant SPARSTITION_INT_INIT : sparstition_int :=(
	    read0_line          => (others => '0'),
	    read1_line          => (others => '0'),
	    read_fields         => (others => (others => '0')), 
	    state               => idle,
	    LU_state            => spmvp,
	    current_color_sizes => (others => (others => '0')), 
	    current_color       => (others => '0'),
	    next_color          => (others => '0'),
	    num_colors          => (others => '0'),
	    fifos_read_addr     => (others => '0'),
	    spmvp_reset         => '1', 
	    ext_read_control    => (others => '0'),
	    current_ext_read    => (others => '0'),
	    int_read_control    => (others => '0'),
	    spmvp_valid         => (others => '0'), 
        done                => '0',
        ilu0_field          => (others => '0'),
	    write_rq            => WRITE_RQ_INIT,
	    debug_overflow_bits => (others => '0'),
	    others              => '0'
	);
	
	type sparstition_fifo_ext is record
	   full         : std_logic;
	   almost_full  : std_logic;
	   empty        : std_logic;
	   almost_empty : std_logic;
	   wr_rst_busy  : std_logic;
	   rd_rst_busy  : std_logic;
	   prog_full    : std_logic;
    end record;
	
	type sparstition_ext is record
        X_P_line            : cacheline;
        P_we                : std_logic;
        X_we                : std_logic;
        color_sizes_row     : std_logic_vector(MAT_SIZE_WIDTH - 1 downto 0);
        color_sizes_arow    : std_logic_vector(MAT_SIZE_WIDTH - 1 downto 0);
        color_sizes_col     : std_logic_vector(MAT_SIZE_WIDTH - 1 downto 0);
        color_sizes_val     : std_logic_vector(MAT_SIZE_WIDTH - 1 downto 0);
        color_sizes         : sparstition_color_sizes;
        nnz_vals_fifo_data  : field_array(mult_range);
        nnz_vals_fifo       : sparstition_fifo_ext;
        col_inds_fifo_data  : col_index_array(mult_range);
        col_inds_fifo       : sparstition_fifo_ext;
        NRs_fifo_data       : offset_array(mult_range);
        NRs_fifo            : sparstition_fifo_ext;
        read_dones          : std_logic_vector(3 downto 0);
        int_read_dones      : std_logic_vector(2 downto 0);
        read_wes            : read_wes_type;
        read_wr_addrs       : write_addrs_type;
        spmvp_res           : elem_array(SPMVP_OUTPUT_NUM - 1 downto 0);
        spmvp_done_up_to_addr : row_index;
        spmvp_done          : std_logic;
        write_field         : write_field_type;
        write_ready         : std_logic;
        write_done          : std_logic;
        ilu0_last_val       : std_logic;
        ilu0_in_elem        : element;
        ilu0_out_elem       : element;
        ilu0_done           : std_logic;
        read_interrupt      : std_logic;
        
        found_merge_overflow : std_logic;
        merge_overflow     : std_logic_vector(15 downto 0);
        found_write_overflow : std_logic;
        write_overflow     : std_logic_vector(7 downto 0);
        found_reduce_overflow : std_logic;
        found_ilu0_fifo_overflow : std_logic;
        spmvp_lost_value   : std_logic_vector(SPMVP_OUTPUT_NUM - 1 downto 0);
	end record;
	
	type ilu0_int is record
	    ready           : std_logic;
	    U_active        : std_logic;
	    fifo_pull       : std_logic_vector(5 downto 0);
	    fifo_count      : unsigned(ADD_DELAY_DEPTH - 1 downto 0);
	    diag_read_addr  : row_index;
	    diag_write_addr : row_index;
	    p_write_addr    : row_index;
	    next_sub_in     : field;
	    sub_in          : field;
        sub_valid       : std_logic;
        next_aggrs      : field_array(1 downto 0);
        aggregates      : field_array(2 downto 0);
        aggr_valids     : std_logic_vector(2 downto 0);
        aggr_count      : integer range 0 to 2;
	    write_elem      : element;
	    spmvp_done      : std_logic;
	    read_interrupt  : std_logic_vector(15 downto 0);
	    done_count      : unsigned(7 downto 0);
	    done            : std_logic;
	end record;
	
	constant ILU0_INT_INIT : ilu0_int := ( 
           '0',                         -- ready           
           '0',                         -- U_active
           "000000",                    -- fifo_pull
           (others => '0'),             -- fifo_count
           (others => '0'),             -- diag_read_addr
           (others => '0'),             -- diag_write_addr 
           (others => '0'),             -- p_write_addr
           (others => '0'),             -- next_sub_in
           (others => '0'),             -- sub_in      
           '0',                         -- sub_valid
           (others => (others => '0')), -- next_aggrs
           (others => (others => '0')), -- aggregates
           "000",                       -- aggr_valids
           0,                           -- aggr_count
           ELEMENT_INIT,                -- write_elem
           '0',                         -- spmvp_done
           (others => '0'),             -- read_interrrupt
           (others => '0'),             -- done_count
           '0'                          -- done
    );
	
	type ilu0_ext is record
	    fifo           : wm_fifo_out_type;
	    p_value        : field;
	    diag_read_addr : std_logic_vector(row_index_range);
	    sub_res        : field;
	    sub_valid      : std_logic;
	    diag_vals      : std_logic_vector(4 * FIELD_WIDTH - 1 downto 0);
	    write_addr     : std_logic_vector(row_index_range);
	    mult_res       : field_array(2 downto 0);
	    mult_valid     : std_logic_vector(2 downto 0);
	    delayed_mult2  : field;
	    add0_res       : field;
	    add0_valid     : std_logic;
        add1_res       : field;
        add1_valid     : std_logic;
        -- Dummy signal added to circumvent xsim internal memory bug
        dummy_signal   : field;
	end record;

end package;
