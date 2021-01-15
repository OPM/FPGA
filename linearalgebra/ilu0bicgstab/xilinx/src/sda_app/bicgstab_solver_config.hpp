/*
  Copyright 2020 Equinor ASA

  This file is part of the Open Porous Media project (OPM).

  OPM is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  OPM is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with OPM.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef __BICGSTAB_SOLVER_CONFIG_HPP__
#define __BICGSTAB_SOLVER_CONFIG_HPP__

#include "dev_config.hpp"

// *****************************************************************************
// macros that are spefific for a configuration
// *****************************************************************************

#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  // number of read/write buffers
  #define RW_BUF 5
  // kernel name
  #define KERNEL_NAME "bicgstab_2r_3r3w_rtl_v1"
#else
  #error "The macro PORTS_CONFIG must be defined and set to a supported target."
#endif

// *****************************************************************************
// macros that are common between configurations
// *****************************************************************************

// number of configuration setup cachelines
#define SETUP_LINES 5

// max number of results buffers
#define RES_BUF_MAX 10

// default size in cachelines of the debug output buffer:
// max for Alveo boards is 2048, but SDx hwemu fails if set beyond 640
#define DEBUG_OUTBUF_WORDS_DEFAULT 512
#define DEBUG_OUTBUF_WORDS_MAX 2048
#define DEBUG_OUTBUF_WORDS_MAX_EMU 640
// size of the cacheline in bytes, bits and double words
#define CACHELINE_BYTES 64
#define CACHELINE_BITS (CACHELINE_BYTES*8)
#define CACHELINE_DBL_WORDS (CACHELINE_BYTES/8)

#endif //__BICGSTAB_SOLVER_CONFIG_HPP__
