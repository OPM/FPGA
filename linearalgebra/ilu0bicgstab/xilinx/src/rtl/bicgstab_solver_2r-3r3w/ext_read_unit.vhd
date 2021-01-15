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
    use work.rw_pkg.all;

-- This unit handles all reads from memories outside of the FPGA chip for the sparstition unit
-- It can be instructed to perform a read of the sizes of the current SpMV/ILU0 operation, 
-- perform vector reads or to perform matrix reads. 
-- The vector read reads the vector indices of the values that make up the vector partition in 
-- the current color. when the U_bs is performed, it also read the diagonal values.
-- The matrix read reads all matrix data for the current color: non-zero values, column indices 
-- and new-row offsets.
-- This unit does not actually send the read data lines to the memories that should store them, 
-- but only generates the write eneable signals of those memories, which are statically connected 
-- to the read line of the port from which their data is read.
-- This unit is instantiated by the spastition unit.

entity ext_read_unit is
    port ( 
        clk            : in std_logic;
        reset          : in std_logic;
        read_sizes     : in std_logic;
        read_vect      : in std_logic;
        read_spm       : in std_logic;
        is_L_fs        : in std_logic;
        is_U_bs        : in std_logic;
        sizes          : in sparstition_sizes;
        addresses      : in sparstition_addresses;
        read_valids    : in std_logic_vector(NUM_DDR_READ_PORTS - 1 downto 0);
        read_dones     : in std_logic_vector(NUM_DDR_READ_PORTS - 1 downto 0);
        color_sizes    : in sparstition_color_sizes;
        read0_rq       : out read_request_type;
        read1_rq       : out read_request_type;
        read_ack       : out std_logic_vector(NUM_DDR_READ_PORTS - 1 downto 0);
        sizes_done     : out std_logic;
        vect_vals_done : out std_logic;
        mat_vals_done  : out std_logic;
        diag_done      : out std_logic;
        write_enables  : out read_wes_type;
        write_addrs    : out write_addrs_type
    );
end ext_read_unit;

architecture behavioral of ext_read_unit is

    signal r, q : ext_read_int;

begin

