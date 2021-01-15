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
  use ieee.std_logic_textio.all;
  use std.textio.all;

package functions is
	--type slv_array is array (integer range <>) of std_logic_vector;
	--type unsigned_array is array (integer range <>) of unsigned;

	constant ADD_DELAY_WIDTH : natural := 4;

	function bool2sl(a : in boolean) return std_logic;
	function sel(cond: boolean; if_true, if_false: integer) return integer;
	function index(v : in std_logic_vector; i : in natural; n : in natural) return std_logic_vector;
	function round_up_to_index(v: in unsigned; i : in natural) return unsigned;
	function sl2unsigned(a : in std_logic) return unsigned;
	function slvint(a: in natural; n: in natural) return std_logic_vector;
	function min(a: in unsigned; b:in unsigned) return unsigned;
	function invert_field(a : in std_logic_vector) return std_logic_vector;
	function sorting_connection(a : in integer; stage : in integer; n : in integer; invert : in boolean) return integer; 
    function range_check_error(name: in string; read: in boolean; clk_cycle: in integer;
      address, req_size, addr_start, length: in unsigned) return integer;

end package;

package body functions is
	function bool2sl(a : in boolean) return std_logic is
		variable res : std_logic;
	begin
		if a then
			res := '1';
		else
			res := '0';
		end if;
		return res;
	end function bool2sl;
	
	function sel(cond: boolean; if_true, if_false: integer) return integer is
    begin
        if (cond = true) then
            return(if_true);
        else
            return(if_false);
        end if;
    end function sel; 
	
	-- get the ith batch of n bits from std_logic_vector v
    function index(v : in std_logic_vector; i : in natural; n : in natural) return std_logic_vector is
    begin
        return v((i+1)*n - 1 downto i*n);
    end function index;
    
    function round_up_to_index(v: in unsigned; i : in natural) return unsigned is
    begin
        if v(i-1 downto v'low) = 0 then
            return v(v'high downto i);
        else
            return v(v'high downto i) + 1;
        end if;
    end function round_up_to_index;
    
	-- convert  a single std_logic bit to a 0 or 1 unsigned value
    function sl2unsigned(a : in std_logic) return unsigned is
    begin
        if a = '1' then
            return to_unsigned(1, 1);
        else
            return to_unsigned(0, 1);
        end if;
    end function sl2unsigned;
    
	-- convert a natural to a std_logic_vector of length n
    function slvint(a: in natural; n: in natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(a, n));
    end function;
	
	-- get the lowest of two unsigned values of potentially uneven length
    function min(a: in unsigned; b: in unsigned) return unsigned is
        variable lowSize, highSize : natural;
        variable compA: unsigned(a'high - a'low downto 0);
        variable compB: unsigned(b'high - b'low downto 0);
        variable higherB : boolean := false;
        variable higherA : boolean := false; 
    begin
        if a'high - a'low > b'high - b'low then
            lowSize := b'high - b'low;
            higherA := a(a'high downto a'low + lowSize) /= 0;
        else
            lowSize := a'high - a'low;
            higherB := b(b'high downto b'low + lowSize) /= 0;
        end if;
        compA(lowSize downto 0) := a(a'low + lowSize downto a'low);
        compB(lowSize downto 0) := b(b'low + lowSize downto b'low);
        if (compA(lowSize downto 0) < compB(lowSize downto 0) AND NOT(higherA)) OR higherB then
            return compA(lowSize downto 0) ;
        else 
            return compB(lowSize downto 0);
        end if;
    end function;
    
	-- multiply a field by -1 (only works for field encodings that have the sign bit at the most significant bit)
    function invert_field(a : in std_logic_vector) return std_logic_vector is
    begin
        return NOT(a(a'high)) & a(a'high - 1 downto a'low);
    end function;
    
	-- For an n-input connection network that performs 2^stage parallel omega-network stage connections, calculate to which ouptut input a should be connected
	-- If invert is set, instead calculae for the same connection network to which input port output port a is connected.
	-- For example: if n = 8 and stage = 0, the connection network is one stage of an 8 input omega network (0->0, 1->2, 2->4, 3->6, 4->1, 5->3, 6->5, 7->7),
	-- and if n = 16 and stage = 1, two of those 8 input omega network connections are applied in parallel, one on inputs 0 to 7, and one on inputs 8 to 15.
    function sorting_connection(a : in integer; stage : in integer; n : in integer; invert : in boolean) return integer is
        variable logic_a : unsigned( n - 1 downto 0);
        variable logic_b : unsigned(n downto 0); 
        variable constant_part : unsigned(stage downto 0);
        variable shift_part : unsigned(n - stage - 1 downto 0);
    begin
        logic_a := to_unsigned(a, n);
        constant_part := logic_a(n-1 downto n-1-stage);
        shift_part := logic_a(n-1-stage downto 0);
        if invert then 
            shift_part := shift_part rol 1;
        else
            shift_part := shift_part rol 1;
        end if;
        logic_b := constant_part & shift_part;
        return to_integer(logic_b(n-1 downto 0));
    end function;

    function range_check_error(name: in string;
        read: in boolean; clk_cycle: in integer;
        address, req_size, addr_start, length: in unsigned) return integer is
        variable below,above: boolean := false;
        variable lineout: line;
        variable ret: integer := 0;
    begin
-- synthesis translate_off
        below := (address < addr_start);
        above := (address + req_size > addr_start + length);
        if (below = true or above = true) then
            ret := 1;
            write(lineout,string'("ERROR: time="));
            write(lineout,time'image(now));
            if (clk_cycle>0) then
                write(lineout,string'(", clk cycle="));
                write(lineout,clk_cycle);
            end if;
            write(lineout,string'(" - "));
            write(lineout,string'(name));
            if (read = true) then
                write(lineout,string'(" - requesting read "));
            else
                write(lineout,string'(" - requesting write "));
            end if;
            if (below = true) then
                write(lineout,string'("at address outside of expected range (below): start 0x"));
                hwrite(lineout,std_logic_vector(addr_start));
                write(lineout,string'(", req address 0x"));
                hwrite(lineout,std_logic_vector(address));
            else
                write(lineout,string'("at address outside of expected range (above): end 0x"));
                hwrite(lineout,std_logic_vector(addr_start + length - 1));
                write(lineout,string'(", req address 0x"));
                hwrite(lineout,std_logic_vector(address));
                write(lineout,string'(" to 0x"));
                hwrite(lineout,std_logic_vector(address + req_size - 1));
            end if;
            writeline(output,lineout);
        end if;
-- synthesis translate_on
        return ret;
    end function;

end package body functions;
