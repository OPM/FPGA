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

#ifndef __BDA_UTILS_HPP__
#define __BDA_UTILS_HPP__

int roundUpTo(int i, int n);
bool even(int n);
void wait_for_enter();
size_t get_file_size(char *filename);
int get_matrix_name(char *matrix_path, char *matrix_name);

union int2chars {
  int intVal;
  char charVals[4];
};

union double2int {
  unsigned long int int_val;
  double double_val;
};

// memory alignment for SDx/Vitis host buffers
#define SDX_MEM_ALIGNMENT 4096

// macro to use defines in pragma (see UG902, "Using #Define with Pragma Directives")
#define PRAGMA_SUB(x) _Pragma (#x)
#define PRAGMA_HLS(x) PRAGMA_SUB(x)

// define BDA_DEBUG_LEVEL to a value greater than 0 to activate debug printouts
#if !defined (BDA_DEBUG_LEVEL)
#define BDA_DEBUG_LEVEL 0
#endif

#if defined(__SYNTHESIS__)
  #define BDA_DEBUG(y,x) { }
  #define BDA_DEBUG_SW BDA_DEBUG
#else
  #define BDA_DEBUG(y,x) { if (y <= BDA_DEBUG_LEVEL) { x; fflush(NULL); } }
  #define BDA_DEBUG_SW BDA_DEBUG
#endif

#endif //__BDA_UTILS_HPP__

