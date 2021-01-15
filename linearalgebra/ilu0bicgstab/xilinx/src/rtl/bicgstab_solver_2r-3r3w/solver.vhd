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

-- -----------------
-- solver module top
-- -----------------

-- KEEP THIS UP-TO-DATE!
-- current meaning of the debug port bits (index 1):
--   bit 0        : reduce unit overflow (no. nnz values per column too large)
--   bit 4        : ilu0 fifo overflow (unable to use ilu0 results as inputs during the next color)
--   bit 13..8    : overflows in the merge2 modules of the write_merge unit
--   bit 19..16   : overflows in the split2 modules of the write_merge unit
--   bit 23..20   : overflows in the output fifos of the write_merge unit
--   bit 27..24   : overflows of the spmv res BRAMs in the write unit
--   bit 31..28   : (currently unused)
--   bit 36..32   : read fifo underflows for ports hbm(2..0) & ddr(1..0)
--   bit 40..42   : vector fifo overflows for vectors 2..0
--   bit 44..46   : vector fifo underflows for vector reads 2..0   
--   bit 52..48   : read requests on ports hbm(2..0) & ddr(1..0) given before previous read request finished
--   bit 55..53   : write requests on ports 2..0 given before previous write request finished
--   bit 59..56   : overwritten dot_axpy inputs
--   bit 63..60   : result on one of the spmvp outputs has a lower address than the done-up-to address
--   bit 79..64   : number of reads on port read0 in current state
--   bit 95..80   : number of reads on port read1 in current state
--   bit 111..96  : number of reads on port read2 in current state
--   bit 127..112 : number of reads on port read3 in current state
--   bit 143..128 : number of writes on port write0 in current state
--   bit 159..144 : number of writes on port write1 in current state
--   bit 175..160 : number of writes on port write2 in current state
--   bit 179..176 : encoded solver state
--            idle => "0000"
--            init_read => "0001"
--            read_x => "0010"
--            SpMV => "0011"
--            wait_for_write => "0100"
--            ILU0_L_fs => "0101"
--            ILU0_U_bs => "0110"
--            calc_p => "0111"
--            dot1 => "1000"
--            dot2 => "1001"
--            axpy1 => "1010"
--            axpy2 => "1011"
--            wait_for_debug => "1100"
--   bit 185..184 : encoded dot_axpy1 state
--   bit 189..188 : endoced dot_axpy2 state
--            idle => "00"
--            dot => "01"
--            axpy => "10"
--   bit 194..192 : encoded sparstition state
--            idle => "000"
--            wait_for_sizes_read => "001"
--            wait_for_first_vector_read => "010"
--            wait_for_transfer => "011"
--            wait_for_P_vector_read => "100"
--            running => "101"
--            init_U => "110"
--            finished => "111"
--   bit 197..196 : encoded sparstition mode
--            forward subst => "01"
--            backward subst => "10"
--            SpMV => "11"
--   bit 207..200 : State change information:

--   bit 200      : read0 done
--   bit 201      : read fifo0 empty
--   bit 202      : vector fifo0 empty
--   bit 203      : read1 done
--   bit 204      : read fifo1 empty
--   bit 205      : vector fifo1 empty
--   bit 206      : dot_axpy1 done

--   bit 223..208 : The number of times a debug line has been written (including the current one, so starts at 1)
--   bit 239..224 : The iteration count.
--   bit 255..511 : The four most recent norm results (refer to the iteration_count%4 to know which one is the most recent).

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_misc.all;

-- synthesis translate_off
use std.textio.all;
use IEEE.std_logic_textio.all;
-- synthesis translate_on

library xpm;
    use xpm.vcomponents.all;

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.rw_pkg.all;
    use work.sparstition_pkg.all;
    use work.solver_pkg.all;

-- This is the top-level unit of the logic of solver kernel. It performs initialization, 
-- in which it read the other read addresses and matrix sizes, and the initial X vector 
-- to be stored in the URAM. Then, it performs the solver by utilizing the SpMV and 
-- vector_ops units that it instantiates. It bases the order in whcih it performs these 
-- operations and on which data those operations work based on a program constant defined 
-- in its package file.

entity solver is
    generic (
        SIM_DEBUG: natural := 0;
        WRITE_ILU0_RESULTS: boolean := false
    );
    port(
		clk   : in std_logic;
		reset : in std_logic;
		start : in std_logic;
		debug_rate : in std_logic_vector(15 downto 0);
		debug_lines : in std_logic_vector(15 downto 0);

		done  : out std_logic;
		iteration_end : out std_logic;
		no_change : out std_logic;
		
        read_ins   : in read_ports_ins_array(NUM_READ_PORTS - 1 downto 0);
		read_outs  : out read_ports_outs_array(NUM_READ_PORTS - 1 downto 0);
		
		write_ins  : in write_ports_ins_array(NUM_WRITE_PORTS - 1 downto 0);
		write_outs : out write_ports_outs_array(NUM_WRITE_PORTS - 1 downto 0)
		
		; max_iters : in std_logic_vector(15 downto 0)
		; desired_precision : in std_logic_vector(63 downto 0)
		
		; debug_write_ins  : in solver_write_port_ins
		; debug_write_outs : out solver_write_port_outs
	);
end solver;

architecture behavioral of solver is
 
    component FP_multiplier
        port (
            aclk : in std_logic;
            s_axis_a_tvalid : in std_logic;
            s_axis_a_tdata : in std_logic_vector(63 DOWNTO 0);
            s_axis_b_tvalid : in std_logic;
            s_axis_b_tdata : in std_logic_vector(63 DOWNTO 0);
            m_axis_result_tvalid : out std_logic;
            m_axis_result_tdata : out std_logic_vector(63 DOWNTO 0)
        );
    end component;

    component FP_divider
        port (
            aclk : in std_logic;
            s_axis_a_tvalid : in std_logic;
            s_axis_a_tdata : in std_logic_vector(63 DOWNTO 0);
            s_axis_b_tvalid : in std_logic;
            s_axis_b_tdata : in std_logic_vector(63 DOWNTO 0);
            m_axis_result_tvalid : out std_logic;
            m_axis_result_tdata : out std_logic_vector(63 DOWNTO 0)
        );
    end component;
    
    component FP_square_root
        port (
            aclk : in std_logic;
            s_axis_a_tvalid : in std_logic;
            s_axis_a_tdata : in std_logic_vector(63 DOWNTO 0);
            m_axis_result_tvalid : out std_logic;
            m_axis_result_tdata : out std_logic_vector(63 DOWNTO 0)
        );
    end component;
    
    COMPONENT FP_greater_than
        PORT (
            aclk : IN STD_LOGIC;
            s_axis_a_tvalid : IN STD_LOGIC;
            s_axis_a_tdata : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
            s_axis_b_tvalid : IN STD_LOGIC;
            s_axis_b_tdata : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
            m_axis_result_tvalid : OUT STD_LOGIC;
            m_axis_result_tdata : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
        );
    end component;

    signal r, q : solver_int;
    signal re   : solver_ext;
    
    -- non-buffered input signals of submodules:
    
    signal reads : reads_in_array(NUM_READ_PORTS - 1 downto 0);
