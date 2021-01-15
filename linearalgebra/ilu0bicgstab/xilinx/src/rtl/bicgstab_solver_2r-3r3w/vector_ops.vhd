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

library xpm;
    use xpm.vcomponents.all;

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_misc.all;

library work;
    use work.functions.all;
    use work.constants.all;
    use work.types.all;
    use work.rw_pkg.all;
    use work.sparstition_pkg.all;
    use work.solver_pkg.all;

-- The vector_ops unit performs up to two vector operations in parallel. Which operations are performed 
-- is selected with the op input signal. It delagates the handling of the vector reads needed during 
-- these vector operations to the vector read unit, and stores the read data into one of three FIFOs, 
-- which are not selected based on the port from which their data is read, but rather based on which 
-- input port of which dot_axpy unit their data will be sent to. The active_reads and active_write input 
-- signals select from which ports will be read and to which ports will be written, and the port1_sel input 
-- signal select to which FIFOs the data read from each port will be written.
-- This unit instantiates the vector read unit and two dot_axpy units, and is instantiated by the solver unit.

    -- the debug data signal output by the vector_ops unit contains the following information in this order:
    --    bits  0..2 : fifo overflow signals for all vector read fifos
    --    bits  3..5 : fifo underflow signals for all vector fifos
    --    bits  6..9: data sent to axpy unit ports while not ready 
    --    bits 10..12: debug data on state changes: fifo 0 and 1 empty signals and dot_axpy1 done signal
    --    bits 13..16: debug signals on current states of the axpy units.

entity vector_ops is
    port (
        clk   : in std_logic;
        reset : in std_logic;
        -- control and configuration
        start : in std_logic;
        op    : in vector_ops_sel_type;
        read_vect_addrs : in cpu_addr_array(NUM_HBM_READ_PORTS - 1 downto 0);
        row_size        : in vector_address;
        active_reads    : in std_logic_vector(NUM_HBM_READ_PORTS - 1 downto 0);
        active_writes   : in std_logic_vector(NUM_HBM_WRITE_PORTS - 1 downto 0);
        port1_sel       : in std_logic_vector(2 downto 0);
        scaling_factor1 : in field;
        scaling_factor2 : in field;
        minus_scale     : in std_logic;
        
        reads         : in reads_in_array(NUM_HBM_READ_PORTS - 1 downto 0);
        URAM0_valid   : in std_logic;
        URAM0_line    : in cacheline;
        
        write_ready   : in std_logic_vector(NUM_HBM_WRITE_PORTS - 1 downto 0);
        read_rqs      : out read_request_array(NUM_HBM_READ_PORTS - 1 downto 0);
        read_ack      : out std_logic_vector(NUM_HBM_READ_PORTS - 1 downto 0);
        read_ready    : out std_logic_vector(NUM_HBM_READ_PORTS - 1 downto 0);
        URAM_read_ready : out std_logic;
        
        dot1_result   : out field;
        dot2_result   : out field;
        done          : out std_logic;
        
        write_line    : out cacheline;
        write_valid   : out std_logic
        
        ; debug_data : out std_logic_vector(16 downto 0)
    );
end vector_ops;

architecture structural of vector_ops is

    signal dot_axpy1_vect1, dot_axpy1_vect2   : field_array(mult_range);
    signal dot_axpy2_vect1, dot_axpy2_vect2   : field_array(mult_range);
    signal dot_axpy2_valid1, dot_axpy2_valid2 : std_logic;
    signal dot_axpy1_writing_ready : std_logic;
    signal dot_axpy2_writing_ready : std_logic;
    signal dot_axpy2_last_val : std_logic;
    signal axpy1_res_line, axpy2_res_line : cacheline;
    signal read_fifos_valid : std_logic_vector(NUM_HBM_READ_PORTS- 1 downto 0);
    signal read_dones : std_logic_vector(NUM_HBM_READ_PORTS- 1 downto 0);
    
    signal vector_wes : std_logic_vector(2 downto 0);
    signal fifos_pull : std_logic_vector(2 downto 0);
    signal vect_fifos_full : std_logic_vector(2 downto 0);
    
    signal fifos_uu_full : std_logic_vector(NUM_HBM_READ_PORTS - 1 downto 0);
    
    signal r, q : vector_ops_int;
    signal re : vector_ops_ext;

begin
    
