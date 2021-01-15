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

-- **************************
-- SDAccel/Vitis-compatible wrapper for the bicgstab solver design
-- **************************
-- integrates:
-- * the memory read module [RTL + HLS]
-- * the memory write module [RTL + HLS]
-- * the bicgstab solver core [RTL]
-- * logic to convert the HLS control interface to AXI-lite [RTL]

-- KEEP THIS UP-TO-DATE!

-- Port mapping:
--  kernel port | wrapper port  | memory type
--  read 0      | gmem0         | DDR
--  read 1      | gmem1         | DDR
--  read 2      | gmem2         | HBM
--  read 3      | gmem3         | HBM
--  read 4      | gmem4         | HBM
--  write 0     | gmem5         | HBM
--  write 1     | gmem6         | HBM
--  write 2     | gmem7         | HBM
--  N/A         | gmem8 (debug) | PLRAM
--
-- current meaning of param0 bits:
--   bit 31..0: kernel abort clock cycles (0=DISABLED)
-- current meaning of param1 bits:
--   bit 15..0 : kernel max number of iterations
--   bit 31..16: kernel debug sampling rate in clock cycles
--   bit 47..32: kernel debug max cachelines
--   bit 48    : query kernel limits (does not run the kernel)
-- current meaning of param2 bits:
--   bit 63..0: kernel precision (as double FP number)
--
-- current meaning of the debug port bits (index 0) after a kernel limits query:
--   bit 31..0   : VECTOR_SIZE_ELEM
--   bit 63..32  : MAX_ROW_SIZE
--   bit 95..64  : MAX_COLUMN_SIZE
--   bit 127..96 : MAX_COLORS_SIZE
--   bit 143..128: MAX_NNZS_PER_ROW
--   bit 175..144: MAX_MATRIX_SIZE
--   bit 207..176: READ_BATCH_SIZE
--   bit 319..208: unused
--   bit 335..320: kernel_reset_cycles
--   bit 351..336: kernel_reset_settle
--   bit 383..352: unused
--   bit 384     : USE_URAM
--   bit 385     : WRITE_ILU0_RESULTS
--   bit 399..386: unused
--   bit 415..400: DMA_DATA_WIDTH
--   bit 423..416: INT_VECTOR_MEM_LATENCY
--   bit 431..424: ADD_DELAY
--   bit 439..432: MULT_DELAY
--   bit 447..440: MULT_NUM
--   bit 451..448: NUM_READ_PORTS
--   bit 455..452: NUM_WRITE_PORTS
--   bit 487..456: unused
--   bit 511..488: signature ("BDA")
--
-- current meaning of the debug port bits (index 0):
--   bit  0      : kernel aborted
--   bit  1      : kernel exited without running (precision already met)
--   bit  2      : error-kernel wrote after ending
--   bit  3      : warning-debug fifo full
--   bit 95..64  : number of cycles (in the ap_clk domain) for the kernel execution
--   bit 511..488: signature ("BDA")

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_misc.all;
use IEEE.numeric_std.all;
library work;
use work.axi_io_common.all;
use work.rw_pkg.all;
use work.solver_pkg.all;
use work.functions.all;
use work.constants.all;

