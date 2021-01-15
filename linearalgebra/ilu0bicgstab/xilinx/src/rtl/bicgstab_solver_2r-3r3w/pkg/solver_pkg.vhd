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

library ieee_proposed;
    use ieee_proposed.float_pkg.all;
    use ieee_proposed.fixed_pkg.all;
    use ieee_proposed.fixed_float_types.all;

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.rw_pkg.all;
    use work.sparstition_pkg.all;

package solver_pkg is

    constant ALREADY_SOLVED_PRECISION : field := to_slv(to_float(ALREADY_SOLVED_THRESHOLD,11,52,round_nearest,false));

    type solver_state is (
        idle,
        init_read,
        read_x,
        SpMV,
        ILU0_L_fs,
        ILU0_U_bs,
        calc_p,
        dot1,
        dot2,
        axpy1, 
        axpy2
        , write_debug
    );
    
	type solver_state_encoding_type is array(solver_state) of std_logic_vector(3 downto 0);

    constant solver_state_encoding : solver_state_encoding_type := (
        idle => "0000",
        init_read => "0001",
        read_x => "0010",
        SpMV => "0011",
        ILU0_L_fs => "0101",
        ILU0_U_bs => "0110",
        calc_p => "0111",
        dot1 => "1000",
        dot2 => "1001",
        axpy1 => "1010",
        axpy2 => "1011"
        , write_debug => "1100"
    );

    type debug_state_type is (idle, count, write);
	
    constant MAX_ITERATIONS : integer := 1;

	-- The constants and types below are all related to the PROGRAM, a constant that largely controls the behaviour of the solver finite state machine
	
	  
    type matrix_sel_type is (SpMV, L_FS, U_BS, XXXX);
	
    type vector_sel_type is (vect_p1, vect_p2, vect_r1, vect_r2, vect_rt, vect_t, vect_v, vect_x1, vect_x2, vect_y, res_L, res_U, U); 
    type vects_sel_type is array (2 downto 0) of vector_sel_type;
	-- * A selector for which scalar value should be used or should be written to in a state
    type field_sel_type  is (alpha, omega, rho, rho_new, beta, norm, one, precision, U);
	-- * A selector for the selection criterion by which the next state should be chosen    
    type state_sel_criterion is (is_first_iter, is_even_iter, is_half_iter, is_final_iter, none);
    
	-- The PROGRAM consists of program steps, each of which contains:
    type program_step is record
		-- * Which state of the finite state machine this program step is in
        state          : solver_state;
		-- * A selector for which matrix data (if any) should be read during this step
        matrix         : matrix_sel_type;
		-- * Selectors for which vectors (if any) should be read during this step
        read_vects     : vects_sel_type;
		-- * Flags to select which read ports (if any) are used during this step
        active_reads   : std_logic_vector(2 downto 0);
		-- * A vect_ops unit specific, 1-hot encoding value to indicate which fifo in that unit read port 1 is connected to
        port1_sel      : std_logic_vector(2 downto 0);
		-- * Selectors for which vectors (if any) should be written during this step
        write_vects    : vects_sel_type;
		-- * Flags to select which write ports (if any) are used during this step
        active_writes  : std_logic_vector(2 downto 0);
		-- * A selector for which scalar value should be used as the scaling factor during an axpy vector operation
        scaling_factor : field_sel_type;
		-- * A boolean to decide whether the scalar of an axpy vector operation should be multiplied by -1 or not
        minus_scale    : std_logic;
		-- * A selector for to which scalar value the result of a dot product vector operation should be written
        dot_res        : field_sel_type;
		-- * The first of two possible steps that could come after the current one.
        next_step0     : unsigned(4 downto 0);
		-- * The second of two possible steps that could come after the current one.
        next_step1     : unsigned(4 downto 0);
		-- * A selector for the criterion by which one of the two possible next steps should be chosen. 
        criterion      : state_sel_criterion;
		-- * A number to differentiate the current step (for debugging processes only)
        debug_num      : integer;
    end record;

    type program_type is array(0 to 18) of program_step;

    constant PROGRAM : program_type := (
    --   state     matrix  r_vect3  r_vect2  r_vect1   a_r    p1s    write3   write2   write1    a_w   sf    minus dot_res   next_step0          next_step1         criterion
        (SpMV,      SpMV, (U,      U,       U),       "000", "000", (vect_v, U,       U),       "100", U,     '0', U,       to_unsigned(1, 5),  to_unsigned(1, 5),  none            , 0),          -- apply_scale_add part 1
        (axpy2,     XXXX, (vect_v, U,       vect_r1), "101", "010", (U,      vect_rt, U),       "010", one,   '1', rho_new, to_unsigned(2, 5),  to_unsigned(2, 5),  none            , 1),          -- apply_scale_add part 2. Includes dot product that calculates first rho_new
        (ILU0_L_fs, L_FS, (U,      U,       U),       "000", "000", (res_L,  U,       U),       "000", U,     '0', U,       to_unsigned(3, 5),  to_unsigned(3, 5),  none            , 2),          -- the forward substitution: always followed by backward substitution
        (ILU0_U_bs, U_BS, (U,      U,       U),       "000", "000", (res_U,  U,       U),       "000", U,     '0', U,       to_unsigned(4, 5),  to_unsigned(9, 5),  is_half_iter    , 3),  -- the backward substitution: followed by either spmvp, depending on the half iteration count
        (SpMV,      SpMV, (U,      U,       U),       "000", "000", (vect_v, U,       U),       "100", U,     '0', U,       to_unsigned(5, 5),  to_unsigned(5, 5),  none            , 4),          -- the SpMVP in the first half iteration. 
        (dot1,      XXXX, (vect_v, vect_rt, U),       "110", "000", (U,      U,       U),       "000", U,     '0', alpha,   to_unsigned(6, 5),  to_unsigned(6, 5),  none            , 5),          -- the dot product in the first half iteration. Calculates alpha.
        (axpy1,     XXXX, (U,      vect_x1, U),       "010", "000", (U,      U,       vect_x2), "001", alpha, '0', U,       to_unsigned(8, 5),  to_unsigned(7, 5),  is_first_iter   , 6), -- the first axpy in the first half iteration. Followed by an axpy, which either is or is not in the first iteration
        (axpy2,     XXXX, (vect_v, vect_rt, U),       "110", "000", (U,      vect_r2, U),       "010", alpha, '1', norm,    to_unsigned(2, 5),  to_unsigned(18, 5), is_final_iter   , 7),          -- the second axpy in the first half of the first iteration. Reads from rt and writes to r.
        (axpy2,     XXXX, (vect_v, U,       vect_r1), "101", "010", (U,      vect_r2, U),       "010", alpha, '1', norm,    to_unsigned(2, 5),  to_unsigned(18, 5), is_final_iter   , 8),          -- the second axpy in the first half of any other iteration. Reads and writes to and from r.
        (SpMV,      SpMV, (U,      U,       U),       "000", "000", (vect_t, U,       U),       "100", U,     '0', U,       to_unsigned(10, 5), to_unsigned(10, 5), none            , 9),          -- the SpMVP in the second half iteration
        (dot2,      XXXX, (vect_t, vect_r2, U),       "110", "000", (U,      U,       U),       "000", U,     '0', omega,   to_unsigned(11, 5), to_unsigned(11, 5), none            , 10),          -- the two dot products in the second half iteration
        (axpy1,     XXXX, (U,      U,       vect_x2), "001", "010", (U,      vect_x1, U),       "010", omega, '0', U,       to_unsigned(12, 5), to_unsigned(12, 5), none            , 11),          -- the first axpy in the second half iteration
        (axpy2,     XXXX, (vect_t, vect_r2, U),       "110", "000", (U,      U,       vect_r1), "001", omega, '1', norm,    to_unsigned(14, 5), to_unsigned(13, 5), is_first_iter   , 12),          -- the second axpy int the second half iteration
        (dot1,      XXXX, (U,      vect_rt, vect_r1), "011", "001", (U,      U,       U),       "000", U,     '0', beta,    to_unsigned(15, 5), to_unsigned(15, 5), none            , 13),  -- the r * rt dot product that precedes the p_vector update 
        (dot1,      XXXX, (U,      vect_rt, vect_r1), "011", "001", (U,      U,       U),       "000", U,     '0', beta,    to_unsigned(16, 5), to_unsigned(17, 5), is_even_iter    , 14),  -- the r * rt dot product that precedes the p_vector update 
        (calc_p,    XXXX, (vect_v, vect_rt, vect_r1), "111", "100", (U,      vect_p2, U),       "010", omega, '1', beta,    to_unsigned(2, 5),  to_unsigned(2, 5),  none            , 15),
        (calc_p,    XXXX, (vect_v, vect_p1, vect_r1), "111", "100", (U,      vect_p2, U),       "010", omega, '1', beta,    to_unsigned(2, 5),  to_unsigned(2, 5),  none            , 16),          -- the p_vector update after the first iteration (p has not yet been initialized. Read rt instead)
        (calc_p,    XXXX, (vect_v, vect_p2, vect_r1), "111", "100", (U,      vect_p1, U),       "010", omega, '1', beta,    to_unsigned(2, 5),  to_unsigned(2, 5),  none            , 17)           -- the p_vector update after any other iteration
        , (write_debug, XXXX, (U,  U,       U),       "000", "000", (U,      U,       U),       "000", U,     '0', U,       to_unsigned(0, 5),  to_unsigned(0, 5),  none            , 18)           -- a debug state strictly for ending the program early.
    );
    
    type solver_read_port_ins is record
        rq_idle           : std_logic;
        rq_ready          : std_logic;
        rq_end            : std_logic;
        fifo_data         : std_logic_vector(511 downto 0);
        fifo_almost_empty : std_logic;
        fifo_empty        : std_logic;
    end record;
    
    type read_ports_ins_array is array(integer range <>) of solver_read_port_ins;
    
    type solver_read_port_outs is record
        rq_address        : std_logic_vector(63 downto 0);
        rq_size           : std_logic_vector(31 downto 0);
        rq_start          : std_logic;
        fifo_pull         : std_logic;
    end record;
    
    type read_ports_outs_array is array(integer range <>) of solver_read_port_outs;
    
    type solver_write_port_ins is record
        rq_idle          : std_logic;
        rq_ready         : std_logic;
        rq_end           : std_logic;
        fifo_almost_full : std_logic;
        fifo_full        : std_logic;
    end record;
    
    type write_ports_ins_array is array(integer range <>) of solver_write_port_ins;

    type solver_write_port_outs is record
        rq_address       : std_logic_vector(63 downto 0);
        rq_size          : std_logic_vector(31 downto 0);
        rq_start         : std_logic;
        fifo_data        : std_logic_vector(511 downto 0);
        fifo_push        : std_logic;
    end record;
    
    type write_ports_outs_array is array(integer range <>) of solver_write_port_outs;
    
    type vector_addresses is array(vector_sel_type) of cpu_address;
    type matrix_sizes_type is array(matrix_sel_type) of sparstition_sizes;
    type matrix_addresses is array(matrix_sel_type) of sparstition_addresses;
    type fields_type is array(field_sel_type) of field;
    type criteria_type is array(state_sel_criterion) of std_logic;
    
    type read_lines_type is array (0 to 2) of cacheline;
    type addr_lsb_delay_type is array(INT_VECTOR_MEM_LATENCY downto 0) of unsigned(2 downto 0);
    type read_fifo_valids_array is array(integer range <>) of std_logic_vector(READ_FIFO_LATENCY downto 0);
    
	type vector_ops_sel_type is (dot1, dot2, axpy1, axpy2, update_p);

    type counts_array is array(integer range <>) of unsigned(15 downto 0);

    type solver_int is record
        state           : solver_state;
        init_read_count : std_logic_vector(2 downto 0);
        vector_addrs    : vector_addresses;
        next_step       : program_step;
        current_step    : program_step;
        first_cycle     : std_logic;
        first_iteration : std_logic;
        iter_num        : unsigned(15 downto 0);
        iteration_end   : std_logic;
        do_reset_debug  : std_logic;
        absolute_compare : std_logic;
        
        state_done      : std_logic;
        calc_done       : std_logic;
        divide_set      : std_logic;
        multiply_set    : std_logic;
        no_change       : std_logic;
        write_dones     : std_logic_vector(NUM_HBM_WRITE_PORTS - 1 downto 0);
        write_sel       : std_logic_vector(NUM_HBM_WRITE_PORTS - 1 downto 0);

        sparse_start   : std_logic;
        apply_ILU0     : std_logic;
        matrix_sizes   : matrix_sizes_type;
        sparse_sizes   : sparstition_sizes;
        matrix_addrs   : matrix_addresses;
        sparse_addrs   : sparstition_addresses;
        fields         : fields_type;
        criteria       : criteria_type;
        field_re       : std_logic_vector(1 downto 0);
        
        next_read_dones : std_logic_vector(NUM_READ_PORTS - 1 downto 0);
        read_dones      : std_logic_vector(NUM_READ_PORTS - 1 downto 0);
        read_rq_done          : std_logic_vector(NUM_READ_PORTS - 1 downto 0);
        read_vect_addr        : cpu_addr_array(NUM_HBM_READ_PORTS - 1 downto 0);
        
        dot_axpy_start    : std_logic;
        vect_op_sel       : vector_ops_sel_type;

        -- URAM signals
        URAM_enable      : std_logic;
        URAM_addr1       : vector_address;
        URAM_we1         : std_logic_vector(63 downto 0);
        URAM_in_data1    : cacheline;
        URAM_addr2       : vector_address;
        URAM_we2         : std_logic_vector(63 downto 0);
        URAM_in_data2    : cacheline;
        debug_URAM0_out_fields : field_array(7 downto 0);
        debug_URAM1_out_fields : field_array(7 downto 0);
        
        -- valid memory-output delays
        read_fifo_pulls  : std_logic_vector(NUM_READ_PORTS - 1 downto 0);
        read_fifo_valids : read_fifo_valids_array(NUM_READ_PORTS - 1 downto 0);
        
        read_URAM_delay0 : std_logic_vector(INT_VECTOR_MEM_LATENCY downto 0);
        read_URAM_delay1 : std_logic_vector(INT_VECTOR_MEM_LATENCY downto 0);
        read_URAM_addr_lsb0 : addr_lsb_delay_type;
        read_URAM_addr_lsb1 : addr_lsb_delay_type;
        URAM_out_data    : field_array(1 downto 0);

        -- field operation signals
        do_divide        : std_logic;
        divident         : field;
        divisor          : field;
        do_square_root   : std_logic;

        multiply_in1     : field;
        multiply_in2     : field;
        do_multiply      : std_logic;
        -- output signals
        read_rqs     : read_request_array(NUM_READ_PORTS - 1 downto 0);
 
        -- write signals
        write_rqs        : write_request_array;
        write_vect_sel   : std_logic_vector(NUM_WRITE_PORTS - 1 downto 0);
        write_line       : cacheline;
        write_valid      : std_logic;
      
        compute_done     : std_logic;
        done             : std_logic;
        
        debug_vector_count : vector_address;
        debug_write_rq  : write_request_type;
        prev_norms : field_array(3 downto 0);
        norm_count : unsigned(1 downto 0);
        sparse_debug_line : cacheline;
        sparse_debug_valid : std_logic;
        read_request_active : std_logic_vector(NUM_READ_PORTS - 1 downto 0);
        write_request_active : std_logic_vector(NUM_WRITE_PORTS - 1 downto 0);
        
        debug_rate : unsigned(15 downto 0);
        debug_lines : unsigned(15 downto 0);
        debug_count : unsigned(15 downto 0);
        debug_read_done  : std_logic_vector(NUM_DDR_READ_PORTS + NUM_HBM_READ_PORTS - 1 downto 0);
        num_debug_writes : unsigned(15 downto 0);
        read_counts  : counts_array(NUM_READ_PORTS - 1 downto 0);
        write_counts     : counts_array(NUM_WRITE_PORTS - 1 downto 0);
        debug_state      : debug_state_type;
        debug_address    : cpu_address;
        debug_done       : std_logic;
        is_last_debug_write : std_logic;
