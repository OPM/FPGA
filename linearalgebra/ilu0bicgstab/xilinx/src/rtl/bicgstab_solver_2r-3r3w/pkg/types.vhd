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
    use ieee.std_logic_misc.all;

library std;
    use std.textio.all;
    

library work;
    use work.constants.all;
    
package types is
    -- ranges
    subtype mult_range is natural range MULT_NUM - 1 downto 0;
    subtype offset_range is natural range OFFSET_WIDTH - 1 downto 0;
    subtype mat_size_range is natural range MAT_SIZE_WIDTH - 1 downto 0;
    subtype cacheline is std_logic_vector(DMA_DATA_WIDTH-1 downto 0);
    subtype cpu_addr_range is natural range CPU_ADDR_WIDTH - 1 downto 0;
    
    -- address types:
    subtype vector_addr_range is natural range VECTOR_ADDR_WIDTH - 1 downto 0;
    subtype row_index_range is natural range ROW_INDEX_WIDTH - 1 downto 0;
    subtype col_index_range is natural range COL_INDEX_WIDTH - 1 downto 0;
    subtype mat_part_addr_range is natural range MAT_PART_ADDR_WIDTH - 1 downto 0;
    subtype matrix_addr_range is natural range MATRIX_ADDR_WIDTH - 1 downto 0;
    
    subtype vector_address is unsigned(vector_addr_range);
    subtype row_index is unsigned(row_index_range);
    subtype column_index is unsigned(col_index_range);
    subtype mat_part_address is unsigned(mat_part_addr_range);
    subtype matrix_address is unsigned(matrix_addr_range);
    subtype mat_size is unsigned(mat_size_range);
    subtype cpu_address is unsigned(cpu_addr_range);
    
    type vect_addr_array is array (integer range <>) of vector_address;
    type row_index_array is array (integer range <>) of row_index;
    type col_index_array is array (integer range <>) of column_index;

    -- matrix element types:
    subtype field is std_logic_vector(FIELD_WIDTH - 1 downto 0);
    subtype offset is unsigned(OFFSET_WIDTH - 1 downto 0);
    
    type field_array is array(integer range <>) of field;
    type offset_array is array(integer range <>) of offset;
    type cpu_addr_array is array(integer range <>) of cpu_address;
    
    type element is record
        field : field;
        addr  : row_index;
        valid : std_logic;
    end record;
    
    constant ELEMENT_INIT : element := ((others => '0'), (others => '0'), '0');

    type elem_array is array(integer range <>) of element;
    
    type field_valid is record
        field : field;
        valid : std_logic;
    end record;
    
    constant FIELD_VALID_INIT : field_valid := ((others => '0'), '0');
    
    type field_valid_array is array(integer range <>) of field_valid;
       
    type IntegerFileType is file of integer;
    
    type read_sizes is record
        num_colors  : integer;
        row_size     : integer;
        val_size     : integer;
        L_num_colors : integer;
        L_row_size   : integer;
        L_val_size   : integer;
        U_num_colors : integer;
        U_row_size   : integer;
        U_val_size   : integer;
    end record;
    
    type string_array is array (integer range <>) of string(1 to 512);
end package;