entity bicgstab_solver_wrapper_2r_3r3w_v1 is
generic (
  SIM_DEBUG : natural := 0;
  WRITE_ILU0_RESULTS : boolean := WRITE_ILU0_RES
);
port (
  -- Kernel clock/reset (unused)
  ap_clk_2 : in std_logic;
  ap_rst_2 : in std_logic;
  -- SDA controls
  ap_clk : in std_logic;
  ap_rst : in std_logic;
  ap_start : in std_logic;
  ap_done : out std_logic;
  ap_idle : out std_logic;
  ap_ready : out std_logic;
  param0 : in  std_logic_vector(63 downto 0);
  param1 : in  std_logic_vector(63 downto 0);
  param2 : in  std_logic_vector(63 downto 0);
  m_axi_gmem0_offset : in std_logic_vector (63 downto 0);
  m_axi_gmem1_offset : in std_logic_vector (63 downto 0);
  m_axi_gmem2_offset : in std_logic_vector (63 downto 0);
  m_axi_gmem3_offset : in std_logic_vector (63 downto 0);
  m_axi_gmem4_offset : in std_logic_vector (63 downto 0);
  m_axi_gmem5_offset : in std_logic_vector (63 downto 0);
  m_axi_gmem6_offset : in std_logic_vector (63 downto 0);
  m_axi_gmem7_offset : in std_logic_vector (63 downto 0);
  m_axi_gmem8_offset : in std_logic_vector (63 downto 0);
  -- AXI memory interface: for read module
  m_axi_gmem0_AWVALID : out std_logic;
  m_axi_gmem0_AWREADY : in std_logic;
  m_axi_gmem0_AWADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem0_AWID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem0_AWLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem0_AWSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem0_AWBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem0_AWLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem0_AWCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem0_AWPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem0_AWQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem0_AWREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem0_AWUSER : out std_logic_vector (C_M_AXI_GMEMREAD_AWUSER_WIDTH-1 downto 0);
  m_axi_gmem0_WVALID : out std_logic;
  m_axi_gmem0_WREADY : in std_logic;
  m_axi_gmem0_WDATA : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem0_WSTRB : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH/8-1 downto 0);
  m_axi_gmem0_WLAST : out std_logic;
  m_axi_gmem0_WID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem0_WUSER : out std_logic_vector (C_M_AXI_GMEMREAD_WUSER_WIDTH-1 downto 0);
  m_axi_gmem0_ARVALID : out std_logic;
  m_axi_gmem0_ARREADY : in std_logic;
  m_axi_gmem0_ARADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem0_ARID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem0_ARLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem0_ARSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem0_ARBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem0_ARLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem0_ARCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem0_ARPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem0_ARQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem0_ARREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem0_ARUSER : out std_logic_vector (C_M_AXI_GMEMREAD_ARUSER_WIDTH-1 downto 0);
  m_axi_gmem0_RVALID : in std_logic;
  m_axi_gmem0_RREADY : out std_logic;
  m_axi_gmem0_RDATA : in std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem0_RLAST : in std_logic;
  m_axi_gmem0_RID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem0_RUSER : in std_logic_vector (C_M_AXI_GMEMREAD_RUSER_WIDTH-1 downto 0);
  m_axi_gmem0_RRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem0_BVALID : in std_logic;
  m_axi_gmem0_BREADY : out std_logic;
  m_axi_gmem0_BRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem0_BID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem0_BUSER : in std_logic_vector (C_M_AXI_GMEMREAD_BUSER_WIDTH-1 downto 0);
  -- AXI memory interface: for read module
  m_axi_gmem1_AWVALID : out std_logic;
  m_axi_gmem1_AWREADY : in std_logic;
  m_axi_gmem1_AWADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem1_AWID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem1_AWLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem1_AWSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem1_AWBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem1_AWLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem1_AWCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem1_AWPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem1_AWQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem1_AWREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem1_AWUSER : out std_logic_vector (C_M_AXI_GMEMREAD_AWUSER_WIDTH-1 downto 0);
  m_axi_gmem1_WVALID : out std_logic;
  m_axi_gmem1_WREADY : in std_logic;
  m_axi_gmem1_WDATA : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem1_WSTRB : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH/8-1 downto 0);
  m_axi_gmem1_WLAST : out std_logic;
  m_axi_gmem1_WID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem1_WUSER : out std_logic_vector (C_M_AXI_GMEMREAD_WUSER_WIDTH-1 downto 0);
  m_axi_gmem1_ARVALID : out std_logic;
  m_axi_gmem1_ARREADY : in std_logic;
  m_axi_gmem1_ARADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem1_ARID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem1_ARLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem1_ARSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem1_ARBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem1_ARLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem1_ARCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem1_ARPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem1_ARQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem1_ARREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem1_ARUSER : out std_logic_vector (C_M_AXI_GMEMREAD_ARUSER_WIDTH-1 downto 0);
  m_axi_gmem1_RVALID : in std_logic;
  m_axi_gmem1_RREADY : out std_logic;
  m_axi_gmem1_RDATA : in std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem1_RLAST : in std_logic;
  m_axi_gmem1_RID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem1_RUSER : in std_logic_vector (C_M_AXI_GMEMREAD_RUSER_WIDTH-1 downto 0);
  m_axi_gmem1_RRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem1_BVALID : in std_logic;
  m_axi_gmem1_BREADY : out std_logic;
  m_axi_gmem1_BRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem1_BID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem1_BUSER : in std_logic_vector (C_M_AXI_GMEMREAD_BUSER_WIDTH-1 downto 0);
  -- AXI memory interface: for read module
  m_axi_gmem2_AWVALID : out std_logic;
  m_axi_gmem2_AWREADY : in std_logic;
  m_axi_gmem2_AWADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem2_AWID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem2_AWLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem2_AWSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem2_AWBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem2_AWLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem2_AWCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem2_AWPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem2_AWQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem2_AWREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem2_AWUSER : out std_logic_vector (C_M_AXI_GMEMREAD_AWUSER_WIDTH-1 downto 0);
  m_axi_gmem2_WVALID : out std_logic;
  m_axi_gmem2_WREADY : in std_logic;
  m_axi_gmem2_WDATA : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem2_WSTRB : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH/8-1 downto 0);
  m_axi_gmem2_WLAST : out std_logic;
  m_axi_gmem2_WID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem2_WUSER : out std_logic_vector (C_M_AXI_GMEMREAD_WUSER_WIDTH-1 downto 0);
  m_axi_gmem2_ARVALID : out std_logic;
  m_axi_gmem2_ARREADY : in std_logic;
  m_axi_gmem2_ARADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem2_ARID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem2_ARLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem2_ARSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem2_ARBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem2_ARLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem2_ARCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem2_ARPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem2_ARQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem2_ARREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem2_ARUSER : out std_logic_vector (C_M_AXI_GMEMREAD_ARUSER_WIDTH-1 downto 0);
  m_axi_gmem2_RVALID : in std_logic;
  m_axi_gmem2_RREADY : out std_logic;
  m_axi_gmem2_RDATA : in std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem2_RLAST : in std_logic;
  m_axi_gmem2_RID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem2_RUSER : in std_logic_vector (C_M_AXI_GMEMREAD_RUSER_WIDTH-1 downto 0);
  m_axi_gmem2_RRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem2_BVALID : in std_logic;
  m_axi_gmem2_BREADY : out std_logic;
  m_axi_gmem2_BRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem2_BID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem2_BUSER : in std_logic_vector (C_M_AXI_GMEMREAD_BUSER_WIDTH-1 downto 0);
  -- AXI memory interface: for read module
  m_axi_gmem3_AWVALID : out std_logic;
  m_axi_gmem3_AWREADY : in std_logic;
  m_axi_gmem3_AWADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem3_AWID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem3_AWLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem3_AWSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem3_AWBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem3_AWLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem3_AWCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem3_AWPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem3_AWQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem3_AWREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem3_AWUSER : out std_logic_vector (C_M_AXI_GMEMREAD_AWUSER_WIDTH-1 downto 0);
  m_axi_gmem3_WVALID : out std_logic;
  m_axi_gmem3_WREADY : in std_logic;
  m_axi_gmem3_WDATA : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem3_WSTRB : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH/8-1 downto 0);
  m_axi_gmem3_WLAST : out std_logic;
  m_axi_gmem3_WID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem3_WUSER : out std_logic_vector (C_M_AXI_GMEMREAD_WUSER_WIDTH-1 downto 0);
  m_axi_gmem3_ARVALID : out std_logic;
  m_axi_gmem3_ARREADY : in std_logic;
  m_axi_gmem3_ARADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem3_ARID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem3_ARLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem3_ARSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem3_ARBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem3_ARLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem3_ARCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem3_ARPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem3_ARQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem3_ARREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem3_ARUSER : out std_logic_vector (C_M_AXI_GMEMREAD_ARUSER_WIDTH-1 downto 0);
  m_axi_gmem3_RVALID : in std_logic;
  m_axi_gmem3_RREADY : out std_logic;
  m_axi_gmem3_RDATA : in std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem3_RLAST : in std_logic;
  m_axi_gmem3_RID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem3_RUSER : in std_logic_vector (C_M_AXI_GMEMREAD_RUSER_WIDTH-1 downto 0);
  m_axi_gmem3_RRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem3_BVALID : in std_logic;
  m_axi_gmem3_BREADY : out std_logic;
  m_axi_gmem3_BRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem3_BID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem3_BUSER : in std_logic_vector (C_M_AXI_GMEMREAD_BUSER_WIDTH-1 downto 0);
  -- AXI memory interface: for read module
  m_axi_gmem4_AWVALID : out std_logic;
  m_axi_gmem4_AWREADY : in std_logic;
  m_axi_gmem4_AWADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem4_AWID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem4_AWLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem4_AWSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem4_AWBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem4_AWLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem4_AWCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem4_AWPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem4_AWQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem4_AWREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem4_AWUSER : out std_logic_vector (C_M_AXI_GMEMREAD_AWUSER_WIDTH-1 downto 0);
  m_axi_gmem4_WVALID : out std_logic;
  m_axi_gmem4_WREADY : in std_logic;
  m_axi_gmem4_WDATA : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem4_WSTRB : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH/8-1 downto 0);
  m_axi_gmem4_WLAST : out std_logic;
  m_axi_gmem4_WID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem4_WUSER : out std_logic_vector (C_M_AXI_GMEMREAD_WUSER_WIDTH-1 downto 0);
  m_axi_gmem4_ARVALID : out std_logic;
  m_axi_gmem4_ARREADY : in std_logic;
  m_axi_gmem4_ARADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem4_ARID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem4_ARLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem4_ARSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem4_ARBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem4_ARLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem4_ARCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem4_ARPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem4_ARQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem4_ARREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem4_ARUSER : out std_logic_vector (C_M_AXI_GMEMREAD_ARUSER_WIDTH-1 downto 0);
  m_axi_gmem4_RVALID : in std_logic;
  m_axi_gmem4_RREADY : out std_logic;
  m_axi_gmem4_RDATA : in std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem4_RLAST : in std_logic;
  m_axi_gmem4_RID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem4_RUSER : in std_logic_vector (C_M_AXI_GMEMREAD_RUSER_WIDTH-1 downto 0);
  m_axi_gmem4_RRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem4_BVALID : in std_logic;
  m_axi_gmem4_BREADY : out std_logic;
  m_axi_gmem4_BRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem4_BID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem4_BUSER : in std_logic_vector (C_M_AXI_GMEMREAD_BUSER_WIDTH-1 downto 0);
  -- AXI memory interface: for write module
  m_axi_gmem5_AWVALID : out std_logic;
  m_axi_gmem5_AWREADY : in std_logic;
  m_axi_gmem5_AWADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem5_AWID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem5_AWLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem5_AWSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem5_AWBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem5_AWLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem5_AWCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem5_AWPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem5_AWQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem5_AWREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem5_AWUSER : out std_logic_vector (C_M_AXI_GMEMREAD_AWUSER_WIDTH-1 downto 0);
  m_axi_gmem5_WVALID : out std_logic;
  m_axi_gmem5_WREADY : in std_logic;
  m_axi_gmem5_WDATA : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem5_WSTRB : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH/8-1 downto 0);
  m_axi_gmem5_WLAST : out std_logic;
  m_axi_gmem5_WID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem5_WUSER : out std_logic_vector (C_M_AXI_GMEMREAD_WUSER_WIDTH-1 downto 0);
  m_axi_gmem5_ARVALID : out std_logic;
  m_axi_gmem5_ARREADY : in std_logic;
  m_axi_gmem5_ARADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem5_ARID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem5_ARLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem5_ARSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem5_ARBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem5_ARLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem5_ARCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem5_ARPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem5_ARQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem5_ARREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem5_ARUSER : out std_logic_vector (C_M_AXI_GMEMREAD_ARUSER_WIDTH-1 downto 0);
  m_axi_gmem5_RVALID : in std_logic;
  m_axi_gmem5_RREADY : out std_logic;
  m_axi_gmem5_RDATA : in std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem5_RLAST : in std_logic;
  m_axi_gmem5_RID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem5_RUSER : in std_logic_vector (C_M_AXI_GMEMREAD_RUSER_WIDTH-1 downto 0);
  m_axi_gmem5_RRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem5_BVALID : in std_logic;
  m_axi_gmem5_BREADY : out std_logic;
  m_axi_gmem5_BRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem5_BID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem5_BUSER : in std_logic_vector (C_M_AXI_GMEMREAD_BUSER_WIDTH-1 downto 0);
  -- AXI memory interface: for write module
  m_axi_gmem6_AWVALID : out std_logic;
  m_axi_gmem6_AWREADY : in std_logic;
  m_axi_gmem6_AWADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem6_AWID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem6_AWLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem6_AWSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem6_AWBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem6_AWLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem6_AWCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem6_AWPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem6_AWQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem6_AWREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem6_AWUSER : out std_logic_vector (C_M_AXI_GMEMREAD_AWUSER_WIDTH-1 downto 0);
  m_axi_gmem6_WVALID : out std_logic;
  m_axi_gmem6_WREADY : in std_logic;
  m_axi_gmem6_WDATA : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem6_WSTRB : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH/8-1 downto 0);
  m_axi_gmem6_WLAST : out std_logic;
  m_axi_gmem6_WID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem6_WUSER : out std_logic_vector (C_M_AXI_GMEMREAD_WUSER_WIDTH-1 downto 0);
  m_axi_gmem6_ARVALID : out std_logic;
  m_axi_gmem6_ARREADY : in std_logic;
  m_axi_gmem6_ARADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem6_ARID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem6_ARLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem6_ARSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem6_ARBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem6_ARLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem6_ARCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem6_ARPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem6_ARQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem6_ARREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem6_ARUSER : out std_logic_vector (C_M_AXI_GMEMREAD_ARUSER_WIDTH-1 downto 0);
  m_axi_gmem6_RVALID : in std_logic;
  m_axi_gmem6_RREADY : out std_logic;
  m_axi_gmem6_RDATA : in std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem6_RLAST : in std_logic;
  m_axi_gmem6_RID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem6_RUSER : in std_logic_vector (C_M_AXI_GMEMREAD_RUSER_WIDTH-1 downto 0);
  m_axi_gmem6_RRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem6_BVALID : in std_logic;
  m_axi_gmem6_BREADY : out std_logic;
  m_axi_gmem6_BRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem6_BID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem6_BUSER : in std_logic_vector (C_M_AXI_GMEMREAD_BUSER_WIDTH-1 downto 0);
  -- AXI memory interface: for write module
  m_axi_gmem7_AWVALID : out std_logic;
  m_axi_gmem7_AWREADY : in std_logic;
  m_axi_gmem7_AWADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem7_AWID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem7_AWLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem7_AWSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem7_AWBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem7_AWLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem7_AWCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem7_AWPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem7_AWQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem7_AWREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem7_AWUSER : out std_logic_vector (C_M_AXI_GMEMREAD_AWUSER_WIDTH-1 downto 0);
  m_axi_gmem7_WVALID : out std_logic;
  m_axi_gmem7_WREADY : in std_logic;
  m_axi_gmem7_WDATA : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem7_WSTRB : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH/8-1 downto 0);
  m_axi_gmem7_WLAST : out std_logic;
  m_axi_gmem7_WID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem7_WUSER : out std_logic_vector (C_M_AXI_GMEMREAD_WUSER_WIDTH-1 downto 0);
  m_axi_gmem7_ARVALID : out std_logic;
  m_axi_gmem7_ARREADY : in std_logic;
  m_axi_gmem7_ARADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem7_ARID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem7_ARLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem7_ARSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem7_ARBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem7_ARLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem7_ARCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem7_ARPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem7_ARQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem7_ARREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem7_ARUSER : out std_logic_vector (C_M_AXI_GMEMREAD_ARUSER_WIDTH-1 downto 0);
  m_axi_gmem7_RVALID : in std_logic;
  m_axi_gmem7_RREADY : out std_logic;
  m_axi_gmem7_RDATA : in std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem7_RLAST : in std_logic;
  m_axi_gmem7_RID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem7_RUSER : in std_logic_vector (C_M_AXI_GMEMREAD_RUSER_WIDTH-1 downto 0);
  m_axi_gmem7_RRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem7_BVALID : in std_logic;
  m_axi_gmem7_BREADY : out std_logic;
  m_axi_gmem7_BRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem7_BID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem7_BUSER : in std_logic_vector (C_M_AXI_GMEMREAD_BUSER_WIDTH-1 downto 0);
  -- AXI memory interface: for write module (debug)
  m_axi_gmem8_AWVALID : out std_logic;
  m_axi_gmem8_AWREADY : in std_logic;
  m_axi_gmem8_AWADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem8_AWID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem8_AWLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem8_AWSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem8_AWBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem8_AWLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem8_AWCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem8_AWPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem8_AWQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem8_AWREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem8_AWUSER : out std_logic_vector (C_M_AXI_GMEMREAD_AWUSER_WIDTH-1 downto 0);
  m_axi_gmem8_WVALID : out std_logic;
  m_axi_gmem8_WREADY : in std_logic;
  m_axi_gmem8_WDATA : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem8_WSTRB : out std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH/8-1 downto 0);
  m_axi_gmem8_WLAST : out std_logic;
  m_axi_gmem8_WID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem8_WUSER : out std_logic_vector (C_M_AXI_GMEMREAD_WUSER_WIDTH-1 downto 0);
  m_axi_gmem8_ARVALID : out std_logic;
  m_axi_gmem8_ARREADY : in std_logic;
  m_axi_gmem8_ARADDR : out std_logic_vector (C_M_AXI_GMEMREAD_ADDR_WIDTH-1 downto 0);
  m_axi_gmem8_ARID : out std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem8_ARLEN : out std_logic_vector (7 downto 0);
  m_axi_gmem8_ARSIZE : out std_logic_vector (2 downto 0);
  m_axi_gmem8_ARBURST : out std_logic_vector (1 downto 0);
  m_axi_gmem8_ARLOCK : out std_logic_vector (1 downto 0);
  m_axi_gmem8_ARCACHE : out std_logic_vector (3 downto 0);
  m_axi_gmem8_ARPROT : out std_logic_vector (2 downto 0);
  m_axi_gmem8_ARQOS : out std_logic_vector (3 downto 0);
  m_axi_gmem8_ARREGION : out std_logic_vector (3 downto 0);
  m_axi_gmem8_ARUSER : out std_logic_vector (C_M_AXI_GMEMREAD_ARUSER_WIDTH-1 downto 0);
  m_axi_gmem8_RVALID : in std_logic;
  m_axi_gmem8_RREADY : out std_logic;
  m_axi_gmem8_RDATA : in std_logic_vector (C_M_AXI_GMEMREAD_DATA_WIDTH-1 downto 0);
  m_axi_gmem8_RLAST : in std_logic;
  m_axi_gmem8_RID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem8_RUSER : in std_logic_vector (C_M_AXI_GMEMREAD_RUSER_WIDTH-1 downto 0);
  m_axi_gmem8_RRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem8_BVALID : in std_logic;
  m_axi_gmem8_BREADY : out std_logic;
  m_axi_gmem8_BRESP : in std_logic_vector (1 downto 0);
  m_axi_gmem8_BID : in std_logic_vector (C_M_AXI_GMEMREAD_ID_WIDTH-1 downto 0);
  m_axi_gmem8_BUSER : in std_logic_vector (C_M_AXI_GMEMREAD_BUSER_WIDTH-1 downto 0)
);
end;

