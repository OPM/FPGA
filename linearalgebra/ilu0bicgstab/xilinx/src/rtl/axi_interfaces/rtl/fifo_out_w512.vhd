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

-- ==============================================================
-- File generated on Fri May 17 10:41:45 CEST 2019
-- Vivado(TM) HLS - High-Level Synthesis from C, C++ and SystemC v2018.3 (64-bit)
-- SW Build 2405991 on Thu Dec  6 23:36:41 MST 2018
-- IP Build 2404404 on Fri Dec  7 01:43:56 MST 2018
-- Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
-- ==============================================================

-- FIFO for the memory write module
-- Modifications vs. HLS-generated FIFO:
-- * modified name of the entity
-- * added interface signal "if_almost_full"
-- * modified polarity of interface signal "if_full" (was "if_full_n")
-- * removed generic ADDR_WIDTH (self-computed using DEPTH)

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use IEEE.math_real.all;

entity fifo_out_w512 is
    generic (
        MEM_STYLE   : string  := "block";
        DATA_WIDTH  : natural := 512;
        DEPTH       : natural := 512
    );
    port (
        clk            : in  std_logic;
        reset          : in  std_logic;
        if_almost_full : out std_logic;
        if_full        : out std_logic;
        if_write_ce    : in  std_logic;
        if_write       : in  std_logic;
        if_din         : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
        if_empty_n     : out std_logic;
        if_read_ce     : in  std_logic;
        if_read        : in  std_logic;
        if_dout        : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
end entity;

architecture arch of fifo_out_w512 is
    type memtype is array (0 to DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal mem        : memtype;
    constant ADDR_WIDTH : natural := natural(ceil(log2(real(DEPTH))));
    signal q_buf      : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal waddr      : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal raddr      : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal wnext      : unsigned(ADDR_WIDTH - 1 downto 0);
    signal rnext      : unsigned(ADDR_WIDTH - 1 downto 0);
    signal push       : std_logic;
    signal pop        : std_logic;
    signal usedw      : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal almost_full : std_logic := '0';
    signal full_n     : std_logic := '1';
    signal empty_n    : std_logic := '0';
    signal q_tmp      : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal show_ahead : std_logic := '0';
    signal dout_buf   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal dout_valid : std_logic := '0';
    attribute ram_style: string;
    attribute ram_style of mem: signal is MEM_STYLE;
begin
    if_almost_full <= almost_full;
    if_full    <= not full_n;
    if_empty_n <= dout_valid;
    if_dout    <= dout_buf;
    push       <= full_n and if_write_ce and if_write;
    pop        <= empty_n and if_read_ce and (not dout_valid or if_read);
    wnext      <= waddr when push = '0' else
                  (others => '0') when waddr = DEPTH - 1 else
                  waddr + 1;
    rnext      <= raddr when pop = '0' else
                  (others => '0') when raddr = DEPTH - 1 else
                  raddr + 1;

    -- waddr
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                waddr <= (others => '0');
            else
                waddr <= wnext;
            end if;
        end if;
    end process;

    -- raddr
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                raddr <= (others => '0');
            else
                raddr <= rnext;
            end if;
        end if;
    end process;

    -- usedw
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                usedw <= (others => '0');
            elsif push = '1' and pop = '0' then
                usedw <= usedw + 1;
            elsif push = '0' and pop = '1' then
                usedw <= usedw - 1;
            end if;
        end if;
    end process;

    -- full_n
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                full_n <= '1';
            elsif push = '1' and pop = '0' then
                if usedw = DEPTH - 1 then
                    full_n <= '0';
                else
                    full_n <= '1';
                end if;
            elsif push = '0' and pop = '1' then
                full_n <= '1';
            end if;
        end if;
    end process;

    -- signal added to make easier the use of the FIFO
    -- almost_full
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                almost_full <= '0';
            elsif push = '1' and pop = '0' then
                -- when pushing, almost full is set to 4 elements before full
                if usedw = DEPTH - 4 or usedw = DEPTH - 3 or usedw = DEPTH - 2 or usedw = DEPTH - 1 then
                    almost_full <= '1';
                else
                    almost_full <= '0';
                end if;
            elsif push = '0' and pop = '1' then
                if usedw = DEPTH - 2 or usedw = DEPTH - 1 then
                    almost_full <= '1';
                else
                    almost_full <= '0';
                end if;
            end if;
        end if;
    end process;

    -- empty_n
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                empty_n <= '0';
            elsif push = '1' and pop = '0' then
                empty_n <= '1';
            elsif push = '0' and pop = '1' then
                if usedw = 1 then
                    empty_n <= '0';
                else
                    empty_n <= '1';
                end if;
            end if;
        end if;
    end process;

    -- mem
    process (clk) begin
        if clk'event and clk = '1' then
            if push = '1' then
                mem(to_integer(waddr)) <= if_din;
            end if;
        end if;
    end process;

    -- q_buf
    process (clk) begin
        if clk'event and clk = '1' then
            q_buf <= mem(to_integer(rnext));
        end if;
    end process;

    -- q_tmp
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                q_tmp <= (others => '0');
            elsif push = '1' then
                q_tmp <= if_din;
            end if;
        end if;
    end process;

    -- show_ahead
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                show_ahead <= '0';
            elsif push = '1' and (usedw = 0 or (usedw = 1 and pop = '1')) then
                show_ahead <= '1';
            else
                show_ahead <= '0';
            end if;
        end if;
    end process;

    -- dout_buf
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                dout_buf <= (others => '0');
            elsif pop = '1' then
                if show_ahead = '1' then
                    dout_buf <= q_tmp;
                else
                    dout_buf <= q_buf;
                end if;
            end if;
        end if;
    end process;

    -- dout_valid
    process (clk) begin
        if clk'event and clk = '1' then
            if reset = '1' then
                dout_valid <= '0';
            elsif pop = '1' then
                dout_valid <= '1';
            elsif if_read_ce = '1' and if_read = '1' then
                dout_valid <= '0';
            end if;
        end if;
    end process;
end architecture;