--    signal hbm_reads : reads_in_array(NUM_HBM_READ_PORTS - 1 downto 0);
    signal vect_read_dones : std_logic_vector(2 downto 0);
    signal vect_write_ready : std_logic_vector(2 downto 0);
    signal scaling_factor1 : field;
    
    signal debug_URAM_in1, debug_URAM_in2   : field_array(7 downto 0);
    signal debug_URAM_out1, debug_URAM_out2 : field_array(7 downto 0);
begin

    assert SPMVP_OUTPUT_NUM <= 4
    report "WARNING: an SpMVP_OUTPUT_NUM larger than 4 will have some debug signals being overwritten by other debug signals."
    severity warning;

gen_uram_vector: if (USE_URAM = true) generate
    -- xpm_memory_tdpram: True Dual Port RAM - using URAM
    -- Xilinx Parameterized Macro, version 2018.3
    -- Replaces the IP: blk_mem_uram_complete_vector
    vect_mem : xpm_memory_tdpram
    generic map (
        ADDR_WIDTH_A => VECTOR_ADDR_WIDTH - FIELDS_PER_LINE_DEPTH,
        ADDR_WIDTH_B => VECTOR_ADDR_WIDTH - FIELDS_PER_LINE_DEPTH,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => 8,
        BYTE_WRITE_WIDTH_B => 8,
        CLOCKING_MODE => "common_clock",
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "ultra",
        MEMORY_SIZE => VECTOR_SIZE_BITS,  -- size in bits
        MESSAGE_CONTROL => 1,
        READ_DATA_WIDTH_A => DMA_DATA_WIDTH,
        READ_DATA_WIDTH_B => DMA_DATA_WIDTH,
        READ_LATENCY_A => INT_VECTOR_MEM_LATENCY_URAM-1, -- see constants pkg
        READ_LATENCY_B => INT_VECTOR_MEM_LATENCY_URAM-1, -- see constants pkg
        READ_RESET_VALUE_A => "0",
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => DMA_DATA_WIDTH,
        WRITE_DATA_WIDTH_B => DMA_DATA_WIDTH,
        WRITE_MODE_A => "no_change",
        WRITE_MODE_B => "no_change"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        rsta => reset,
        ena => bit_1,
        addra => std_logic_vector(r.URAM_addr1(VECTOR_ADDR_WIDTH-1 downto FIELDS_PER_LINE_DEPTH)),
        dina => r.URAM_in_data1,
        wea => r.URAM_we1,
        douta => re.URAM_out0,
        regcea => bit_1,
        sbiterra => open,
        dbiterra => open,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.URAM_addr2(VECTOR_ADDR_WIDTH-1 downto FIELDS_PER_LINE_DEPTH)),
        dinb => r.URAM_in_data2,
        web => r.URAM_we2,
        doutb => re.URAM_out1,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open,
        injectsbiterrb => bit_0,
        injectdbiterrb => bit_0
    );
end generate;

gen_bram_vector: if (USE_URAM = false) generate
    -- xpm_memory_tdpram: True Dual Port RAM - using BRAM
    -- Xilinx Parameterized Macro, version 2018.3
    -- Replaces the IP: blk_mem_complete_vector
    vect_mem : xpm_memory_tdpram
    generic map (
        ADDR_WIDTH_A => VECTOR_ADDR_WIDTH - FIELDS_PER_LINE_DEPTH,
        ADDR_WIDTH_B => VECTOR_ADDR_WIDTH - FIELDS_PER_LINE_DEPTH,
        AUTO_SLEEP_TIME => 0,
        BYTE_WRITE_WIDTH_A => 8,
        BYTE_WRITE_WIDTH_B => 8,
        CLOCKING_MODE => "common_clock",
        ECC_MODE => "no_ecc",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        MEMORY_OPTIMIZATION => "true",
        MEMORY_PRIMITIVE => "block",
        MEMORY_SIZE => VECTOR_SIZE_BITS,  -- size in bits
        MESSAGE_CONTROL => 1,
        READ_DATA_WIDTH_A => DMA_DATA_WIDTH,
        READ_DATA_WIDTH_B => DMA_DATA_WIDTH,
        READ_LATENCY_A => INT_VECTOR_MEM_LATENCY_BRAM-1, -- see constants pkg
        READ_LATENCY_B => INT_VECTOR_MEM_LATENCY_BRAM-1, -- see constants pkg
        READ_RESET_VALUE_A => "0",
        READ_RESET_VALUE_B => "0",
        RST_MODE_A => "SYNC",
        RST_MODE_B => "SYNC",
        USE_EMBEDDED_CONSTRAINT => 0,
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        WRITE_DATA_WIDTH_A => DMA_DATA_WIDTH,
        WRITE_DATA_WIDTH_B => DMA_DATA_WIDTH,
        WRITE_MODE_A => "no_change",
        WRITE_MODE_B => "no_change"
    )
    port map (
        sleep => bit_0,
        clka => clk,
        rsta => reset,
        ena => bit_1,
        addra => std_logic_vector(r.URAM_addr1(VECTOR_ADDR_WIDTH-1 downto FIELDS_PER_LINE_DEPTH)),
        dina => r.URAM_in_data1,
        wea => r.URAM_we1,
        douta => re.URAM_out0,
        regcea => bit_1,
        sbiterra => open,
        dbiterra => open,
        injectsbiterra => bit_0,
        injectdbiterra => bit_0,
        clkb => bit_0, -- common clock, using clka
        rstb => reset,
        enb => bit_1,
        addrb => std_logic_vector(r.URAM_addr2(VECTOR_ADDR_WIDTH-1 downto FIELDS_PER_LINE_DEPTH)),
        dinb => r.URAM_in_data2,
        web => r.URAM_we2,
        doutb => re.URAM_out1,
        regceb => bit_1,
        sbiterrb => open,
        dbiterrb => open,
        injectsbiterrb => bit_0,
        injectdbiterrb => bit_0
    );
end generate;

debug_URAM: for g in 0 to 7 generate
        debug_URAM_in1(g) <= index(r.URAM_in_data1, g, FIELD_WIDTH);
        debug_URAM_in2(g) <= index(r.URAM_in_data2, g, FIELD_WIDTH);
        debug_URAM_out1(g) <= index(re.URAM_out0, g, FIELD_WIDTH);
        debug_URAM_out2(g) <= index(re.URAM_out1, g, FIELD_WIDTH);
    end generate;

reads_loop: for g in 0 to NUM_READ_PORTS - 1 generate
        reads(g).data  <= read_ins(g).fifo_data;
        reads(g).valid <= r.read_fifo_valids(g)(READ_FIFO_LATENCY - 1);
        reads(g).done  <= r.read_dones(g);
    end generate;

    vect_write_ready <= NOT(write_ins(2).fifo_almost_full) & NOT(write_ins(1).fifo_almost_full) & NOT(write_ins(0).fifo_almost_full);