read_valids: for g in 0 to NUM_HBM_WRITE_PORTS - 1 generate
        read_fifos_valid(g) <= reads(g).valid ;
        read_dones(g) <= reads(g).done;
    end generate;
    vect_fifos_full <= re.fifos(2).full & re.fifos(1).full & re.fifos(0).full;

vect_read: entity work.vector_read_unit port map(
            clk             => clk,
            reset           => reset,
            vect_addrs      => read_vect_addrs,
     
            read_size       => row_size,
            
            vect_fifos_full => vect_fifos_full,
            read_dones => read_dones,
            read_fifos_valid => read_fifos_valid,
            
            read_rqs  => read_rqs,
            read_ack  => read_ack,
            
            vector_sel  => active_reads,
		    start_read => r.start_vect_read,
    
            wes        => re.read_wes,
            done       => re.vect_read_done
        );
 
    vector_wes(0) <= URAM0_valid when r.state = axpy1 else re.read_wes(2) OR (re.read_wes(0) AND port1_sel(0));
    vector_wes(1) <= re.read_wes(1) OR (re.read_wes(0) AND port1_sel(1));
    vector_wes(2) <= re.read_wes(0) AND port1_sel(2);
 
read_fifos: for g in 0 to 2 generate
    -- The chosing of how each fifo is pulled by one of the two axpy units 
    -- does not automatically change when the number of read fifos increases.
    da1_pull: if g < 2 generate
        fifos_pull(g) <= NOT(re.fifos(g).empty) AND re.dot_axpy1_ready(g);         
    end generate;
    da2_pull: if g = 2 generate
        fifos_pull(g) <= NOT(re.fifos(g).empty) AND re.dot_axpy2_ready(1);          
    end generate;
        
    -- xpm_fifo_sync: Synchronous FIFO
    -- Xilinx Parameterized Macro, version 2018.3
    -- Replaces the IP: fifo_vector_ops
    fifo : xpm_fifo_sync
        generic map (
            DOUT_RESET_VALUE => "0",
            ECC_MODE => "no_ecc",
            FIFO_MEMORY_TYPE => "block",  -- "auto", "block", "distributed", "ultra"
            FIFO_READ_LATENCY => 0,       -- must be 0 if READ_MODE = "fwft"
            FIFO_WRITE_DEPTH => 256,       -- must be a power of two
            FULL_RESET_VALUE => 0,
            PROG_EMPTY_THRESH => 10,
            PROG_FULL_THRESH => 250,
            RD_DATA_COUNT_WIDTH => 1,
            READ_DATA_WIDTH => DMA_DATA_WIDTH, -- Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1,4:1 and 2:1
            READ_MODE => "fwft",          -- "std": standard read mode; "fwft": First-Word-Fall-Through read mode
            USE_ADV_FEATURES => "080A",   -- enable prog_full, almost_full and almost_empty flags
            WAKEUP_TIME => 0,
            WRITE_DATA_WIDTH => DMA_DATA_WIDTH,
            WR_DATA_COUNT_WIDTH => 1
        )
        port map (
            sleep => bit_0,
            rst => reset,
            wr_rst_busy => open,
            rd_rst_busy => open,
            wr_clk => clk,
            wr_en => vector_wes(g),
            wr_ack => open,
            din => r.read_lines(g),
            rd_en => fifos_pull(g),
            dout => re.fifos(g).data,
            data_valid => open,
            empty => re.fifos(g).empty,
            almost_empty => re.fifos(g).almost_empty,
            prog_empty => open,
            full => fifos_uu_full(g),
            almost_full => re.fifos(g).almost_full,
            prog_full => re.fifos(g).full,
            overflow => open,
            underflow => open,
            rd_data_count => open,
            wr_data_count => open,
            injectdbiterr => bit_0,
            injectsbiterr => bit_0,
            sbiterr => open,
            dbiterr => open
        );
    end generate;

    dot_axpy1_writing_ready <= re.dot_axpy2_ready(0) when r.state = update_p OR r.state = axpy2 else bool2sl((write_ready OR NOT(active_writes)) = "111");

