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

#ifndef __FPGA_FUNCTIONS_BICGSTAB_HPP__
#define __FPGA_FUNCTIONS_BICGSTAB_HPP__

#include <CL/opencl.h>

#include "dev_config.hpp"
#include "bicgstab_solver_config.hpp"

// --- host data setup

int fpga_setup_host_debugbuf(unsigned int debug_outbuf_words,
 unsigned long int **debugBuffer, unsigned int *debugbufferSize);

int fpga_setup_host_datamem(bool level_scheduling, unsigned int config_bits, 
 int *processedSizes,
 long unsigned int **setupArray,
 double ***nnzValArrays, int *nnzValArrays_sizes, short unsigned int **columnIndexArray, unsigned char **newRowOffsetArray,
 unsigned int **PIndexArray, unsigned int **colorSizesArray,
 double ***L_nnzValArrays, int *L_nnzValArrays_sizes, short unsigned int **L_columnIndexArray, unsigned char **L_newRowOffsetArray,
 unsigned int **L_PIndexArray, unsigned int **L_colorSizesArray,
 double ***U_nnzValArrays, int *U_nnzValArrays_sizes, short unsigned int **U_columnIndexArray, unsigned char **U_newRowOffsetArray,
 unsigned int **U_PIndexArray, unsigned int **U_colorSizesArray,
 double **BLKDArray, double **X1Array, double **R1Array, double **X2Array, double **R2Array,
 double **LresArray, double **UresArray,
 unsigned int **totalSize, unsigned char **dataBuffer,
 unsigned int result_offsets[6], int nnzValArrays_num,
 bool reset_data_buffers,
 unsigned int dbgbuffer_bytes);

int fpga_copy_host_datamem(void **vectorPointers, int *vectorSizes, long unsigned int *setupArray,
 double **nnzValArrays, int *nnzValArrays_sizes, short unsigned int *columnIndexArray, unsigned char *newRowOffsetArray,
 unsigned int *PIndexArray, unsigned int *colorSizesArray,
 double **L_nnzValArrays, int *L_nnzValArrays_sizes, short unsigned int *L_columnIndexArray, unsigned char *L_newRowOffsetArray,
 unsigned int *L_PIndexArray, unsigned int *L_colorSizesArray,
 double **U_nnzValArrays, int *U_nnzValArrays_sizes, short unsigned int *U_columnIndexArray, unsigned char *U_newRowOffsetArray,
 unsigned int *U_PIndexArray, unsigned int *U_colorSizesArray,
 double *BLKDArray, double *X1Array, double *R1Array, double *X2Array, double *R2Array,
 bool use_LU_res, double *LresArray, double *UresArray,
 unsigned int *totalSize, unsigned char **dataBuffer,
 int nnzValArrays_num,
 bool reset_data_buffers, bool fill_results_buffers,
 int dump_data_buffers, unsigned int sequence);

// --- device data setup

int fpga_setup_device_debugbuf(cl_context context,
 unsigned long int *debugBuffer, cl_mem *cldebug, unsigned int debugbufferSize);

int fpga_setup_device_datamem(cl_context context,
 unsigned int *databufferSize, unsigned char *dataBuffer[RW_BUF],
 cl_mem *cldata);

// --- data movement to/from device

int fpga_copy_to_device_debugbuf(cl_command_queue commands,
 cl_mem cldebug, unsigned long int *debugBuffer, unsigned int debugbufferSize,
 unsigned int debug_outbuf_words);

int fpga_copy_to_device_datamem(cl_command_queue commands,
 int dataBufNum, cl_mem *cldata);

int DEBUG_fpga_copy_to_device_datamem(cl_command_queue commands,
 int dataBufNum, cl_mem *cldata, unsigned int *dataBufferSize, unsigned char **dataBuffer);

int fpga_copy_from_device_debugbuf(bool quiet,
 cl_command_queue commands,
 unsigned int debug_outbuf_words, unsigned int debugBufferSize,
 cl_mem cldebug, unsigned long int *debugBuffer, 
 unsigned int abort_cycles,
 unsigned int *kernel_cycles, unsigned int *kernel_iter_run,
 double *norms, unsigned char *last_norm_idx,
 bool *kernel_aborted, bool *kernel_signature, bool *kernel_overflow,
 bool *kernel_noresults, bool *kernel_wrafterend, bool *kernel_dbgfifofull);

int DEBUG_fpga_copy_from_device_results(bool evenBuffers,
 bool use_residuals, bool use_LU_res,
 cl_command_queue commands,
 int resultsNum, int resultsBufferNum, unsigned int *resultsBufferSize,
 unsigned int debugbufferSize,
 cl_mem *cldata, double **resultsBuffer,
 unsigned int result_offsets[6],
 bool dumpBufferFiles, char *data_dir, char *basename, unsigned int sequence);

// --- mapping/unmapping

int fpga_map_results(bool evenBuffers,
 bool use_residuals, bool use_LU_res, cl_command_queue commands,
 int resultsNum, int resultsBufferNum, unsigned int *resultsBufferSize,
 unsigned int debugbufferSize,
 cl_mem *cldata, double **resultsBuffer,
 unsigned int result_offsets[6],
 bool dumpBufferFiles, char *data_dir, char *basename, unsigned int sequence);

int fpga_unmap_results(bool evenBuffers,
 bool use_residuals, bool use_LU_res,
 cl_command_queue commands, cl_mem *cldata, double **resultsBuffer);

// --- kernel setup/run

int fpga_set_kernel_parameters(cl_kernel kernel,
 unsigned int abort_cycles, unsigned int debug_lines, unsigned int kernel_iter,
 unsigned int debug_sample_rate, double kernel_precision,
 cl_mem *cldata, cl_mem cldebug);

int fpga_kernel_run(cl_command_queue commands, cl_kernel kernel, double *time_elapsed_ms);

int fpga_kernel_query(cl_context context, cl_command_queue commands, cl_kernel kernel, cl_mem cldebug,
 unsigned long int *debugBuffer, unsigned int debug_outbuf_words,
 unsigned short rst_assert_cycles, unsigned short rst_settle_cycles,
 unsigned int *hw_x_vector_elem, unsigned int *hw_max_row_size,
 unsigned int *hw_max_column_size, unsigned int *hw_max_colors_size,
 unsigned short *hw_max_nnzs_per_row, unsigned int *hw_max_matrix_size,
 bool *hw_use_uram, bool *hw_write_ilu0_results,
 unsigned short *hw_dma_data_width, unsigned char *hw_mult_num,
 unsigned char *hw_x_vector_latency, unsigned char *hw_add_latency, unsigned char *hw_mult_latency, 
 unsigned char *hw_num_read_ports, unsigned char *hw_num_write_ports,
 unsigned short *hw_reset_cycles, unsigned short *hw_reset_settle);

#endif //__FPGA_FUNCTIONS_BICGSTAB_HPP__