cu: entity work.sparstition 
    generic map (
        SIM_DEBUG => SIM_DEBUG,
        WRITE_ILU0_RESULTS => WRITE_ILU0_RESULTS
    )
    port map(
        clk         => clk,
        reset       => reset,
        start       => r.sparse_start,
        apply_ILU0  => r.apply_ILU0,
        sizes       => r.sparse_sizes,
        addresses   => r.sparse_addrs,
        reads       => reads(NUM_DDR_READ_PORTS - 1 downto 0),
        read_fields => r.URAM_out_data,
        field_re    => r.field_re,
        write_ready => vect_write_ready(2),
        L_done      => re.sparse_L_done,
        done        => re.sparse_done,
        read0_rq    => re.read_rqs(0),
        read1_rq    => re.read_rqs(1),
        read_ack    => re.read_ack(NUM_DDR_READ_PORTS - 1 downto 0),
        read_ready  => re.read_ready(NUM_DDR_READ_PORTS - 1 downto 0),
        read_P      => re.sparse_read_P,
        write_rq    => re.sparse_write_rq,
        write_line  => re.sparse_write_line,
        write_field => re.sparse_write_field
        , debug_line => re.sparse_debug_line
        , debug_encoded_state => re.sparse_encoded_state
    );
   
    scaling_factor1 <= r.fields(r.current_step.scaling_factor);
    
 vect_ops: entity work.vector_ops port map (
            clk   => clk,
            reset => reset,
            -- control and configuration
            start => r.dot_axpy_start,
            op    => r.vect_op_sel,
            read_vect_addrs => r.read_vect_addr,
            row_size        => r.matrix_sizes(SpMV).row_size(vector_addr_range),
            active_reads    => r.current_step.active_reads,
            active_writes   => r.current_step.active_writes,
            port1_sel       => r.current_step.port1_sel,
            scaling_factor1 => scaling_factor1,
            scaling_factor2 => r.fields(beta),
            minus_scale     => r.current_step.minus_scale,
            
            reads         => reads(NUM_READ_PORTS - 1 downto NUM_DDR_READ_PORTS),
            URAM0_valid   => r.read_URAM_delay0(INT_VECTOR_MEM_LATENCY),
            URAM0_line    => re.URAM_out0,
            write_ready   => vect_write_ready,
            read_rqs      => re.read_rqs(NUM_READ_PORTS - 1 downto NUM_DDR_READ_PORTS),
            read_ready    => re.read_ready(NUM_READ_PORTS - 1 downto NUM_DDR_READ_PORTS),
            URAM_read_ready => re.vect_URAM_read_ready,
            read_ack      => re.read_ack(NUM_READ_PORTS - 1 downto NUM_DDR_READ_PORTS),
            
            dot1_result   => re.dot1_result,
            dot2_result   => re.dot2_result,
            done          => re.vect_op_done, 
            
            write_line    => re.vect_write_line,
            write_valid   => re.vect_write_valid
            
            , debug_data  => re.vect_debug_data
        );

div : FP_divider
    port  map (
        aclk                 => clk,
        s_axis_a_tvalid      => r.do_divide,
        s_axis_a_tdata       => r.divident,
        s_axis_b_tvalid      => r.do_divide,
        s_axis_b_tdata       => r.divisor,
        m_axis_result_tvalid => re.divide_valid,
        m_axis_result_tdata  => re.divide_result
    );
     
mult : FP_multiplier
    port map (
        aclk                 => clk,
        s_axis_a_tvalid      => r.do_multiply,
        s_axis_a_tdata       => r.multiply_in1,
        s_axis_b_tvalid      => r.do_multiply,
        s_axis_b_tdata       => r.multiply_in2,
        m_axis_result_tvalid => re.multiply_valid,
        m_axis_result_tdata  => re.multiply_result
    );  


sqrt : FP_square_root
    port map (
        aclk                 => clk,
        s_axis_a_tvalid      => r.do_square_root,
        s_axis_a_tdata       => re.dot2_result,
        m_axis_result_tvalid => re.square_root_valid,
        m_axis_result_tdata  => re.square_root_result
    );
    
gt : FP_greater_than
  port map (
    aclk => clk,
    s_axis_a_tvalid => re.square_root_valid,
    s_axis_a_tdata => re.square_root_result,
    s_axis_b_tvalid => re.square_root_valid,
    s_axis_b_tdata => r.fields(precision),
    m_axis_result_tvalid => re.compare_valid,
    m_axis_result_tdata => re.compare_result
  ); 
    
