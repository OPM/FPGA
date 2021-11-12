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

#ifndef __OPENCL_LIB_HPP__
#define __OPENCL_LIB_HPP__

#include <CL/opencl.h>

int setup_opencl(const char *target_device_name,
 cl_device_id *device_id, cl_context *context,
 cl_command_queue *commands, cl_program *program, cl_kernel *kernel,
 const char *kernel_name, const char *xclbin, bool *platform_awsf1);
int swap_kernel(cl_device_id device_id, cl_context context, cl_program *program,
 cl_kernel *kernel, char *dummy_kernel_name, char *dummy_xclbin,
 char *main_kernel_name, char *main_xclbin);

#endif //__OPENCL_LIB_HPP__