architecture behavioral of bicgstab_solver_wrapper_2r_3r3w_v1 is
-- constants
constant RESET_ASSERT_CYCLES: natural := 50;  -- default number of cycles the reset should be asserted for the kernel
constant RESET_SETTLE_CYCLES: natural := 25;  -- default number of cycles to wait after reset has been deasserted for the kernel
-- signals
signal read_ins: read_ports_ins_array(NUM_READ_PORTS - 1 downto 0);
signal read_outs: read_ports_outs_array(NUM_READ_PORTS - 1 downto 0);
signal write_ins: write_ports_ins_array(NUM_WRITE_PORTS - 1 downto 0);
signal write_outs: write_ports_outs_array(NUM_WRITE_PORTS - 1 downto 0);
signal debug_write_i: solver_write_port_ins;
signal debug_write_o: solver_write_port_outs;
signal wrapper_debug_i: solver_write_port_ins;
signal wrapper_debug_o: solver_write_port_outs;
signal debug_write_port_i: solver_write_port_ins;
signal debug_write_port_o: solver_write_port_outs;
signal wap_done: std_logic;
signal wstart_query_limits, wstart_debug_write, wdebug_write_done: std_logic;
signal kernel_ap_start, kernel_ap_done, kernel_ap_rst: std_logic;
signal kernel_debug_rate, kernel_debug_lines: std_logic_vector(15 downto 0);
signal kernel_max_iter: std_logic_vector(15 downto 0);
signal kernel_precision: std_logic_vector(63 downto 0);
signal kernel_reset_cycles: std_logic_vector(15 downto 0);
signal kernel_reset_settle: std_logic_vector(15 downto 0);
signal kernel_abort, kernel_aborted: std_logic;
signal kernel_running: std_logic;
signal kernel_no_change, kernel_no_change_reg: std_logic;
signal error_write_after_end, warning_debug_fifo_full: std_logic;
signal clk_cycles: std_logic_vector(31 downto 0);
signal clk_cycles_rst: std_logic;
-- keep the registered reset signals as they will be used to specify a timing exception
attribute dont_touch: string;
attribute dont_touch of kernel_ap_rst: signal is "true";
type control_t is (idle,
 reset_design,reset_wait_1,reset_wait_2,
 query_limits,query_write_wait,
 start_compute,start_compute_2,start_compute_wait,wait_for_compute,
 debug_write,debug_write_wait,
 done_wait);
type debug_write_t is (idle,
 debug_write,
 debug_write_wait);
type timeout_t is (idle,running,running_check,stopped);
-- sim debug signals
signal wdebug_timeout_param0_cycles: std_logic_vector(31 downto 0);
signal wdebug_timeout_state: timeout_t;
signal wdebug_control_state: control_t;
signal wdebug_write_state: debug_write_t;

component binary_counter_32 is
  port (
    clk  : in  std_logic;
    sclr : in  std_logic;
    q    : out std_logic_vector(31 downto 0)
  );
end component;