da1: entity work.dot_axpy port map(
        clk            => clk,
        reset          => reset,
        start_op       => r.do_vect_op1,
        last_val       => r.dot_axpy_last_val,
        input_vect1    => dot_axpy1_vect1,
        input_valid1   => fifos_pull(0),
        input_vect2    => dot_axpy1_vect2,
        input_valid2   => fifos_pull(1),
        scaling_factor => r.scaling_factor1,
        writing_ready  => dot_axpy1_writing_ready,
        vect1_ready    => re.dot_axpy1_ready(0),
        vect2_ready    => re.dot_axpy1_ready(1),
        dot_output     => dot1_result,
        axpy_output    => re.axpy1_result,
        axpy_valid     => re.axpy1_valid,
        done           => re.dot_axpy1_done
        , debug_encoded_state => re.dot_axpy1_state_debug
    );
    
split_lines: for g in 0 to MULT_NUM - 1 generate
        dot_axpy1_vect1(g)  <= index(re.fifos(0).data, g, FIELD_WIDTH);
        dot_axpy1_vect2(g)  <= index(re.fifos(1).data, g, FIELD_WIDTH);
        dot_axpy2_vect2(g)  <= index(re.fifos(2).data, g, FIELD_WIDTH);
        axpy1_res_line(FIELD_WIDTH * (g + 1) - 1 downto FIELD_WIDTH * g) <= re.axpy1_result(g);
        axpy2_res_line(FIELD_WIDTH * (g + 1) - 1 downto FIELD_WIDTH * g) <= re.axpy2_result(g);
    end generate;
    dot_axpy2_valid1 <= and_reduce(re.axpy1_valid) AND r.dot_axpy2_enable;
    dot_axpy2_valid2 <= fifos_pull(2) when r.state = update_p else and_reduce(re.axpy1_valid) AND r.dot_axpy2_enable;
    
    dot_axpy2_writing_ready <= bool2sl((write_ready OR NOT(active_writes)) = "111");
    dot_axpy2_last_val <= r.dot_axpy_last_val when r.state = dot2 else re.dot_axpy1_done;
    
da2: entity work.dot_axpy port map(
            clk            => clk,
            reset          => reset,
            start_op       => r.do_vect_op2,
            last_val       => dot_axpy2_last_val,
            input_vect1    => re.axpy1_result,
            input_valid1   => dot_axpy2_valid1,
            input_vect2    => dot_axpy2_vect2,
            input_valid2   => dot_axpy2_valid2,
            scaling_factor => r.scaling_factor2,
            writing_ready  => dot_axpy2_writing_ready,
            vect1_ready    => re.dot_axpy2_ready(0),
            vect2_ready    => re.dot_axpy2_ready(1),
            dot_output     => dot2_result,
            axpy_output    => re.axpy2_result,
            axpy_valid     => re.axpy2_valid,
            done           => re.dot_axpy2_done
            , debug_encoded_state => re.dot_axpy2_state_debug
        );
    
--    vector_wes(0) <= re.read_wes(2) OR (re.read_wes(0) AND port1_sel(0));
--    vector_wes(1) <= re.read_wes(1) OR (re.read_wes(0) AND port1_sel(1));
--    vector_wes(2) <= re.read_wes(0) AND port1_sel(2);
    
    read_ready(0) <= bool2sl((re.fifos(2).full & re.fifos(1).full & re.fifos(0).full AND port1_sel) = "000") OR NOT(r.active);
    read_ready(1) <= (NOT(re.fifos(1).full) AND NOT(port1_sel(1))) OR NOT(r.active);
    read_ready(2) <= (NOT(re.fifos(0).full) AND NOT(port1_sel(0))) OR NOT(r.active);
    URAM_read_ready <= NOT(re.fifos(0).full);

