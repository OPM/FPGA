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

-- ***********************************
-- common stuff for AXI memory modules
-- ***********************************

library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

package axi_io_common is

-- constants for mem_read_top modules
constant C_M_AXI_GMEMREAD_ADDR_WIDTH: integer := 64;
constant C_M_AXI_GMEMREAD_ID_WIDTH: integer := 1;
constant C_M_AXI_GMEMREAD_AWUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMREAD_DATA_WIDTH: integer := 512;
constant C_M_AXI_GMEMREAD_WUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMREAD_ARUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMREAD_RUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMREAD_BUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMREAD_USER_VALUE: integer := 0;
constant C_M_AXI_GMEMREAD_PROT_VALUE: integer := 0;
constant C_M_AXI_GMEMREAD_CACHE_VALUE: integer := 3;
constant C_FIFOREAD_DATAIN_WIDTH: integer := 512;
constant C_FIFOREAD_DATAOUT_WIDTH: integer := 512;

-- constants for mem_write_top modules
constant C_M_AXI_GMEMWRITE_ADDR_WIDTH: integer := 64;
constant C_M_AXI_GMEMWRITE_ID_WIDTH: integer := 1;
constant C_M_AXI_GMEMWRITE_AWUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMWRITE_DATA_WIDTH: integer := 512;
constant C_M_AXI_GMEMWRITE_WUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMWRITE_ARUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMWRITE_RUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMWRITE_BUSER_WIDTH: integer := 1;
constant C_M_AXI_GMEMWRITE_USER_VALUE: integer := 0;
constant C_M_AXI_GMEMWRITE_PROT_VALUE: integer := 0;
constant C_M_AXI_GMEMWRITE_CACHE_VALUE: integer := 3;
constant C_FIFOWRITE_DATAIN_WIDTH: integer := 512;
constant C_FIFOWRITE_DATAOUT_WIDTH: integer := 512;

-- hls constants
constant ap_const_lv512_lc_1: std_logic_vector(511 downto 0) := X"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

end package;

package body axi_io_common is
end package body;

