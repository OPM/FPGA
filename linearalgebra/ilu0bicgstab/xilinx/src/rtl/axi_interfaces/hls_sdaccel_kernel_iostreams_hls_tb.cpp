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
  HLS-SDAccel/Vitis integration
  This file must be used with Vivado HLS
  Testbench
*/

#include <iostream>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <stdio.h>
#include <fstream>
#include <string>
#include <sstream>
#include <ap_int.h>
#include <math.h>
#include <unistd.h>
#include <assert.h>
#include <time.h>
#include "hls_sdaccel_kernel_iostreams_hls.hpp"

int main(int argc, char** argv){
  int data_input, data_len;
  double *input=NULL,*output=NULL,*sw_output=NULL;
  unsigned long long input_address;  // index (in cachelines) of where to start reading from input buffer
  unsigned long long output_address; // index (in cachelines) of where to start writing to the output buffer
  unsigned long long offset;

  // WARNING: if creating the RTL (EXPORT=1), do not use more lines than the
  // size of the streams, otherwise the simulation will deadlock (not using dataflow)
  
#if defined(EXPORT_DESIGN)
  // add some offset to the addresses
  input_address = 5;
  output_address = 3;
  offset = input_address > output_address ? input_address : output_address;
  // number of double elements to transfer
  data_input = (511-offset) * (CACHELINE_BYTES/sizeof(double)); // size in cachelines
#else
  input_address = 0;
  output_address = 0;
  offset = 0;
  // compute how many elements to use to make 3 rounds of filled buffer + 15 lines
  data_input = (INPUT_BUF_LEN*3+15) * (CACHELINE_BYTES/sizeof(double)); // size in cachelines
#endif

  // if data_input is not aligned to 512-bit (8x double), it will be rounded
  if (data_input % (int)sizeof(double) != 0) {
    data_input = data_input - data_input % (int)sizeof(double) + (int)sizeof(double);
    printf("Warning: data_input size not aligned with input, rounding to %d\n",data_input);
  }
  // number of data elements
  data_len = data_input / (int)sizeof(double);

  BDA_DEBUG(1,printf("Allocating buffers for %d elements (%d lines)\n",data_input,data_len);)

  input = (double *) malloc(sizeof(double) * (data_input + input_address*CACHELINE_BYTES));
  if (input == NULL) {
    fprintf(stderr, "Memory allocation failed for input\n");
    return EXIT_FAILURE;
  }
  output = (double *) malloc(sizeof(double) * (data_input + output_address*CACHELINE_BYTES));
  if (output == NULL) {
    fprintf(stderr, "Memory allocation failed for output\n");
    return EXIT_FAILURE;
  }
  sw_output = (double *) malloc(sizeof(double) * (data_input + output_address*CACHELINE_BYTES));

  if (sw_output == NULL) {
    fprintf(stderr, "Memory allocation failed for sw_output\n");
    return EXIT_FAILURE;
  }

  for (int i=0;i<data_input;i++) input[i+(input_address*CACHELINE_ELEMS)]=(double)i;
#if defined(DUMMY_COMPUTE_VADD1)
  for (int i=0;i<data_input;i++) sw_output[i+(output_address*CACHELINE_ELEMS)]=(double)i+1;
#else
  for (int i=0;i<data_input;i++) sw_output[i+(output_address*CACHELINE_ELEMS)]=(double)i;
#endif
  printf("HLS start.\n"); fflush(NULL);

  hls_sdaccel_kernel_iostreams_hls(
   (const ap_uint<512>*)input,
   (ap_uint<512>*)output,
   input_address, output_address, data_len);

  printf("HLS end.\n"); fflush(NULL);

  // results check
  unsigned int correct=0;
  for (int i = 0;i < data_input; i++){
    if(fabs(output[i] - sw_output[i]) <= fabs(sw_output[i] * 1e-6)) {
      correct++;
      BDA_DEBUG(2,printf("res %5d: sw %13le , hw %13le : PASS\n",i,sw_output[i],output[i]);)
    } else {
      printf("res %5d: sw %13le , hw %13le : *FAIL*\n",i,sw_output[i],output[i]);
    }
  }
  printf("Computed '%d/%d' correct values!\n", correct, data_input);

  if(correct == data_input){
    printf("Test passed!\n");
    return EXIT_SUCCESS;
  } else {
    printf("Test failed\n");
    return EXIT_FAILURE;
  }
}

