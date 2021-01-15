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

library work;
    use work.constants.all;
    use work.types.all;

package rw_pkg is

    --constant READ_BATCH_WIDTH  : integer := 11; --commit:9b2b07fc: used in ddr5; *makes kernel hang*
    constant READ_BATCH_WIDTH  : integer := 9; --commit:bdf44d0f: used in ddr0-4
	constant READ_BATCH_SIZE   : integer := 2 ** READ_BATCH_WIDTH;
	constant WRITE_BATCH_WIDTH : integer := 0;
	constant WRITE_BATCH_SIZE  : integer := 2 ** WRITE_BATCH_WIDTH;
	
	--constant BATCH_NUM_WIDTH   : integer := 2; --commit:all, used in ddr0-1
    constant BATCH_NUM_WIDTH   : integer := 1; --commit:new, used in ddr2 and later --only 2 batches are currently loaded in memory
	constant BATCHES_IN_MEMORY : integer := 2 ** BATCH_NUM_WIDTH;
    constant FIFO_DEPTH        : integer := READ_BATCH_WIDTH + BATCH_NUM_WIDTH;
	constant FIFO_SIZE         : integer := BATCHES_IN_MEMORY*READ_BATCH_SIZE;
	
	constant SPMVP_RES_MEM_WIDTH : integer := 13;
	constant SPMVP_RES_MEM_SIZE  : integer := 2 ** SPMVP_RES_MEM_WIDTH;
	
	constant NUM_DDR_READ_PORTS  : integer := 2;
    constant NUM_DDR_WRITE_PORTS : integer := 0;
    constant NUM_HBM_READ_PORTS  : integer := 3;
    constant NUM_HBM_WRITE_PORTS : integer := 3;
    
    constant NUM_READ_PORTS      : integer := NUM_DDR_READ_PORTS + NUM_HBM_READ_PORTS;
    constant NUM_WRITE_PORTS     : integer := NUM_DDR_WRITE_PORTS + NUM_HBM_WRITE_PORTS;
	
	--matrix specific constants
        
    constant ROW_COLOR_SIZE_DEPTH : integer := 11;
    constant COL_COLOR_SIZE_DEPTH : integer := 13;
    constant VAL_COLOR_SIZE_DEPTH : integer := 17;
    
    --derived constants
    constant READ_RQ_SIZE_WIDTH     : integer := VECTOR_ADDR_WIDTH - FIELDS_PER_LINE_DEPTH;
    constant WRITE_RQ_SIZE_WIDTH    : integer := VECTOR_ADDR_WIDTH - FIELDS_PER_LINE_DEPTH;

    subtype sparstition_counter is unsigned(FIFO_DEPTH - 1 downto 0);

    type sparstition_sizes is record
	   row_size    : mat_size;
       val_size    : mat_size;
       num_colors  : unsigned(MAX_COLORS_DEPTH - 1 downto 0);
	end record;
	
	type sparstition_addresses is record
	    nnz_vals_addr      : cpu_address;
        col_indices_addr   : cpu_address;
        NRs_addr           : cpu_address;
        P_indices_addr     : cpu_address;
        color_sizes_addr   : cpu_address;
        block_diag_addr    : cpu_address;
    end record;
	
    type sparstition_color_sizes is record
        row : mat_size;
        arow : mat_size;
        col : mat_size;
        val : mat_size;
    end record;

    type ext_read_state is(
	    idle,
	    start,
	    read_color_sizes,
	    read_mult_indices,
	    read_multiplicant,
		read_matrix_vals
	);
	
	type int_read_state is(
	   idle,
	   read_P_vector,
       read_U_P_vector,
	   read_vect_inds,
	   transfer_vect
	);
	
	type write_state is(
	   idle,
	   reset_state,
	   fill_batch,
	   write_batch,
	   write_ILU0,
	   next_ilu0_color
	);

    type read_request_type is record
        addr   : cpu_address;
        size   : unsigned(READ_RQ_SIZE_WIDTH -1 downto 0);
        valid  : std_logic;
	end record;

    constant READ_RQ_INIT : read_request_type := ((others => '0'), (others => '0'), '0');
    
    type read_request_array is array(integer range <>) of read_request_type;

    type read_P_type is record
	    addrs  : vect_addr_array(1 downto 0);
	    valids : std_logic_vector(1 downto 0);
	end record; 
	
	type write_request_type is record
        addr   : cpu_address;
        size   : unsigned(WRITE_RQ_SIZE_WIDTH - 1 downto 0);
        valid  : std_logic;
    end record;
    
    constant WRITE_RQ_INIT : write_request_type := ((others => '0'), (others => '0'), '0');
    
    type write_request_array is array(NUM_HBM_WRITE_PORTS - 1 downto 0) of write_request_type;
    
    type write_line_type is record
        data  : cacheline;
        valid : std_logic;
    end record;
    
    constant WRITE_LINE_INIT : write_line_type := ((others=> '0'), '0');

    type write_field_type is record
        data  : field;
        addr  : vector_address;
        valid : std_logic;
    end record;
    
    constant WRITE_FIELD_INIT : write_field_type := ((others => '0'), (others => '0'), '0');
    
    type read_wes_type is record
        color_sizes : std_logic_vector(0 downto 0);
        block_diag  : std_logic_vector(0 downto 0);
        P_indices   : std_logic_vector(0 downto 0);
        nnz_vals    : std_logic_vector(0 downto 0);
        col_inds    : std_logic_vector(0 downto 0);
        NRs         : std_logic_vector(0 downto 0);
    end record;
    
    type write_addrs_type is record
        color_sizes : unsigned(MAX_COLORS_DEPTH + 1 downto 0);
        block_diag  : row_index;
        P_indices   : unsigned(COL_INDEX_WIDTH downto 0);
        nnz_vals    : sparstition_counter;
        col_inds    : sparstition_counter;
        NRs         : sparstition_counter;
    end record;

    type next_P_enable_type is array(READ_FIFO_LATENCY + 4 downto 0) of std_logic_vector(1 downto 0);
    type lines_to_read_type is array(2 downto 0) of unsigned(READ_RQ_SIZE_WIDTH - 1 downto 0);
    
    type ext_read_int is record
        state           : ext_read_state;
        sizes           : sparstition_sizes;
        addrs           : sparstition_addresses;
        mat_val_batches : unsigned(MAT_PART_ADDR_WIDTH - READ_BATCH_WIDTH - 1 downto 0);
        val_size        : mat_size;
        wes             : read_wes_type;
        wr_addrs        : write_addrs_type; 
        read0_rq        : read_request_type;
        read1_rq        : read_request_type;
        requested_nnz_vals : mat_part_address;
        requested_col_inds : mat_part_address;
        requested_NRs   : mat_part_address;
        lines_to_read   : lines_to_read_type;
        prev_read_dones : std_logic_vector(2 downto 0);
        read_dones      : std_logic_vector(2 downto 0);
        read_ack        : std_logic_vector(1 downto 0);
        reading_col_inds : std_logic;
        zero_vect_read  : std_logic;
        sizes_done      : std_logic;
        vect_vals_done  : std_logic;
        mat_vals_done   : std_logic;
        diag_done       : std_logic;
    end record;
	
	constant EXT_READ_INT_INIT : ext_read_int := (
	   state           => idle,
	   sizes           => (others => (others => '0')),
	   addrs           => (others => (others => '0')),
	   mat_val_batches => (others => '0'),
	   val_size        => (others => '0'),
	   wes             => (others => "0"),
	   wr_addrs        => (others => (others => '0')),
	   read0_rq        => READ_RQ_INIT,
	   read1_rq        => READ_RQ_INIT,
	   requested_nnz_vals => (others => '0'),
	   requested_col_inds => (others => '0'),
	   requested_NRs   => (others => '0'),
	   lines_to_read   => (others => (others => '0')),
	   prev_read_dones => (others => '0'),
	   read_dones      => (others => '0'),
	   read_ack        => (others => '0'),
	   reading_col_inds => '0',
	   zero_vect_read  => '0',
	   sizes_done      => '0',
	   vect_vals_done  => '0',
	   mat_vals_done   => '0'
	   ,diag_done      => '0'
	);
	
	type int_read_int is record
	    state           : int_read_state;
	    P_inds_addr     : unsigned(COL_INDEX_WIDTH downto 0);
	    done_rows       : vector_address;
	    do_transfer     : std_logic;
        next_P_enables  : next_P_enable_type;
        read_P_enable   : std_logic_vector(1 downto 0);
        read_P_addrs    : vect_addr_array(1 downto 0);
        X_P_we          : std_logic_vector(1 downto 0);
        X_P_in_fields   : field_array(1 downto 0);
        temp_X_P_addr1  : unsigned(COL_INDEX_WIDTH downto 0);
        temp_X_P_addr2  : unsigned(COL_INDEX_WIDTH downto 0);
        write_addr      : unsigned(COL_INDEX_WIDTH downto 0);
        ilu0_start_addr : unsigned(COL_INDEX_WIDTH downto 0);
        next_transfer_size : unsigned(COL_INDEX_WIDTH downto 0);
        prev_col_size   : unsigned(COL_INDEX_WIDTH downto 0);
        single_uneven_P_inds_addr : std_logic_vector(1 downto 0);
        ilu0_fifo_pull  : std_logic;
        ext_read_done   : std_logic;
        next_P_valid    : std_logic;
        P_valid         : std_logic;
        next_X_valid    : std_logic;
        X_valid         : std_logic;
        P_vect_we       : std_logic_vector(1 downto 0);
        X_vect_we       : std_logic_vector(1 downto 0);
        LU_done         : std_logic;
        done            : std_logic;
        transfer_done   : std_logic;
        ilu0_fifo_overflow : std_logic;
	end record;
	
	constant INT_READ_INT_INIT : int_read_int := (
	    state           => idle,
	    P_inds_addr     => (others => '0'),
	    do_transfer     => '0',
	    done_rows       => (others => '0'),
        next_P_enables  => (others => "00"),
	    read_P_enable   => "00",
	    read_P_addrs    => (others => (others => '0')),
	    X_P_we          => (others => '0'),
	    X_P_in_fields   => (others => (others => '0')),
	    temp_X_P_addr1  => (others => '0'),
	    temp_X_P_addr2  => (others => '0'),
	    write_addr      => (others => '0'),
	    ilu0_start_addr => (others => '0'),
	    next_transfer_size => (others => '0'),
	    prev_col_size   => (others => '0'),
	    single_uneven_P_inds_addr => "00",
	    ilu0_fifo_pull  => '0',
	    ext_read_done   => '0',
	    next_P_valid    => '0',
	    P_valid         => '0',
	    next_X_valid    => '0',
	    X_valid         => '0',
	    P_vect_we       => "00",
	    X_vect_we       => "00",
	    LU_done         => '0',
	    done            => '0',
	    transfer_done   => '0'
	    , ilu0_fifo_overflow => '0'
	);
	
	type vector_read_state is (idle, read_vects);
	
	type vector_read_int is record
	   state           : vector_read_state;
	   vect_sel        : std_logic_vector(2 downto 0);
	   wes             : std_logic_vector(2 downto 0);
       read_batches    : unsigned(READ_BATCH_WIDTH - 1 downto 0);
       size_to_read    : vector_address;
       vector_addrs    : cpu_addr_array(2 downto 0);
       read_fifos_pull : std_logic_vector(2 downto 0);
       read_rqs        : read_request_array(2 downto 0);
	   lines_to_read   : lines_to_read_type;
	   vect_dones      : std_logic_vector(2 downto 0);
	   read_ack        : std_logic_vector(2 downto 0);
	   done            : std_logic;
	end record;
	
	constant VECTOR_READ_INT_INIT : vector_read_int := (
	   state => idle,
	   vect_sel => (others => '0'),
	   wes => (others => '0'),
	   vector_addrs => (others => (others => '0')),
       read_fifos_pull => (others => '0'),
	   read_rqs => (others => READ_RQ_INIT),
	   lines_to_read => (others => (others=> '0')),
	   vect_dones => (others => '0'),
	   done => '0',
	   read_ack => (others => '0'),
	   others => (others => '0')
	);

    type write_int is record
        state : write_state;
        reset_addrs : row_index_array(SPMVP_OUTPUT_NUM - 1  downto 0);
        is_U            : std_logic;
        write_elems     : elem_array(SPMVP_OUTPUT_NUM - 1 downto 0);
        zero_pad_offset : unsigned(FIELDS_PER_LINE_DEPTH downto 0);
        done_up_to_addr : vector_address;
        written_up_to_addr : vect_addr_array(2 downto 0);
        done_rows       : vector_address;
        spmvp_res_addr  : vector_address;
        write_addr      : vector_address;
        flushed         : std_logic;
        set_wr_data_addr   : vector_address;
        set_wr_data_valid  : std_logic;
        next_wr_data_addr  : vector_address;
        next_wr_data_valid : std_logic;
        line_to_split   : cacheline;
        do_split        : std_logic;
        split_addr      : row_index;
        next_ilu0_addr  : row_index;
        ilu0_input      : element;
        ilu0_last_val   : std_logic;
        write_line      : write_line_type;
        write_field     : write_field_type;
        ready           : std_logic;
        done            : std_logic;
        write_line_filled : std_logic;
        found_overflow  : std_logic;
        overflow : std_logic_vector(7 downto 0);
     end record;

    constant WRITE_INT_INIT : write_int := (
        state           => idle,
        reset_addrs     => (others=> (others => '0')),
        is_U            => '0',
        write_elems     => (others => ELEMENT_INIT),
        zero_pad_offset => (others => '0'),
        done_up_to_addr => (others => '0'),
        written_up_to_addr => (others => (others => '0')),
        done_rows       => (others => '0'),
        spmvp_res_addr  => (others => '0'),
        write_addr      => (others => '0'),
        flushed         => '0',
        set_wr_data_addr  => (others => '0'),
        set_wr_data_valid => '0',
        next_wr_data_addr => (others => '0'),
        next_wr_data_valid => '0',
        line_to_split   => (others => '0'),
        do_split        => '0',
        split_addr      => (others => '0'),
        next_ilu0_addr  => (others => '0'),
        ilu0_input      => ELEMENT_INIT,
        ilu0_last_val   => '0',
        write_line      => WRITE_LINE_INIT,
        write_field     => WRITE_FIELD_INIT,
        ready           => '0',
        done            => '0',
        write_line_filled => '0'
        , found_overflow => '0'
        , overflow      => (others => '0')
    );

end package;
