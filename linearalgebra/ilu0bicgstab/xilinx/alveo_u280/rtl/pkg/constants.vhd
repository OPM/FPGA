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

package constants is

    type integer_array is array (integer range <>) of integer;
    constant u_zero : unsigned(63 downto 0) := (others => '0');
    constant bit_0: std_logic := '0';
    constant bit_1: std_logic := '1';

    -- set constant to tell if the current mode is synthesis or simulation
    constant SIM_ON : boolean := false
    --pragma synthesis_off
      or true
    --pragma synthesis_on
      ;
    constant SYNTH_ON  : boolean := not SIM_ON;

    constant DMA_DATA_WIDTH    : integer := 512;
    constant DMA_DATA_DEPTH    : integer := integer(ceil(log2(real(DMA_DATA_WIDTH))));
    constant CPU_ADDR_WIDTH    : integer := 64;

    -- design flags

    -- enable writing ILU0 results along with normal results
    constant WRITE_ILU0_RES : boolean := false;

    -- Switch between block ram and distributed memory
    constant USE_BRAM_OFFSET_FIFO   : boolean := false; -- amount of buffers: MULT_DEPTH + 1        of size: MULT_NUM * OFFSET_WIDTH * ADDER_DELAY
    -- The use of BRAM blocks is currently not supported in the adder tree if the tree pipeline is blocking
    constant USE_BRAM_ADD_TREE_FIFO : boolean := true; -- amount of buffers: MULT_DEPTH * MULT_NUM of size: FIELD_WIDTH * ADDER_DELAY
    -- Switch between outputting intermediate results of reduce stages is a row is done or nor
    -- Advantage of doing so:     lower latency (effect size depends on sparsity pattern)
    -- Advantage of not doing so: fewer resources in write_merge, less logic in reduce stages
    -- Deprecated: newest write_merge does not support the merging of intermidiate reduce results.
    --constant INTERMEDIATE_REDUCE_RESULTS : integer := 0;

    -- Constants related to the solver as a function:
    -- NOTE: the below constant is specifically for fields of the double type
    constant ALREADY_SOLVED_THRESHOLD : real := 10.0**(0.0-30.0);

    -- Platform specific constants:

    -- use this constant to select between BRAMs and URAMs components for the complete vector
    constant USE_URAM          : boolean := true;
    
	-- constants specific to the Foating-Point IP cores used:
    constant ADD_DELAY         : integer := 14;
    constant ADD_DELAY_DEPTH   : integer := integer(ceil(log2(real(ADD_DELAY))));
    constant MULT_DELAY        : integer := 12;

    -- Matrix size specific constants:
    -- for VECTOR_SIZE_ELEM: when using URAM, the memory will be composed of blocks of 4096x64 bits,
    -- and the blocks will be concatenated per cacheline (e.g. minimum 8 blocks when cacheline is 512 bit),
    -- hence the number of elements should be aligned to 4096 * (number of elements in a cacheline)
    -- E.g.: 65536 elements => 2 rows of 8 URAMs = 16 URAMs ; 163840 elements => 5 rows of 8 URAMs = 40 URAMs
    constant VECTOR_SIZE_ELEM  : natural := 163840; -- number of elements the memory should hold
	-- MAX_ROW_SIZE is the limit for number of rows per color
    constant ROW_INDEX_WIDTH   : integer := 11;
    constant ROW_INDEX_DEPTH   : integer := integer(ceil(log2(real(ROW_INDEX_WIDTH))));
    constant MAX_ROW_SIZE      : integer := 2 ** ROW_INDEX_WIDTH;
	-- MAX_COLUMN_SIZE is the limit for number of columns shared by the rows in each column
    constant COL_INDEX_WIDTH   : integer := 13;
    constant COL_INDEX_DEPTH   : integer := integer(ceil(log2(real(COL_INDEX_WIDTH))));
    constant MAX_COLUMN_SIZE   : integer := 2 ** COL_INDEX_WIDTH;
	
    constant MAT_SIZE_DEPTH    : integer := 5;
    constant MAT_SIZE_WIDTH    : integer := 2 ** MAT_SIZE_DEPTH;

    constant P_INDS_MEM_SIZE_ELEM : integer := 512; -- size in elements (relative to port A) of the p_inds_mem vector

	-- MAX_MAT_PART_SIZE sets the maximum number of nonzeroes per matrix partition
    constant MAT_PART_ADDR_WIDTH : integer := 15;
    constant MAX_MAT_PART_SIZE   : integer := 2 ** MAT_PART_ADDR_WIDTH;
	-- MAX_MATRIX_SIZE sets the maximum number of nonzeroes in the matrix
    constant MATRIX_ADDR_WIDTH : integer := 21;
    constant MAX_MATRIX_SIZE   : integer := 2 ** MATRIX_ADDR_WIDTH;

	-- the width of double-precision floating point values is 2^6
    constant FIELD_DEPTH       : integer := 6;
    constant FIELD_WIDTH       : integer := 2 ** FIELD_DEPTH;
	-- the maximum value for new-row offsets is 2^OFFSET_WIDTH-1 = 255
    constant OFFSET_DEPTH      : integer := 3;
    constant OFFSET_WIDTH      : integer := 2 ** OFFSET_DEPTH;
    constant MAX_COLORS_DEPTH  : integer := 8;
    constant MAX_COLORS_SIZE   : integer := 2 ** MAX_COLORS_DEPTH;

    -- Design specific constants:
    constant MULT_DEPTH        : integer := 3;
    constant MULT_NUM          : integer := 8;
    
    constant SPMVP_OUTPUT_DEPTH : integer := 2;
    constant SPMVP_OUTPUT_NUM  : integer := 4;

    constant REDUCE_NUM        : integer := 4;
    constant MAX_REDUCE_LINES  : integer := 2 ** REDUCE_NUM;

    constant MAX_REDUCE_NUM    : integer := 4;

    constant DEBUG_PORT_START_IDX   : integer := 1; -- start index for debug cachelines written by the kernel

    -- Constants related to memory latency (Specific to the IP cores used)
    constant READ_FIFO_LATENCY      : integer := 2;
    constant SPMV_FIFO_LATENCY      : integer := 1;
    constant SPMV_X_LOOKUP_LATENCY  : integer := 4;
    -- WARNING: the latencies for the INT_VECTOR_MEM_LATENCY_xxx constants must
    -- be incremented by 1 vs. the actual latencies used by the IPs, because of
    -- the additional word selection logic present at their outputs.
    constant INT_VECTOR_MEM_LATENCY_BRAM : integer := 3;  -- set this latency for BRAMs
    constant INT_VECTOR_MEM_LATENCY_URAM : integer := 4;  -- set this latency for URAMs
    --constant INT_VECTOR_MEM_LATENCY_URAM_SIM : integer := 4; -- set this latency for URAMs in SIMULATION
    --constant INT_VECTOR_MEM_LATENCY_URAM_SYN : integer := 4; -- set this latency for URAMs in SYNTHESIS
    --type     uram_simsyn_sel_t is array (boolean) of integer;
    --constant uram_simsyn_sel: uram_simsyn_sel_t := (true => INT_VECTOR_MEM_LATENCY_URAM_SYN, false => INT_VECTOR_MEM_LATENCY_URAM_SIM);
    --constant INT_VECTOR_MEM_LATENCY_URAM : integer := uram_simsyn_sel(SYNTH_ON);
    type     latency_sel_t is array (boolean) of integer;
    constant latency_sel: latency_sel_t := (true => INT_VECTOR_MEM_LATENCY_URAM, false => INT_VECTOR_MEM_LATENCY_BRAM);
    constant INT_VECTOR_MEM_LATENCY : integer := latency_sel(USE_URAM);

    -- Derived constants
	-- As a general rule, <NAME>_WIDTH constants describe the width of the signal that contains a signal of the type NAME
	-- and <NAME>_DEPTH constants contain the number of bit needed to note down the <NAME>_WIDTH
    constant VECTOR_SIZE_BITS  : natural := VECTOR_SIZE_ELEM * FIELD_WIDTH; -- macro needs size in bits
    constant VECTOR_ADDR_WIDTH : natural := natural(ceil(log2(real(VECTOR_SIZE_ELEM))));
    constant VECTOR_ADDR_DEPTH : natural := natural(ceil(log2(real(VECTOR_ADDR_WIDTH))));
    constant VECT_ADDRS_PER_LINE_DEPTH : integer := DMA_DATA_DEPTH - VECTOR_ADDR_DEPTH;
    constant NUM_VECT_ADDRS_PER_LINE   : integer := 2 ** VECT_ADDRS_PER_LINE_DEPTH;
    constant ROW_INDS_PER_LINE_DEPTH : integer := DMA_DATA_DEPTH - ROW_INDEX_DEPTH;
    constant NUM_ROW_INDS_PER_LINE   : integer := 2 ** ROW_INDS_PER_LINE_DEPTH;
    constant COL_INDS_PER_LINE_DEPTH : integer := DMA_DATA_DEPTH - COL_INDEX_DEPTH;
    constant NUM_COL_INDS_PER_LINE   : integer := 2 ** COL_INDS_PER_LINE_DEPTH;
    constant NUM_CPS_PER_LINE        : integer := DMA_DATA_WIDTH / (MAT_SIZE_WIDTH * 4); -- there are 4 matrix sizes per color
    constant CPS_PER_LINE_DEPTH      : integer := integer(ceil(log2(real(NUM_CPS_PER_LINE))));
    constant NUM_FIELDS_PER_LINE     : integer := DMA_DATA_WIDTH / FIELD_WIDTH;
    constant FIELDS_PER_LINE_DEPTH   : integer := integer(ceil(log2(real(NUM_FIELDS_PER_LINE))));
    constant OFFSETS_PER_LINE_DEPTH  : integer := DMA_DATA_DEPTH - OFFSET_DEPTH;
    constant NUM_OFFSETS_PER_LINE    : integer := 2 ** OFFSETS_PER_LINE_DEPTH;
    constant P_INDS_MEM_SIZE_BITS: natural := P_INDS_MEM_SIZE_ELEM * ( (DMA_DATA_WIDTH/32) * VECTOR_ADDR_WIDTH ); -- 32=elements are integers
    constant MAX_NNZS_PER_ROW        : natural := MULT_NUM * (2 ** REDUCE_NUM) - MULT_NUM + 1;

    -- Calculate the numbers below by hand when modifying MULT_DEPTH and/or REDUCE_NUM,
    -- or after making a modification to the spmvp pipeline that influences its delay:
    -- TODO: generate this array automatically.
    constant LAST_VAL_TIMER_DEPTH   : integer := 8;
    constant LAST_VAL_TIMES         : integer_array(0 to MAX_REDUCE_NUM) := (
            MULT_DELAY + MULT_DEPTH * ADD_DELAY + 4
            ,MULT_DELAY + (MULT_DEPTH + 1) * ADD_DELAY + 6
            ,MULT_DELAY + (MULT_DEPTH + 2) * ADD_DELAY + 8
            ,MULT_DELAY + (MULT_DEPTH + 3) * ADD_DELAY + 10
            ,MULT_DELAY + (MULT_DEPTH + 4) * ADD_DELAY + 12
    );

    constant ZEROES            : std_logic_vector(DMA_DATA_WIDTH - 1 downto 0) := (others => '0');
    constant ALL_ONES          : std_logic_vector(DMA_DATA_WIDTH - 1 downto 0) := (others => '1');

    -- Simulation constants:

    -- Alveo U200/U250/U280 max kernel clock: 500 MHz
    constant kernel_clk_period : time := 2 ns;
    -- Alveo U200/U250/U280 max memory clock: 300 MHz
    constant memory_clk_period : time := 3.333 ns;

    -- Debug constants:

    constant SIM_DEBUG_MT    : natural := 1; -- enable memory transactions printouts
    constant SIM_DEBUG_MT_RD : natural := 2; -- select only read memory transactions printouts; SIM_DEBUG_MT must be defined
    constant SIM_DEBUG_MT_WR : natural := 4; -- select only write memory transactions printouts; SIM_DEBUG_MT must be defined
    constant SIM_DEBUG_WU    : natural := 8; -- enable write_unit debug printouts

end package;