logic_proc: process(start, op, port1_sel, minus_scale, URAM0_line, scaling_factor1, scaling_factor2, axpy1_res_line, axpy2_res_line, reads, r, re, 
 fifos_uu_full, vector_wes, fifos_pull, dot_axpy2_valid1, dot_axpy2_valid2, write_ready, active_writes)
        variable v : vector_ops_int;
    begin
        v := r;
        
        -- default assignments
        v.do_vect_op1 := (others => '0');
        v.do_vect_op2 := (others => '0');
        v.start_vect_read := '0';
        v.write_valid := '0';
        
        -- buffer incoming read lines
        if port1_sel(0) = '1' then
            v.read_lines(0) := reads(0).data;
        else
            v.read_lines(0) := reads(2).data;
        end if;
        if port1_sel(1) = '1' then
            v.read_lines(1) := reads(0).data;
        else 
            v.read_lines(1) := reads(1).data;
        end if;
        v.read_lines(2) := reads(0).data;
        
        case r.state is 
            when idle => 
                v.line_set := '0';
                v.vect_read_done := '0';
                v.done := '0';
                v.active := '0';
                if start = '1' then
                    v.start_vect_read := '1';
					-- each start signal goes together with an op code that determine which vector operation(s) should be performed
					-- each operation has a different combination of vector operations that each of the two dotaxpy units should perform
                    case op is
                        when dot1 =>
                            v.state := dot1;
							-- dotaxpy1 performs a dot product, dotaxpy2 does nothing
                            v.do_vect_op1 := "001";
                        when dot2 =>
                            v.state := dot2;
							-- dot_axpy1 performs a dot product, dot_axpy2 performs a norm
                            v.do_vect_op1 := "001";
                            v.do_vect_op2 := "010";
                        when axpy1 =>
                            v.state := axpy1;
							-- dot_axpy1 performs an axpy, dot_axpy2 does nothing
                            v.do_vect_op1 := "100";
                        when axpy2 =>
                            v.state := axpy2;
							-- dot_axpy1 performs an axpy, dot_axpy2 performs a norm
                            v.do_vect_op1 := "100";
                            v.do_vect_op2 := "010";
                        when update_p =>
                            v.state := update_p;
							-- dot_axpy1 and dot_axpy2 both perform an axpy
                            v.do_vect_op1 := "100";
                            v.do_vect_op2 := "100";
                        when others => 
                            NULL;
                    end case;
                    if minus_scale = '1' then
                        v.scaling_factor1 := invert_field(scaling_factor1); 
                    else
                        v.scaling_factor1 := scaling_factor1;
                    end if;
                end if;
            when dot1 =>
				-- the dot_axpy2 unit is not used in this state
				-- last_val and done signals are the only this that the vetor_ops unit need to keep track of here
				-- everything else is handled by dot_axpy1
                v.active := '1';
                v.dot_axpy2_enable := '0';
                if re.vect_read_done = '1' then
                    v.vect_read_done := '1';
                end if;
                if r.vect_read_done = '1' AND re.fifos(2).empty = '1' AND re.fifos(1).empty = '1' AND re.fifos(0).empty = '1' then
                    v.dot_axpy_last_val := '1';
                end if;
                if re.dot_axpy1_done = '1' then
                    v.dot_axpy_last_val := '0';
                    v.done := '1';
                    v.state := idle;
                end if;
            when dot2 =>
				-- last_val and done signals are the only this that the vetor_ops unit need to keep track of here
				-- everything else is handled by dot_axpy1 and dot_axpy2
                v.active := '1';
                v.dot_axpy2_enable := '1';
                if re.vect_read_done = '1' then
                    v.vect_read_done := '1';
                end if;
                if r.vect_read_done = '1' AND re.fifos(2).empty = '1' AND re.fifos(1).empty = '1' AND re.fifos(0).empty = '1' then
                    v.dot_axpy_last_val := '1';
                end if;
                if re.dot_axpy1_done = '1' AND re.dot_axpy2_done = '1' then
                    v.dot_axpy_last_val := '0';
                    v.done := '1';
                    v.state := idle;
                end if;
             when axpy1 =>
				-- the dot_axpy2 unit is not used in this state
                v.active := '1';
                v.dot_axpy2_enable := '0';
                v.read_lines(0) := URAM0_line;
                
				-- handle last_val and done signals
                if re.vect_read_done = '1' then
                    v.vect_read_done := '1';
                end if;

                if r.vect_read_done = '1' AND re.fifos(0).empty = '1' AND re.fifos(1).empty = '1' then
                    v.dot_axpy_last_val := '1';
                end if;

				if re.dot_axpy1_done = '1' then
                    v.done := '1';
                    v.dot_axpy_last_val := '0';
                    v.state := idle;
                end if;
                
				-- write the dot_axpy1 output to the memory
                if re.axpy1_valid(0) = '1' then
                    v.write_line := axpy1_res_line;
                    v.line_set := '1';
                end if;
                if v.line_set = '1' AND (write_ready OR NOT(active_writes)) = "111" then
                    v.write_valid := '1';
                    v.line_set := '0';
                end if;
            when axpy2 =>
                v.active := '1';
                v.dot_axpy2_enable := '1';
				-- the axpy2 state is the only place where the scaling factor could either need to 
				-- be inverted or not, based on in which part of the solve this state is called
                if minus_scale = '1' then
                    v.scaling_factor1 := invert_field(scaling_factor1); 
                else
                    v.scaling_factor1 := scaling_factor1;
                end if;
                
				-- handle last_val and done signals
                if re.vect_read_done = '1' then
                    v.vect_read_done := '1';
                end if;
                if r.vect_read_done = '1' AND re.fifos(0).empty = '1' AND re.fifos(1).empty = '1' then
                    v.dot_axpy_last_val := '1';
                end if;
				if re.dot_axpy2_done = '1' then
                    v.done := '1';
                    v.dot_axpy_last_val := '0';
                    v.state := idle;
                end if;
                
				-- write the dot_axpy1 output to the memory
                if re.axpy1_valid(0) = '1' then
                    v.write_line := axpy1_res_line;
                    v.line_set := '1';
                end if;
                if v.line_set = '1' AND (write_ready OR NOT(active_writes)) = "111" then
                    v.write_valid := '1';
                    v.line_set := '0';                    
                end if;
            when update_p =>
                v.active := '1';
                v.dot_axpy2_enable := '1';

                v.scaling_factor1 := invert_field(scaling_factor1); 
                v.scaling_factor2 := scaling_factor2;
                
				-- handle last_val and done signals
                if re.vect_read_done = '1' then
                    v.vect_read_done := '1';
                end if;
                if r.vect_read_done = '1' AND re.fifos(0).empty = '1' AND re.fifos(1).empty = '1' AND re.fifos(2).empty = '1' then
                    v.dot_axpy_last_val := '1';
                end if;
                
				if re.dot_axpy2_done = '1' then
                    v.done := '1';
                    v.dot_axpy_last_val := '0';
                    v.state := idle;
                end if;

				-- write the dot_axpys output to the memory
                if re.axpy2_valid(0) = '1' then
                    v.write_line := axpy2_res_line;
                    v.line_set := '1';
                end if;
                if v.line_set = '1' AND (write_ready OR NOT(active_writes)) = "111" then
                    v.write_valid := '1';
                    v.line_set := '0';
                end if;
            when others =>
                NULL; 
        end case;
        v.dot_axpy1_full(0) := NOT(re.dot_axpy1_ready(0)) AND fifos_pull(0);
        v.dot_axpy1_full(1) := NOT(re.dot_axpy1_ready(1)) AND fifos_pull(1);
        v.dot_axpy2_full(0) := NOT(re.dot_axpy2_ready(0)) AND dot_axpy2_valid1;
        v.dot_axpy2_full(1) := NOT(re.dot_axpy2_ready(1)) AND dot_axpy2_valid2;
        
        q <= v;
        
        --assign output signals
        done         <= r.done;
        write_line   <= r.write_line;
        write_valid  <= r.write_valid;
        
        -- assign debug signals
        for l in 0 to NUM_HBM_READ_PORTS - 1 loop
            debug_data(l) <= fifos_uu_full(l) AND vector_wes(l);
            debug_data(l + 3) <= fifos_pull(l) AND re.fifos(l).empty;
        end loop;
        
        debug_data(6) <= r.dot_axpy1_full(0) AND NOT(re.dot_axpy1_ready(0)) AND fifos_pull(0);
        debug_data(7) <= r.dot_axpy1_full(1) AND NOT(re.dot_axpy1_ready(1)) AND fifos_pull(1);
        debug_data(8) <= r.dot_axpy2_full(0) AND NOT(re.dot_axpy2_ready(0)) AND dot_axpy2_valid1;
        debug_data(9) <= r.dot_axpy2_full(1) AND NOT(re.dot_axpy2_ready(1)) AND dot_axpy2_valid2;
        debug_data(10) <= re.fifos(0).empty;
        debug_data(11) <= re.fifos(1).empty;
        debug_data(12) <= re.dot_axpy1_done;
        debug_data(14 downto 13) <= re.dot_axpy1_state_debug;
        debug_data(16 downto 15) <= re.dot_axpy1_state_debug;
    end process;
    
clk_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= VECTOR_OPS_INT_INIT;
            else
                r <= q;
            end if;
        end if;
    end process;
end structural;