logic_proc: process(start, read_ins, write_ins, debug_write_ins, r, re, debug_rate, debug_lines, max_iters, desired_precision) --, debug_next_state)
        variable v : solver_int;
        variable remaining_size : vector_address;
    begin
        v := r;

        -- default assignments
        v.sparse_start := '0';
        v.URAM_we1 := (others => '0');
        v.URAM_we2 := (others => '0');
        for l in 0 to NUM_READ_PORTS - 1 loop
            v.read_rqs(l).valid  := '0';
        end loop;
        for l in 0 to NUM_WRITE_PORTS - 1 loop
            v.write_rqs(l).valid := '0';
        end loop;
        v.write_valid     := '0';
        v.read_fifo_pulls := (others => '0');
        v.do_divide := '0';
        v.do_multiply := '0';

        v.write_valid := '0';
        v.iteration_end := '0';

        -- registers
        v.read_URAM_delay0(INT_VECTOR_MEM_LATENCY downto 1)  := r.read_URAM_delay0(INT_VECTOR_MEM_LATENCY - 1 downto 0);
        v.read_URAM_delay1(INT_VECTOR_MEM_LATENCY downto 1)  := r.read_URAM_delay1(INT_VECTOR_MEM_LATENCY - 1 downto 0);
        v.read_URAM_addr_lsb0 := r.read_URAM_addr_lsb0(INT_VECTOR_MEM_LATENCY - 1 downto 0) & re.sparse_read_P.addrs(0)(2 downto 0);
        v.read_URAM_addr_lsb1 := r.read_URAM_addr_lsb1(INT_VECTOR_MEM_LATENCY - 1 downto 0) & re.sparse_read_P.addrs(1)(2 downto 0);
        
        -- v.read_URAM_delay0(0) is overwritten in axpy1 state
        v.read_URAM_delay0(0) := re.sparse_read_P.valids(0);
        v.read_URAM_delay1(0) := re.sparse_read_P.valids(1);
        
        for l in 0 to NUM_READ_PORTS - 1 loop
			-- set read pull fifo signal
			-- The solver pulls as soon as data is availlable, since the kernel has space to store/process 
			-- the read data it requests at the moment the read request is given.
            v.read_fifo_valids(l) := r.read_fifo_valids(l)(READ_FIFO_LATENCY - 1 downto 0) & r.read_fifo_pulls(l);
            if (read_ins(l).fifo_almost_empty = '0' OR (read_ins(l).fifo_empty = '0' AND r.read_fifo_pulls(l) = '0')) AND re.read_ready(l) = '1' then
                v.read_fifo_pulls(l) := '1';
            end if;
			-- Send a read done signal to the vector_ops and sparstition units after a read request has ended and its fifo has been read empty.
            v.next_read_dones(l) := r.read_rq_done(l) AND read_ins(l).fifo_empty;
            if read_ins(l).rq_end = '1' then
                v.read_rq_done(l) := '1';
                v.debug_read_done(l) := '1'; 
            end if;
			-- Reset the given read done signal after it has been acknowledged by the receiving units.
			if re.read_ack(l) = '1' then
                v.read_rq_done(l) := '0';
            end if;
            -- count reads and writes (only used for debugging purposes)
            if r.read_fifo_pulls(l) = '1' then
                v.read_counts(l) := r.read_counts(l) + 1;
            end if;
        end loop;
        
        -- Set URAM signals
        v.field_re(0) := r.read_URAM_delay0(INT_VECTOR_MEM_LATENCY - 1);
        v.field_re(1) := r.read_URAM_delay1(INT_VECTOR_MEM_LATENCY - 1);
        v.URAM_out_data(0) := index(re.URAM_out0, to_integer(r.read_URAM_addr_lsb0(INT_VECTOR_MEM_LATENCY - 1)), FIELD_WIDTH);
        v.URAM_out_data(1) := index(re.URAM_out1, to_integer(r.read_URAM_addr_lsb1(INT_VECTOR_MEM_LATENCY - 1)), FIELD_WIDTH);
        for l in 0 to 7 loop
            v.debug_URAM0_out_fields(l) := index(re.URAM_out0, l, FIELD_WIDTH);
            v.debug_URAM1_out_fields(l) := index(re.URAM_out1, l, FIELD_WIDTH);
        end loop;

        -- give read done signals
        v.read_dones := r.next_read_dones;
        
        -- default read request signals (read0_rq is overwritten during initialization states)
        v.read_rqs := re.read_rqs;

        -- write_done signals
        for l in 0 to NUM_WRITE_PORTS - 1 loop
            if (write_ins(l).rq_end = '1' AND r.write_sel(l) = '1') OR r.write_sel(l) = '0' then
                v.write_dones(l) := '1';
            end if;
            if r.write_valid = '1' AND r.write_sel(l) = '1' then
                v.write_counts(l) := r.write_counts(l) + 1;
            end if;
        end loop;
        
		-- The iter_num variable contains the iteration number counted in half iterations, 
		-- So the lsb shows whether the solver is in the first or second half of an iteration
		-- and the second least significant bit shows whether the current (full) iteration number is even or odd
        v.criteria(is_even_iter)  := r.iter_num(1);
        v.criteria(is_first_iter) := bool2sl(r.iter_num(15 downto 1) = 0);
        v.criteria(is_final_iter) := bool2sl(r.iter_num(15 downto 1) = unsigned(max_iters));
	    v.criteria(is_half_iter)  := r.iter_num(0);
        
        case r.state is
            when idle =>
                v.fields(one) := x"3ff0000000000000";
                
                v.read_counts  := (others => (others => '0'));
                v.write_counts := (others => (others => '0'));
                v.iter_num := (others => '0');

                v.URAM_enable := '0';
                v.read_rqs(0).addr   := (others => '0');
                v.debug_vector_count := (others => '0');
                v.read_rqs(0).size   := to_unsigned(5, READ_RQ_SIZE_WIDTH);
                if start = '1' then
                    v.compute_done := '0';
                	v.read_rqs(0).valid := '1';
                	v.criteria(is_half_iter) := '1';
                    v.debug_read_done := (others => '0'); 
                	v.init_read_count := "000";
                	v.state := init_read;
                end if;
            when init_read =>
                case r.init_read_count is
                    when "000" =>
                        v.matrix_sizes(SpMV).row_size := unsigned(read_ins(0).fifo_data(MAT_SIZE_WIDTH - 1 downto 0));
                        v.matrix_sizes(SpMV).val_size := unsigned(read_ins(0).fifo_data(MAT_SIZE_WIDTH + 31 downto 32));
                        v.matrix_sizes(SpMV).num_colors := unsigned(read_ins(0).fifo_data(MAX_COLORS_DEPTH + 63 downto 64));
                        v.do_reset_debug := read_ins(0).fifo_data(96);
                        v.absolute_compare := read_ins(0).fifo_data(97);
                        v.vector_addrs(vect_r1)    := unsigned(index(read_ins(0).fifo_data, 2, CPU_ADDR_WIDTH));
                        v.vector_addrs(vect_r2)    := unsigned(index(read_ins(0).fifo_data, 3, CPU_ADDR_WIDTH));
                        v.vector_addrs(vect_x1)    := unsigned(index(read_ins(0).fifo_data, 4, CPU_ADDR_WIDTH));
                        v.vector_addrs(vect_x2)    := unsigned(index(read_ins(0).fifo_data, 5, CPU_ADDR_WIDTH));
                        v.vector_addrs(vect_p1)    := unsigned(index(read_ins(0).fifo_data, 6, CPU_ADDR_WIDTH));
                        v.vector_addrs(vect_p2)    := unsigned(index(read_ins(0).fifo_data, 7, CPU_ADDR_WIDTH));
                        if r.read_fifo_valids(0)(READ_FIFO_LATENCY - 1) = '1' then
                            v.init_read_count := "001";
                        end if;
                    when "001" =>              
                        -- store sizes and addresses into correct places.
                        v.matrix_sizes(L_FS).row_size         := unsigned(read_ins(0).fifo_data(MAT_SIZE_WIDTH - 1 downto 0));
                        v.matrix_sizes(L_FS).val_size         := unsigned(read_ins(0).fifo_data(MAT_SIZE_WIDTH + 31 downto 32));
                        v.matrix_sizes(L_FS).num_colors       := unsigned(read_ins(0).fifo_data(MAX_COLORS_DEPTH + 63 downto 64));
                        v.matrix_addrs(SpMV).color_sizes_addr := unsigned(index(read_ins(0).fifo_data, 2, CPU_ADDR_WIDTH));
                        v.matrix_addrs(SpMV).P_indices_addr   := unsigned(index(read_ins(0).fifo_data, 3, CPU_ADDR_WIDTH));
                        v.matrix_addrs(SpMV).nnz_vals_addr    := unsigned(index(read_ins(0).fifo_data, 4, CPU_ADDR_WIDTH));
                        v.matrix_addrs(SpMV).col_indices_addr := unsigned(index(read_ins(0).fifo_data, 5, CPU_ADDR_WIDTH));
                        v.matrix_addrs(SpMV).NRs_addr         := unsigned(index(read_ins(0).fifo_data, 6, CPU_ADDR_WIDTH));
                        v.vector_addrs(vect_rt)               := unsigned(index(read_ins(0).fifo_data, 7, CPU_ADDR_WIDTH));
                        if r.read_fifo_valids(0)(READ_FIFO_LATENCY - 1) = '1' then
                            v.init_read_count := "010";
                        end if;
                    when "010" =>
                        -- store sizes and addresses into correct places.
                        v.matrix_sizes(U_BS).row_size := unsigned(read_ins(0).fifo_data(MAT_SIZE_WIDTH - 1 downto 0));
                        v.matrix_sizes(U_BS).val_size := unsigned(read_ins(0).fifo_data(MAT_SIZE_WIDTH + 31 downto 32));
                        v.matrix_sizes(U_BS).num_colors := unsigned(read_ins(0).fifo_data(MAX_COLORS_DEPTH + 63 downto 64));
                        v.matrix_addrs(L_FS).color_sizes_addr := unsigned(index(read_ins(0).fifo_data, 2, CPU_ADDR_WIDTH));
                        v.matrix_addrs(L_FS).P_indices_addr   := unsigned(index(read_ins(0).fifo_data, 3, CPU_ADDR_WIDTH));
                        v.matrix_addrs(L_FS).nnz_vals_addr    := unsigned(index(read_ins(0).fifo_data, 4, CPU_ADDR_WIDTH));
                        v.matrix_addrs(L_FS).col_indices_addr := unsigned(index(read_ins(0).fifo_data, 5, CPU_ADDR_WIDTH));
                        v.matrix_addrs(L_FS).NRs_addr         := unsigned(index(read_ins(0).fifo_data, 6, CPU_ADDR_WIDTH));
                        v.matrix_addrs(U_BS).block_diag_addr  := unsigned(index(read_ins(0).fifo_data, 7, CPU_ADDR_WIDTH));
                        if r.read_fifo_valids(0)(READ_FIFO_LATENCY - 1) = '1' then
                            v.init_read_count := "011";
                        end if;
                    when "011" =>
                        -- store sizes and addresses into correct places.
                        v.matrix_addrs(U_BS).color_sizes_addr := unsigned(index(read_ins(0).fifo_data, 0, CPU_ADDR_WIDTH));
                        v.matrix_addrs(U_BS).P_indices_addr   := unsigned(index(read_ins(0).fifo_data, 1, CPU_ADDR_WIDTH));
                        v.matrix_addrs(U_BS).nnz_vals_addr    := unsigned(index(read_ins(0).fifo_data, 2, CPU_ADDR_WIDTH));
                        v.matrix_addrs(U_BS).col_indices_addr := unsigned(index(read_ins(0).fifo_data, 3, CPU_ADDR_WIDTH));
                        v.matrix_addrs(U_BS).NRs_addr         := unsigned(index(read_ins(0).fifo_data, 4, CPU_ADDR_WIDTH));
                        v.vector_addrs(vect_t)                := unsigned(index(read_ins(0).fifo_data, 5, CPU_ADDR_WIDTH));
                        v.vector_addrs(vect_v)                := unsigned(index(read_ins(0).fifo_data, 6, CPU_ADDR_WIDTH));
                        v.vector_addrs(res_L)                 := v.vector_addrs(vect_v) + round_up_to_index(r.matrix_sizes(SpMV).row_size, 3) ;
                        v.vector_addrs(res_U)                 := v.vector_addrs(vect_v) + 2 * round_up_to_index(r.matrix_sizes(SpMV).row_size, 3);
