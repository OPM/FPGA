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
  use work.dot_axpy_pkg.all;
  use work.types.all;
  use work.constants.all;

-- This unit adds together all of its input values into a single value
-- It does this in two steps: during the first stages, in which it keeps 
-- receiving new data, it keeps feeding th results of the adder it is 
-- connected to back into that adder together with the incoming valeu.
-- Then, when no new data will come in, it stores valid results of the 
-- adder it is connected to, and send two of those results back into 
-- the adder to be added together, until only one value is left.   
-- This unit is instantiated in the dot_axpy unit.

entity dot_reduce is
  port(
    clk      : in std_logic;
    enable   : in std_logic;
    data_in  : in field;
    valid_in : in std_logic;
    last_val : in std_logic;
    result   : out field;
    done     : out std_logic := '0';
    -- connections to an adder  (Adder is not part of this unit
	-- so it can be used differently during an axpy operation)
    add_inputs : out op_input_type;
    add_valid  : out std_logic_vector(1  downto 0);
    add_result : in field;
    add_done   : in std_logic
  );
end entity dot_reduce;

architecture behavioural of dot_reduce is

    signal q, r : dr_int;

begin

logic_proc: process(r, enable, data_in, valid_in, last_val, add_result, add_done)
        variable v : dr_int;
    begin
	    v := r;
	    
	    -- default assignments
	    v.add_valid := "00";
	    
	    -- registers
	    v.prev_vals_in_add := r.vals_in_add;
	   	
		-- count the number of separate values in the reduce adder 
		-- (this value will always be equal of less then the adder delay)
	    if add_done = '1' XOR r.add_valid = "11" then
	        if add_done = '1' then
	            v.vals_in_add := r.vals_in_add - 1;
	        else
	            v.vals_in_add := r.vals_in_add + 1;
	        end if;
	    end if;
	    
	    case r.state is
	        when idle =>
	            v.vals_in_add := (others => '0');
	            v.temp_valid := '0';
	            v.done := '0';
	            
	            if enable = '1' then
	                v.state := tree;
	            end if;
	        when tree =>
				-- while the dot product is running, simply accumulate incoming values 
                v.add_inputs(0) := make_valid(data_in, valid_in);
                v.add_inputs(1) := make_valid(add_result, add_done);
                v.add_valid := "11";
				-- When the dot product is done, start the reduction process
                if last_val = '1' then 
                    v.state := reduce;
                end if;
	        when reduce =>
				-- reduce all values in the reduce adder's pipeline by continuously 
				-- feeding two of its subsequent valid ouputs back into it.
                if add_done = '1' AND r.temp_valid = '0' then--count(0) = '0' then
                    v.temp_res := make_valid(add_result, add_done);
                    v.temp_valid := '1';
                elsif add_done = '1' AND r.temp_valid = '1' then
                    v.add_inputs(0) := r.temp_res;
                    v.add_inputs(1) := make_valid(add_result, add_done);
                    v.temp_valid := '0';
                    v.add_valid := "11";
                end if;
				-- If there are no more values in the reduce adder, the reduce is done
                if r.prev_vals_in_add = 0 AND r.vals_in_add = 0 then
                    v.state  := done_state;
                    v.done   := '1';
                    v.result := r.temp_res; 
                    v.temp_valid := '0';
                end if;
            when done_state => 
                v.done   := '1';
                if enable = '0' then
                    v.state := idle;
                end if;
            when others => NULL;
	    end case;
	  
	    add_inputs <= r.add_inputs;
	    add_valid  <= r.add_valid;
	    result     <= r.result;
	    done       <= r.done;
	    q          <= v;
	end process;
	
reg: process(clk) 
	begin
	    if rising_edge(clk) then
	       r <= q;
	    end if;
	end process;
end architecture behavioural;
