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

-- This unit handles the read operations of the vector_ops unit. In this respect, 
-- it is similar in function as the ext_read unit in the sparstition unit.
-- When it receives a high start_read signal, it will start a read on the ports 
-- selected by vector_sel at the given addresses and of the given sizes, split
-- into batches the with size READ_BATCH_SIZE.
-- This unit is instantiated by the vector_ops unit

entity vector_read_unit is
	port(
		clk        : in std_logic;
		reset      : in std_logic;
		vect_addrs : in cpu_addr_array(2 downto 0);
		read_size  : in vector_address;
		
		vect_fifos_full : in std_logic_vector(2 downto 0);
		read_dones : in std_logic_vector(2 downto 0);
		read_fifos_valid : in  std_logic_vector(2 downto 0);
		read_rqs   : out read_request_array(2 downto 0);
		read_ack   : out std_logic_vector(2 downto 0);
		
		vector_sel : in std_logic_vector(2 downto 0);
		start_read : in std_logic;
        
		wes        : out std_logic_vector(2 downto 0);
		done       : out std_logic
	);
end entity vector_read_unit;

architecture behavioural of vector_read_unit is

	signal r, q : vector_read_int;

begin

logic_proc: process(r, read_size, read_dones, read_fifos_valid, vect_addrs, vect_fifos_full, vector_sel, start_read)
		variable v : vector_read_int;
	begin
		v := r;
		
		-- default assignments
		v.wes := (others => '0');
        for l in 0 to 2 loop
		    v.read_rqs(l).valid := '0';
		end loop;
		v.read_ack        := (others => '0');
		
        case r.state is
            when idle =>
                v.done := '0';
                v.vect_dones := (others => '0');
				
                if start_read = '1' then
                    for l in 0 to 2 loop
						-- The vector_sel input signals determine on which ports vector reads are initiated
                        v.read_rqs(l).valid := vector_sel(l);
                        v.read_rqs(l).addr  := vect_addrs(l);
						-- Read each vector in batches of the READ_BATCH_SIZE
                        v.read_rqs(l).size  := work.functions.min(to_unsigned(READ_BATCH_SIZE/NUM_FIELDS_PER_LINE, FIFO_DEPTH), round_up_to_index(read_size, FIELDS_PER_LINE_DEPTH)) + to_unsigned(0, READ_RQ_SIZE_WIDTH);
                        v.vector_addrs(l)   := vect_addrs(l) + v.read_rqs(l).size;
                        v.lines_to_read(l) := v.read_rqs(l).size;
                    end loop;
                    v.read_batches   := round_up_to_index(read_size, READ_BATCH_WIDTH)  + to_unsigned(0, READ_BATCH_WIDTH) - 1;
                    v.vect_sel       := vector_sel;
                    v.size_to_read   := round_up_to_index(read_size, FIELDS_PER_LINE_DEPTH) + to_unsigned(0, VECTOR_ADDR_WIDTH) - v.read_rqs(0).size;
                    v.state          := read_vects;          
                end if;
            when read_vects =>
                for l in 0 to 2 loop
					-- Send the data from the read ports to the FIFOs
                    v.wes(l) := read_fifos_valid(l);
                    if read_fifos_valid(l) = '1' then
                        v.lines_to_read(l) := r.lines_to_read(l) - 1;
                    end if;
					-- react to the read being done
                    if read_dones(l) = '1' AND r.lines_to_read(l) = 0 then
                        v.vect_dones(l) := '1';
                        v.read_ack(l) := '1';
                    end if;
					-- pre-load address and size information for next read
                    v.read_rqs(l).addr  := r.vector_addrs(l);
                    if r.read_batches > 1 then
                        v.read_rqs(l).size := to_unsigned(READ_BATCH_SIZE/NUM_FIELDS_PER_LINE, FIFO_DEPTH) + to_unsigned(0, READ_RQ_SIZE_WIDTH);
                    else
                        v.read_rqs(l).size := r.size_to_read(READ_RQ_SIZE_WIDTH - 1 downto 0);
                    end if;   
                end loop;
				
                if ((r.vect_dones(0) = '1' AND read_dones(0) = '0') OR r.vect_sel(0) = '0') AND ((r.vect_dones(1) = '1' AND read_dones(1) = '0') OR r.vect_sel(1) = '0') AND ((r.vect_dones(2) = '1' AND read_dones(2) = '0') OR r.vect_sel(2) = '0') then
					-- If the previous reads are all done, and no more batches need to be read, then the unit is done.
                    if r.read_batches = 0 then
                        v.done := '1';
                        v.state := idle;
                    else
						-- Otherwise, start new reads on all active read ports
                        for l in 0 to 2 loop
                            v.read_rqs(l).valid := r.vect_sel(l);
                            v.vector_addrs(l)   := r.vector_addrs(l) + r.read_rqs(l).size; 
                            v.lines_to_read(l) := v.read_rqs(l).size;
                        end loop;
                        v.read_batches := r.read_batches - 1;
                        v.vect_dones := (others => '0');
                        v.size_to_read := r.size_to_read - r.read_rqs(0).size;
                    end if;                    
                end if;
            when others => NULL;
        end case;
        
        -- assign output values
        done <= r.done;
        wes <= r.wes;
        read_ack <= r.read_ack;
        read_rqs <= r.read_rqs;
        
        q <= v;
    end process;

clk_proc: process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				r <= VECTOR_READ_INT_INIT;
			else
				r <= q;
			end if;
		end if;
	end process;

end architecture behavioural;