--                        v.fields(precision)                   := read_ins(0).fifo_data(448 + FIELD_WIDTH - 1 downto 448);
                        if r.absolute_compare = '1' then
                            v.fields(precision)               := desired_precision;
                        else
                            v.fields(precision)               := ALREADY_SOLVED_PRECISION;
                        end if;
                        if r.read_fifo_valids(0)(READ_FIFO_LATENCY - 1) = '1' then
                            v.init_read_count := "100";
                        end if;
                    when "100" =>
                        -- Nothing is read from the 5th line of the second file. 
						-- When multiple nnz_vals arrays are spported again, their addresses will be read from here.

                        if r.read_fifo_valids(0)(READ_FIFO_LATENCY - 1) = '1' then
                            v.init_read_count := "101";
                        end if;
                    when others =>
                        NULL;
                end case;
            	if r.init_read_count = "101" AND r.read_rq_done(0) = '1' then
            	    v.read_rq_done(0) := '0';
                    v.debug_read_done := (others => '0'); 
					-- Start the reading of the starting X vector
                    v.next_step := PROGRAM(0);
                    v.state := read_x;
                    v.read_rqs(3).addr  := r.vector_addrs(vect_x1);
                    v.read_rqs(3).size  := round_up_to_index(r.matrix_sizes(SpMV).row_size(READ_RQ_SIZE_WIDTH + FIELDS_PER_LINE_DEPTH - 1 downto 0), FIELDS_PER_LINE_DEPTH);
                    v.read_rqs(3).valid := '1';

                    v.URAM_addr1 := (others => '0');
                    v.read_counts  := (others => (others => '0'));
                    v.write_counts := (others => (others => '0'));
            	end if;
            when read_x =>
            	v.URAM_enable := '1';
                v.URAM_in_data1 := read_ins(3).fifo_data;
				-- Write the initial X vector to the URAM
                if r.read_fifo_valids(3)(READ_FIFO_LATENCY - 1) = '1' then
                    v.URAM_we1 := (others => '1');
                end if;

                if r.URAM_we1(0) = '1' then
            		v.URAM_addr1 := r.URAM_addr1 + 8;
            	end if;
                
                if r.read_rq_done(3) = '1' AND read_ins(3).fifo_empty = '1' AND r.URAM_addr1 >= r.matrix_sizes(SpMV).row_size(vector_addr_range) then
                    v.read_rq_done(3) := '0';
                    v.state_done := '1';
                    v.URAM_addr1 := (others => '0');
                    v.iter_num := (others => '1');
                end if;
            when SpMV =>
                v.sparse_start := r.first_cycle;
                v.apply_ILU0 := '0';
                v.URAM_enable := '1';       

                -- read/write from/to the URAM at the addresses provided by the sparstition unit
                if re.sparse_write_field.valid = '1' then
                	v.URAM_addr2 := re.sparse_write_field.addr;
                    for l in 0 to 7 loop
                	   v.URAM_we2(to_integer(re.sparse_write_field.addr(2 downto 0)) * 8 + l) := '1';
                	end loop;
               	else
               		v.URAM_addr2 := re.sparse_read_P.addrs(1);
                end if;

                v.URAM_addr1 := re.sparse_read_P.addrs(0);
                for l in 0 to 7 loop
                    v.URAM_in_data2(FIELD_WIDTH * (l + 1) - 1 downto FIELD_WIDTH * l) := re.sparse_write_field.data;
                end loop;               
                v.write_line  := re.sparse_write_line.data;
		        v.write_valid := re.sparse_write_line.valid;

                -- register done signals
                if re.sparse_done = '1' then
                    v.calc_done := '1';
                end if;
                if r.calc_done = '1' then
                    v.URAM_addr1 := (others => '0');
                    v.URAM_addr2 := (others => '0');
                end if; 
                if r.calc_done  = '1' AND r.write_dones(2) = '1' then
                    v.state_done := '1';
                    v.write_dones(2) := '0';
                end if;

            when ILU0_L_fs =>
                v.sparse_start := r.first_cycle;
                v.apply_ILU0 := '1';
                
                v.URAM_enable := '1';

                -- read/write from/to the URAM at the addresses provided by the sparstition unit
                if re.sparse_write_field.valid = '1' then
                    v.URAM_addr2 := re.sparse_write_field.addr;
                    for l in 0 to 7 loop
                	   v.URAM_we2(to_integer(re.sparse_write_field.addr(2 downto 0)) * 8 + l) := '1';
                	end loop;
                else
                    v.URAM_addr2 := re.sparse_read_P.addrs(1);
                end if;
                v.URAM_addr1 := re.sparse_read_P.addrs(0);
                for l in 0 to 7 loop
                    v.URAM_in_data2(FIELD_WIDTH * (l + 1) - 1 downto FIELD_WIDTH * l) := re.sparse_write_field.data;
                end loop;
                
                v.write_line  := re.sparse_write_line.data;
		        v.write_valid := re.sparse_write_line.valid;
                
                v.state_done := re.sparse_L_done AND and_reduce(r.write_dones OR NOT(r.write_sel));-- AND NOT(r.state_done);
                
                if re.sparse_L_done = '1' then
                    v.URAM_addr1 := (others => '0');
                    v.URAM_addr2 := (others => '0');
                end if;
                
            when ILU0_U_bs =>
                v.sparse_start := r.first_cycle;
                v.apply_ILU0 := '1';
                
                v.URAM_enable := '1';

                -- read/write from/to the URAM at the addresses provided by the sparstition unit
                if re.sparse_write_field.valid = '1' then
                    v.URAM_addr2 := re.sparse_write_field.addr;
                    for l in 0 to 7 loop
                	   v.URAM_we2(to_integer(re.sparse_write_field.addr(2 downto 0)) * 8 + l) := '1';
                	end loop;
                else
                    v.URAM_addr2 := re.sparse_read_P.addrs(1);
                end if;
                v.URAM_addr1 := re.sparse_read_P.addrs(0);
                for l in 0 to 7 loop
                    v.URAM_in_data2(FIELD_WIDTH * (l + 1) - 1 downto FIELD_WIDTH * l) := re.sparse_write_field.data;
                end loop;

                v.write_line  := re.sparse_write_line.data;
		        v.write_valid := re.sparse_write_line.valid;
                
                if re.sparse_done = '1' then
                    v.calc_done := '1';
                end if;
                
                v.state_done := r.calc_done AND and_reduce(r.write_dones OR NOT(r.write_sel));
                
                if r.calc_done = '1' then
                    v.URAM_addr1 := (others => '0');
                    v.URAM_addr2 := (others => '0');
                end if;
            when dot1 =>
                --TODO: incorporate the write for rt to p in the first iteration
                v.dot_axpy_start := r.first_cycle;
                v.vect_op_sel := dot1;
                
                -- set division inputs
                -- TODO: The following code is hardcoded while a more elaborate program step system could make this more flexible
                if r.divide_set = '0' then
                    if r.current_step.dot_res = alpha then
                        -- during step 5, divide rho_new by the dot result
                        v.divide_set := re.vect_op_done;
                        v.divident := r.fields(rho_new);
                        v.divisor  := re.dot1_result;
                        v.do_divide := re.vect_op_done;
                    else
                        -- during step 13, first divide the result by the old rho_new, make this rho_new rho, and make the dot result rho_new
                        if r.do_divide = '0' then
                            if re.vect_op_done = '1' then
                                v.divident := re.dot1_result;
                                v.fields(rho_new) := re.dot1_result;
                                v.fields(rho) := r.fields(rho_new);
                                v.divisor := r.fields(rho_new);
                                v.do_divide := '1';
                            end if;
                        else
                        --  right after this happens, divide alpha by omega
                            v.divident := r.fields(alpha);
                            v.divisor  := r.fields(omega);
                            v.do_divide := '1';
                            v.divide_set := '1';
                        end if;
                    end if;
                end if;
                -- set multiply inputs
                if r.multiply_set = '0' AND r.current_step.dot_res = beta then
                    v.multiply_set := re.divide_valid;
                    v.multiply_in1 := re.divide_result;
                elsif r.multiply_set = '1' AND r.current_step.dot_res = beta then
                    v.multiply_in2 := re.divide_result;
                    v.do_multiply := '1';
                    v.state_done := re.multiply_valid;-- AND NOT(r.state_done);
                    v.fields(beta) := re.multiply_result;
                else
                    v.state_done := re.divide_valid; --AND NOT(r.state_done);
                    v.fields(r.current_step.dot_res) := re.divide_result;
                end if;
            when dot2 =>
                v.dot_axpy_start := r.first_cycle;
                v.vect_op_sel := dot2;

                -- do division
                v.divident := re.dot1_result;
                v.divisor  := re.dot2_result;
                v.do_divide := re.vect_op_done;
                if re.divide_valid = '1' then
                    v.fields(r.current_step.dot_res) := re.divide_result;
                end if;
                v.state_done := re.divide_valid;
            when axpy1 =>
                v.dot_axpy_start := r.first_cycle;
                v.vect_op_sel := axpy1;

                v.URAM_enable := '1';
                -- Read internal vector into read fifo 1
                v.read_URAM_delay0(0) := re.vect_URAM_read_ready AND bool2sl(r.URAM_addr1 + 8 < r.matrix_sizes(SpMV).row_size(vector_addr_range));
                if r.read_URAM_delay0(0) = '1' then 
                    v.URAM_addr1 := r.URAM_addr1 + 8;
                end if;
                
                v.write_line  := re.vect_write_line;
		        v.write_valid := re.vect_write_valid;
                
                -- buffer done signals
                if re.vect_op_done = '1' then
                    v.calc_done := '1';
                    v.URAM_addr1 := (others => '0');
                end if;

                if r.calc_done = '1' AND r.write_dones = "111" then
                    v.state_done := '1';
                    v.calc_done := '0';
                end if;
            when axpy2 =>
                v.dot_axpy_start := r.first_cycle;
                v.vect_op_sel := axpy2;
                
                v.write_line  := re.vect_write_line;
		        v.write_valid := re.vect_write_valid;
                
                v.do_square_root := re.vect_op_done;
                
                -- write the axpy result to URAM
                v.URAM_enable := '1';
                
                if re.vect_write_valid = '1' then                   
                	v.URAM_we2 := (others => '1');
                end if;
                if r.URAM_we2(0) = '1' then
                    v.URAM_addr2 := r.URAM_addr2 + 8;
                end if;
                v.URAM_in_data2 := re.vect_write_line;
                
                -- hardcoded code for calculating the desired precision.
                if r.current_step.dot_res = rho_new AND r.absolute_compare = '0' then
                    v.multiply_in1 := desired_precision;
                    v.multiply_in2 := re.square_root_result;
                    v.do_multiply  := re.square_root_valid;
                end if;
                if re.compare_valid = '1' then
                    v.divide_set := '1';