logic_proc: process(r, addresses, sizes, read_valids, read_sizes, read_spm, read_vect, is_L_fs, is_U_bs, color_sizes, read_dones)
        variable v : ext_read_int;
        variable diag_size : unsigned(READ_RQ_SIZE_WIDTH- 1 downto 0);
    begin
        v := r;
        
        -- default assignments
        v.wes             := (others => "0");
        v.read0_rq.valid  := '0';
        v.read1_rq.valid  := '0';
        v.sizes_done      := '0';
        v.vect_vals_done  := '0';
        v.mat_vals_done   := '0';
        v.diag_done       := '0';
        v.read_ack        := (others => '0');
            
        case r.state is  
            when idle =>
                v.read_dones(1 downto 0) := read_dones;
                v.prev_read_dones := r.read_dones;
                if read_sizes = '1' then
					-- start the reading of the color sizes
                    v.state      := start;
                    v.addrs      := addresses;
                elsif read_vect = '1' then
					-- start the read of the X vector partition indices (if there are any this color)
                    if color_sizes.col /= 0 then
                        v.read1_rq.valid := '1';
                    else
                        v.zero_vect_read := '1';    
                    end if;
                    v.read1_rq.addr  := r.addrs.P_indices_addr ;
                    v.read1_rq.size  := round_up_to_index(color_sizes.col(READ_RQ_SIZE_WIDTH + 4 - 1 downto 0), 4);
                    
                    v.lines_to_read(1) := v.read1_rq.size;
                    
                    v.addrs.P_indices_addr := r.addrs.P_indices_addr + v.read1_rq.size;
                    v.wr_addrs.P_indices   := (others => '0');
                    v.read_dones := (others => '0');
                    if is_U_bs = '1' then
						-- in the U_bs case, also read the diagonal values
                        v.read0_rq.addr := r.addrs.block_diag_addr;
                        diag_size := color_sizes.arow(READ_RQ_SIZE_WIDTH - 1 downto 0) sll 2;
                        v.read0_rq.size := round_up_to_index(diag_size, FIELDS_PER_LINE_DEPTH) + to_unsigned(0, READ_RQ_SIZE_WIDTH);
                        v.read0_rq.valid := '1';
                        v.addrs.block_diag_addr := r.addrs.block_diag_addr + v.read0_rq.size;
                        v.wr_addrs.block_diag := (others => '0');
                        
                        v.lines_to_read(0) := v.read0_rq.size;
                    end if;
                    
                    v.state := read_mult_indices;
                elsif read_spm = '1' then
                    -- (re)set color counter signals
                    if color_sizes.val(VAL_COLOR_SIZE_DEPTH - 1 downto FIELDS_PER_LINE_DEPTH) /= 0 then
                        v.mat_val_batches := round_up_to_index(color_sizes.val(MAT_PART_ADDR_WIDTH - 1 downto 0), READ_BATCH_WIDTH) - 1;
                        v.wr_addrs.nnz_vals := (others => '0');
                        v.wr_addrs.col_inds := (others => '0');
                        v.requested_col_inds := (others => '0');
                        v.requested_NRs := (others => '0');
                        v.wr_addrs.NRs := (others => '0');
                        -- give the first read request for the running state
                        v.read0_rq.addr := r.addrs.nnz_vals_addr;
                        v.read0_rq.size := work.functions.min(to_unsigned(READ_BATCH_SIZE/NUM_FIELDS_PER_LINE, FIFO_DEPTH), color_sizes.val(VAL_COLOR_SIZE_DEPTH - 1 downto FIELDS_PER_LINE_DEPTH)) + to_unsigned(0, READ_RQ_SIZE_WIDTH);
                        v.read0_rq.valid := '1';
                        v.requested_nnz_vals  := v.read0_rq.size(FIFO_DEPTH - 1 downto 0) + to_unsigned(0, MAT_PART_ADDR_WIDTH);               
                        v.addrs.nnz_vals_addr := r.addrs.nnz_vals_addr + v.read0_rq.size;
                        
                        v.read1_rq.addr := r.addrs.col_indices_addr;
                        v.read1_rq.size := work.functions.min(to_unsigned(READ_BATCH_SIZE/NUM_COL_INDS_PER_LINE, FIFO_DEPTH), color_sizes.val(VAL_COLOR_SIZE_DEPTH - 1 downto COL_INDS_PER_LINE_DEPTH)) + to_unsigned(0, READ_RQ_SIZE_WIDTH);
                        v.read1_rq.valid := '1';
                        v.requested_col_inds  := v.read1_rq.size(FIFO_DEPTH - 1 downto 0) + to_unsigned(0, MAT_PART_ADDR_WIDTH);               
                        v.addrs.col_indices_addr := r.addrs.col_indices_addr + v.read1_rq.size;
                        
                        v.requested_NRs  := to_unsigned(0, MAT_PART_ADDR_WIDTH);               

                        v.lines_to_read(0) := v.read0_rq.size;
                        v.lines_to_read(1) := v.read1_rq.size;
                        v.reading_col_inds := '1';

                        v.val_size := color_sizes.val;
                        v.read_dones := "000";
                        
                        v.state := read_matrix_vals;
                    else
                        v.mat_vals_done := '1';
                    end if;
                end if;
            when start =>
				-- This state just gives the read request for the read_color_sizes state
                v.read_dones(1 downto 0) := read_dones;
                v.prev_read_dones := r.read_dones;
                v.state        := read_color_sizes;
                v.read0_rq.addr := r.addrs.color_sizes_addr;
                v.read0_rq.size := round_up_to_index(sizes.num_colors, CPS_PER_LINE_DEPTH) + to_unsigned(0, READ_RQ_SIZE_WIDTH);
                v.read0_rq.valid := '1';
                v.wr_addrs.color_sizes := (others => '0');
                v.addrs.color_sizes_addr := r.addrs.color_sizes_addr + v.read0_rq.size;
                v.lines_to_read(0) := v.read0_rq.size;
                v.state := read_color_sizes;
            when read_color_sizes =>
				-- This state read the sizes of all colors
                v.read_dones(1 downto 0) := read_dones;
                v.prev_read_dones := r.read_dones;
                v.wes.color_sizes(0) := read_valids(0);
                v.wr_addrs.color_sizes := r.wr_addrs.color_sizes + unsigned(r.wes.color_sizes(0) & ZEROES(CPS_PER_LINE_DEPTH - 1 downto 0));
                if read_valids(0) = '1' then                      --commit:9b2b07fc: used in ddr4 and later
                    v.lines_to_read(0) := r.lines_to_read(0) - 1; --commit:9b2b07fc: used in ddr4 and later
                end if;                                           --commit:9b2b07fc: used in ddr4 and later
                if read_valids(0) = '1' AND r.lines_to_read(0) = 0  then
                    v.lines_to_read(0) := r.lines_to_read(0) - 1;
                end if;
                if r.prev_read_dones(0) = '0' AND r.read_dones(0) = '1' AND r.lines_to_read(0) = 0 then --r.wr_addrs.color_sizes(MAX_COLORS_DEPTH - 1 downto CPS_PER_LINE_DEPTH) >= r.read_rq.size then  --commit:9b2b07fc: used in ddr4 and later
                --if r.prev_read_dones(0) = '0' AND r.read_dones(0) = '1' then --r.wr_addrs.color_sizes(MAX_COLORS_DEPTH - 1 downto CPS_PER_LINE_DEPTH) >= r.read_rq.size then  --commit:bdf44d0f: used in ddr0-3
                    v.sizes_done := '1';
                    v.read_ack(0) := '1';
                    v.state      := idle;
                end if;
            when read_mult_indices =>
				-- This state reads the X vector partition indices, and the diag values in the U_bs case
                v.prev_read_dones := r.read_dones;
                for l in 0 to 1 loop
                    if read_valids(l) = '1' then
                        v.lines_to_read(l) := r.lines_to_read(l) - 1;
                    end if;
                    if read_dones(l) = '1' AND r.lines_to_read(l) = 0 then
                        v.read_dones(l) := '1';
                        v.read_ack(l) := '1';
                    end if;
                end loop;
                
                -- store incoming values
                v.wes.P_indices(0)   := read_valids(1);
                v.wr_addrs.P_indices := r.wr_addrs.P_indices + unsigned(r.wes.P_indices(0) & ZEROES(4- 1 downto 0));
                v.wes.block_diag(0)   := read_valids(0);
                v.wr_addrs.block_diag := r.wr_addrs.block_diag + unsigned(r.wes.block_diag(0) & ZEROES(FIELDS_PER_LINE_DEPTH + 1 downto 0));
                
                if ((r.read_dones(0) = '1' AND read_dones(0) = '0') OR is_U_bs = '0') AND ((r.read_dones(1) = '1' AND read_dones(1) = '0') OR r.zero_vect_read = '1') then
                    v.zero_vect_read := '0';
                    v.vect_vals_done := '1';
                    v.diag_done := '1';
                    v.vect_vals_done := '1';
                    v.state := idle; 
                end if;
            when read_matrix_vals =>
				-- send read natrix data to the correct fifo in the sparstition unit
                v.wes.nnz_vals(0) := read_valids(0);
                v.wr_addrs.nnz_vals := r.wr_addrs.nnz_vals + unsigned(r.wes.nnz_vals(0) & ZEROES(FIELDS_PER_LINE_DEPTH - 1 downto 0));
                v.wes.col_inds(0) := read_valids(1) AND r.reading_col_inds;
                v.wr_addrs.col_inds := r.wr_addrs.col_inds + unsigned(r.wes.col_inds(0) & ZEROES(COL_INDS_PER_LINE_DEPTH - 1 downto 0));
                v.wes.NRs(0) := read_valids(1) AND NOT(r.reading_col_inds);
                v.wr_addrs.NRs := r.wr_addrs.NRs + unsigned(r.wes.NRs(0) & ZEROES(OFFSETS_PER_LINE_DEPTH - 1 downto 0));
                -- count how much data has been read
				if read_valids(0) = '1' then
                    v.lines_to_read(0) := r.lines_to_read(0) - 1;
                end if;
				if read_valids(1) = '1' then
                    if r.reading_col_inds = '1' then
                        v.lines_to_read(1) := r.lines_to_read(1) - 1;
                    else
                        v.lines_to_read(2) := r.lines_to_read(2) - 1; --commit:9b2b07fc: used since ddr0
                    end if;
                end if;
				-- set acknowledge and done signals
                if read_dones(0) = '1' AND r.lines_to_read(0) = 0 then
                    v.read_ack(0) := '1';
                    v.read_dones(0) := '1';
                end if;
                if read_dones(1) = '1' AND r.lines_to_read(1) = 0 then
                    v.read_ack(1) := '1';
                    if r.reading_col_inds = '1' then
                        v.read_dones(1) := '1';
                    else
                        v.read_dones(2) := '1';
                    end if;
                end if;
                
                v.prev_read_dones := r.read_dones;
                -- start a new_row_offsets read after the read for the col_indices has finished
                if r.read_dones(1) = '1' AND r.lines_to_read(1) = 0 AND read_dones(1) = '0' AND r.reading_col_inds = '1' then --commit:9b2b07fc: used in ddr4 and later
                --if r.read_dones(1) = '1' AND read_dones(1) = '0' AND r.reading_col_inds = '1' then --commit:bdf44d0f: used in ddr0-3
                    v.read1_rq.size := work.functions.min(to_unsigned(READ_BATCH_SIZE/NUM_OFFSETS_PER_LINE, FIFO_DEPTH), round_up_to_index(r.val_size, OFFSETS_PER_LINE_DEPTH)) + to_unsigned(0, READ_RQ_SIZE_WIDTH);
                    v.read1_rq.addr := r.addrs.NRs_addr;
                    v.read1_rq.valid := '1';
                    v.requested_NRs  := r.requested_NRs + v.read1_rq.size(FIFO_DEPTH - 1 downto 0);
                    v.addrs.NRs_addr := r.addrs.NRs_addr + v.read1_rq.size;
                    v.reading_col_inds := '0';
                    v.lines_to_read(2) := v.read1_rq.size; --commit:9b2b07fc: used in ddr4 and later
                    v.val_size := r.val_size - to_unsigned(READ_BATCH_SIZE, FIFO_DEPTH);
                end if;
				-- after reads of the nnz_vals, col_indices and new_row_offsets have all finished,
				-- start new nnz_vals and col_indices reads.
                if r.read_dones = "111" AND read_dones = "00" AND r.lines_to_read(0) = 0 AND r.lines_to_read(2) = 0 then --commit:9b2b07fc: used in ddr4 and later
                --if r.read_dones = "111" AND read_dones = "00" then --commit:bdf44d0f: used in ddr0-3
                    if r.mat_val_batches > 0 then
                        v.mat_val_batches := r.mat_val_batches - 1;
                        -- give the first read requests for the running state
                        v.read0_rq.addr := r.addrs.nnz_vals_addr;
                        v.read0_rq.size := work.functions.min(to_unsigned(READ_BATCH_SIZE/NUM_FIELDS_PER_LINE, FIFO_DEPTH), r.val_size(VAL_COLOR_SIZE_DEPTH - 1 downto FIELDS_PER_LINE_DEPTH)) + to_unsigned(0, READ_RQ_SIZE_WIDTH);
                        v.read0_rq.valid := '1';
                        v.requested_nnz_vals  := r.requested_nnz_vals + v.read0_rq.size(FIFO_DEPTH - 1 downto 0);
                        v.addrs.nnz_vals_addr := r.addrs.nnz_vals_addr + v.read0_rq.size;
                        
                        v.read1_rq.size := work.functions.min(to_unsigned(READ_BATCH_SIZE/NUM_COL_INDS_PER_LINE, FIFO_DEPTH), r.val_size(VAL_COLOR_SIZE_DEPTH - 1 downto COL_INDS_PER_LINE_DEPTH)) + to_unsigned(0, READ_RQ_SIZE_WIDTH);
                        v.read1_rq.addr := r.addrs.col_indices_addr;
                        v.read1_rq.valid := '1';
                        v.requested_col_inds     := r.requested_col_inds + v.read1_rq.size(FIFO_DEPTH - 1 downto 0);
                        v.addrs.col_indices_addr := r.addrs.col_indices_addr + v.read1_rq.size;
                        
                        v.lines_to_read(0) := v.read0_rq.size;
                        v.lines_to_read(1) := v.read1_rq.size;
                        
                        v.read_dones := "000";
                        v.reading_col_inds := '1';
--                        v.vect_vals_done := '1';
                    else
                        v.mat_vals_done := '1';
                        v.read_dones := "000";
                        v.state := idle;
                    end if;
                end if;

            when others => 

        end case;
        
        --output signals
        read0_rq       <= r.read0_rq;
        read1_rq       <= r.read1_rq;
        read_ack       <= r.read_ack;
        sizes_done     <= r.sizes_done;
        vect_vals_done <= r.vect_vals_done;
        mat_vals_done  <= r.mat_vals_done;
        diag_done      <= r.diag_done;
        write_enables  <= r.wes;
        write_addrs    <= r.wr_addrs;
        
        q <= v;
    end process;   

clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= EXT_READ_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;

end behavioral;