begin

  -- check expected number of read/write ports for the solver unit
  assert (NUM_READ_PORTS = 5) report "Expected NUM_READ_PORTS=5" severity failure;
  assert (NUM_WRITE_PORTS = 3) report "Expected NUM_WRITE_PORTS=3" severity failure;

  ap_ready <= wap_done;
  ap_done <= wap_done;

  -- generate an abort signal if the kernel ran too long, controlled by param0:
  -- * when param0 = 0, the timeout is DISABLED
  -- * when param0 > 0, abort is requested if the kernel runs for more clock cycles
  --   than the ones specified by param0
  -- clk_cycles has 32 bits, hence at 300 MHz (3.333 ns), 2^32 clock cycles are
  -- around 14.3 sec
  timeout_p: process(ap_clk)
  variable param0_cycles: std_logic_vector(31 downto 0);
  variable state: timeout_t;
  begin
    if rising_edge(ap_clk) then
      if (ap_rst = '1') then
        kernel_abort <= '0';
        state := idle;
      else
        case state is
          when idle =>
            kernel_abort <= '0';
            param0_cycles := std_logic_vector(param0(31 downto 0));
            if kernel_ap_start = '1' and or_reduce(param0_cycles) = '1' then
              state := running;
            end if;
          when running =>
            kernel_abort <= '0';
            if kernel_ap_done = '1' then
              state := idle;
            elsif clk_cycles >= param0_cycles then
              kernel_abort <= '1';
              state := stopped;
            end if;
          when stopped =>
            kernel_abort <= '1';
            state := idle;
          when others =>
            state := idle;
        end case;
      end if;
      wdebug_timeout_state <= state; --SIM DEBUG
      wdebug_timeout_param0_cycles <= param0_cycles;  --SIM DEBUG
    end if;
  end process;

  -- count the number of cycles kernel executed in the ap_clk domain
  binary_counter_32_i: binary_counter_32
  port map (
    clk => ap_clk,
    sclr => clk_cycles_rst,
    q => clk_cycles
  );

  -- SDAccel control will have a single-clock pulse for ap_start and ap_done
  control_p: process(ap_clk)
  variable state: control_t;
  variable rst_cycles,rst_wait_cycles: unsigned(15 downto 0);
  variable start_wait_cycles: natural;
  variable all_busy: std_logic;
  begin
    if rising_edge(ap_clk) then
      if ap_rst = '1' then
        wap_done <= '0';
        ap_idle <= '1';
        clk_cycles_rst <= '1';
        kernel_ap_start <= '0';
        kernel_ap_rst <= '1';
        kernel_debug_rate <= (others => '0');
        kernel_debug_lines <= (others => '0');
        kernel_max_iter <= (others => '0');
        kernel_precision <= (others => '0');
        kernel_reset_cycles <= std_logic_vector(to_unsigned(RESET_ASSERT_CYCLES,16));
        kernel_reset_settle <= std_logic_vector(to_unsigned(RESET_SETTLE_CYCLES,16));
        kernel_running <= '0';
        kernel_aborted <= '0';
        wstart_query_limits <= '0';
        wstart_debug_write <= '0';
        rst_cycles := (others => '0');
        rst_wait_cycles := (others => '0');
        start_wait_cycles := 0;
        all_busy := '0';
        state := idle;
      else
        case state is
          when idle =>
            -- wait until ap_start is set
            wap_done <= '0';
            ap_idle <= '1';
            clk_cycles_rst <= '1';
            kernel_ap_start <= '0';
            kernel_ap_rst <= '0';
            kernel_debug_rate <= (others => '0');
            kernel_debug_lines <= (others => '0');
            kernel_max_iter <= (others => '0');
            kernel_precision <= (others => '0');
            kernel_running <= '0';
            kernel_aborted <= '0';
            wstart_query_limits <= '0';
            wstart_debug_write <= '0';
            rst_cycles := (others => '0');
            rst_wait_cycles := (others => '0');
            start_wait_cycles := 0;
            all_busy := '0';
            if ap_start = '1' then
              ap_idle <= '0';
              state := reset_design;
            end if;

          when reset_design =>
            -- reset the design
            kernel_ap_rst <= '1';
            rst_cycles := rst_cycles + 1;
            if rst_cycles >= unsigned(kernel_reset_cycles) then
              state := reset_wait_1;
              rst_cycles := (others => '0');
            end if;
          when reset_wait_1 =>
            -- let the design settle
            kernel_ap_rst <= '0';
            rst_wait_cycles := rst_wait_cycles + 1;
            if rst_wait_cycles >= unsigned(kernel_reset_settle) then
              rst_wait_cycles := (others => '0');
              -- if the kernel run was aborted, proceed to write a debug line, otherwise keep going
              if kernel_aborted = '1' then
                state := debug_write;
              else
                state := reset_wait_2;
              end if;
            end if;
          when reset_wait_2 =>
            -- choose which action must be performed: start the kernel or query limits
            if param1(48) = '0' then
              state := start_compute;
            else
              state := query_limits;
            end if;

          when query_limits =>
            -- request to write the debug line, handled by another process
            wstart_query_limits <= '1';
            -- modify the default reset cycles and settle parameters if param1(31 downto 0) is > 0
            if or_reduce(param1(15 downto 0)) = '1' then
              kernel_reset_cycles <= param1(15 downto 0);
            end if;
            if or_reduce(param1(31 downto 16)) = '1' then
              kernel_reset_settle <= param1(31 downto 16);
            end if;
            state := query_write_wait;
          when query_write_wait =>
            -- wait until the debug port write finished
            wstart_query_limits <= '0';
            if wdebug_write_done = '1' then
              wap_done <= '1';
              ap_idle <= '1';
              state := done_wait;
            end if;

          when start_compute =>
            -- set the parameters
            kernel_debug_rate <= param1(31 downto 16);
            kernel_debug_lines <= param1(47 downto 32);
            kernel_max_iter <= param1(15 downto 0);
            kernel_precision <= param2;
            state := start_compute_2;
          when start_compute_2 =>
            -- run the kernel
            clk_cycles_rst <= '0';
            kernel_ap_start <= '1';
            kernel_running <= '1';
            state := start_compute_wait;
          when start_compute_wait =>
            -- wait some cycles to allow for control signals to be synchronized
            -- to the kernel clock domain; a previous execution's ap_done should
            -- have enough time to be reset by the kernel before being sampled
            kernel_ap_start <= '0';
            start_wait_cycles := start_wait_cycles + 1;
            if start_wait_cycles >= 20 then
              state := wait_for_compute;
              start_wait_cycles := 0;
            end if;
          when wait_for_compute =>
            -- wait until the kernel is done or an abort is requested
            if kernel_ap_done = '1' then
              kernel_running <= '0';
              state := debug_write;
            end if;
            -- lower priority
            if kernel_abort = '1' then
              kernel_running <= '0';
              kernel_aborted <= '1';
              state := reset_design;
            end if;

          when debug_write =>
            -- request to write the debug line(s), handled by another process
            wstart_debug_write <= '1';
            state := debug_write_wait;
          when debug_write_wait =>
            -- wait until the debug port write finished
            wstart_debug_write <= '0';
            if wdebug_write_done = '1' then
              wap_done <= '1';
              ap_idle <= '1';
              state := done_wait;
            end if;

          when done_wait =>
            -- wait until the ap_start signal goes low to avoid spurious restart
            wap_done <= '0';
            if ap_start = '0' then
              state := idle;
            end if;

          when others =>
            state := idle;
        end case;
      end if;
      wdebug_control_state <= state; --SIM DEBUG
    end if;
  end process;

  -- write debug line
  -- supports two modes:
  -- * limits query
  -- * signature+info (after kernel finished)
  debug_write_p: process(ap_clk)
  variable state: debug_write_t;
  variable write_type: natural;
  begin
    if rising_edge(ap_clk) then
      if kernel_ap_rst = '1' then
        wrapper_debug_o.rq_start <= '0';
        wrapper_debug_o.rq_address <= (others => '0');
        wrapper_debug_o.rq_size <= (others => '0');
        wrapper_debug_o.fifo_data <= (others => '0');
        wrapper_debug_o.fifo_push <= '0';
        wdebug_write_done <= '0';
        error_write_after_end <= '0';
        warning_debug_fifo_full <= '0';
        state := idle;
      else
        case state is
          when idle =>
            wrapper_debug_o.rq_start <= '0';
            wrapper_debug_o.rq_address <= (others => '0');
            wrapper_debug_o.rq_size <= (others => '0');
            wrapper_debug_o.fifo_data <= (others => '0');
            wrapper_debug_o.fifo_push <= '0';
            wdebug_write_done <= '0';
            error_write_after_end <= '0';
            warning_debug_fifo_full <= '0';
            -- start when any of these signals is given
            if wstart_query_limits = '1' then
              write_type := 0;
              state := debug_write;
            elsif wstart_debug_write = '1' then
              write_type := 1;
              state := debug_write;
            end if;

          when debug_write =>
            -- wait until the debug port is ready
            if (wrapper_debug_i.rq_idle = '1' and wrapper_debug_i.fifo_almost_full = '0') then
              if write_type=0 then
                -- write a cacheline to debug port @ address 0
                wrapper_debug_o.rq_start <= '1';
                wrapper_debug_o.fifo_data <= (others => '0');
                wrapper_debug_o.rq_address <= (others => '0');
                wrapper_debug_o.rq_size <= std_logic_vector(to_unsigned(1,wrapper_debug_o.rq_size'length));
                -- limits
                wrapper_debug_o.fifo_data(31 downto 0)    <= std_logic_vector(to_unsigned(VECTOR_SIZE_ELEM,32));
                wrapper_debug_o.fifo_data(63 downto 32)   <= std_logic_vector(to_unsigned(MAX_ROW_SIZE,32));
                wrapper_debug_o.fifo_data(95 downto 64)   <= std_logic_vector(to_unsigned(MAX_COLUMN_SIZE,32));
                wrapper_debug_o.fifo_data(127 downto 96)  <= std_logic_vector(to_unsigned(MAX_COLORS_SIZE,32));
                wrapper_debug_o.fifo_data(143 downto 128) <= std_logic_vector(to_unsigned(MAX_NNZS_PER_ROW,16));
                wrapper_debug_o.fifo_data(175 downto 144) <= std_logic_vector(to_unsigned(MAX_MATRIX_SIZE,32));
                -- internal configurations
                wrapper_debug_o.fifo_data(335 downto 320) <= kernel_reset_cycles;
                wrapper_debug_o.fifo_data(351 downto 336) <= kernel_reset_settle;
                -- configurations
                wrapper_debug_o.fifo_data(384) <= bool2sl(USE_URAM);
                wrapper_debug_o.fifo_data(385) <= bool2sl(WRITE_ILU0_RESULTS);
                wrapper_debug_o.fifo_data(415 downto 400) <= std_logic_vector(to_unsigned(DMA_DATA_WIDTH,16));
                wrapper_debug_o.fifo_data(423 downto 416) <= std_logic_vector(to_unsigned(INT_VECTOR_MEM_LATENCY,8));
                wrapper_debug_o.fifo_data(431 downto 424) <= std_logic_vector(to_unsigned(ADD_DELAY,8));
                wrapper_debug_o.fifo_data(439 downto 432) <= std_logic_vector(to_unsigned(MULT_DELAY,8));
                wrapper_debug_o.fifo_data(447 downto 440) <= std_logic_vector(to_unsigned(MULT_NUM,8));
                wrapper_debug_o.fifo_data(451 downto 448) <= std_logic_vector(to_unsigned(NUM_READ_PORTS,4));
                wrapper_debug_o.fifo_data(455 downto 452) <= std_logic_vector(to_unsigned(NUM_WRITE_PORTS,4));
                --wrapper_debug_o.fifo_data(459 downto 456) <= std_logic_vector(to_unsigned(field_sel_type'pos(FIELD_SEL),4)); -- data type, currently unused (always double)
                -- signature (BDA)
                wrapper_debug_o.fifo_data(511 downto 488) <= X"414442";
                wrapper_debug_o.fifo_push <= '1';
                state := debug_write_wait;
              elsif write_type=1 then
                -- write a cacheline to debug port @ address 0
                wrapper_debug_o.rq_start <= '1';
                wrapper_debug_o.fifo_data <= (others => '0');
                wrapper_debug_o.rq_address <= (others => '0');
                wrapper_debug_o.rq_size <= std_logic_vector(to_unsigned(1,wrapper_debug_o.rq_size'length));
                -- status
                wrapper_debug_o.fifo_data(0) <= kernel_aborted;
                wrapper_debug_o.fifo_data(1) <= kernel_no_change_reg;
                wrapper_debug_o.fifo_data(2) <= error_write_after_end;
                wrapper_debug_o.fifo_data(3) <= warning_debug_fifo_full;
                wrapper_debug_o.fifo_data(95 downto 64) <= clk_cycles;
                -- signature (BDA)
                wrapper_debug_o.fifo_data(511 downto 488) <= X"414442";
                wrapper_debug_o.fifo_push <= '1';
                state := debug_write_wait;
              end if;
            else
              if wrapper_debug_i.rq_idle = '0' then
                error_write_after_end <= '1';
              end if;
              if wrapper_debug_i.fifo_almost_full = '1' then
                warning_debug_fifo_full <= '1';
              end if;
            end if;

          when debug_write_wait =>
            -- wait until the debug port write finished
            wrapper_debug_o.rq_start <= '0';
            wrapper_debug_o.fifo_push <= '0';
            if wrapper_debug_i.rq_end = '1' then
              wdebug_write_done <= '1';
              state := idle;
            end if;  

          when others =>
            state := idle;
        end case;
      end if;
      --SIM DEBUG
      wdebug_write_state <= state;
    end if;
  end process;

  -- read ports

  mem_read_top_p0_i: entity work.mem_read_top_ddr
  port map (
    -- HLS/parameters/stream interface
    ap_clk => ap_clk,
    ap_rst => kernel_ap_rst,
    ap_start => read_outs(0).rq_start,
    ap_done => read_ins(0).rq_end,
    ap_idle => read_ins(0).rq_idle,
    ap_ready => read_ins(0).rq_ready,
    address => read_outs(0).rq_address,
    data_len => read_outs(0).rq_size,
    mem_offset => m_axi_gmem0_offset,
    in_fifo_data => read_ins(0).fifo_data,
    in_fifo_empty => read_ins(0).fifo_empty,
    in_fifo_almost_empty => read_ins(0).fifo_almost_empty,
    in_fifo_rd => read_outs(0).fifo_pull,
    -- AXI interface
    m_axi_gmem_AWVALID => m_axi_gmem0_AWVALID,
    m_axi_gmem_AWREADY => m_axi_gmem0_AWREADY,
    m_axi_gmem_AWADDR => m_axi_gmem0_AWADDR,
    m_axi_gmem_AWID => m_axi_gmem0_AWID,
    m_axi_gmem_AWLEN => m_axi_gmem0_AWLEN,
    m_axi_gmem_AWSIZE => m_axi_gmem0_AWSIZE,
    m_axi_gmem_AWBURST => m_axi_gmem0_AWBURST,
    m_axi_gmem_AWLOCK => m_axi_gmem0_AWLOCK,
    m_axi_gmem_AWCACHE => m_axi_gmem0_AWCACHE,
    m_axi_gmem_AWPROT => m_axi_gmem0_AWPROT,
    m_axi_gmem_AWQOS => m_axi_gmem0_AWQOS,
    m_axi_gmem_AWREGION => m_axi_gmem0_AWREGION,
    m_axi_gmem_AWUSER => m_axi_gmem0_AWUSER,
    m_axi_gmem_WVALID => m_axi_gmem0_WVALID,
    m_axi_gmem_WREADY => m_axi_gmem0_WREADY,
    m_axi_gmem_WDATA => m_axi_gmem0_WDATA,
    m_axi_gmem_WSTRB => m_axi_gmem0_WSTRB,
    m_axi_gmem_WLAST => m_axi_gmem0_WLAST,
    m_axi_gmem_WID => m_axi_gmem0_WID,
    m_axi_gmem_WUSER => m_axi_gmem0_WUSER,
    m_axi_gmem_ARVALID => m_axi_gmem0_ARVALID,
    m_axi_gmem_ARREADY => m_axi_gmem0_ARREADY,
    m_axi_gmem_ARADDR => m_axi_gmem0_ARADDR,
    m_axi_gmem_ARID => m_axi_gmem0_ARID,
    m_axi_gmem_ARLEN => m_axi_gmem0_ARLEN,
    m_axi_gmem_ARSIZE => m_axi_gmem0_ARSIZE,
    m_axi_gmem_ARBURST => m_axi_gmem0_ARBURST,
    m_axi_gmem_ARLOCK => m_axi_gmem0_ARLOCK,
    m_axi_gmem_ARCACHE => m_axi_gmem0_ARCACHE,
    m_axi_gmem_ARPROT => m_axi_gmem0_ARPROT,
    m_axi_gmem_ARQOS => m_axi_gmem0_ARQOS,
    m_axi_gmem_ARREGION => m_axi_gmem0_ARREGION,
    m_axi_gmem_ARUSER => m_axi_gmem0_ARUSER,
    m_axi_gmem_RVALID => m_axi_gmem0_RVALID,
    m_axi_gmem_RREADY => m_axi_gmem0_RREADY,
    m_axi_gmem_RDATA => m_axi_gmem0_RDATA,
    m_axi_gmem_RLAST => m_axi_gmem0_RLAST,
    m_axi_gmem_RID => m_axi_gmem0_RID,
    m_axi_gmem_RUSER => m_axi_gmem0_RUSER,
    m_axi_gmem_RRESP => m_axi_gmem0_RRESP,
    m_axi_gmem_BVALID => m_axi_gmem0_BVALID,
    m_axi_gmem_BREADY => m_axi_gmem0_BREADY,
    m_axi_gmem_BRESP => m_axi_gmem0_BRESP,
    m_axi_gmem_BID => m_axi_gmem0_BID,
    m_axi_gmem_BUSER => m_axi_gmem0_BUSER
  );

  mem_read_top_p1_i: entity work.mem_read_top_ddr
  port map (
    -- HLS/parameters/stream interface
    ap_clk => ap_clk,
    ap_rst => kernel_ap_rst,
    ap_start => read_outs(1).rq_start,
    ap_done => read_ins(1).rq_end,
    ap_idle => read_ins(1).rq_idle,
    ap_ready => read_ins(1).rq_ready,
    address => read_outs(1).rq_address,
    data_len => read_outs(1).rq_size,
    mem_offset => m_axi_gmem1_offset,
    in_fifo_data => read_ins(1).fifo_data,
    in_fifo_empty => read_ins(1).fifo_empty,
    in_fifo_almost_empty => read_ins(1).fifo_almost_empty,
    in_fifo_rd => read_outs(1).fifo_pull,
    -- AXI interface
    m_axi_gmem_AWVALID => m_axi_gmem1_AWVALID,
    m_axi_gmem_AWREADY => m_axi_gmem1_AWREADY,
    m_axi_gmem_AWADDR => m_axi_gmem1_AWADDR,
    m_axi_gmem_AWID => m_axi_gmem1_AWID,
    m_axi_gmem_AWLEN => m_axi_gmem1_AWLEN,
    m_axi_gmem_AWSIZE => m_axi_gmem1_AWSIZE,
    m_axi_gmem_AWBURST => m_axi_gmem1_AWBURST,
    m_axi_gmem_AWLOCK => m_axi_gmem1_AWLOCK,
    m_axi_gmem_AWCACHE => m_axi_gmem1_AWCACHE,
    m_axi_gmem_AWPROT => m_axi_gmem1_AWPROT,
    m_axi_gmem_AWQOS => m_axi_gmem1_AWQOS,
    m_axi_gmem_AWREGION => m_axi_gmem1_AWREGION,
    m_axi_gmem_AWUSER => m_axi_gmem1_AWUSER,
    m_axi_gmem_WVALID => m_axi_gmem1_WVALID,
    m_axi_gmem_WREADY => m_axi_gmem1_WREADY,
    m_axi_gmem_WDATA => m_axi_gmem1_WDATA,
    m_axi_gmem_WSTRB => m_axi_gmem1_WSTRB,
    m_axi_gmem_WLAST => m_axi_gmem1_WLAST,
    m_axi_gmem_WID => m_axi_gmem1_WID,
    m_axi_gmem_WUSER => m_axi_gmem1_WUSER,
    m_axi_gmem_ARVALID => m_axi_gmem1_ARVALID,
    m_axi_gmem_ARREADY => m_axi_gmem1_ARREADY,
    m_axi_gmem_ARADDR => m_axi_gmem1_ARADDR,
    m_axi_gmem_ARID => m_axi_gmem1_ARID,
    m_axi_gmem_ARLEN => m_axi_gmem1_ARLEN,
    m_axi_gmem_ARSIZE => m_axi_gmem1_ARSIZE,
    m_axi_gmem_ARBURST => m_axi_gmem1_ARBURST,
    m_axi_gmem_ARLOCK => m_axi_gmem1_ARLOCK,
    m_axi_gmem_ARCACHE => m_axi_gmem1_ARCACHE,
    m_axi_gmem_ARPROT => m_axi_gmem1_ARPROT,
    m_axi_gmem_ARQOS => m_axi_gmem1_ARQOS,
    m_axi_gmem_ARREGION => m_axi_gmem1_ARREGION,
    m_axi_gmem_ARUSER => m_axi_gmem1_ARUSER,
    m_axi_gmem_RVALID => m_axi_gmem1_RVALID,
    m_axi_gmem_RREADY => m_axi_gmem1_RREADY,
    m_axi_gmem_RDATA => m_axi_gmem1_RDATA,
    m_axi_gmem_RLAST => m_axi_gmem1_RLAST,
    m_axi_gmem_RID => m_axi_gmem1_RID,
    m_axi_gmem_RUSER => m_axi_gmem1_RUSER,
    m_axi_gmem_RRESP => m_axi_gmem1_RRESP,
    m_axi_gmem_BVALID => m_axi_gmem1_BVALID,
    m_axi_gmem_BREADY => m_axi_gmem1_BREADY,
    m_axi_gmem_BRESP => m_axi_gmem1_BRESP,
    m_axi_gmem_BID => m_axi_gmem1_BID,
    m_axi_gmem_BUSER => m_axi_gmem1_BUSER
  );

  mem_read_top_p2_i: entity work.mem_read_top_hbm
  port map (
    -- HLS/parameters/stream interface
    ap_clk => ap_clk,
    ap_rst => kernel_ap_rst,
    ap_start => read_outs(2).rq_start,
    ap_done => read_ins(2).rq_end,
    ap_idle => read_ins(2).rq_idle,
    ap_ready => read_ins(2).rq_ready,
    address => read_outs(2).rq_address,
    data_len => read_outs(2).rq_size,
    mem_offset => m_axi_gmem2_offset,
    in_fifo_data => read_ins(2).fifo_data,
    in_fifo_empty => read_ins(2).fifo_empty,
    in_fifo_almost_empty => read_ins(2).fifo_almost_empty,
    in_fifo_rd => read_outs(2).fifo_pull,
    -- AXI interface
    m_axi_gmem_AWVALID => m_axi_gmem2_AWVALID,
    m_axi_gmem_AWREADY => m_axi_gmem2_AWREADY,
    m_axi_gmem_AWADDR => m_axi_gmem2_AWADDR,
    m_axi_gmem_AWID => m_axi_gmem2_AWID,
    m_axi_gmem_AWLEN => m_axi_gmem2_AWLEN,
    m_axi_gmem_AWSIZE => m_axi_gmem2_AWSIZE,
    m_axi_gmem_AWBURST => m_axi_gmem2_AWBURST,
    m_axi_gmem_AWLOCK => m_axi_gmem2_AWLOCK,
    m_axi_gmem_AWCACHE => m_axi_gmem2_AWCACHE,
    m_axi_gmem_AWPROT => m_axi_gmem2_AWPROT,
    m_axi_gmem_AWQOS => m_axi_gmem2_AWQOS,
    m_axi_gmem_AWREGION => m_axi_gmem2_AWREGION,
    m_axi_gmem_AWUSER => m_axi_gmem2_AWUSER,
    m_axi_gmem_WVALID => m_axi_gmem2_WVALID,
    m_axi_gmem_WREADY => m_axi_gmem2_WREADY,
    m_axi_gmem_WDATA => m_axi_gmem2_WDATA,
    m_axi_gmem_WSTRB => m_axi_gmem2_WSTRB,
    m_axi_gmem_WLAST => m_axi_gmem2_WLAST,
    m_axi_gmem_WID => m_axi_gmem2_WID,
    m_axi_gmem_WUSER => m_axi_gmem2_WUSER,
    m_axi_gmem_ARVALID => m_axi_gmem2_ARVALID,
    m_axi_gmem_ARREADY => m_axi_gmem2_ARREADY,
    m_axi_gmem_ARADDR => m_axi_gmem2_ARADDR,
    m_axi_gmem_ARID => m_axi_gmem2_ARID,
    m_axi_gmem_ARLEN => m_axi_gmem2_ARLEN,
    m_axi_gmem_ARSIZE => m_axi_gmem2_ARSIZE,
    m_axi_gmem_ARBURST => m_axi_gmem2_ARBURST,
    m_axi_gmem_ARLOCK => m_axi_gmem2_ARLOCK,
    m_axi_gmem_ARCACHE => m_axi_gmem2_ARCACHE,
    m_axi_gmem_ARPROT => m_axi_gmem2_ARPROT,
    m_axi_gmem_ARQOS => m_axi_gmem2_ARQOS,
    m_axi_gmem_ARREGION => m_axi_gmem2_ARREGION,
    m_axi_gmem_ARUSER => m_axi_gmem2_ARUSER,
    m_axi_gmem_RVALID => m_axi_gmem2_RVALID,
    m_axi_gmem_RREADY => m_axi_gmem2_RREADY,
    m_axi_gmem_RDATA => m_axi_gmem2_RDATA,
    m_axi_gmem_RLAST => m_axi_gmem2_RLAST,
    m_axi_gmem_RID => m_axi_gmem2_RID,
    m_axi_gmem_RUSER => m_axi_gmem2_RUSER,
    m_axi_gmem_RRESP => m_axi_gmem2_RRESP,
    m_axi_gmem_BVALID => m_axi_gmem2_BVALID,
    m_axi_gmem_BREADY => m_axi_gmem2_BREADY,
    m_axi_gmem_BRESP => m_axi_gmem2_BRESP,
    m_axi_gmem_BID => m_axi_gmem2_BID,
    m_axi_gmem_BUSER => m_axi_gmem2_BUSER
  );

  mem_read_top_p3_i: entity work.mem_read_top_hbm
  port map (
    -- HLS/parameters/stream interface
    ap_clk => ap_clk,
    ap_rst => kernel_ap_rst,
    ap_start => read_outs(3).rq_start,
    ap_done => read_ins(3).rq_end,
    ap_idle => read_ins(3).rq_idle,
    ap_ready => read_ins(3).rq_ready,
    address => read_outs(3).rq_address,
    data_len => read_outs(3).rq_size,
    mem_offset => m_axi_gmem3_offset,
    in_fifo_data => read_ins(3).fifo_data,
    in_fifo_empty => read_ins(3).fifo_empty,
    in_fifo_almost_empty => read_ins(3).fifo_almost_empty,
    in_fifo_rd => read_outs(3).fifo_pull,
    -- AXI interface
    m_axi_gmem_AWVALID => m_axi_gmem3_AWVALID,
    m_axi_gmem_AWREADY => m_axi_gmem3_AWREADY,
    m_axi_gmem_AWADDR => m_axi_gmem3_AWADDR,
    m_axi_gmem_AWID => m_axi_gmem3_AWID,
    m_axi_gmem_AWLEN => m_axi_gmem3_AWLEN,
    m_axi_gmem_AWSIZE => m_axi_gmem3_AWSIZE,
    m_axi_gmem_AWBURST => m_axi_gmem3_AWBURST,
    m_axi_gmem_AWLOCK => m_axi_gmem3_AWLOCK,
    m_axi_gmem_AWCACHE => m_axi_gmem3_AWCACHE,
    m_axi_gmem_AWPROT => m_axi_gmem3_AWPROT,
    m_axi_gmem_AWQOS => m_axi_gmem3_AWQOS,
    m_axi_gmem_AWREGION => m_axi_gmem3_AWREGION,
    m_axi_gmem_AWUSER => m_axi_gmem3_AWUSER,
    m_axi_gmem_WVALID => m_axi_gmem3_WVALID,
    m_axi_gmem_WREADY => m_axi_gmem3_WREADY,
    m_axi_gmem_WDATA => m_axi_gmem3_WDATA,
    m_axi_gmem_WSTRB => m_axi_gmem3_WSTRB,
    m_axi_gmem_WLAST => m_axi_gmem3_WLAST,
    m_axi_gmem_WID => m_axi_gmem3_WID,
    m_axi_gmem_WUSER => m_axi_gmem3_WUSER,
    m_axi_gmem_ARVALID => m_axi_gmem3_ARVALID,
    m_axi_gmem_ARREADY => m_axi_gmem3_ARREADY,
    m_axi_gmem_ARADDR => m_axi_gmem3_ARADDR,
    m_axi_gmem_ARID => m_axi_gmem3_ARID,
    m_axi_gmem_ARLEN => m_axi_gmem3_ARLEN,
    m_axi_gmem_ARSIZE => m_axi_gmem3_ARSIZE,
    m_axi_gmem_ARBURST => m_axi_gmem3_ARBURST,
    m_axi_gmem_ARLOCK => m_axi_gmem3_ARLOCK,
    m_axi_gmem_ARCACHE => m_axi_gmem3_ARCACHE,
    m_axi_gmem_ARPROT => m_axi_gmem3_ARPROT,
    m_axi_gmem_ARQOS => m_axi_gmem3_ARQOS,
    m_axi_gmem_ARREGION => m_axi_gmem3_ARREGION,
    m_axi_gmem_ARUSER => m_axi_gmem3_ARUSER,
    m_axi_gmem_RVALID => m_axi_gmem3_RVALID,
    m_axi_gmem_RREADY => m_axi_gmem3_RREADY,
    m_axi_gmem_RDATA => m_axi_gmem3_RDATA,
    m_axi_gmem_RLAST => m_axi_gmem3_RLAST,
    m_axi_gmem_RID => m_axi_gmem3_RID,
    m_axi_gmem_RUSER => m_axi_gmem3_RUSER,
    m_axi_gmem_RRESP => m_axi_gmem3_RRESP,
    m_axi_gmem_BVALID => m_axi_gmem3_BVALID,
    m_axi_gmem_BREADY => m_axi_gmem3_BREADY,
    m_axi_gmem_BRESP => m_axi_gmem3_BRESP,
    m_axi_gmem_BID => m_axi_gmem3_BID,
    m_axi_gmem_BUSER => m_axi_gmem3_BUSER
  );

  mem_read_top_p4_i: entity work.mem_read_top_hbm
  port map (
    -- HLS/parameters/stream interface
    ap_clk => ap_clk,
    ap_rst => kernel_ap_rst,
    ap_start => read_outs(4).rq_start,
    ap_done => read_ins(4).rq_end,
    ap_idle => read_ins(4).rq_idle,
    ap_ready => read_ins(4).rq_ready,
    address => read_outs(4).rq_address,
    data_len => read_outs(4).rq_size,
    mem_offset => m_axi_gmem4_offset,
    in_fifo_data => read_ins(4).fifo_data,
    in_fifo_empty => read_ins(4).fifo_empty,
    in_fifo_almost_empty => read_ins(4).fifo_almost_empty,
    in_fifo_rd => read_outs(4).fifo_pull,
    -- AXI interface
    m_axi_gmem_AWVALID => m_axi_gmem4_AWVALID,
    m_axi_gmem_AWREADY => m_axi_gmem4_AWREADY,
    m_axi_gmem_AWADDR => m_axi_gmem4_AWADDR,
    m_axi_gmem_AWID => m_axi_gmem4_AWID,
    m_axi_gmem_AWLEN => m_axi_gmem4_AWLEN,
    m_axi_gmem_AWSIZE => m_axi_gmem4_AWSIZE,
    m_axi_gmem_AWBURST => m_axi_gmem4_AWBURST,
    m_axi_gmem_AWLOCK => m_axi_gmem4_AWLOCK,
    m_axi_gmem_AWCACHE => m_axi_gmem4_AWCACHE,
    m_axi_gmem_AWPROT => m_axi_gmem4_AWPROT,
    m_axi_gmem_AWQOS => m_axi_gmem4_AWQOS,
    m_axi_gmem_AWREGION => m_axi_gmem4_AWREGION,
    m_axi_gmem_AWUSER => m_axi_gmem4_AWUSER,
    m_axi_gmem_WVALID => m_axi_gmem4_WVALID,
    m_axi_gmem_WREADY => m_axi_gmem4_WREADY,
    m_axi_gmem_WDATA => m_axi_gmem4_WDATA,
    m_axi_gmem_WSTRB => m_axi_gmem4_WSTRB,
    m_axi_gmem_WLAST => m_axi_gmem4_WLAST,
    m_axi_gmem_WID => m_axi_gmem4_WID,
    m_axi_gmem_WUSER => m_axi_gmem4_WUSER,
    m_axi_gmem_ARVALID => m_axi_gmem4_ARVALID,
    m_axi_gmem_ARREADY => m_axi_gmem4_ARREADY,
    m_axi_gmem_ARADDR => m_axi_gmem4_ARADDR,
    m_axi_gmem_ARID => m_axi_gmem4_ARID,
    m_axi_gmem_ARLEN => m_axi_gmem4_ARLEN,
    m_axi_gmem_ARSIZE => m_axi_gmem4_ARSIZE,
    m_axi_gmem_ARBURST => m_axi_gmem4_ARBURST,
    m_axi_gmem_ARLOCK => m_axi_gmem4_ARLOCK,
    m_axi_gmem_ARCACHE => m_axi_gmem4_ARCACHE,
    m_axi_gmem_ARPROT => m_axi_gmem4_ARPROT,
    m_axi_gmem_ARQOS => m_axi_gmem4_ARQOS,
    m_axi_gmem_ARREGION => m_axi_gmem4_ARREGION,
    m_axi_gmem_ARUSER => m_axi_gmem4_ARUSER,
    m_axi_gmem_RVALID => m_axi_gmem4_RVALID,
    m_axi_gmem_RREADY => m_axi_gmem4_RREADY,
    m_axi_gmem_RDATA => m_axi_gmem4_RDATA,
    m_axi_gmem_RLAST => m_axi_gmem4_RLAST,
    m_axi_gmem_RID => m_axi_gmem4_RID,
    m_axi_gmem_RUSER => m_axi_gmem4_RUSER,
    m_axi_gmem_RRESP => m_axi_gmem4_RRESP,
    m_axi_gmem_BVALID => m_axi_gmem4_BVALID,
    m_axi_gmem_BREADY => m_axi_gmem4_BREADY,
    m_axi_gmem_BRESP => m_axi_gmem4_BRESP,
    m_axi_gmem_BID => m_axi_gmem4_BID,
    m_axi_gmem_BUSER => m_axi_gmem4_BUSER
  );

  -- write ports

  mem_write_top_p0_i: entity work.mem_write_top_hbm
  port map (
    -- HLS/parameters/stream interface
    ap_clk => ap_clk,
    ap_rst => kernel_ap_rst,
    ap_start => write_outs(0).rq_start,
    ap_done => write_ins(0).rq_end,
    ap_idle => write_ins(0).rq_idle,
    ap_ready => write_ins(0).rq_ready,
    address => write_outs(0).rq_address,
    data_len => write_outs(0).rq_size,
    mem_offset => m_axi_gmem5_offset,
    out_fifo_data => write_outs(0).fifo_data,
    out_fifo_full => write_ins(0).fifo_full,
    out_fifo_almost_full => write_ins(0).fifo_almost_full,
    out_fifo_wr => write_outs(0).fifo_push,
    -- AXI interface
    m_axi_gmem_AWVALID => m_axi_gmem5_AWVALID,
    m_axi_gmem_AWREADY => m_axi_gmem5_AWREADY,
    m_axi_gmem_AWADDR => m_axi_gmem5_AWADDR,
    m_axi_gmem_AWID => m_axi_gmem5_AWID,
    m_axi_gmem_AWLEN => m_axi_gmem5_AWLEN,
    m_axi_gmem_AWSIZE => m_axi_gmem5_AWSIZE,
    m_axi_gmem_AWBURST => m_axi_gmem5_AWBURST,
    m_axi_gmem_AWLOCK => m_axi_gmem5_AWLOCK,
    m_axi_gmem_AWCACHE => m_axi_gmem5_AWCACHE,
    m_axi_gmem_AWPROT => m_axi_gmem5_AWPROT,
    m_axi_gmem_AWQOS => m_axi_gmem5_AWQOS,
    m_axi_gmem_AWREGION => m_axi_gmem5_AWREGION,
    m_axi_gmem_AWUSER => m_axi_gmem5_AWUSER,
    m_axi_gmem_WVALID => m_axi_gmem5_WVALID,
    m_axi_gmem_WREADY => m_axi_gmem5_WREADY,
    m_axi_gmem_WDATA => m_axi_gmem5_WDATA,
    m_axi_gmem_WSTRB => m_axi_gmem5_WSTRB,
    m_axi_gmem_WLAST => m_axi_gmem5_WLAST,
    m_axi_gmem_WID => m_axi_gmem5_WID,
    m_axi_gmem_WUSER => m_axi_gmem5_WUSER,
    m_axi_gmem_ARVALID => m_axi_gmem5_ARVALID,
    m_axi_gmem_ARREADY => m_axi_gmem5_ARREADY,
    m_axi_gmem_ARADDR => m_axi_gmem5_ARADDR,
    m_axi_gmem_ARID => m_axi_gmem5_ARID,
    m_axi_gmem_ARLEN => m_axi_gmem5_ARLEN,
    m_axi_gmem_ARSIZE => m_axi_gmem5_ARSIZE,
    m_axi_gmem_ARBURST => m_axi_gmem5_ARBURST,
    m_axi_gmem_ARLOCK => m_axi_gmem5_ARLOCK,
    m_axi_gmem_ARCACHE => m_axi_gmem5_ARCACHE,
    m_axi_gmem_ARPROT => m_axi_gmem5_ARPROT,
    m_axi_gmem_ARQOS => m_axi_gmem5_ARQOS,
    m_axi_gmem_ARREGION => m_axi_gmem5_ARREGION,
    m_axi_gmem_ARUSER => m_axi_gmem5_ARUSER,
    m_axi_gmem_RVALID => m_axi_gmem5_RVALID,
    m_axi_gmem_RREADY => m_axi_gmem5_RREADY,
    m_axi_gmem_RDATA => m_axi_gmem5_RDATA,
    m_axi_gmem_RLAST => m_axi_gmem5_RLAST,
    m_axi_gmem_RID => m_axi_gmem5_RID,
    m_axi_gmem_RUSER => m_axi_gmem5_RUSER,
    m_axi_gmem_RRESP => m_axi_gmem5_RRESP,
    m_axi_gmem_BVALID => m_axi_gmem5_BVALID,
    m_axi_gmem_BREADY => m_axi_gmem5_BREADY,
    m_axi_gmem_BRESP => m_axi_gmem5_BRESP,
    m_axi_gmem_BID => m_axi_gmem5_BID,
    m_axi_gmem_BUSER => m_axi_gmem5_BUSER
  );

  mem_write_top_p1_i: entity work.mem_write_top_hbm
  port map (
    -- HLS/parameters/stream interface
    ap_clk => ap_clk,
    ap_rst => kernel_ap_rst,
    ap_start => write_outs(1).rq_start,
    ap_done => write_ins(1).rq_end,
    ap_idle => write_ins(1).rq_idle,
    ap_ready => write_ins(1).rq_ready,
    address => write_outs(1).rq_address,
    data_len => write_outs(1).rq_size,
    mem_offset => m_axi_gmem6_offset,
    out_fifo_data => write_outs(1).fifo_data,
    out_fifo_full => write_ins(1).fifo_full,
    out_fifo_almost_full => write_ins(1).fifo_almost_full,
    out_fifo_wr => write_outs(1).fifo_push,
    -- AXI interface
    m_axi_gmem_AWVALID => m_axi_gmem6_AWVALID,
    m_axi_gmem_AWREADY => m_axi_gmem6_AWREADY,
    m_axi_gmem_AWADDR => m_axi_gmem6_AWADDR,
    m_axi_gmem_AWID => m_axi_gmem6_AWID,
    m_axi_gmem_AWLEN => m_axi_gmem6_AWLEN,
    m_axi_gmem_AWSIZE => m_axi_gmem6_AWSIZE,
    m_axi_gmem_AWBURST => m_axi_gmem6_AWBURST,
    m_axi_gmem_AWLOCK => m_axi_gmem6_AWLOCK,
    m_axi_gmem_AWCACHE => m_axi_gmem6_AWCACHE,
    m_axi_gmem_AWPROT => m_axi_gmem6_AWPROT,
    m_axi_gmem_AWQOS => m_axi_gmem6_AWQOS,
    m_axi_gmem_AWREGION => m_axi_gmem6_AWREGION,
    m_axi_gmem_AWUSER => m_axi_gmem6_AWUSER,
    m_axi_gmem_WVALID => m_axi_gmem6_WVALID,
    m_axi_gmem_WREADY => m_axi_gmem6_WREADY,
    m_axi_gmem_WDATA => m_axi_gmem6_WDATA,
    m_axi_gmem_WSTRB => m_axi_gmem6_WSTRB,
    m_axi_gmem_WLAST => m_axi_gmem6_WLAST,
    m_axi_gmem_WID => m_axi_gmem6_WID,
    m_axi_gmem_WUSER => m_axi_gmem6_WUSER,
    m_axi_gmem_ARVALID => m_axi_gmem6_ARVALID,
    m_axi_gmem_ARREADY => m_axi_gmem6_ARREADY,
    m_axi_gmem_ARADDR => m_axi_gmem6_ARADDR,
    m_axi_gmem_ARID => m_axi_gmem6_ARID,
    m_axi_gmem_ARLEN => m_axi_gmem6_ARLEN,
    m_axi_gmem_ARSIZE => m_axi_gmem6_ARSIZE,
    m_axi_gmem_ARBURST => m_axi_gmem6_ARBURST,
    m_axi_gmem_ARLOCK => m_axi_gmem6_ARLOCK,
    m_axi_gmem_ARCACHE => m_axi_gmem6_ARCACHE,
    m_axi_gmem_ARPROT => m_axi_gmem6_ARPROT,
    m_axi_gmem_ARQOS => m_axi_gmem6_ARQOS,
    m_axi_gmem_ARREGION => m_axi_gmem6_ARREGION,
    m_axi_gmem_ARUSER => m_axi_gmem6_ARUSER,
    m_axi_gmem_RVALID => m_axi_gmem6_RVALID,
    m_axi_gmem_RREADY => m_axi_gmem6_RREADY,
    m_axi_gmem_RDATA => m_axi_gmem6_RDATA,
    m_axi_gmem_RLAST => m_axi_gmem6_RLAST,
    m_axi_gmem_RID => m_axi_gmem6_RID,
    m_axi_gmem_RUSER => m_axi_gmem6_RUSER,
    m_axi_gmem_RRESP => m_axi_gmem6_RRESP,
    m_axi_gmem_BVALID => m_axi_gmem6_BVALID,
    m_axi_gmem_BREADY => m_axi_gmem6_BREADY,
    m_axi_gmem_BRESP => m_axi_gmem6_BRESP,
    m_axi_gmem_BID => m_axi_gmem6_BID,
    m_axi_gmem_BUSER => m_axi_gmem6_BUSER
  );

  mem_write_top_p2_i: entity work.mem_write_top_hbm
  port map (
    -- HLS/parameters/stream interface
    ap_clk => ap_clk,
    ap_rst => kernel_ap_rst,
    ap_start => write_outs(2).rq_start,
    ap_done => write_ins(2).rq_end,
    ap_idle => write_ins(2).rq_idle,
    ap_ready => write_ins(2).rq_ready,
    address => write_outs(2).rq_address,
    data_len => write_outs(2).rq_size,
    mem_offset => m_axi_gmem7_offset,
    out_fifo_data => write_outs(2).fifo_data,
    out_fifo_full => write_ins(2).fifo_full,
    out_fifo_almost_full => write_ins(2).fifo_almost_full,
    out_fifo_wr => write_outs(2).fifo_push,
    -- AXI interface
    m_axi_gmem_AWVALID => m_axi_gmem7_AWVALID,
    m_axi_gmem_AWREADY => m_axi_gmem7_AWREADY,
    m_axi_gmem_AWADDR => m_axi_gmem7_AWADDR,
    m_axi_gmem_AWID => m_axi_gmem7_AWID,
    m_axi_gmem_AWLEN => m_axi_gmem7_AWLEN,
    m_axi_gmem_AWSIZE => m_axi_gmem7_AWSIZE,
    m_axi_gmem_AWBURST => m_axi_gmem7_AWBURST,
    m_axi_gmem_AWLOCK => m_axi_gmem7_AWLOCK,
    m_axi_gmem_AWCACHE => m_axi_gmem7_AWCACHE,
    m_axi_gmem_AWPROT => m_axi_gmem7_AWPROT,
    m_axi_gmem_AWQOS => m_axi_gmem7_AWQOS,
    m_axi_gmem_AWREGION => m_axi_gmem7_AWREGION,
    m_axi_gmem_AWUSER => m_axi_gmem7_AWUSER,
    m_axi_gmem_WVALID => m_axi_gmem7_WVALID,
    m_axi_gmem_WREADY => m_axi_gmem7_WREADY,
    m_axi_gmem_WDATA => m_axi_gmem7_WDATA,
    m_axi_gmem_WSTRB => m_axi_gmem7_WSTRB,
    m_axi_gmem_WLAST => m_axi_gmem7_WLAST,
    m_axi_gmem_WID => m_axi_gmem7_WID,
    m_axi_gmem_WUSER => m_axi_gmem7_WUSER,
    m_axi_gmem_ARVALID => m_axi_gmem7_ARVALID,
    m_axi_gmem_ARREADY => m_axi_gmem7_ARREADY,
    m_axi_gmem_ARADDR => m_axi_gmem7_ARADDR,
    m_axi_gmem_ARID => m_axi_gmem7_ARID,
    m_axi_gmem_ARLEN => m_axi_gmem7_ARLEN,
    m_axi_gmem_ARSIZE => m_axi_gmem7_ARSIZE,
    m_axi_gmem_ARBURST => m_axi_gmem7_ARBURST,
    m_axi_gmem_ARLOCK => m_axi_gmem7_ARLOCK,
    m_axi_gmem_ARCACHE => m_axi_gmem7_ARCACHE,
    m_axi_gmem_ARPROT => m_axi_gmem7_ARPROT,
    m_axi_gmem_ARQOS => m_axi_gmem7_ARQOS,
    m_axi_gmem_ARREGION => m_axi_gmem7_ARREGION,
    m_axi_gmem_ARUSER => m_axi_gmem7_ARUSER,
    m_axi_gmem_RVALID => m_axi_gmem7_RVALID,
    m_axi_gmem_RREADY => m_axi_gmem7_RREADY,
    m_axi_gmem_RDATA => m_axi_gmem7_RDATA,
    m_axi_gmem_RLAST => m_axi_gmem7_RLAST,
    m_axi_gmem_RID => m_axi_gmem7_RID,
    m_axi_gmem_RUSER => m_axi_gmem7_RUSER,
    m_axi_gmem_RRESP => m_axi_gmem7_RRESP,
    m_axi_gmem_BVALID => m_axi_gmem7_BVALID,
    m_axi_gmem_BREADY => m_axi_gmem7_BREADY,
    m_axi_gmem_BRESP => m_axi_gmem7_BRESP,
    m_axi_gmem_BID => m_axi_gmem7_BID,
    m_axi_gmem_BUSER => m_axi_gmem7_BUSER
  );

  -- debug port: PLRAM memory

  mem_write_top_pd_i: entity work.mem_write_top_hbm
  port map (
    -- HLS/parameters/stream interface
    ap_clk => ap_clk,
    ap_rst => kernel_ap_rst,
    ap_start => debug_write_port_o.rq_start,
    ap_done => debug_write_port_i.rq_end,
    ap_idle => debug_write_port_i.rq_idle,
    ap_ready => debug_write_port_i.rq_ready,
    address => debug_write_port_o.rq_address,
    data_len => debug_write_port_o.rq_size,
    mem_offset => m_axi_gmem8_offset,
    out_fifo_data => debug_write_port_o.fifo_data,
    out_fifo_full => debug_write_port_i.fifo_full,
    out_fifo_almost_full => debug_write_port_i.fifo_almost_full,
    out_fifo_wr => debug_write_port_o.fifo_push,
    -- AXI interface
    m_axi_gmem_AWVALID => m_axi_gmem8_AWVALID,
    m_axi_gmem_AWREADY => m_axi_gmem8_AWREADY,
    m_axi_gmem_AWADDR => m_axi_gmem8_AWADDR,
    m_axi_gmem_AWID => m_axi_gmem8_AWID,
    m_axi_gmem_AWLEN => m_axi_gmem8_AWLEN,
    m_axi_gmem_AWSIZE => m_axi_gmem8_AWSIZE,
    m_axi_gmem_AWBURST => m_axi_gmem8_AWBURST,
    m_axi_gmem_AWLOCK => m_axi_gmem8_AWLOCK,
    m_axi_gmem_AWCACHE => m_axi_gmem8_AWCACHE,
    m_axi_gmem_AWPROT => m_axi_gmem8_AWPROT,
    m_axi_gmem_AWQOS => m_axi_gmem8_AWQOS,
    m_axi_gmem_AWREGION => m_axi_gmem8_AWREGION,
    m_axi_gmem_AWUSER => m_axi_gmem8_AWUSER,
    m_axi_gmem_WVALID => m_axi_gmem8_WVALID,
    m_axi_gmem_WREADY => m_axi_gmem8_WREADY,
    m_axi_gmem_WDATA => m_axi_gmem8_WDATA,
    m_axi_gmem_WSTRB => m_axi_gmem8_WSTRB,
    m_axi_gmem_WLAST => m_axi_gmem8_WLAST,
    m_axi_gmem_WID => m_axi_gmem8_WID,
    m_axi_gmem_WUSER => m_axi_gmem8_WUSER,
    m_axi_gmem_ARVALID => m_axi_gmem8_ARVALID,
    m_axi_gmem_ARREADY => m_axi_gmem8_ARREADY,
    m_axi_gmem_ARADDR => m_axi_gmem8_ARADDR,
    m_axi_gmem_ARID => m_axi_gmem8_ARID,
    m_axi_gmem_ARLEN => m_axi_gmem8_ARLEN,
    m_axi_gmem_ARSIZE => m_axi_gmem8_ARSIZE,
    m_axi_gmem_ARBURST => m_axi_gmem8_ARBURST,
    m_axi_gmem_ARLOCK => m_axi_gmem8_ARLOCK,
    m_axi_gmem_ARCACHE => m_axi_gmem8_ARCACHE,
    m_axi_gmem_ARPROT => m_axi_gmem8_ARPROT,
    m_axi_gmem_ARQOS => m_axi_gmem8_ARQOS,
    m_axi_gmem_ARREGION => m_axi_gmem8_ARREGION,
    m_axi_gmem_ARUSER => m_axi_gmem8_ARUSER,
    m_axi_gmem_RVALID => m_axi_gmem8_RVALID,
    m_axi_gmem_RREADY => m_axi_gmem8_RREADY,
    m_axi_gmem_RDATA => m_axi_gmem8_RDATA,
    m_axi_gmem_RLAST => m_axi_gmem8_RLAST,
    m_axi_gmem_RID => m_axi_gmem8_RID,
    m_axi_gmem_RUSER => m_axi_gmem8_RUSER,
    m_axi_gmem_RRESP => m_axi_gmem8_RRESP,
    m_axi_gmem_BVALID => m_axi_gmem8_BVALID,
    m_axi_gmem_BREADY => m_axi_gmem8_BREADY,
    m_axi_gmem_BRESP => m_axi_gmem8_BRESP,
    m_axi_gmem_BID => m_axi_gmem8_BID,
    m_axi_gmem_BUSER => m_axi_gmem8_BUSER
  );

  -- solver instance

  solver_i: entity work.solver
  generic map (
    SIM_DEBUG => SIM_DEBUG,
    WRITE_ILU0_RESULTS => WRITE_ILU0_RESULTS
  )
  port map (
    clk               => ap_clk,
    reset             => kernel_ap_rst,
    start             => kernel_ap_start,
    debug_rate        => kernel_debug_rate,
    debug_lines       => kernel_debug_lines,
    done              => kernel_ap_done,
    iteration_end     => open,
    no_change         => kernel_no_change,
    read_ins          => read_ins,
    read_outs         => read_outs,
    write_ins         => write_ins,
    write_outs        => write_outs,
    max_iters         => kernel_max_iter,
    desired_precision => kernel_precision,
    debug_write_ins   => debug_write_i,
    debug_write_outs  => debug_write_o
  );

  -- register some outputs when kernel finished to avoid losing their status at reset
  kernel_out_save_p: process(ap_clk)
  begin
    if rising_edge(ap_clk) then
      if kernel_ap_rst = '1' then
        kernel_no_change_reg <= '0';
      else
        if kernel_ap_done = '1' then
          kernel_no_change_reg <= kernel_no_change;
        end if;
      end if;
    end if;
  end process;

  -- sharing of debug write port between solver and debug_write_p process

  -- from solver/wrapper
  debug_write_port_o.rq_start   <= debug_write_o.rq_start   when kernel_running = '1' else wrapper_debug_o.rq_start;
  debug_write_port_o.rq_address <= debug_write_o.rq_address when kernel_running = '1' else wrapper_debug_o.rq_address;
  debug_write_port_o.rq_size    <= debug_write_o.rq_size    when kernel_running = '1' else wrapper_debug_o.rq_size;
  debug_write_port_o.fifo_data  <= debug_write_o.fifo_data  when kernel_running = '1' else wrapper_debug_o.fifo_data;
  debug_write_port_o.fifo_push  <= debug_write_o.fifo_push  when kernel_running = '1' else wrapper_debug_o.fifo_push;
  -- to solver
  debug_write_i.rq_end           <= debug_write_port_i.rq_end;
  debug_write_i.rq_idle          <= debug_write_port_i.rq_idle;
  debug_write_i.rq_ready         <= debug_write_port_i.rq_ready;
  debug_write_i.fifo_full        <= debug_write_port_i.fifo_full;
  debug_write_i.fifo_almost_full <= debug_write_port_i.fifo_almost_full;
  -- to wrapper
  wrapper_debug_i.rq_end           <= debug_write_port_i.rq_end;
  wrapper_debug_i.rq_idle          <= debug_write_port_i.rq_idle;
  wrapper_debug_i.rq_ready         <= debug_write_port_i.rq_ready;
  wrapper_debug_i.fifo_full        <= debug_write_port_i.fifo_full;
  wrapper_debug_i.fifo_almost_full <= debug_write_port_i.fifo_almost_full;

end architecture;
