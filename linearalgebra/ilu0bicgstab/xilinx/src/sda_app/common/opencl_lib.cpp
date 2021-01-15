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
  Library of functions to setup the OpenCL environment
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// this define avoids the warning about deprecated function "clCreateCommandQueue",
// which in 2018.x has no alternatives in Xilinx OpenCL 1.2 impementation
#define CL_USE_DEPRECATED_OPENCL_1_2_APIS
#include <CL/opencl.h>
#include "bda_utils.hpp"

// load a bitstream into memory
static size_t load_file_to_memory(const char *filename, unsigned char **result, int *err) {
  size_t fsize,bsize = 0;
  *err = 0;
  FILE *f = fopen(filename, "rb");
  if (f == NULL) {
    *result = NULL;
    *err = -1; // -1 means file opening fail
    return 0;
  }
  fseek(f, 0, SEEK_END);
  fsize = ftell(f);
  fseek(f, 0, SEEK_SET);
  BDA_DEBUG(1,printf("INFO: %s: bitstream file size = %d bytes\n",__func__,(unsigned int)fsize);)
  bsize = fsize + 1;
  *result = (unsigned char *)malloc(bsize);
  memset(*result,0,bsize);
  if (fsize != fread(*result, sizeof(char), fsize, f)) {
    free(*result);
    *err = -2; // -2 means file reading fail
    return 0;
  }
  fclose(f);
  return fsize;
}

