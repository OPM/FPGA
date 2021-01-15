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

package wm_pkg is

    constant FIFO_DATA_WIDTH : integer := ROW_INDEX_WIDTH + FIELD_WIDTH;
    constant SPLIT_BUFFER_DEPTH : integer := 5;
    constant SPLIT_BUFFER_SIZE : integer := 2 ** SPLIT_BUFFER_DEPTH;
    constant NUM_MERGE_STAGES : integer := integer(ceil(log2(real(MULT_NUM / SPMVP_OUTPUT_NUM))));
    constant NUM_SPLIT_STAGES : integer := integer(ceil(log2(real(SPMVP_OUTPUT_NUM))));
    
    type wm_fifo_out_type is record
        data         : std_logic_vector(FIFO_DATA_WIDTH - 1 downto 0);
        full         : std_logic;
        empty        : std_logic;
        almost_empty : std_logic;
        read_count   : std_logic_vector(7 downto 0);
        write_count  : std_logic_vector(7 downto 0);
--        wr_rst_busy  : std_logic;
--        rd_rst_busy  : std_logic;
    end record;
    
    type wm_fifo_out_array is array (integer range <>) of wm_fifo_out_type;
    
    type wm_fifo_in_type is record
        data : std_logic_vector(FIFO_DATA_WIDTH - 1 downto 0);
        push : std_logic_vector(3 downto 0);
        pull : std_logic;
    end record;
    
    constant WM_FIFO_IN_INIT : wm_fifo_in_type := ((others => '0'), "0000", '0');
    type wm_fifo_in_array is array (integer range <>) of wm_fifo_in_type;
    
    type split2_int is record
        stored_elem : elem_array(SPLIT_BUFFER_SIZE - 1 downto 0);
        read_addr   : unsigned(SPLIT_BUFFER_DEPTH downto 0);
        write_addr  : unsigned(SPLIT_BUFFER_DEPTH downto 0);
        eo_elems    : elem_array(1 downto 0);
        out_sel     : unsigned(0 downto 0);
        even_elem   : element;
        odd_elem    : element;
        done        : std_logic;
        overflow    : std_logic;
    end record;
    
    constant SPLIT2_INT_INIT : split2_int := (
            (others => ELEMENT_INIT),   -- stored_elem
            (others => '0'),
            (others => '0'),
            (others => ELEMENT_INIT),   -- eo_elems
            to_unsigned(0, 1),          -- out_sel
            ELEMENT_INIT,               -- even_elem
            ELEMENT_INIT,               -- odd_elem
            '0',                        -- done
            '0'                         -- overflow
        );
    
    type merge2_int is record
        fifos     : wm_fifo_in_array(1 downto 0);
        out_elem  : element;
        fifo_sel  : unsigned(0 downto 0);
        done      : std_logic;
        overflow  : std_logic_vector(1 downto 0);
    end record;
    
    constant MERGE2_INT_INIT : merge2_int := (
        (others => WM_FIFO_IN_INIT),    -- fifos
        ELEMENT_INIT,       -- out_elem
        to_unsigned(0, 1),  -- fifo_sel
        '0'                 -- done        
        ,"00"               -- overflow
    );
    
    type write_merge_int is record
        fifos       : wm_fifo_in_array(3 downto 0);
        next_elem   : element;
        out_elems   : elem_array(3 downto 0);
        done        : std_logic;
        found_overflow : std_logic;
        overflow    : std_logic_vector(15 downto 0);
    end record;
    
    constant WRITE_MERGE_INT_INIT : write_merge_int := (
        (others => WM_FIFO_IN_INIT), -- fifos
        ELEMENT_INIT,                -- next_elem
        (others => ELEMENT_INIT),    -- out_elems
        '0'                          -- done
        ,'0'                         -- found_overflow     
        , (others => '0')            -- overflow
    );
    
    type merge_stages_elems is array(NUM_MERGE_STAGES - 1 downto 0) of elem_array(MULT_NUM/2 - 1 downto 0);
    type merge_stages_flags is array(NUM_MERGE_STAGES - 1 downto 0) of std_logic_vector(MULT_NUM - 1 downto 0);
    type split_stages_elems is array(NUM_SPLIT_STAGES - 1 downto 0) of elem_array(SPMVP_OUTPUT_NUM - 1 downto 0);
    type split_stages_flags is array(NUM_SPLIT_STAGES - 1 downto 0) of std_logic_vector(SPMVP_OUTPUT_NUM - 1 downto 0);
    
    type write_merge_ext is record
        merge_elems     : merge_stages_elems;
        merge_dones     : merge_stages_flags;
        merge_overflows : merge_stages_flags;
        split_in_elems  : split_stages_elems;
        split_ready     : split_stages_flags;
        split_out_elems : split_stages_elems;
        split_dones     : split_stages_flags;
        split_overflows : split_stages_flags;
        
        fifos :  wm_fifo_out_array(3 downto 0);
    end record;
    
    function fifo_data2element(fifo : in wm_fifo_out_type; prev_pull : in std_logic) return element;
    
end package;

package body wm_pkg is

    function fifo_data2element(fifo : in wm_fifo_out_type; prev_pull : in std_logic) return element is
        variable res : element;
    begin
        res.field := fifo.data(FIELD_WIDTH - 1 downto 0);
        res.valid := prev_pull;
        res.addr  := unsigned(fifo.data(FIFO_DATA_WIDTH - 1 downto FIELD_WIDTH));
        return res; 
    end function fifo_data2element;

end package body;