--        debug_write_done : std_logic;
    end record;

    constant SOLVER_INT_INIT : solver_int := (
        state           => idle,
        vector_addrs    => (others => (others => '0')),
        next_step       => PROGRAM(0),
        current_step    => PROGRAM(0),
        first_cycle     => '0',
        first_iteration => '0',
        iter_num        => (others => '0'),
        iteration_end   => '0',
        do_reset_debug  => '0',
        absolute_compare => '0',
        
        state_done      => '0',
        calc_done       => '0',
        divide_set      => '0',
        multiply_set    => '0',
        no_change       => '0',
        
        sparse_start   => '0',
        apply_ILU0     => '0',
        matrix_sizes   => (others => (others => (others => '0'))),
        sparse_sizes   => (others => (others => '0')),
        matrix_addrs   => (others => (others => (others => '0'))),
        sparse_addrs   => (others => (others => '0')),
        fields         => (others => (others => '0')),
        criteria       => (others => '0'),
        
        read_vect_addr => (others => (others => '0')),
        dot_axpy_start => '0',
        vect_op_sel    => dot1,
        
        -- URAM signals
        URAM_enable      => '0',
        URAM_addr1       => (others => '0'),
        URAM_addr2       => (others => '0'),
        debug_URAM0_out_fields => (others => (others => '0')),
        debug_URAM1_out_fields => (others => (others => '0')),
        
        -- valid memory-output delays
        read_fifo_valids => (others => (others => '0')),
        read_URAM_addr_lsb0 => (others => (others => '0')),
        read_URAM_addr_lsb1 => (others => (others => '0')),
        URAM_out_data    => (others => (others => '0')),

        -- field operation signals
        do_divide        => '0',
        do_square_root   => '0',
        do_multiply      => '0',
        -- output signals
        read_rqs         => (others => READ_RQ_INIT),
        -- write signals
        write_rqs        => (others => WRITE_RQ_INIT),
        write_valid      => '0',
      
        compute_done     => '0',
        done             => '0',
        
        debug_vector_count => (others => '0'),
        debug_write_rq  => WRITE_RQ_INIT,
        prev_norms => (others => (others => '0')),
        norm_count => (others => '0'),
        sparse_debug_valid => '0',
		debug_rate => (others => '0'),
        debug_lines => (others => '0'),
        debug_count => (others => '0'),
        num_debug_writes => (others => '0'),
        read_counts  => (others => (others => '0')),
        write_counts => (others => (others => '0')),
        debug_state => idle,
        debug_address => (others => '0'),
        debug_done => '0',
        is_last_debug_write => '0',
        others => (others => '0') -- default for std_logic_vectors
    );

    type solver_ext is record
        sparse_done        : std_logic;
        sparse_L_done      : std_logic;
        sparse_read_P      : read_P_type;
        sparse_write_rq    : write_request_type;
        sparse_write_line  : write_line_type;
        sparse_write_field : write_field_type;
        sparse_debug_line  : write_line_type;
        URAM_out0          : cacheline;
        URAM_out1          : cacheline;
        -- vector fifo outputs
        
        vect_URAM_read_ready : std_logic;
        -- shared by vector ops and spmv units:
        read_rqs           : read_request_array(NUM_READ_PORTS - 1 downto 0);
        read_ready         : std_logic_vector(NUM_READ_PORTS - 1 downto 0);
        read_ack           : std_logic_vector(NUM_READ_PORTS - 1 downto 0);
        
        dot1_result        : field;
        dot2_result        : field;
        vect_op_done       : std_logic;
        vect_write_line    : cacheline;
        vect_write_valid   : std_logic;
        
        -- field operation outputs
        divide_valid       : std_logic;
        divide_result      : field;
        square_root_valid  : std_logic;
        square_root_result : field;
        multiply_valid     : std_logic;
        multiply_result    : field;
        compare_valid      : std_logic;
        compare_result     : std_logic_vector(7 downto 0);
		
		-- debug signals
        sparse_encoded_state : std_logic_vector(7 downto 0);
        
        vect_debug_data : std_logic_vector(16 downto 0);
    end record;
    
    type vector_ops_state is (idle, dot1, dot2, axpy1, axpy2, update_p);
    
    type vector_ops_int is record
        state             : vector_ops_state;
        active            : std_logic;
        read_lines        : read_lines_type;
        start_vect_read   : std_logic;
        read_vect_addrs   : cpu_addr_array(NUM_HBM_READ_PORTS - 1 downto 0);
        read_vect_sel     : std_logic_vector(NUM_HBM_READ_PORTS - 1 downto 0);
        vect_read_done    : std_logic;
        do_vect_op1       : std_logic_vector(2 downto 0);
        dot_axpy2_enable  : std_logic;
        do_vect_op2       : std_logic_vector(2 downto 0);
        scaling_factor1 : field;
        scaling_factor2 : field;  
        dot_axpy_last_val : std_logic;
        dot_axpy2_write_ready : std_logic;
        dot_axpy2_done    : std_logic;
        write_line       : cacheline;
        write_valid      : std_logic;
        line_set         : std_logic;
        done : std_logic;
        dot_axpy1_full : std_logic_vector(1 downto 0);
        dot_axpy2_full : std_logic_vector(1 downto 0);
    end record;
    
    constant VECTOR_OPS_INT_INIT : vector_ops_int := (
        state           => idle,
        read_lines      => (others => (others => '0')),
        read_vect_addrs => (others => (others => '0')),
        read_vect_sel   => (others => '0'),
        do_vect_op1     => (others => '0'),
        do_vect_op2     => (others => '0'),
        scaling_factor1 => (others => '0'),
        scaling_factor2 => (others => '0'),
        write_line      => (others => '0'),
        dot_axpy1_full  => (others => '0'),
        dot_axpy2_full  => (others => '0'),
        others          => '0'
    );
    
    type vector_fifo_ext is record
        data         : cacheline;
        full         : std_logic;
        almost_full  : std_logic;
        empty        : std_logic;
        almost_empty : std_logic;
    end record;
    
    type vector_fifos_ext is array(0 to 2) of vector_fifo_ext;
    
    type vector_ops_ext is record
        vect_read_ack      : std_logic_vector(NUM_HBM_READ_PORTS - 1 downto 0);
        read_wes           : std_logic_vector(NUM_HBM_READ_PORTS - 1 downto 0);
        vect_read_done     : std_logic;
        fifos              : vector_fifos_ext;
        
        dot_axpy1_ready    : std_logic_vector(1 downto 0);
        dot_axpy2_ready    : std_logic_vector(1 downto 0);
        axpy1_result       : field_array(mult_range);
        axpy1_valid        : std_logic_vector(mult_range);
        dot_axpy1_done     : std_logic;
        dot_axpy1_state_debug : std_logic_vector(1 downto 0);
        axpy2_result       : field_array(mult_range);
        axpy2_valid        : std_logic_vector(mult_range);
        dot_axpy2_done     : std_logic;
        dot_axpy2_state_debug : std_logic_vector(1 downto 0);
    end record;

    function set_read_outs(read_rq : in read_request_type; pull : in std_logic) return solver_read_port_outs;
    function set_write_outs(write_rq : in write_request_type; data: in cacheline; push : in std_logic) return solver_write_port_outs;

end package;

package body solver_pkg is

function set_read_outs(read_rq : in read_request_type; pull : in std_logic) return solver_read_port_outs is
    variable res : solver_read_port_outs;
begin
    res.rq_address := std_logic_vector(read_rq.addr);
    res.rq_size    := ZEROES(31 downto READ_RQ_SIZE_WIDTH) & std_logic_vector(read_rq.size);
    res.rq_start   := read_rq.valid;
    res.fifo_pull  := pull;
    return res;
end function;

function set_write_outs(write_rq : in write_request_type; data: in cacheline; push : in std_logic) return solver_write_port_outs is
    variable res : solver_write_port_outs;
begin
    res.rq_address := std_logic_vector(write_rq.addr);
    res.rq_size    := ZEROES(31 downto WRITE_RQ_SIZE_WIDTH) & std_logic_vector(write_rq.size);
    res.rq_start   := write_rq.valid;
    res.fifo_data  := data;
    res.fifo_push  := push;
    return res;
end function;

end package body solver_pkg;