// setup OpenCL platform for one kernel instance
int setup_opencl(const char *target_device_name,
 cl_device_id *device_id, cl_context *context,
 cl_command_queue *commands, cl_program *program, cl_kernel *kernel,
 char *kernel_name, char *xclbin, bool *platform_awsf1) {
  int err;
  int status;
  char platform_vendor[1024];
  bool platform_found = false;
  bool autoselect = false;
  bool device_found = false;
  unsigned char *kernelbinary;
  size_t bitsize;
  char device_name_cl[1024];
  char device_name[1024];
  cl_platform_id platforms[16]; // platform ids list
  cl_platform_id platform_id=0; // platform id
  cl_uint platform_count;
  cl_device_id devices[16];  // compute device id
  cl_uint device_count;

  *platform_awsf1 = false;

  // Get all platforms and then select Xilinx platform
  err = clGetPlatformIDs(16, platforms, &platform_count);
  if (err != CL_SUCCESS) {
    printf("ERROR: %s: failed to find an OpenCL platform (%d)\n",__func__,err);
    return 1;
  }
  BDA_DEBUG(1,printf("INFO: %s: found %d platforms.\n",__func__, platform_count);)

  // Find Xilinx Plaftorm
  for (unsigned int iplat=0; iplat<platform_count; iplat++) {
    err = clGetPlatformInfo(platforms[iplat], CL_PLATFORM_VENDOR, 1000, (void *)platform_vendor,NULL);
    if (err != CL_SUCCESS) {
      printf("ERROR: %s: clGetPlatformInfo(CL_PLATFORM_VENDOR) failed (%d)\n",__func__,err);
      return 1;
    }
    if (strcmp(platform_vendor, "Xilinx") == 0) {
      BDA_DEBUG(1,printf("INFO: %s: selected platform %d from %s\n",__func__, iplat, platform_vendor);)
      platform_id = platforms[iplat];
      platform_found = true;
    }
  }
  if (!platform_found) {
    printf("ERROR: %s: platform Xilinx not found.\n",__func__);
    return 1;
  }

  // List all devices of type accelerator
  err = clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_ACCELERATOR,
    16, devices, &device_count);
  if (err != CL_SUCCESS) {
    printf("ERROR: %s: failed to create a device list (%d)\n",__func__,err);
    return 1;
  }

  // Load bitstream from disk
  BDA_DEBUG(1,printf("INFO: %s: loading %s\n",__func__, xclbin);)
  bitsize = load_file_to_memory(xclbin, (unsigned char **)&kernelbinary, &err);
  if (err < 0) {
    printf("ERROR: %s: failed to load kernel from xclbin (%d): %s\n",__func__, err, xclbin);
    return 1;
  }

  // iterate all devices to select the target device - here we have 2 cases:
  // - if target_device_name is given: scan all devices and select the *first*
  //   one that matches it;
  // - if target_device_name is NULL: scan all devices, try to load the bitstream
  //   on each device and stop when this first succeedes

  autoselect = (target_device_name == NULL);

  for (int i=0; i<(int)device_count; i++) {
    err = clGetDeviceInfo(devices[i], CL_DEVICE_NAME, 1024, device_name_cl, 0);
    if (err != CL_SUCCESS) {
      printf("ERROR: %s: failed to get device name for device %d (%d)\n",__func__, i,err);
      return 1;
    }
    BDA_DEBUG(1,printf("INFO: %s: found device %s\n",__func__, device_name_cl);)

    if (autoselect) {
      strcpy(device_name, device_name_cl);
      *device_id = devices[i];
    } else {
      if (strcmp(device_name_cl, target_device_name) == 0) {
        // found target device, save device id
        *device_id = devices[i];
        device_found = true;
        strcpy(device_name, device_name_cl);
        BDA_DEBUG(1,printf("INFO: %s: selected %s as the target device.\n",__func__, device_name);)
      } else {
        // not found, skip the rest
        continue;
      }
    }

    // currently expected platforms have this name structure:
    // - for Alveo: xilinx_u2xx_xdma_xxxxxx_x
    // - for AWS:   xilinx_aws-vu9p-f1_shell-vxxxxxxxx_xxxxxx_x
    // determine if it's AWS
    if (strstr(device_name, "aws-vu9p-f1-") != NULL) *platform_awsf1 = true;

    // Create a compute context
    *context = clCreateContext(0, 1, device_id, NULL, NULL, &err);
    if (!*context) {
      printf("ERROR: %s: failed to create a compute context (%d)\n",__func__,err);
      return 1;
    }

    // Create the compute program from offline
    BDA_DEBUG(2,printf("INFO: %s: before clCreateProgramWithBinary\n",__func__);)
    *program = clCreateProgramWithBinary(*context, 1, device_id, &bitsize,
     (const unsigned char **)&kernelbinary, &status, &err);
    BDA_DEBUG(2,printf("INFO: %s: after clCreateProgramWithBinary\n",__func__);)
    if ( (!*program) || (err!=CL_SUCCESS) ) {
      // if not autoselect, cleanup and keep going
      BDA_DEBUG(1,printf("WARNING: %s: device %s could not load the bitstream (%d)\n",__func__, device_name, err);)
      clReleaseContext(*context);
      if (!autoselect) {
        free(kernelbinary);
        return 1;
      }
    } else {
      if (autoselect) {
        BDA_DEBUG(1,printf("INFO: %s: selected %s as the target device.\n",__func__, device_name);)
        device_found = true;
      }
    }

    // if device_found, we're done here
    if (device_found) break;
  }

  free(kernelbinary);

  if (!device_found) {
    if (autoselect) {
      printf("ERROR: %s: could not find any suitable/free device.\n",__func__);
      return 1;
    } else {
      printf("ERROR: %s: target device %s not found.\n",__func__, target_device_name);
      return 1;
    }
  }  // loop on device_count

  // Create a command queue
  *commands = clCreateCommandQueue(*context, *device_id, 0, &err); // DEPRECATED
  if (!*commands) {
    printf("ERROR: %s: failed to create a command queue (%d)\n",__func__,err);
    return 1;
  }

  // Build the program executable
  err = clBuildProgram(*program, 0, NULL, NULL, NULL, NULL);
  if (err != CL_SUCCESS) {
    size_t len;
    char buffer[2048];
    printf("ERROR: %s: failed to build program executable (%d)\n",__func__,err);
    clGetProgramBuildInfo(*program, *device_id, CL_PROGRAM_BUILD_LOG, sizeof(buffer), buffer, &len);
    printf(" %s: %s\n",__func__, buffer);
    return 1;
  }

  // Create the compute kernel in the program we wish to run
  *kernel = clCreateKernel(*program, kernel_name, &err);
  if (!*kernel || err != CL_SUCCESS) {
    printf("ERROR: %s: failed to create compute kernel %s\n",__func__,kernel_name);
    return 1;
  }

  return 0;
}

