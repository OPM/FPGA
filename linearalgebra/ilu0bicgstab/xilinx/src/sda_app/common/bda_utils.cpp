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

/*
  Library of functions (generic)
*/

#include <stdio.h>
#include <string.h>
#include <iostream>

#include "bda_utils.hpp"

int roundUpTo(int i, int n){
    if(i % n == 0)
        return i;
    else
        return (i / n + 1) * n;
}

bool even(int n) {
  return (n % 2 == 0);
}

void wait_for_enter() {
  printf("\nPress ENTER to continue after setting up ILA trigger...\n");
  do {} while (std::cin.get() != '\n');
}

size_t get_file_size(char *filename) {
  FILE *fin;
  size_t size;
  fin = fopen(filename, "rb");
  if (fin == NULL) return -1;
  fseek(fin, 0, SEEK_END);
  size = ftell(fin);
  fclose(fin);
  return size;
}

// remove path from matrix name
int get_matrix_name(char *matrix_path, char *matrix_name) {
char *ret,*ret1;
  // input checks
  if (matrix_path == NULL) {
    printf("%s: ERROR: matrix_path string must be already allocated\n",__func__);
    return 1;
  }
  if (matrix_name == NULL) {
    printf("%s: ERROR: matrix_name string must be already allocated\n",__func__);
    return 1;
  }
  if (strlen(matrix_path) == 0) {
    printf("%s: ERROR: matrix_path string must not be empty\n",__func__);
    return 1;
  }
  // find the last occurrence of '/'
  ret = strrchr(matrix_path, '/');
  // no '/' found in path
  if (ret == NULL) {
    strcpy(matrix_name, matrix_path);
    return 0;
  }
  // remove the last '/'
  ret1 = &ret[1];
  // check there's anything left
  if (strlen(ret1) == 0) {
    printf("%s: ERROR: matrix_path must not be terminating with '/'\n",__func__);
    return 1;
  }
  strcpy(matrix_name, ret1);
  return 0;
}

