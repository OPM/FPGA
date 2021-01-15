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

#ifndef __HLS_SDACCEL_KERNEL_IOSTREAMS_HLS_HPP__
#define __HLS_SDACCEL_KERNEL_IOSTREAMS_HLS_HPP__

/*
  HLS-SDAccel/Vitis integration
  This file must be used with Vivado HLS
*/

extern "C"
void hls_sdaccel_kernel_iostreams_hls(
 const ap_uint<512> *mem_in,
 ap_uint<512> *mem_out,
 const unsigned long long mem_in_address,
 const unsigned long long mem_out_address,
 unsigned int data_len);

// *****************************************************************************
// design specific macros
// *****************************************************************************

// use data flow variant of the design
// WARNING: all function's interfaces will be implemented as streams (even simple scalars)
//#define USE_DATAFLOW

// define this to use a dummy compute core that performs out[*] = in[*] + 1
//#define DUMMY_COMPUTE_VADD1

// size of input buffer in 512-bit words
#define INPUT_BUF_LEN 512

// size of output buffer in 512-bit words
#define RESULTS_BUF_LEN 512

// size in bytes of a cacheline
#define CACHELINE_BYTES 64
// size in elements of a cacheline (8 doubles)
#define CACHELINE_ELEMS 8

// *****************************************************************************
// debug / general usage macros
// *****************************************************************************

// macro to use defines in pragma (see UG902, "Using #Define with Pragma Directives")
#define PRAGMA_SUB(x) _Pragma (#x)
#define PRAGMA_HLS(x) PRAGMA_SUB(x)

// define BDA_DEBUG_LEVEL to a value greater than 0 to activate debug printouts
#if !defined (BDA_DEBUG_LEVEL)
#define BDA_DEBUG_LEVEL 0
#endif

#if defined(__SYNTHESIS__)
  #define BDA_DEBUG(y,x)    { if (y <= BDA_DEBUG_LEVEL) { x; fflush(NULL); } }
  #define BDA_DEBUG_SW(y,x) {  }
#else
  #define BDA_DEBUG(y,x)    { if (y <= BDA_DEBUG_LEVEL) { x; fflush(NULL); } }
  #define BDA_DEBUG_SW      BDA_DEBUG
#endif

#endif //__HLS_SDACCEL_KERNEL_IOSTREAMS_HLS_HPP__