--                    v.calc_done := '1';
                    v.URAM_addr2 := (others => '0');
                end if;
                if re.multiply_valid = '1' then
                    v.multiply_set := '1';
                end if;
				-- All calculations in this state are done if the compare is done, and if it is either:
				--  * set to do a compare with an  absolute exit precision
				--  * In the initial residual calculation (iteration -1) (this is where dot_res is written to rho_new)
				--  * Done with the multiplication of the desired precision and the most recent norm.
                v.calc_done := r.divide_set AND (r.absolute_compare OR bool2sl(r.current_step.dot_res /= rho_new) OR r.multiply_set);

                if r.calc_done = '1' AND r.write_dones = "111" then
                    v.fields(r.current_step.dot_res) := re.dot2_result;
					-- update the precision if the exit precision is relative
                    if r.current_step.dot_res = rho_new AND r.absolute_compare = '0' then
                        v.fields(precision) := re.multiply_result;
                    end if;
                    v.prev_norms(to_integer(r.norm_count)) := re.square_root_result;
                    if r.norm_count = 3 then
                        v.norm_count := to_unsigned(1, 2);
                    else
                        v.norm_count := r.norm_count + 1;
                    end if;
                    v.calc_done := '0';
                    v.divide_set := '0';
                    v.multiply_set := '0';
					-- If the norm result is lower than the desired precision, the solver is done
                    if re.compare_result(0) = '0' then
                        v.state := write_debug;
                        v.no_change := bool2sl(r.current_step.dot_res = rho_new);
                    else
					-- otherwise, another half iteration is needed
                        v.state_done := '1';
                        if r.next_step.state = write_debug then
                            v.iteration_end := '0';
                        else
                            v.iteration_end := '1';
                            v.iter_num := r.iter_num + 1;
                        end if;
                    end if;
                end if;
            when calc_p =>
                v.dot_axpy_start := r.first_cycle;
                v.vect_op_sel := update_p;

                -- write the axpy result to URAM
                v.URAM_enable := '1';
                
                if re.vect_write_valid = '1' then                   
                	v.URAM_we2 := (others => '1');
                end if;
                if r.URAM_we2(0) = '1' then
                    v.URAM_addr2 := r.URAM_addr2 + 8;
                end if;
                v.URAM_in_data2 := re.vect_write_line;
                
                v.write_line  := re.vect_write_line;
		        v.write_valid := re.vect_write_valid;
                
                if re.vect_op_done = '1' then
                    v.calc_done := '1';
                    
                    v.URAM_addr2 := (others => '0');
                end if;

                v.state_done := r.calc_done AND bool2sl(r.write_dones = "111") ;
                if r.state_done = '1' then
                    v.state_done := '0';
                    v.calc_done := '0';
                end if;

            when write_debug =>
				-- The final state of the solver: wait until the latest debug read finishes, and then exit with a done
                v.compute_done := '1';
                v.debug_write_rq.valid := '0';
                v.sparse_debug_valid := r.debug_write_rq.valid;
                --if debug_write_ins.rq_end = '1' then
                if r.debug_done = '1' then
                	v.done  := '1';
                	v.iteration_end := '1';
                	v.state := idle;
                end if;

            when others =>
                NULL;
        end case;
        
        -- default state-change logic. overwritten by initialization/finalization states
		-- The above state machine does not handle the majority of state changes,
		-- but rather sets a state_done signal, which triggers the below logic.

        v.first_cycle := r.state_done; --debug_next_state;
        if r.state_done = '1' then --debug_next_state = '1'  then -- should be r.state_done, made debug signal for running tests
			-- All state-specific done and count signals are reset
            v.read_counts := (others => (others => '0'));
            v.write_counts := (others => (others => '0'));
            v.debug_read_done := (others => '0'); 
            v.state_done    := '0';
            v.write_dones   := "000";
            v.calc_done     := '0';
            v.divide_set    := '0';
            v.multiply_set  := '0';
			-- The next state is set, and the matrix used in that state (if any) is set to the active one.
            v.state         := r.next_step.state;
            v.sparse_sizes  := r.matrix_sizes(r.next_step.matrix);
            v.sparse_addrs  := r.matrix_addrs(r.next_step.matrix);
			-- The vector write requests of the upcoming state are given and the read addresses are set
            if (r.next_step.state = ILU0_L_fs OR r.next_step.state = ILU0_U_bs) AND WRITE_ILU0_RESULTS then
                v.write_sel := "100";
            else
                v.write_sel     := r.next_step.active_writes;
            end if;
            for l in 0 to 2 loop
                v.read_vect_addr(l) := r.vector_addrs(r.next_step.read_vects(l));
                v.write_rqs(l).addr := r.vector_addrs(r.next_step.write_vects(l));
                v.write_rqs(l).size := round_up_to_index(r.matrix_sizes(SpMV).row_size(WRITE_RQ_SIZE_WIDTH + FIELDS_PER_LINE_DEPTH - 1 downto 0), FIELDS_PER_LINE_DEPTH);
                v.write_rqs(l).valid := v.write_sel(l);
            end loop;
           	-- The step after the one that is being switched to is determined and lined up as next_step
            if r.criteria(r.next_step.criterion) = '1' then
                v.next_step := PROGRAM(to_integer(r.next_step.next_step1));
            else
                v.next_step := PROGRAM(to_integer(r.next_step.next_step0));
            end if;
            v.current_step  := r.next_step;
        end if;

        --debug initializations
        v.debug_write_rq.valid := '0';
        v.sparse_debug_valid := '0';

        -- fill debug write line
        if r.state_done = '1' AND r.do_reset_debug = '1' then
            v.sparse_debug_line(63 downto 0) := (others => '0');
        else
            v.sparse_debug_line(31 downto 0) := r.sparse_debug_line(31 downto 0) OR re.sparse_debug_line.data(31 downto 0);
            for l in 0 to NUM_READ_PORTS - 1 loop
                if r.read_fifo_pulls(l) = '1' AND read_ins(l).fifo_empty = '1' then
                    v.sparse_debug_line(32 + l) := '1';
                end if;
            end loop;
            -- vector fifo overflows and underflows
            for l in 0 to 2 loop
                v.sparse_debug_line(40 + l) := r.sparse_debug_line(40 + l) OR re.vect_debug_data(l);
                v.sparse_debug_line(44 + l) := r.sparse_debug_line(44 + l) OR re.vect_debug_data(l + 3);
            end loop;
            
            -- obtain read/write request debug signals.
            for l in 0 to NUM_READ_PORTS - 1 loop
                if r.read_rqs(l).valid = '1' then
                    if r.read_request_active(l) = '0' then
                        v.read_request_active(l) := '1';
                    else
                        v.sparse_debug_line(48 + l) := '1';
                    end if;
                end if;
                if read_ins(l).rq_end = '1' then
                    v.read_request_active(l) := '0';
                end if;
            end loop;
            for l in 0 to NUM_WRITE_PORTS - 1 loop
                if r.write_rqs(l).valid = '1' then
                    if r.write_request_active(l) = '0' then
                        v.write_request_active(l) := '1';
                    else
                        v.sparse_debug_line(53 + l) := '1';
                    end if;
                end if;
                if write_ins(l).rq_end = '1' then
                    v.write_request_active(l) := '0';
                end if;
            end loop;
            
            v.sparse_debug_line(59 downto 56) := r.sparse_debug_line(59 downto 56) OR re.vect_debug_data(9 downto 6);
            
            v.sparse_debug_line(59 + SPMVP_OUTPUT_NUM downto 60) := r.sparse_debug_line(59 + SPMVP_OUTPUT_NUM downto 60) OR re.sparse_debug_line.data(31 + SPMVP_OUTPUT_NUM downto 32);
        end if;

        v.sparse_debug_line(79 downto 64)   := std_logic_vector(r.read_counts(2));
        v.sparse_debug_line(95 downto 80)   := std_logic_vector(r.read_counts(3));
        v.sparse_debug_line(111 downto 96)  := std_logic_vector(r.read_counts(4));
        v.sparse_debug_line(143 downto 128) := std_logic_vector(r.write_counts(0));
        v.sparse_debug_line(159 downto 144) := std_logic_vector(r.write_counts(1));
        v.sparse_debug_line(175 downto 160) := std_logic_vector(r.write_counts(2));
        v.sparse_debug_line(179 downto 176) := solver_state_encoding(r.state);
        v.sparse_debug_line(185 downto 184) := re.vect_debug_data(14 downto 13);
        v.sparse_debug_line(189 downto 188) := re.vect_debug_data(16 downto 15);
        v.sparse_debug_line(199 downto 192) := re.sparse_encoded_state;
        v.sparse_debug_line(200) := r.debug_read_done(0);
        v.sparse_debug_line(201) := read_ins(0).fifo_empty;
        v.sparse_debug_line(202) := re.vect_debug_data(10);
        v.sparse_debug_line(203) := r.debug_read_done(1);
        v.sparse_debug_line(204) := read_ins(1).fifo_empty;
        v.sparse_debug_line(205) := re.vect_debug_data(11);
        v.sparse_debug_line(206) := re.vect_debug_data(12);
        v.sparse_debug_line(223 downto 208) := std_logic_vector(r.num_debug_writes);
        v.sparse_debug_line(239 downto 224) := std_logic_vector(r.iter_num);
        
        for l in 0 to 3 loop
            v.sparse_debug_line(319 + FIELD_WIDTH * l downto 256 + FIELD_WIDTH * l) := r.prev_norms(l);
        end loop;

        -- debug count signals
        case r.debug_state is
            when idle =>
                v.debug_count := (others => '0');
                v.num_debug_writes := (others => '0');
                v.is_last_debug_write := '0';
                v.debug_address := to_unsigned(DEBUG_PORT_START_IDX,v.debug_address'length);
                if start = '1' then
                    -- use debug_rate and debug_lines port values only if greater than 0,
                    -- otherwise use defaults
                    if to_integer(unsigned(debug_rate)) > 0 then
                      v.debug_rate := unsigned(debug_rate);
                    else
                      v.debug_rate := to_unsigned(1024,v.debug_rate'length);
                    end if;
                    if to_integer(unsigned(debug_lines)) > 0 then
                      v.debug_lines := unsigned(debug_lines);
                    else
                      v.debug_lines := to_unsigned(511,v.debug_lines'length);
                    end if;
                    v.debug_done := '0';
                    v.debug_state := count;
                end if;
            when count =>
                if r.compute_done = '1' AND r.is_last_debug_write = '1' then
                    v.debug_done := '1';
                    v.debug_state := idle;
                elsif r.debug_count >= r.debug_rate OR r.compute_done = '1' then
                    v.debug_count := (others => '0');
                    v.is_last_debug_write := r.compute_done;
                    v.num_debug_writes := r.num_debug_writes + 1;
                    v.debug_write_rq.valid := '1';
                    v.debug_write_rq.addr := r.debug_address;
                    v.debug_write_rq.size := to_unsigned(1, WRITE_RQ_SIZE_WIDTH);
                    v.sparse_debug_valid := '1';
                    if r.debug_address >= r.debug_lines then
                        v.debug_address := to_unsigned(DEBUG_PORT_START_IDX,v.debug_address'length);
                    else
                        v.debug_address := r.debug_address + 1;
                    end if;
                    v.debug_state := write;
                else
                    v.debug_count := r.debug_count + 1;
                end if;
            when write =>
                if debug_write_ins.rq_end = '1' then
                    v.debug_state := count;
                end if;
            when others =>
                NULL;
        end case;

        -- output signals
        for l in 0 to NUM_READ_PORTS - 1 loop
            read_outs(l) <= set_read_outs(r.read_rqs(l), r.read_fifo_pulls(l));
        end loop;
        
        for l in 0 to NUM_WRITE_PORTS - 1 loop
            write_outs(l) <= set_write_outs(r.write_rqs(l),  r.write_line, r.write_valid AND r.write_sel(l)); 
        end loop;
        debug_write_outs <= set_write_outs(r.debug_write_rq, r.sparse_debug_line, r.sparse_debug_valid); 

        done <= r.done;
        no_change <= r.no_change;
		
        iteration_end <= r.iteration_end;

        q <= v;
        
--        debug_state_change <= v.state_done;
    end process;

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= SOLVER_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;
    
-- synthesis translate_off
-- DEBUG code to print all memory transactions, including data read/written
-- It's placed here in order to be used also when doing co-simulation with SDAccel
print_trans_proc: process(clk)
    variable lineout: line;
    begin
        if rising_edge(clk) and ( or_reduce(std_logic_vector(to_unsigned(SIM_DEBUG,32) and to_unsigned(SIM_DEBUG_MT,32)))='1' ) then
            if or_reduce(std_logic_vector(to_unsigned(SIM_DEBUG,32) and to_unsigned(SIM_DEBUG_MT_RD,32)))='1' then
                for l in 0 to NUM_READ_PORTS - 1 loop
                    -- dump read request
                    if (r.read_rqs(l).valid = '1') then
                        write(lineout,string'("DBGMT:  READ on port "));
                        write(lineout,l);
                        write(lineout,string'(", time="));
                        write(lineout,time'image(now));
                        write(lineout,string'(" - addr="));
                        write(lineout,string'("0x"));
                        hwrite(lineout,std_logic_vector( r.read_rqs(l).addr(63 downto 0) ));
                        write(lineout,string'(" "));
                        write(lineout,to_integer(unsigned( r.read_rqs(l).addr(63 downto 32)) ));
                        write(lineout,string'("|"));
                        write(lineout,to_integer(unsigned( r.read_rqs(l).addr(31 downto 0)) ));
                        write(lineout,string'(", size="));
                        write(lineout,to_integer(unsigned(r.read_rqs(l).size)));
                        writeline(output, lineout);
                    end if;
                    -- dump read data
                    if (reads(l).valid = '1') then
                        write(lineout,string'("DBGMT:    READ data, port "));
                        write(lineout,l);
                        write(lineout,string'(", time="));
                        write(lineout,time'image(now));
                        write(lineout,string'(" - 0x "));
                        hwrite(lineout,std_logic_vector( reads(l).data(511 downto 448) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( reads(l).data(447 downto 384) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( reads(l).data(383 downto 320) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( reads(l).data(319 downto 256) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( reads(l).data(255 downto 192) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( reads(l).data(191 downto 128) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( reads(l).data(127 downto 64) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( reads(l).data(63 downto 0) ));
                        writeline(output, lineout);
                    end if;
                end loop;
            end if;
            if or_reduce(std_logic_vector(to_unsigned(SIM_DEBUG,32) and to_unsigned(SIM_DEBUG_MT_WR,32)))='1' then
                -- dump write request
                for l in 0 to NUM_HBM_WRITE_PORTS - 1 loop
                    if (r.write_rqs(l).valid = '1') then
                        write(lineout,string'("DBGMT: WRITE on port "));
                        write(lineout,l);
                        write(lineout,string'(", time="));
                        write(lineout,time'image(now));
                        write(lineout,string'(" - addr="));
                        write(lineout,string'("0x"));
                        hwrite(lineout,std_logic_vector( r.write_rqs(l).addr(63 downto 0) ));
                        write(lineout,string'(" "));
                        write(lineout,to_integer(unsigned( r.write_rqs(l).addr(63 downto 32)) ));
                        write(lineout,string'("|"));
                        write(lineout,to_integer(unsigned( r.write_rqs(l).addr(31 downto 0)) ));
                        write(lineout,string'(", size="));
                        write(lineout,to_integer(unsigned( r.write_rqs(l).size)));
                        writeline(output, lineout);
                    end if;
                    -- dump write data
                    if (r.write_valid = '1' AND r.write_sel(l) = '1') then
                        write(lineout,string'("DBGMT:   WRITE data, port "));
                        write(lineout,l);
                        write(lineout,string'(", time="));
                        write(lineout,time'image(now));
                        write(lineout,string'(" - 0x "));
                        hwrite(lineout,std_logic_vector( r.write_line(511 downto 448) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( r.write_line(447 downto 384) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( r.write_line(383 downto 320) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( r.write_line(319 downto 256) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( r.write_line(255 downto 192) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( r.write_line(191 downto 128) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( r.write_line(127 downto 64) ));
                        write(lineout,string'(" "));
                        hwrite(lineout,std_logic_vector( r.write_line(63 downto 0) ));
                        writeline(output, lineout);
                    end if;
                end loop;
            end if;
        end if;
    end process;
-- synthesis translate_on

end behavioral;
