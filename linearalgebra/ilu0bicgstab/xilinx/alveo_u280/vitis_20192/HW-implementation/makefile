#  Copyright 2020 Equinor ASA
#
#  This file is part of the Open Porous Media project (OPM).
#
#  OPM is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  OPM is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with OPM.  If not, see <http://www.gnu.org/licenses/>.

# ------------------------------------------------------------------------------
# tool/platform configuration
# ------------------------------------------------------------------------------

# Vitis target platform
VITIS_PLATFORM = xilinx_u280_xdma_201920_1
# Platform XSA file (default installation path; change as needed)
PLATFORM_XSA ?= /opt/xilinx/platforms/xilinx_u280_xdma_201920_1/hw/xilinx_u280_xdma_201920_1.xsa

# available targets are:
#   sw_emu : C simulation, only for HLS/OpenCL kernels
#   hw_emu : HW emulation
#   hw     : HW implementation
# Here we must use "hw" to enable the HW implementation flow.
TARGET = hw

# ------------------------------------------------------------------------------
# design-specific configuration
# ------------------------------------------------------------------------------

# ports configuration
PORTS_CONFIG = 2r_3r3w_ddr
# short version of PORTS_CONFIG (remove the suffix "_ddr" and "_hbm" if present)
PORTS_CONFIG_SHORT1 = $(patsubst %_ddr,%,$(PORTS_CONFIG))
PORTS_CONFIG_SHORT2 = $(patsubst %_hbm,%,$(PORTS_CONFIG_SHORT1))
PORTS_CONFIG_SHORT = $(PORTS_CONFIG_SHORT2)
# kernel XO package
KERNEL_PACKAGE = bicgstab_$(PORTS_CONFIG_SHORT)_rtl_v1.xo
# sources directory
SRCDIR = ../../../src

# ------------------------------------------------------------------------------

include ../../makefile.primary.vitis