// This function will swap two kernels, one of which is the main
// one and another one is a "dummy" kernel.
// The puspose is to force FPGA reconfiguration in case of a
// catastrophic error which requires a fresh reconfiguration.
// Operations performed are:
//  1) load dummy kernel and program it
//  2) load main kernel and program it
int swap_kernel(
 cl_device_id device_id,
 cl_context context,
 cl_program *program, cl_kernel *kernel,
 char *dummy_kernel_name, char *dummy_xclbin,
 char *main_kernel_name, char *main_xclbin) {

  int err,status;
  unsigned char *kernelbinary;
  size_t bitsize;
  cl_program dummy_program;
  cl_kernel dummy_kernel;

  BDA_DEBUG(1,printf("INFO: %s: kernel swap requested, dummy (%s), main (%s).\n",
   __func__, dummy_kernel_name, main_kernel_name);)

  // release previous main kernel objects
  if (*kernel) clReleaseKernel(*kernel);
  if (*program) clReleaseProgram(*program);

  // dummy kernel: create Program Objects

  // Load binary from disk
  BDA_DEBUG(1,printf("INFO: %s: dummy: loading %s\n",__func__, dummy_xclbin);)
  bitsize = load_file_to_memory(dummy_xclbin, (unsigned char **) &kernelbinary, &err);
  if (bitsize < 0) {
    printf("ERROR: %s: failed to load dummy kernel from xclbin (%d): %s\n",__func__, err, dummy_xclbin);
    return 1;
  }
  // Create the compute program from offline
  dummy_program = clCreateProgramWithBinary(context, 1, &device_id, &bitsize,
    (const unsigned char **) &kernelbinary, &status, &err);
  free(kernelbinary);
  if ((!dummy_program) || (err!=CL_SUCCESS)) {
    printf("ERROR: %s: dummy: failed to create compute program from binary (%d,%d)\n",__func__, err, status);
    return 2;
  }
  // Build the program executable
  err = clBuildProgram(dummy_program, 0, NULL, NULL, NULL, NULL);
  if (err != CL_SUCCESS) {
    size_t len;
    char buffer[2048];
    printf("ERROR: %s: dummy: failed to build program executable (%d)\n",__func__,err);
    clGetProgramBuildInfo(*program, device_id, CL_PROGRAM_BUILD_LOG, sizeof(buffer), buffer, &len);
    printf("%s: %s\n",__func__, buffer);
    return 3;
  }
  // Create the compute kernel in the program we wish to run
  dummy_kernel = clCreateKernel(dummy_program, dummy_kernel_name, &err);
  if (!dummy_kernel || err != CL_SUCCESS) {
    printf("ERROR: %s: dummy: failed to create compute kernel %s\n",__func__,dummy_kernel_name);
    return 4;
  }
  // release dummy kernel

  clReleaseKernel(dummy_kernel);
  clReleaseProgram(dummy_program);

  // main kernel: create Program Objects

  // Load binary from disk
  BDA_DEBUG(1,printf("INFO: %s: main: loading %s\n",__func__, main_xclbin);)
  bitsize = load_file_to_memory(main_xclbin, (unsigned char **) &kernelbinary, &err);
  if (err < 0) {
    printf("ERROR: %s: main: failed to load kernel from xclbin (%d): %s\n",__func__, err, main_xclbin);
    return 5;
  }
  // Create the compute program from offline
  *program = clCreateProgramWithBinary(context, 1, &device_id, &bitsize,
    (const unsigned char **) &kernelbinary, &status, &err);
  free(kernelbinary);
  if ((!*program) || (err!=CL_SUCCESS)) {
    printf("ERROR: %s: main: failed to create compute program from binary (%d)\n",__func__, err);
    return 6;
  }
  // Build the program executable
  err = clBuildProgram(*program, 0, NULL, NULL, NULL, NULL);
  if (err != CL_SUCCESS) {
    size_t len;
    char buffer[2048];
    printf("ERROR: %s: main: failed to build program executable (%d)\n",__func__,err);
    clGetProgramBuildInfo(*program, device_id, CL_PROGRAM_BUILD_LOG, sizeof(buffer), buffer, &len);
    printf("%s: %s\n",__func__, buffer);
    return 7;
  }
  // Create the compute kernel in the program we wish to run
  *kernel = clCreateKernel(*program, main_kernel_name, &err);
  if (!*kernel || err != CL_SUCCESS) {
    printf("ERROR: %s: main: failed to create compute kernel %s\n",__func__,main_kernel_name);
    return 8;
  }

  BDA_DEBUG(1,printf("INFO: %s: kernel swap completed.\n",__func__);)

  return 0;
}

