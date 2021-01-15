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

-- --------------------------------
-- FIFO for the memory write module
-- --------------------------------
-- Replaces the HLS-generated FIFO.
-- Uses asyncronous interface to enable separate clock domains on RD and WR ports.
-- NOTE: the RD port of this FIFO uses "FWFT" mode.

library ieee;
    use ieee.std_logic_1164.all;
library xpm;
    use xpm.vcomponents.all;

entity fifo_out_async_w512 is
    generic (
        MEM_STYLE   : string  := "block";
        DATA_WIDTH  : natural := 512;
        DEPTH       : natural := 512
    );
    port (
        reset           : in  std_logic;
        clk_wr          : in  std_logic;
        if_wr_busy      : out std_logic;
        if_din          : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
        if_write        : in  std_logic;
        if_almost_full  : out std_logic;
        if_full         : out std_logic;
        clk_rd          : in  std_logic;
        if_rd_busy      : out std_logic;
        if_read         : in  std_logic;
        if_dout         : out std_logic_vector(DATA_WIDTH - 1 downto 0);
        if_almost_empty : out std_logic;
        if_empty_n      : out std_logic
    );
end entity;

architecture arch of fifo_out_async_w512 is
    constant bit_0: std_logic := '0';
    signal empty: std_logic;
begin

    -- xpm_fifo_async: Asynchronous FIFO
    -- Xilinx Parameterized Macro, version 2019.2
    xpm_fifo_async_inst : xpm_fifo_async
    generic map (
        CDC_SYNC_STAGES => 3,
        DOUT_RESET_VALUE => "0",
        ECC_MODE => "no_ecc",
        FIFO_MEMORY_TYPE => MEM_STYLE,-- "auto", "block", "distributed"
        FIFO_READ_LATENCY => 0,       -- must be 0 if READ_MODE = "fwft"
        FIFO_WRITE_DEPTH => DEPTH,    -- must be a power of two
        FULL_RESET_VALUE => 0,
        PROG_EMPTY_THRESH => 5,       -- Min_Value=3 when READ_MODE="std"; else Min_Value=5
        PROG_FULL_THRESH => 8,        -- Min_Value=3+(READ_MODE_VAL*2*(FIFO_WRITE_DEPTH/FIFO_READ_DEPTH))+CDC_SYNC_STAGES
                                      --   where READ_MODE_VAL=0 when READ_MODE="std"; else READ_MODE_VAL=1
        RD_DATA_COUNT_WIDTH => 1,     -- Specifies the width of rd_data_count; should be log2(FIFO_READ_DEPTH)+1 where
                                      --   FIFO_READ_DEPTH=FIFO_WRITE_DEPTH*WRITE_DATA_WIDTH/READ_DATA_WIDTH
        READ_DATA_WIDTH => DATA_WIDTH,-- Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1,4:1 and 2:1
        READ_MODE => "fwft",          -- "std": standard read mode; "fwft": First-Word-Fall-Through read mode
        RELATED_CLOCKS => 0,
        SIM_ASSERT_CHK => 0,          -- 0=disable simulation messages, 1=enable simulation messages
        USE_ADV_FEATURES => "0808",   -- enable flags: almost_full,almost_empty  (xxx0 1000 xxx0 1000)
        WAKEUP_TIME => 0,             -- 0: Disable sleep.
        WRITE_DATA_WIDTH => DATA_WIDTH,
        WR_DATA_COUNT_WIDTH => 1      -- Specifies the width of wr_data_count; should be log2(FIFO_WRITE_DEPTH)+1.
    )
    port map (
        sleep => bit_0,
        rst => reset,                 -- Reset: Must be synchronous to wr_clk.
        -- write port
        wr_clk => clk_wr,
        wr_rst_busy => if_wr_busy,    -- Write Reset Busy: Active-High indicator that the FIFO write domain is currently in a reset state.
        wr_en => if_write,
        wr_ack => open,               -- Write Acknowledge: indicates that a write request (wr_en) during the prior clock cycle is succeeded.
        din => if_din,
        full => if_full,
        almost_full => if_almost_full,
        prog_full => open,
        overflow => open,
        wr_data_count => open,
        -- read port
        rd_clk => clk_rd,
        rd_rst_busy => if_rd_busy,    -- Read Reset Busy: Active-High indicator that the FIFO read domain is currently in a reset state.
        rd_en => if_read,
        dout => if_dout,
        data_valid => open,
        empty => empty,
        almost_empty => if_almost_empty,
        prog_empty => open,
        underflow => open,
        rd_data_count => open,
        -- ECC
        injectdbiterr => bit_0,
        injectsbiterr => bit_0,
        sbiterr => open,
        dbiterr => open
    );

    if_empty_n <= not empty;

end architecture;

