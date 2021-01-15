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

# Makefile to create the library with all the functions required to interface
# OPM/flow to the FPGA kernel implementation.

# ------------------------------------------------------------------------------
# design-specific configuration
# ------------------------------------------------------------------------------

# ports configuration
PORTS_CONFIG ?= 2r_3r3w_ddr
# host C sources directory
SRCDIR ?= ../../../src/sda_app
# debug level
DEBUG_LEVEL ?= 0
# output library file name
TARGET_LIB_NAME ?= fpga_lib_alveo_u280.a

# ------------------------------------------------------------------------------

# check that Xilinx XRT has been properly setup
ifeq ($(strip $(XILINX_XRT)),)
  $(error XILINX_XRT must be defined, Xilinx XRT must be installed and properly setup)
endif

# compiler tools
CXX = g++

# host compiler global settings

CXXFLAGS += \
 -DPORTS_CONFIG=PORTS_$(PORTS_CONFIG) -DBDA_DEBUG_LEVEL=$(DEBUG_LEVEL) \
 -D__USE_XOPEN2K8 \
 -I$(XILINX_XRT)/include/ \
 -I$(SRCDIR)/ \
 -I$(SRCDIR)/common/ \
 -O3 -g -Wall -c

.PHONY: all clean

all: $(TARGET_LIB_NAME)

clean:
	rm -f $(HOST_OBJECTS) $(TARGET_LIB_NAME)

# create the static library from all the object files

HOST_OBJECTS = bda_utils.o bicgstab_utils.o opencl_lib.o fpga_functions_bicgstab.o

$(TARGET_LIB_NAME): $(HOST_OBJECTS)
	ar rcs "$@" $?

# compilation of all the object files

bda_utils.o: $(SRCDIR)/common/bda_utils.cpp $(SRCDIR)/common/bda_utils.hpp
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -o "$@" "$<"

bicgstab_utils.o: $(SRCDIR)/common/bicgstab_utils.cpp $(SRCDIR)/common/bicgstab_utils.hpp $(SRCDIR)/common/bda_utils.hpp
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -o "$@" "$<"

opencl_lib.o: $(SRCDIR)/common/opencl_lib.cpp $(SRCDIR)/common/opencl_lib.hpp $(SRCDIR)/common/bda_utils.hpp
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -o "$@" "$<"

fpga_functions_bicgstab.o: $(SRCDIR)/common/fpga_functions_bicgstab.cpp $(SRCDIR)/common/fpga_functions_bicgstab.hpp $(SRCDIR)/common/bda_utils.hpp $(SRCDIR)/common/bicgstab_utils.hpp $(SRCDIR)/common/dev_config.hpp $(SRCDIR)/bicgstab_solver_config.hpp
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -o "$@" "$<"
