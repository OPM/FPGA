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
  Library of functions to interact with the HW kernel

  The following mapping options must be used when generating the kernel bitstream.
  * for Alveo U280 boards and 2r_3r3w ports (all HBM), set kernel linker (misc.) options for mapping to:
    --sp=${KERNEL}_1.m00_axi:HBM[2]  --sp=${KERNEL}_1.m01_axi:HBM[4]
    --sp=${KERNEL}_1.m02_axi:HBM[6]  --sp=${KERNEL}_1.m03_axi:HBM[8]
    --sp=${KERNEL}_1.m04_axi:HBM[10] --sp=${KERNEL}_1.m05_axi:HBM[6]
    --sp=${KERNEL}_1.m06_axi:HBM[8]  --sp=${KERNEL}_1.m07_axi:HBM[10]
    --sp=${KERNEL}_1.m08_axi:PLRAM[0]
  * for Alveo U280 boards and 2r_3r3w ports (mix DDR/HBM), set kernel linker (misc.) options for mapping to:
    --sp=${KERNEL}_1.m00_axi:DDR[0] --sp=${KERNEL}_1.m01_axi:DDR[1]
    --sp=${KERNEL}_1.m02_axi:HBM[2] --sp=${KERNEL}_1.m03_axi:HBM[4]
    --sp=${KERNEL}_1.m04_axi:HBM[6] --sp=${KERNEL}_1.m05_axi:HBM[2]
    --sp=${KERNEL}_1.m06_axi:HBM[4] --sp=${KERNEL}_1.m07_axi:HBM[6]
    --sp=${KERNEL}_1.m08_axi:PLRAM[0]
*/

// this define avoids the warning about deprecated OpenCL functions
#define CL_USE_DEPRECATED_OPENCL_1_2_APIS

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CL/opencl.h>
#include <time.h>
#include <assert.h>

#include "fpga_functions_bicgstab.hpp"
#include "bda_utils.hpp"
#include "bicgstab_utils.hpp"

// =============================================================================
// host data setup
// =============================================================================

// -----------------------
// setup host debug buffer
// -----------------------

int fpga_setup_host_debugbuf(unsigned int debug_outbuf_words,
 unsigned long int **debugBuffer, unsigned int *debugbufferSize) {
  int err;

  // size in bytes of the debug buffer
  *debugbufferSize = CACHELINE_BYTES * debug_outbuf_words;

  // allocate debug output buffers on host
  BDA_DEBUG(1,printf("INFO: %s: allocating debug output buffer: %d bytes, %d cachelines\n",
   __func__,*debugbufferSize,*debugbufferSize/CACHELINE_BYTES);)
  // SDx needs aligned memory when using CL_MEM_USE_HOST_PTR
  err=posix_memalign((void **)debugBuffer, SDX_MEM_ALIGNMENT, *debugbufferSize);
  if (err) {
    printf("ERROR: %s: posix_memalign failed to allocate debugBuffer\n",__func__);
    return 1;
  }

  return 0;
}

// -----------------------
// setup host data buffers
// -----------------------

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
 unsigned int dbgbuffer_bytes) {
  int rowSize, columnSize, valSize, numColors, newrowSize, blkdiagSize;
  int L_rowSize, L_columnSize, L_valSize, L_numColors, L_newrowSize, L_blkdiagSize;
  int U_rowSize, U_columnSize, U_valSize, U_numColors, U_newrowSize, U_blkdiagSize;
  int *len_nzval = NULL, *len_L_nzval = NULL, *len_U_nzval = NULL;

  // always 1 for this version of the solver
  assert(nnzValArrays_num==1);

  // assign vector sizes:
  // these sizes must be, for the vectors that may change between executions,
  // the gretest that can be reached - this way, the data buffers will be
  // allocated only once, and actual sizes will be used when the matrix is updated
  rowSize = processedSizes[0];
  columnSize = processedSizes[3];
  valSize = processedSizes[1];
  numColors = processedSizes[2];
  newrowSize = processedSizes[4];
  blkdiagSize = processedSizes[5];
  L_rowSize = processedSizes[6];
  L_columnSize = processedSizes[9];
  L_valSize = processedSizes[7];
  L_numColors = processedSizes[8];
  L_newrowSize = processedSizes[10];
  L_blkdiagSize = processedSizes[11];
  U_rowSize = processedSizes[12];
  U_columnSize = processedSizes[15];
  U_valSize = processedSizes[13];
  U_numColors = processedSizes[14];
  U_newrowSize = processedSizes[16];
  U_blkdiagSize = processedSizes[17];

  // allocate the vector holding the rounded nnz arrays sizes
  len_nzval = (int*)malloc(sizeof(int) * nnzValArrays_num);
  memset(len_nzval,0,sizeof(int) * nnzValArrays_num);
  len_L_nzval = (int*)malloc(sizeof(int) * nnzValArrays_num);
  memset(len_L_nzval,0,sizeof(int) * nnzValArrays_num);
  len_U_nzval = (int*)malloc(sizeof(int) * nnzValArrays_num);
  memset(len_U_nzval,0,sizeof(int) * nnzValArrays_num);

  /// allocate array of pointers for nnz vectors
  *nnzValArrays = (double**)malloc(sizeof(double*) * nnzValArrays_num);
  memset(*nnzValArrays,0,sizeof(double*) * nnzValArrays_num);
  *L_nnzValArrays = (double**)malloc(sizeof(double*) * nnzValArrays_num);
  memset(*L_nnzValArrays,0,sizeof(double*) * nnzValArrays_num);
  *U_nnzValArrays = (double**)malloc(sizeof(double*) * nnzValArrays_num);
  memset(*U_nnzValArrays,0,sizeof(double*) * nnzValArrays_num);

  BDA_DEBUG(1,
    printf("INFO: %s: sizes  : rowSize=%6d, columnSize=%6d, valSize=%7d, numColors=%3d, newrowSize=%7d, blkdiagSize=%6d\n",
     __func__,rowSize,columnSize,valSize,numColors,newrowSize,blkdiagSize);
    printf("INFO: %s: L sizes: rowSize=%6d, columnSize=%6d, valSize=%7d, numColors=%3d, newrowSize=%7d, blkdiagSize=%6d\n",
     __func__,L_rowSize,L_columnSize,L_valSize,L_numColors,L_newrowSize,L_blkdiagSize);
    printf("INFO: %s: U sizes: rowSize=%6d, columnSize=%6d, valSize=%7d, numColors=%3d, newrowSize=%7d, blkdiagSize=%6d\n",
     __func__,U_rowSize,U_columnSize,U_valSize,U_numColors,U_newrowSize,U_blkdiagSize);
    printf("INFO: %s: ",__func__);
    for (int i=0;i<nnzValArrays_num;i++) {
      printf("nnz_vals[%d]=%d",i,nnzValArrays_sizes[i]);
      if (i+1<nnzValArrays_num) printf(", "); else printf("\n");
    }
    printf("INFO: %s: ",__func__);
    for (int i=0;i<nnzValArrays_num;i++) {
      printf("L_nnz_vals[%d]=%d",i,L_nnzValArrays_sizes[i]);
      if (i+1<nnzValArrays_num) printf(", "); else printf("\n");
    }
    printf("INFO: %s: ",__func__);
    for (int i=0;i<nnzValArrays_num;i++) {
      printf("U_nnz_vals[%d]=%d",i,U_nnzValArrays_sizes[i]);
      if (i+1<nnzValArrays_num) printf(", "); else printf("\n");
    }
  )

  // Calculate the complete size (in bytes) of each array
  int len_setup           = CACHELINE_BYTES*SETUP_LINES;  // setup cachelines
  int len_r1_vector       = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double)); // <-- output: residuals
  int len_r2_vector       = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double)); // <-- output: residuals
  int len_x1_vector       = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double)); // <-- output: results
  int len_x2_vector       = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double)); // <-- output: results
  int len_p1_vector       = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double));
  int len_p2_vector       = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double));
  int len_rt_vector       = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double));
  int len_t_vector        = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double));
  int len_v_vector        = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double));
  int len_L_res_vector    = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double));
  int len_U_res_vector    = sizeof(double) *    roundUpTo(rowSize, CACHELINE_BYTES/sizeof(double));
  int len_blkd_vector     = sizeof(double) *    roundUpTo(blkdiagSize, CACHELINE_BYTES/sizeof(double));
  int len_color_sizes     = sizeof(int) *       roundUpTo(4 * numColors, CACHELINE_BYTES/sizeof(int));
  int len_p_index         = sizeof(int) *       roundUpTo(columnSize, CACHELINE_BYTES/sizeof(int));
  for (int i=0;i<nnzValArrays_num;i++) {
    len_nzval[i]          = sizeof(double) *    roundUpTo(nnzValArrays_sizes[i], CACHELINE_BYTES/sizeof(double));
  }
  int len_col_index       = sizeof(short int) * roundUpTo(valSize, CACHELINE_BYTES/sizeof(short int));
  int len_newrow_offset   = sizeof(char) *      roundUpTo(newrowSize, CACHELINE_BYTES/sizeof(char));
  int len_L_color_sizes   = sizeof(int) *       roundUpTo(4 * L_numColors, CACHELINE_BYTES/sizeof(int));
  int len_L_p_index       = sizeof(int) *       roundUpTo(L_columnSize, CACHELINE_BYTES/sizeof(int));
  for (int i=0;i<nnzValArrays_num;i++) {
    len_L_nzval[i]        = sizeof(double) *    roundUpTo(L_nnzValArrays_sizes[i], CACHELINE_BYTES/sizeof(double));
  }
  int len_L_col_index     = sizeof(short int) * roundUpTo(L_valSize, CACHELINE_BYTES/sizeof(short int));
  int len_L_newrow_offset = sizeof(char) *      roundUpTo(L_newrowSize, CACHELINE_BYTES/sizeof(char));
  int len_U_color_sizes   = sizeof(int) *       roundUpTo(4 * U_numColors, CACHELINE_BYTES/sizeof(int));
  int len_U_p_index       = sizeof(int) *       roundUpTo(U_columnSize, CACHELINE_BYTES/sizeof(int));
  for (int i=0;i<nnzValArrays_num;i++) {
    len_U_nzval[i]        = sizeof(double) *    roundUpTo(U_nnzValArrays_sizes[i], CACHELINE_BYTES/sizeof(double));
  }
  int len_U_col_index     = sizeof(short int) * roundUpTo(U_valSize, CACHELINE_BYTES/sizeof(short int));
  int len_U_newrow_offset = sizeof(char) *      roundUpTo(U_newrowSize, CACHELINE_BYTES/sizeof(char));
  int len_dbg_buffer      = dbgbuffer_bytes;
  if (len_dbg_buffer % CACHELINE_BYTES != 0) {
    printf("ERROR: %s: dbgbuffer_bytes (%d) must be aligned to the cacheline size (%d bytes).\n",
     __func__,len_dbg_buffer,CACHELINE_BYTES);
    free(len_nzval);
    free(len_L_nzval);
    free(len_U_nzval);
    free(*nnzValArrays);
    free(*L_nnzValArrays);
    free(*U_nnzValArrays);
    return 1;
  }

  // allocate the totalSize array
  *totalSize = (unsigned int*)malloc(sizeof(int) * RW_BUF);
  memset(*totalSize,0,sizeof(int) * RW_BUF);

  // fill the vectors with the position of the arrays in the data buffers
  // and fill the totalSize array
  // WARNING: this depends on the number of ports available in the kernel!
  // * the position values are expressed in bytes *
  #define MAX_DBUFPOS 20
  unsigned int dbufpos[RW_BUF][MAX_DBUFPOS] = {0}; // [bank number][array number]
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  #if RW_BUF != 5
    #error "Expected RW_BUF=5 for configuration PORTS_2r_3r3w*"
  #endif
  // data buffer 0
  dbufpos[0][0] = 0;                                  // setup lines
  dbufpos[0][1] = dbufpos[0][0] + len_setup;          // nnz_vals1_addr
  dbufpos[0][2] = dbufpos[0][1] + len_nzval[0];       // L_nnz_vals1_addr
  dbufpos[0][3] = dbufpos[0][2] + len_L_nzval[0];     // U_nnz_vals1_addr
  dbufpos[0][4] = dbufpos[0][3] + len_U_nzval[0];     // color_sizes_addr
  dbufpos[0][5] = dbufpos[0][4] + len_color_sizes;    // L_color_sizes_addr
  dbufpos[0][6] = dbufpos[0][5] + len_L_color_sizes;  // U_color_sizes_addr
  dbufpos[0][7] = dbufpos[0][6] + len_U_color_sizes;  // block_diag_addr
  dbufpos[0][8] = dbufpos[0][7] + len_blkd_vector;    // --> total size
  (*totalSize)[0] = dbufpos[0][8];
  // data buffer 1
  dbufpos[1][0] = 0;                                   // P_indices_addr
  dbufpos[1][1] = dbufpos[1][0] + len_p_index;         // L_P_indices_addr
  dbufpos[1][2] = dbufpos[1][1] + len_L_p_index;       // U_P_indices_addr
  dbufpos[1][3] = dbufpos[1][2] + len_U_p_index;       // col_inds_addr
  dbufpos[1][4] = dbufpos[1][3] + len_col_index;       // L_col_inds_addr
  dbufpos[1][5] = dbufpos[1][4] + len_L_col_index;     // U_col_inds_addr
  dbufpos[1][6] = dbufpos[1][5] + len_U_col_index;     // NRs_addr
  dbufpos[1][7] = dbufpos[1][6] + len_newrow_offset;   // L_NRs_addr
  dbufpos[1][8] = dbufpos[1][7] + len_L_newrow_offset; // U_NRs_addr
  dbufpos[1][9] = dbufpos[1][8] + len_U_newrow_offset; // --> total size
  (*totalSize)[1] = dbufpos[1][9];
  // data buffer 2
  dbufpos[2][0] = 0;                                  // vector X2
  dbufpos[2][1] = dbufpos[2][0] + len_x2_vector;      // vector R1
  dbufpos[2][2] = dbufpos[2][1] + len_r1_vector;      // --> total size
  (*totalSize)[2] = dbufpos[2][2];
  #define BANK_XRES_EVEN 2
  #define BANK_RRES_ODD 2
  result_offsets[0] = dbufpos[2][0]; // X even results
  result_offsets[3] = dbufpos[2][1]; // R odd results
  // data buffer 3
  dbufpos[3][0] = 0;                                  // vector X1
  dbufpos[3][1] = dbufpos[3][0] + len_x1_vector;      // vector R2
  dbufpos[3][2] = dbufpos[3][1] + len_r2_vector;      // vector P1
  dbufpos[3][3] = dbufpos[3][2] + len_p1_vector;      // vector P2
  dbufpos[3][4] = dbufpos[3][3] + len_p2_vector;      // vector RT
  dbufpos[3][5] = dbufpos[3][4] + len_rt_vector;       // --> total size
  (*totalSize)[3] = dbufpos[3][5];
  #define BANK_XRES_ODD 3
  #define BANK_RRES_EVEN 3
  result_offsets[2] = dbufpos[3][0]; // X odd results
  result_offsets[1] = dbufpos[3][1]; // R even results
  // data buffer 4
  dbufpos[4][0] = 0;                                  // T vector
  dbufpos[4][1] = dbufpos[4][0] + len_t_vector;       // V vector
  dbufpos[4][2] = dbufpos[4][1] + len_v_vector;       // L_res vector - address isn't in setup line: ALWAYS after v vector
  dbufpos[4][3] = dbufpos[4][2] + len_L_res_vector;   // U_res vector - address isn't in setup line: ALWAYS after L_res vector
  dbufpos[4][4] = dbufpos[4][3] + len_U_res_vector;   // --> total size
  (*totalSize)[4] = dbufpos[4][4];
  #define BANK_LRES 4
  #define BANK_URES 4
  result_offsets[4] = dbufpos[4][2]; // L results
  result_offsets[5] = dbufpos[4][3]; // U results
#else
  #error "Undefined"
#endif
  free(len_nzval);
  free(len_L_nzval);
  free(len_U_nzval);

  BDA_DEBUG(2,
    for (int b=0;b<RW_BUF;b++) {
      printf("INFO: %s: data buffer #%d, total size (bytes/cachelines): %d/%d\n",
       __func__,b,(*totalSize)[b],(*totalSize)[b]/CACHELINE_BYTES);
      for (int d=0;d<MAX_DBUFPOS;d++) {
        int pos = dbufpos[b][d];
        if (d>1 && pos==0) break;
        printf("INFO: %s: dataBuffer[%d] index: %d (cl: %d)\n",__func__,b,pos,pos/CACHELINE_BYTES);
      }
    }
  )

  // allocate data buffers
  for (int b=0; b<RW_BUF; b++) {
    BDA_DEBUG(1,printf("INFO: %s: allocating data buffer %d: %d bytes, %d cachelines\n",
      __func__,b, (*totalSize)[b],(*totalSize)[b]/CACHELINE_BYTES);)
    // SDx needs aligned memory when using CL_MEM_USE_HOST_PTR
    int err=posix_memalign((void **)&dataBuffer[b], SDX_MEM_ALIGNMENT, sizeof(char) * (*totalSize)[b]);
    if (err) {
      printf("ERROR: %s: posix_memalign failed to allocate dataBuffer %d.\n",__func__,b);
      free(*nnzValArrays);
      free(*L_nnzValArrays);
      free(*U_nnzValArrays);
      return 1;
    }
    // reset data buffer (if requested)
    if (reset_data_buffers) {
      BDA_DEBUG(1,printf("INFO: %s: clearing data buffer %d.\n",__func__,b);)
      memset(dataBuffer[b],0,(*totalSize)[b]);
    }
  }

  // create references to all different arrays in each dataBuffer
  // and fill the setup array with the proper indices (byte-based)
  // buffer names starting with "temp_" are currently not used (intermediary kernel data)
  // WARNING: references depend on the number of ports available in the kernel!
  BDA_DEBUG(1,printf("INFO: %s: creating data buffer references.\n",__func__);)
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  // data buffer 0
  *setupArray =   (long unsigned int *)&dataBuffer[0][ dbufpos[0][0] ];
  (*nnzValArrays)[0] =         (double *)&dataBuffer[0][ dbufpos[0][1] ];
  (*L_nnzValArrays)[0] =       (double *)&dataBuffer[0][ dbufpos[0][2] ];
  (*U_nnzValArrays)[0] =       (double *)&dataBuffer[0][ dbufpos[0][3] ];
  *colorSizesArray =   (unsigned int *)&dataBuffer[0][ dbufpos[0][4] ];
  *L_colorSizesArray = (unsigned int *)&dataBuffer[0][ dbufpos[0][5] ];
  *U_colorSizesArray = (unsigned int *)&dataBuffer[0][ dbufpos[0][6] ];
  *BLKDArray =               (double *)&dataBuffer[0][ dbufpos[0][7] ];
  // data buffer 1
  *PIndexArray =             (unsigned int *)&dataBuffer[1][ dbufpos[1][0] ];
  *L_PIndexArray =           (unsigned int *)&dataBuffer[1][ dbufpos[1][1] ];
  *U_PIndexArray =           (unsigned int *)&dataBuffer[1][ dbufpos[1][2] ];
  *columnIndexArray =   (short unsigned int*)&dataBuffer[1][ dbufpos[1][3] ];
  *L_columnIndexArray = (short unsigned int*)&dataBuffer[1][ dbufpos[1][4] ];
  *U_columnIndexArray = (short unsigned int*)&dataBuffer[1][ dbufpos[1][5] ];
  *newRowOffsetArray =      (unsigned char *)&dataBuffer[1][ dbufpos[1][6] ];
  *L_newRowOffsetArray =    (unsigned char *)&dataBuffer[1][ dbufpos[1][7] ];
  *U_newRowOffsetArray =    (unsigned char *)&dataBuffer[1][ dbufpos[1][8] ];
  // data buffer 2
  *X2Array = (double *)&dataBuffer[2][ dbufpos[2][0] ];
  *R1Array = (double *)&dataBuffer[2][ dbufpos[2][1] ];
  // data buffer 3
  *X1Array =             (double *)&dataBuffer[3][ dbufpos[3][0] ];
  *R2Array =             (double *)&dataBuffer[3][ dbufpos[3][1] ];
  //double *temp_P1Array =        (double *)&dataBuffer[3][ dbufpos[3][2] ];
  //double *temp_P2Array =        (double *)&dataBuffer[3][ dbufpos[3][3] ];
  //double *temp_RTArray =        (double *)&dataBuffer[3][ dbufpos[3][4] ];
  // data buffer 4
  //unsigned char *temp_TArray = (unsigned char *)&dataBuffer[4][ dbufpos[4][0] ];
  //unsigned char *temp_VArray = (unsigned char *)&dataBuffer[4][ dbufpos[4][1] ];
  *LresArray =                        (double *)&dataBuffer[4][ dbufpos[4][2] ];
  *UresArray =                        (double *)&dataBuffer[4][ dbufpos[4][3] ];
#else
  #error "Undefined"
#endif

  // Setup array cachelines map
  // All setup array pointers are expressed as indices of the 512-bit cachelines.
  // Cacheline 0:
  //  - [0]  val size (63..32) | row_size (31..0)
  //  - [1]  config_bits (63..32) | num_colors (31..0)
  //  - [2]  Pointer to R1 vector
  //  - [3]  Pointer to R2 vector, temp data used by solver, also: output residuals
  //  - [4]  Pointer to X1 vector
  //  - [5]  Pointer to X2 vector, temp data used by solver, also: output results
  //  - [6]  Pointer to P1 vector, temp data used by solver
  //  - [7]  Pointer to P2 vector, temp data used by solver
  // Cacheline 1:
  //  - [8]  L_val size (63..32) | L_row_size (31..0)
  //  - [9]  *unused* (63..32)   | L_num_colors (31..0)
  //  - [10] Pointer to color sizes vector
  //  - [11] Pointer to P indices vector
  //  - [12] Pointer to non-zero matrix values vector, part 1 (whole for this kernel)
  //  - [13] Pointer to column indices vector
  //  - [14] Pointer to row offsets vector
  //  - [15] Pointer to RT vector, temp data used by solver
  // Cacheline 2:
  //  - [16] U_val size (63..32) | U_row_size (31..0)
  //  - [17] *unused* (63..32)   | U_num_colors (31..0)
  //  - [18] Pointer to L color sizes vector
  //  - [19] Pointer to L P indices vector
  //  - [20] Pointer to L non-zero matrix values vector, part 1 (whole for this kernel)
  //  - [21] Pointer to L column indices vector
  //  - [22] Pointer to L row offsets vector
  //  - [23] Pointer to block diagonal vector
  // Cacheline 3:
  //  - [24] Pointer to U color sizes vector
  //  - [25] Pointer to U P indices vector
  //  - [26] Pointer to U non-zero matrix values vector, part 1 (whole for this kernel)
  //  - [27] Pointer to U column indices vector
  //  - [28] Pointer to U row offsets vector
  //  - [29] Pointer to T vector, temp data used by solver
  //  - [30] Pointer to V vector, temp data used by solver
  //  - [31] Pointer to non-zero matrix values vector, part 2 (unused for this kernel)
  // Cacheline 4:
  //  - [32] Pointer to L non-zero matrix values vector, part 2 (unused for this kernel)
  //  - [33] Pointer to U non-zero matrix values vector, part 2 (unused for this kernel)
  //  - [34] *reserved* for pointer to non-zero matrix values vector, part 3)
  //  - [35] *reserved* for pointer to L non-zero matrix values vector, part 3
  //  - [36] *reserved* for pointer to U non-zero matrix values vector, part 3
  //  - [37] *reserved* for pointer to non-zero matrix values vector, part 4
  //  - [38] *reserved* for pointer to L non-zero matrix values vector, part 4
  //  - [39] *reserved* for pointer to U non-zero matrix values vector, part 4

  // reset and fill the setup array
  BDA_DEBUG(1,printf("INFO: %s: cleanup of setup array.\n",__func__);)
  for (int i=0;i<SETUP_LINES*CACHELINE_DBL_WORDS;i++) (*setupArray)[i] = 0xDEADC0DEDEADC0DEULL; // cleanup
  BDA_DEBUG(1,printf("INFO: %s: filling setup array.\n",__func__);)
  // cacheline 0
  (*setupArray)[0] = (((long unsigned int) valSize) << 32) + (long unsigned int) rowSize;
  (*setupArray)[1] = (((long unsigned int) config_bits) << 32) + (long unsigned int) numColors;
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  (*setupArray)[2] = dbufpos[2][1]/CACHELINE_BYTES;  // vector R1 addr
  (*setupArray)[3] = dbufpos[3][1]/CACHELINE_BYTES;  // vector R2 addr [temp,uninitialized,output]
  (*setupArray)[4] = dbufpos[3][0]/CACHELINE_BYTES;  // vector X1 addr
  (*setupArray)[5] = dbufpos[2][0]/CACHELINE_BYTES;  // vector X2 addr [temp,uninitialized,output]
  (*setupArray)[6] = dbufpos[3][2]/CACHELINE_BYTES;  // vector P1 addr [temp,uninitialized]
  (*setupArray)[7] = dbufpos[3][3]/CACHELINE_BYTES;  // vector P2 addr [temp,uninitialized]
#else
  #error "Undefined"
#endif
  // cacheline 1
  (*setupArray)[8] = (((long unsigned int) L_valSize) << 32) + (long unsigned int) L_rowSize;
  (*setupArray)[9] = (long unsigned int) L_numColors;
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  (*setupArray)[10] = dbufpos[0][4]/CACHELINE_BYTES; // color_sizes_addr
  (*setupArray)[11] = dbufpos[1][0]/CACHELINE_BYTES; // P_indices_addr
  (*setupArray)[12] = dbufpos[0][1]/CACHELINE_BYTES; // nnz_vals1_addr
  (*setupArray)[13] = dbufpos[1][3]/CACHELINE_BYTES; // col_inds_addr
  (*setupArray)[14] = dbufpos[1][6]/CACHELINE_BYTES; // NRs_addr
  (*setupArray)[15] = dbufpos[3][4]/CACHELINE_BYTES; // vector RT addr [temp,uninitialized]
#else
  #error "Undefined"
#endif
  // cacheline 2
  (*setupArray)[16] = (((long unsigned int) U_valSize) << 32) + (long unsigned int) U_rowSize;
  (*setupArray)[17] = (long unsigned int) U_numColors;
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  (*setupArray)[18] = dbufpos[0][5]/CACHELINE_BYTES; // L_color_sizes_addr
  (*setupArray)[19] = dbufpos[1][1]/CACHELINE_BYTES; // L_P_indices_addr
  (*setupArray)[20] = dbufpos[0][2]/CACHELINE_BYTES; // L_nnz_vals1_addr
  (*setupArray)[21] = dbufpos[1][4]/CACHELINE_BYTES; // L_col_inds_addr
  (*setupArray)[22] = dbufpos[1][7]/CACHELINE_BYTES; // L_NRs_addr
  (*setupArray)[23] = dbufpos[0][7]/CACHELINE_BYTES; // block_diag_addr
#else
  #error "Undefined"
#endif
  // cacheline 3
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  (*setupArray)[24] = dbufpos[0][6]/CACHELINE_BYTES; // U_color_sizes_addr
  (*setupArray)[25] = dbufpos[1][2]/CACHELINE_BYTES; // U_P_indices_addr
  (*setupArray)[26] = dbufpos[0][3]/CACHELINE_BYTES; // U_nnz_vals1_addr
  (*setupArray)[27] = dbufpos[1][5]/CACHELINE_BYTES; // U_col_inds_addr
  (*setupArray)[28] = dbufpos[1][8]/CACHELINE_BYTES; // U_NRs_addr
  (*setupArray)[29] = dbufpos[4][0]/CACHELINE_BYTES; // vector T addr [temp,uninitialized]
  (*setupArray)[30] = dbufpos[4][1]/CACHELINE_BYTES; // vector V addr [temp,uninitialized]
#else
  #error "Undefined"
#endif
  // cacheline 4
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  // (unused for this kernel)
#else
  #error "Undefined"
#endif

  BDA_DEBUG(2,
    printf("INFO: %s: setup array:\n",__func__);
    for (int i=0;i<SETUP_LINES*CACHELINE_DBL_WORDS;i++) {
      if (i==0 || i==1 || i==8 || i==9 || i==16 || i==17) {
        printf(" %2d: 0x%016lX [ %10d, %10d ]\n",
       i,(*setupArray)[i],(int)((*setupArray)[i]>>32),(int)((*setupArray)[i]&0xFFFFFFFF));
      } else {
        if ((*setupArray)[i] == 0xDEADC0DEDEADC0DEULL) {
          printf(" %2d: 0x%016lX [ unused ]\n",i,(*setupArray)[i]);
        } else {
          printf(" %2d: 0x%016lX [ %10ld ]\n",i,(*setupArray)[i],(long)((*setupArray)[i]));
        }
      }
    }
  )

  return 0;
}

// ------------------------------------
// copy input data to host data buffers
// ------------------------------------

// this function is used to copy data after initialization: it will allow to
// update the system to be solved, but it won't reallocate the buffers to a
// bigger size if they are bigger that the first allocation
//FIXME: add checks that the mbuffer sizes are not bigger than the allocation!
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
 int dump_data_buffers, unsigned int sequence) {
  int rowSize, columnSize, valSize, numColors, newrowSize, blkdiagSize;
  int L_rowSize, L_columnSize, L_valSize, L_numColors, L_newrowSize, L_blkdiagSize;
  int U_rowSize, U_columnSize, U_valSize, U_numColors, U_newrowSize, U_blkdiagSize;

  // always 1 for this version of the solver
  assert(nnzValArrays_num==1);

  // assign vector sizes:
  // these sizes must be the actual ones for the system to be solved
  rowSize = vectorSizes[0];         // rowSize (not rounded)
  columnSize = vectorSizes[3];      // total number of columns in all colors (each color rounded up to nearest 16)
  valSize = vectorSizes[1];         // colSize (not rounded)
  numColors = vectorSizes[2];       // numColors (not rounded)
  newrowSize = vectorSizes[4];      // size of the New Row offsets array (each colorrounded up to nearest 64 )
  blkdiagSize = vectorSizes[5];     // diagVals Size (each color rounded to nearest NUM_FIELDS_PER_LINE)
  L_rowSize = vectorSizes[6];       // L_rowSize (not rounded)
  L_columnSize = vectorSizes[9];    // total number of columns in all colors of L matrix (each color rounded up to nearest 16)
  L_valSize = vectorSizes[7];       // L_colSize (not rounded)
  L_numColors = vectorSizes[8];     // L_numColors (not rounded)
  L_newrowSize = vectorSizes[10];   // size of the L_NR_offsets array (each colorrounded up to nearest 64 )
  L_blkdiagSize = vectorSizes[11];  // diagVals Size (duplicate) (each color rounded to nearest NUM_FIELDS_PER_LINE)
  U_rowSize = vectorSizes[12];      // U_rowSize (not rounded)
  U_columnSize = vectorSizes[15];   // total number of columns in all colors of U matrix (each color rounded up to nearest 16)
  U_valSize = vectorSizes[13];      // U_colSize (not rounded)
  U_numColors = vectorSizes[14];    // U_numColors (not rounded)
  U_newrowSize = vectorSizes[16];   // size of the U_NR_offsets array (each colorrounded up to nearest 64 )
  U_blkdiagSize = vectorSizes[17];  // diagVals Size (duplicate) (each color rounded to nearest NUM_FIELDS_PER_LINE)

  BDA_DEBUG(1,
    printf("INFO: %s: sizes  : rowSize=%6d, columnSize=%6d, valSize=%7d, numColors=%3d, newrowSize=%7d, blkdiagSize=%6d\n",
     __func__,rowSize,columnSize,valSize,numColors,newrowSize,blkdiagSize);
    printf("INFO: %s: L sizes: rowSize=%6d, columnSize=%6d, valSize=%7d, numColors=%3d, newrowSize=%7d, blkdiagSize=%6d\n",
     __func__,L_rowSize,L_columnSize,L_valSize,L_numColors,L_newrowSize,L_blkdiagSize);
    printf("INFO: %s: U sizes: rowSize=%6d, columnSize=%6d, valSize=%7d, numColors=%3d, newrowSize=%7d, blkdiagSize=%6d\n",
     __func__,U_rowSize,U_columnSize,U_valSize,U_numColors,U_newrowSize,U_blkdiagSize);
  )

  // reset/fill data buffer (if requested)
  if (reset_data_buffers) {
    BDA_DEBUG(1,printf("INFO: %s: clearing data buffers.\n",__func__);)
    for (int b=0; b<RW_BUF; b++) {
      // must skip the setupArray, because that's already copied to the buffer #0
      if (b==0) {
        size_t offset = (SETUP_LINES*CACHELINE_DBL_WORDS)*sizeof(long unsigned int);
        memset(dataBuffer[b]+offset,0,totalSize[b]-offset);
      } else {
        memset(dataBuffer[b],0,totalSize[b]);
      }
    }
  }

  // Set the output regions of the data buffers to a pre-defined value
  // before transferring to device memory
  if (fill_results_buffers) {
    BDA_DEBUG(1,printf("INFO: %s: setting predefined values in output regions of data buffers.\n",__func__);)
    for (int d=0;d<roundUpTo(rowSize, 8);d++) {
      union double2int dw;
      dw.int_val = 0UL;
      for (int j=15;j>=8;j--) {
        unsigned char c = (j % 2 == 0) ? 0x9 : 0x6;
        dw.int_val |= (((unsigned long int)c&0xF) << j*4);
      }
      dw.int_val |= (unsigned long int)d;
      X2Array[d] = dw.double_val;
      R2Array[d] = dw.double_val;
      if (use_LU_res) {
        LresArray[d] = dw.double_val;
        UresArray[d] = dw.double_val;
      }
      BDA_DEBUG(3,
        printf(" X2/R2/Lres/Ures buf: idx %6d: %13le (%016lx)\n",d,dw.double_val,dw.int_val);
      )
    }
  }

  // update the setup array with the sizes for the current system to be solved;
  // all other values are to be left unchanged
  // Cacheline 0:
  //  - [0]  val size (63..32) | row_size (31..0)
  setupArray[0] = (((long unsigned int) valSize) << 32) + (long unsigned int) rowSize;
  // Cacheline 1:
  //  - [8]  L_val size (63..32) | L_row_size (31..0)
  setupArray[8] = (((long unsigned int) L_valSize) << 32) + (long unsigned int) L_rowSize;
  // Cacheline 2:
  //  - [16] U_val size (63..32) | U_row_size (31..0)
  setupArray[16] = (((long unsigned int) U_valSize) << 32) + (long unsigned int) U_rowSize;

  // copy vectorPointers (from level scheduling/graph coloring) to data buffers
  // vectorPointers arrays contain non-padded data, so we must copy exactly the number of elements
  memcpy(colorSizesArray,     (int*)vectorPointers[0]  + 8,   sizeof(int) *       4 * numColors);
  memcpy(L_colorSizesArray,   (int*)vectorPointers[6]  + 8,   sizeof(int) *       4 * L_numColors);
  memcpy(U_colorSizesArray,   (int*)vectorPointers[12] + 8,   sizeof(int) *       4 * U_numColors);
  memcpy(PIndexArray,         (int*)vectorPointers[1],        sizeof(int) *       columnSize);
  memcpy(L_PIndexArray,       (int*)vectorPointers[7],        sizeof(int) *       L_columnSize);
  memcpy(U_PIndexArray,       (int*)vectorPointers[13],       sizeof(int) *       U_columnSize);
  for (int i=0;i<nnzValArrays_num;i++) {
    memcpy(nnzValArrays[i],   ((double**)vectorPointers[2])[i],  sizeof(double) * nnzValArrays_sizes[i]);
    memcpy(L_nnzValArrays[i], ((double**)vectorPointers[8])[i],  sizeof(double) * L_nnzValArrays_sizes[i]);
    memcpy(U_nnzValArrays[i], ((double**)vectorPointers[14])[i], sizeof(double) * U_nnzValArrays_sizes[i]);
  }
  memcpy(columnIndexArray,    (short int*)vectorPointers[3],  sizeof(short int) * valSize);
  memcpy(L_columnIndexArray,  (short int*)vectorPointers[9],  sizeof(short int) * L_valSize);
  memcpy(U_columnIndexArray,  (short int*)vectorPointers[15], sizeof(short int) * U_valSize);
  memcpy(newRowOffsetArray,   (char*)vectorPointers[4],       sizeof(char) *      newrowSize);
  memcpy(L_newRowOffsetArray, (char*)vectorPointers[10],      sizeof(char) *      L_newrowSize);
  memcpy(U_newRowOffsetArray, (char*)vectorPointers[16],      sizeof(char) *      U_newrowSize);
  memcpy(R1Array,             (double*)vectorPointers[19],    sizeof(double) *    rowSize);
  memset(R2Array,             0,                                 sizeof(double) *    rowSize); // must be initialized or memory map will fail
  memcpy(X1Array,             (double*)vectorPointers[20],    sizeof(double) *    rowSize);
  memset(X2Array,             0,                                 sizeof(double) *    rowSize); // must be initialized or memory map will fail
  memcpy(BLKDArray,           (double*)vectorPointers[18],    sizeof(double) *    blkdiagSize);

  // (partial) dump of R1 input buffer
  BDA_DEBUG(2,
    int cl_max = (sizeof(double) * rowSize)/CACHELINE_BYTES;
    // limit the number of cachelines displayed
    if (cl_max>8) cl_max=8;
    printf("INFO: %s: R1 input buffer dump (first %d cachelines):\n",__func__,cl_max);
    for (int c=0;c<cl_max;c++) {
      printf(" cl %5d: 0x",c);
      for (int i=CACHELINE_DBL_WORDS-1;i>=0;i--) {
        union double2int conv;
        conv.double_val = R1Array[c*CACHELINE_DBL_WORDS+i];
        printf("%016lx",conv.int_val);
        printf(" ");
      }
      printf("\n");
    }
  )

  // dump to file all dataBuffer vectors
  BDA_DEBUG(2,
    if (dump_data_buffers == 1) {
      // dump data buffers in binary format
      for (int b=0;b<RW_BUF;b++) {
        char filename[512];
        sprintf(filename,"dump_input_data_%d_seq_%u.bin",b,sequence);
        FILE *fout;
        fout = fopen(filename, "wb");
        if (fout != NULL) {
          fwrite(dataBuffer[b], 1, totalSize[b], fout);
          fclose(fout);
        } else {
          printf("WARNING: %s: requested input data buffer %d dump, but file cannot be written.\n",__func__,b);
        }
      }
    } else if (dump_data_buffers == 2) {
      // dump data buffers in text format
      char filename[512];
      sprintf(filename,"dump_input_data_seq_%u.txt",sequence);
      FILE *fout=NULL;
      fout = fopen(filename, "w");
      if (fout != NULL) {
        for (int b=0;b<RW_BUF;b++) {
          fprintf(fout, "INFO: data buffer %d dump:\n",b);
          for (int c=0;c<(int)(totalSize[b]/CACHELINE_BYTES);c++) {
            fprintf(fout, " cl %5d: 0x",c);
            for (int i=CACHELINE_DBL_WORDS-1;i>=0;i--) {
              for (int j=7;j>=0;j--) fprintf(fout, "%02x",dataBuffer[b][c*CACHELINE_BYTES+i*CACHELINE_DBL_WORDS+j]);
              fprintf(fout, " ");
            }
            fprintf(fout, "\n");
          }
        }  
        fclose(fout);
      } else {
        printf("WARNING: %s: requested input data buffers dump, but file cannot be written.\n",__func__);
      }
    }
  )

  return 0;
}

// --------------------------------------------
// set host debug buffer to a pre-defined value
// --------------------------------------------

static int fpga_fill_host_debugbuf(unsigned int debug_outbuf_words,
 unsigned long int *debugBuffer) {

  // this will help skipping empty/random-valued lines while reading it
  BDA_DEBUG(1,printf("INFO: %s: debug buffer setup.\n",__func__);)
  for (int l=0;l<(int)debug_outbuf_words;l++){
    for (int i=0;i<CACHELINE_DBL_WORDS;i++) {  // fill a cacheline
      unsigned long int val = 0UL;
      for (int j=15;j>=0;j--) {
        unsigned char c = (j % 2 == 0) ? 0xA : 0x5;
        val |= (((unsigned long int)c&0xF) << j*4);
      }
      debugBuffer[i+l*CACHELINE_DBL_WORDS] = val;
      BDA_DEBUG(3,
        val = debugBuffer[i+l*CACHELINE_DBL_WORDS];
        if (i==0) printf(" debug buf init [%4d]: 0x",l);
        printf("%016lx ",val);
        if (i==CACHELINE_DBL_WORDS-1) printf("\n");
      )
    }
  }
  return 0;
}

// =============================================================================
// device data setup
// =============================================================================

// -------------------------
// setup device debug buffer
// -------------------------

int fpga_setup_device_debugbuf(cl_context context,
 unsigned long int *debugBuffer, cl_mem *cldebug, unsigned int debugbufferSize) {
  unsigned int offset;

  // allocate debug output buffer on device
  BDA_DEBUG(1,printf("INFO: %s: allocating CL debug output buffer: %d bytes\n",
   __func__,debugbufferSize);)
  // explicit bank mapping
  cl_mem_ext_ptr_t cl_ptr_struct;
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  offset = 34;  // skip HBM (0-31) and DDR (32-33), map to PLRAM (34-36)
#else
  #error "Undefined"
#endif
  cl_ptr_struct.flags = (offset+0)|XCL_MEM_TOPOLOGY; // PLRAM[0]
  cl_ptr_struct.param = 0;
  cl_ptr_struct.obj = debugBuffer;
  *cldebug = clCreateBuffer(context,CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR | CL_MEM_EXT_PTR_XILINX,
   debugbufferSize, &cl_ptr_struct, NULL);
  if (!*cldebug) {
    printf("ERROR: %s: failed to allocate device memory for debug output buffer\n",__func__);
    return 1;
  }

  return 0;
}

// -------------------------
// setup device data buffers 
// -------------------------

int fpga_setup_device_datamem(cl_context context,
 unsigned int *databufferSize, unsigned char *dataBuffer[RW_BUF],
 cl_mem *cldata) {

  BDA_DEBUG(1,printf("INFO: %s: creating CL buffers.\n",__func__);)
  for (int b=0;b<RW_BUF;b++) {
    BDA_DEBUG(1,printf("INFO: %s: allocating CL data buffer %d, %d bytes\n",
     __func__,b,databufferSize[b]);)
    // explicit bank mapping
    cl_mem_ext_ptr_t cl_ptr_struct;
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr
    // when using DDR for the first two ports:
    if (b<2) {
      // for buffers <2: skip HBM (0-31), map to DDR (32-33)
      cl_ptr_struct.flags = (32+b)|XCL_MEM_TOPOLOGY;
    } else {
      // for buffers >=2: map to HBM (0-31)
      cl_ptr_struct.flags = ((b-1)*2)|XCL_MEM_TOPOLOGY; // map to HBM 2,4,6
    }
#elif PORTS_CONFIG == PORTS_2r_3r3w_hbm
    // when mapping all ports to HBM:
    // map to HBM (0-31)
    cl_ptr_struct.flags = ((b+1)*2)|XCL_MEM_TOPOLOGY; // map to HBM 2,4,6,...
#else
  #error "Undefined"
#endif
    cl_ptr_struct.obj = dataBuffer[b];
    cl_ptr_struct.param = 0;
    cldata[b] = clCreateBuffer(context,CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR | CL_MEM_EXT_PTR_XILINX,
     databufferSize[b],&cl_ptr_struct,NULL);
    if (!cldata[b]) {
      printf("ERROR: %s: failed to allocate device memory for data buffer %d\n",
       __func__,b);
      return 1;
    }
    BDA_DEBUG(1,printf("INFO: %s: CL data buffer %d: %p\n",__func__,b,cldata[b]);)
  }
  return 0;
}

// =============================================================================
// data movement to/from device
// =============================================================================

// -------------------------------
// copy to device the debug buffer
// -------------------------------

int fpga_copy_to_device_debugbuf(cl_command_queue commands,
 cl_mem cldebug, unsigned long int *debugBuffer, unsigned int debugBufferSize,
 unsigned int debug_outbuf_words) {
  int err;

  // we need at least 2 words in the debug buffer (one for status and one for summary)
  if (debug_outbuf_words < 2) {
    printf("ERROR: %s:output debug buffer words must be at least 2\n",__func__);
    return 1;
  }

  // fill the debug buffer with a pre-defined value
  fpga_fill_host_debugbuf(debug_outbuf_words, debugBuffer);

  // copy debug buffer to device memory
  BDA_DEBUG(1,printf("INFO: %s: transferring debug buffer (host -> device, %u bytes).\n",__func__,debugBufferSize);)
  err = clEnqueueMigrateMemObjects(commands, 1, &cldebug, 0, 0, NULL, NULL);
  if (err != CL_SUCCESS){
    printf("ERROR: %s: failed to transfer debug output buffer to device (%d)\n",__func__,err);
    return 1;
  }
  clFinish(commands);
  // clean the debug buffer
  memset(debugBuffer,0,(size_t)debugBufferSize);

  return 0;
}

// -------------------------------
// copy to device the data buffers
// -------------------------------

int fpga_copy_to_device_datamem(cl_command_queue commands,
 int dataBufNum, cl_mem *cldata) {
  int err;
  struct timespec time_start, time_end;
  double time_elapsed_ms;

  BDA_DEBUG(1,printf("INFO: %s: transferring %d data buffers (host -> device).\n",__func__,dataBufNum);)
  clock_gettime(CLOCK_REALTIME, &time_start);
  err = clEnqueueMigrateMemObjects(commands, dataBufNum, cldata, 0, 0, NULL, NULL);
  if (err != CL_SUCCESS){
    printf("ERROR: %s: failed to transfer input buffers to device (%d)\n",__func__,err);
    return 1;
  }
  clFinish(commands);
  clock_gettime(CLOCK_REALTIME, &time_end);
  time_elapsed_ms = (double)(time_end.tv_sec - time_start.tv_sec)*1000 +
   (double)(time_end.tv_nsec - time_start.tv_nsec) / 1000000;
  BDA_DEBUG(1,printf("INFO: %s: transfer time: %lf ms\n",__func__,time_elapsed_ms);)

  return 0;
}

int DEBUG_fpga_copy_to_device_datamem(cl_command_queue commands,
 int dataBufNum, cl_mem *cldata, unsigned int *dataBufferSize, unsigned char **dataBuffer) {
  int err;
  struct timespec time_start, time_end;
  double time_elapsed_ms;

  BDA_DEBUG(1,printf("INFO: %s: transferring %d data buffers (host -> device).\n",__func__,dataBufNum);)
  clock_gettime(CLOCK_REALTIME, &time_start);
  for (int b=0;b<dataBufNum;b++) {
    err = clEnqueueWriteBuffer(commands, cldata[b], CL_TRUE, 0, dataBufferSize[b], dataBuffer[b], 0, NULL, NULL);
    if (err != CL_SUCCESS){
      printf("ERROR: %s: failed to transfer input buffer %d to device (%d)\n",__func__,b,err);
      return 1;
    }
  }
  clFinish(commands);
  clock_gettime(CLOCK_REALTIME, &time_end);
  time_elapsed_ms = (double)(time_end.tv_sec - time_start.tv_sec)*1000 +
   (double)(time_end.tv_nsec - time_start.tv_nsec) / 1000000;
  BDA_DEBUG(1,printf("INFO: %s: transfer time: %lf ms\n",__func__,time_elapsed_ms);)

  return 0;
}

// ---------------------------------
// copy from device the debug buffer 
// ---------------------------------

int fpga_copy_from_device_debugbuf(bool quiet,
 cl_command_queue commands,
 unsigned int debug_outbuf_words, unsigned int debugBufferSize,
 cl_mem cldebug, unsigned long int *debugBuffer, 
 unsigned int abort_cycles,
 unsigned int *kernel_cycles, unsigned int *kernel_iter_run,
 double *norms, unsigned char *last_norm_idx,
 bool *kernel_aborted, bool *kernel_signature, bool *kernel_overflow,
 bool *kernel_noresults, bool *kernel_wrafterend, bool *kernel_dbgfifofull) {
  int err;

  // Read back the debug buffers from the device
  BDA_DEBUG(1,printf("INFO: %s: transferring debug buffer (device -> host).\n",__func__);)
  err = clEnqueueMigrateMemObjects(commands, 1, &cldebug, CL_MIGRATE_MEM_OBJECT_HOST, 0, NULL, NULL);
  if (err != CL_SUCCESS){
    printf("ERROR: %s: failed to transfer debug buffers from device (%d)\n",__func__,err);
    return 1;
  }
  clFinish(commands);

  // debug output interpretation and check
  err = decode_debuginfo_bicgstab(quiet, BDA_DEBUG_LEVEL>0,
   //map_debugBuffer, debug_outbuf_words, CACHELINE_DBL_WORDS,
   debugBuffer, debug_outbuf_words, CACHELINE_DBL_WORDS,
   abort_cycles, kernel_cycles, kernel_iter_run,
   norms, last_norm_idx,
   kernel_aborted, kernel_signature, kernel_overflow,
   kernel_noresults, kernel_wrafterend, kernel_dbgfifofull);
  BDA_DEBUG(1,
    printf("INFO: %s: kernel ran for %d clock cycles.\n",__func__,*kernel_cycles);
    if (*kernel_noresults) 
     printf("INFO: %s: kernel did not return results because the required precision is already reached.\n",__func__);
    // iterations count starts from 0 (=0.5 iter) and counts every 0.5 iterations (e.g. 5 means 3.0 iters)
    printf("INFO: %s: kernel performed %.1f iterations (%d).\n",
     __func__,(float)(*kernel_iter_run/2.0+0.5),*kernel_iter_run);
    printf("INFO: %s: initial norm is %13le; last three norms (*=newest): ",__func__,norms[0]);
    for (int i=1;i<4;i++) {
      printf("%13le",norms[i]);
      if (i==*last_norm_idx) printf("* "); else printf(" ");
    }
    printf("\n");
  )

  return 0;
}

int DEBUG_fpga_copy_from_device_results(bool evenBuffers,
 bool use_residuals, bool use_LU_res,
 cl_command_queue commands,
 int resultsNum, int resultsBufferNum, unsigned int *resultsBufferSize,
 unsigned int debugbufferSize,
 cl_mem *cldata, double **resultsBuffer,
 unsigned int result_offsets[6],
 bool dumpBufferFiles, char *data_dir, char *basename, unsigned int sequence) {
  int err;
  size_t offset = 0;

  // check that resultsBuffer is allocated
  if (resultsBuffer==NULL) {
    printf("ERROR: %s: resultsBuffer buffer is not allocated.\n",__func__);
    return 1;
  }
  for (int b=0;b<resultsBufferNum;b++) {
    if (resultsBuffer[b]==NULL) {
      printf("ERROR: %s: resultsBuffer %d is not allocated.\n",__func__,b);
      return 1;
    }
  }

  if (evenBuffers) {
    err = clEnqueueReadBuffer(commands, cldata[BANK_XRES_EVEN], CL_TRUE,
     result_offsets[0], resultsBufferSize[0], resultsBuffer[0], 0, NULL, NULL);
    if (err != CL_SUCCESS){
      printf("ERROR: %s: failed to transfer results buffer %d (even) from device (%d)\n",__func__,0,err);
      return 1;
    }
    clFinish(commands);
    BDA_DEBUG(1,printf("INFO: %s: even resultsBuffer[0] = %p\n",__func__,resultsBuffer[0]);)
    if (use_residuals) {
      err = clEnqueueReadBuffer(commands, cldata[BANK_RRES_EVEN], CL_TRUE,
       result_offsets[1], resultsBufferSize[1], resultsBuffer[1], 0, NULL, NULL);
      if (err!=0) {
        printf("ERROR: %s: failed to transfer results buffer %d (even) from device (%d)\n",__func__,1,err);
        return 1;
      }
      BDA_DEBUG(1,printf("INFO: %s: even resultsBuffer[1] = %p\n",__func__,resultsBuffer[1]);)
    }
  } else {
    err = clEnqueueReadBuffer(commands, cldata[BANK_XRES_ODD], CL_TRUE,
     result_offsets[2], resultsBufferSize[0], resultsBuffer[0], 0, NULL, NULL);
    if (err != CL_SUCCESS){
      printf("ERROR: %s: failed to transfer results buffer %d (odd) from device (%d)\n",__func__,0,err);
      return 1;
    }
    clFinish(commands);
    BDA_DEBUG(1,printf("INFO: %s: odd resultsBuffer[0] = %p\n",__func__,resultsBuffer[0]);)
    if (use_residuals) {
      err = clEnqueueReadBuffer(commands, cldata[BANK_RRES_ODD], CL_TRUE,
       result_offsets[3], resultsBufferSize[1], resultsBuffer[1], 0, NULL, NULL);
      if (err!=0) {
        printf("ERROR: %s: failed to transfer results buffer %d (odd) from device (%d)\n",__func__,1,err);
        return 1;
      }
      BDA_DEBUG(1,printf("INFO: %s: odd resultsBuffer[1] = %p\n",__func__,resultsBuffer[1]);)
    }
  }

  // ---> L/U buffers (for debug only)

  if (use_LU_res) {
    // copy back vector L_res and U_res, which contain intermediate results from ILU0_L_fs and ILU0_U_bs
    err = clEnqueueReadBuffer(commands, cldata[BANK_LRES], CL_TRUE,
     offset + result_offsets[4], // offset in byte of the region to be copied
     resultsBufferSize[2], resultsBuffer[2], 0, NULL, NULL);
    if (err!=0) {
      printf("ERROR: %s: failed to transfer results buffer %d from device (%d)\n",__func__,2,err);
      return 1;
    }
    err = clEnqueueReadBuffer(commands, cldata[BANK_URES], CL_TRUE,
     offset + result_offsets[5], // offset in byte of the region to be copied
     resultsBufferSize[3], resultsBuffer[3], 0, NULL, NULL);
    if (err!=0) {
      printf("ERROR: %s: failed to transfer results buffer %d from device (%d)\n",__func__,3,err);
      return 1;
    }
  }

  // (partial) dump of results buffers
  BDA_DEBUG(2,
    int b=0;
    int cl_max = resultsBufferSize[b]/CACHELINE_BYTES;
    // limit the number of cachelines displayed
    if (cl_max>8) cl_max=8;
    for (int b=0;b<resultsBufferNum;b++) {
      printf("INFO: %s: results buffer %d dump (first %d cachelines):\n",__func__,b,cl_max);
      for (int c=0;c<cl_max;c++) {
        printf(" cl %5d: 0x",c);
        for (int i=CACHELINE_DBL_WORDS-1;i>=0;i--) {
          union double2int conv;
          conv.double_val = resultsBuffer[b][c*CACHELINE_DBL_WORDS+i];
          printf("%016lx",conv.int_val);
          printf(" ");
        }
        printf("\n");
      }
    }
  )

  // if enabled, dump results buffers to files
  if (dumpBufferFiles) {
    char res_out_full_path[1024];
    for (int b=0;b<resultsBufferNum;b++) {
      sprintf(res_out_full_path, "%s/%s_seq_%u_res_%d.rdf", data_dir, basename, sequence, b);
      BDA_DEBUG(1,printf("INFO: %s: dump results buffer %d to file.\n",__func__,b);)
      FILE *fout=NULL;
      if ((fout = fopen(res_out_full_path ,"wb")) == NULL) {
        printf("WARNING: %s: could not write file for results buffer %d.\n",__func__,b);
      } else {
        size_t ws = fwrite(resultsBuffer[b], 1, resultsBufferSize[b], fout);
        if ((unsigned int)ws != resultsBufferSize[b]) {
          printf("WARNING: %s: something went wrong while writing file for results buffer %d (wrote %d bytes, expected %d).\n",
           __func__,b,(int)ws,resultsBufferSize[b]);
        }
        fclose(fout);
      }
    }
  }

  return 0;
}

// =============================================================================
// mapping/unmapping
// =============================================================================

// WARNING: Currently, there may be a bug in XRT (v2.3) that sometimes causes a
// segfault when doing clReleaseMemObject on a buffer that has been unmapped
// with clEnqueueUnmapMemObject.

// -----------------------------------------
// map results buffers (from device to host)
// -----------------------------------------

int fpga_map_results(bool evenBuffers,
 bool use_residuals, bool use_LU_res,
 cl_command_queue commands,
 int resultsNum, int resultsBufferNum, unsigned int *resultsBufferSize,
 unsigned int debugbufferSize,
 cl_mem *cldata, double **resultsBuffer,
 unsigned int result_offsets[6],
 bool dumpBufferFiles, char *data_dir, char *basename, unsigned int sequence) {
  int err;
  size_t offset = 0;

  // check that resultsBuffer is allocated
  if (resultsBuffer==NULL) {
    printf("ERROR: %s: resultsBuffer buffer is not allocated.\n",__func__);
    return 1;
  }

  // ---> X/R buffers

  // current mapping of results buffers is:
  // - when iter. count is even (half iters.): results are in X2, residuals are in R2
  // - when iter. count is odd  (full iters.): results are in X1, residuals are in R1

  if (evenBuffers) {
    resultsBuffer[0] = (double*)clEnqueueMapBuffer(commands, cldata[BANK_XRES_EVEN], CL_TRUE,
     CL_MAP_READ, result_offsets[0], resultsBufferSize[0], 0, NULL, NULL, &err);
    if (err!=0) {
      printf("ERROR: %s: failed to map results buffer %d (even) on device (%d)\n",__func__,0,err);
      return 1;
    }
    BDA_DEBUG(1,printf("INFO: %s: even resultsBuffer[0] = %p\n",__func__,resultsBuffer[0]);)
    if (use_residuals) {
      resultsBuffer[1] = (double*)clEnqueueMapBuffer(commands, cldata[BANK_RRES_EVEN], CL_TRUE,
       CL_MAP_READ, result_offsets[1], resultsBufferSize[1], 0, NULL, NULL, &err);
      if (err!=0) {
        printf("ERROR: %s: failed to map results buffer %d (even) on device (%d)\n",__func__,1,err);
        return 1;
      }
      BDA_DEBUG(1,printf("INFO: %s: even resultsBuffer[1] = %p\n",__func__,resultsBuffer[1]);)
    }
  } else {
    resultsBuffer[0] = (double*)clEnqueueMapBuffer(commands, cldata[BANK_XRES_ODD], CL_TRUE,
     CL_MAP_READ, result_offsets[2], resultsBufferSize[0], 0, NULL, NULL, &err);
    if (err!=0) {
      printf("ERROR: %s: failed to map results buffer %d (odd) on device (%d)\n",__func__,0,err);
      return 1;
    }
    BDA_DEBUG(1,printf("INFO: %s: odd resultsBuffer[0] = %p\n",__func__,resultsBuffer[0]);)
    if (use_residuals) {
      resultsBuffer[1] = (double*)clEnqueueMapBuffer(commands, cldata[BANK_RRES_ODD], CL_TRUE,
       CL_MAP_READ, result_offsets[3], resultsBufferSize[1], 0, NULL, NULL, &err);
      if (err!=0) {
        printf("ERROR: %s: failed to map results buffer %d (odd) on device (%d)\n",__func__,1,err);
        return 1;
      }
      BDA_DEBUG(1,printf("INFO: %s: odd resultsBuffer[1] = %p\n",__func__,resultsBuffer[1]);)
    }
  }

  // ---> L/U buffers (for debug only)

  if (use_LU_res) {
    // copy back vector L_res and U_res, which contain intermediate results from ILU0_L_fs and ILU0_U_bs
    offset = 0;
    resultsBuffer[2] = (double*)clEnqueueMapBuffer(commands, cldata[BANK_LRES], CL_TRUE, CL_MAP_READ,
     offset + result_offsets[4], // offset in byte of the region to be mapped
     resultsBufferSize[2], 0, NULL, NULL, &err);
    resultsBuffer[3] = (double*)clEnqueueMapBuffer(commands, cldata[BANK_URES], CL_TRUE, CL_MAP_READ,
     offset + result_offsets[5], // offset in byte of the region to be mapped
     resultsBufferSize[3], 0, NULL, NULL, &err);
  }

/*
  // (partial) dump of results buffers
  //FIXME: disabled because it causes segfaults: to be investigated.
  BDA_DEBUG(2,
    int b=0;
    int cl_max = resultsBufferSize[b]/CACHELINE_BYTES;
    // limit the number of cachelines displayed
    if (cl_max>8) cl_max=8;
    for (int b=0;b<resultsBufferNum;b++) {
      printf("INFO: %s: results buffer %d dump (first %d cachelines):\n",__func__,b,cl_max);
      for (int c=0;c<cl_max;c++) {
        printf(" cl %5d: 0x",c);
        for (int i=CACHELINE_DBL_WORDS-1;i>=0;i--) {
          union double2int conv;
          conv.double_val = resultsBuffer[b][c*CACHELINE_DBL_WORDS+i];
          printf("%016lx",conv.int_val);
          printf(" ");
        }
        printf("\n");
      }
    }
  )
*/

  // if enabled, dump results buffers to files
  if (dumpBufferFiles) {
    char res_out_full_path[1024];
    for (int b=0;b<resultsBufferNum;b++) {
      sprintf(res_out_full_path, "%s/%s_seq_%u_res_%d.rdf", data_dir, basename, sequence, b);
      BDA_DEBUG(1,printf("INFO: %s: dump results buffer %d to file.\n",__func__,b);)
      FILE *fout=NULL;
      if ((fout = fopen(res_out_full_path ,"wb")) == NULL) {
        printf("WARNING: %s: could not write file for results buffer %d.\n",__func__,b);
      } else {
        size_t ws = fwrite(resultsBuffer[b], 1, resultsBufferSize[b], fout);
        if ((unsigned int)ws != resultsBufferSize[b]) {
          printf("WARNING: %s: something went wrong while writing file for results buffer %d (wrote %d bytes, expected %d).\n",
           __func__,b,(int)ws,resultsBufferSize[b]);
        }
        fclose(fout);
      }
    }
  }

  return 0;
}

// ---------------------
// unmap results buffers
// ---------------------

int fpga_unmap_results(bool evenBuffers,
 bool use_residuals, bool use_LU_res,
 cl_command_queue commands, cl_mem *cldata, double **resultsBuffer) {

  // check that resultsBuffer is allocated
  if (resultsBuffer==NULL) {
    printf("ERROR: %s: resultsBuffer buffer is not allocated.\n",__func__);
    return 1;
  }

  // unmap results buffer
  if (evenBuffers) {
    clEnqueueUnmapMemObject(commands, cldata[BANK_XRES_EVEN], resultsBuffer[0], 0, NULL, NULL);
    BDA_DEBUG(1,printf("INFO: %s: even resultsBuffer[0] = %p\n",__func__,resultsBuffer[0]);)
    if (use_residuals) {
      clEnqueueUnmapMemObject(commands, cldata[BANK_RRES_EVEN], resultsBuffer[1], 0, NULL, NULL);
      BDA_DEBUG(1,printf("INFO: %s: even resultsBuffer[1] = %p\n",__func__,resultsBuffer[1]);)
    }
  } else {  
    clEnqueueUnmapMemObject(commands, cldata[BANK_XRES_ODD], resultsBuffer[0], 0, NULL, NULL);
    BDA_DEBUG(1,printf("INFO: %s: odd resultsBuffer[0] = %p\n",__func__,resultsBuffer[0]);)
    if (use_residuals) {
      clEnqueueUnmapMemObject(commands, cldata[BANK_RRES_ODD], resultsBuffer[1], 0, NULL, NULL);
      BDA_DEBUG(1,printf("INFO: %s: odd resultsBuffer[1] = %p\n",__func__,resultsBuffer[1]);)
    }
  }

  // L/U results (for debug only)
  if (use_LU_res) {
    clEnqueueUnmapMemObject(commands, cldata[BANK_LRES], resultsBuffer[2], 0, NULL, NULL);
    clEnqueueUnmapMemObject(commands, cldata[BANK_URES], resultsBuffer[3], 0, NULL, NULL);
    BDA_DEBUG(1,
      printf("INFO: %s: resultsBuffer[2] = %p\n",__func__,resultsBuffer[2]);
      printf("INFO: %s: resultsBuffer[3] = %p\n",__func__,resultsBuffer[3]);
    )
  }

  return 0;
}

// =============================================================================
// kernel setup/run
// =============================================================================

// -----------------------
// kernel parameters setup
// -----------------------

// WARNING: as per Xilinx recommendations (see UG1393), this must be done before
// any host-device data movement
int fpga_set_kernel_parameters(cl_kernel kernel,
 unsigned int abort_cycles, unsigned int debug_lines, unsigned int kernel_iter,
 unsigned int debug_sample_rate, double kernel_precision,
 cl_mem *cldata, cl_mem cldebug) {
  int err;
  cl_ulong clparam[3];
  union double2int prec;

  // compose kernel arguments
  // parameter 0:
  // - abort trigger: number of clk cycles the kernel is allowed to run for; 0 means DISABLED
  clparam[0] = (unsigned long int)abort_cycles;
  // parameter 1:
  // - kernel max number of iterations
  // - sampling rate
  // - max debug cachelines
  clparam[1] = (((unsigned long int)debug_lines & 0xFFFF) << 32) |
               (((unsigned long int)debug_sample_rate & 0xFFFF) << 16) |
                ((unsigned long int)kernel_iter & 0xFFFF);
  // parameter 2:
  // - kernel precision
  prec.double_val = kernel_precision;
  clparam[2] = prec.int_val;
  BDA_DEBUG(1,
    printf("INFO: %s: CL scalar parameter %d: %ld (0x%016lx)\n",__func__,0,clparam[0],clparam[0]);
    printf("INFO: %s: CL scalar parameter %d: %ld (0x%016lx)\n",__func__,1,clparam[1],clparam[1]);
    printf("INFO: %s: CL scalar parameter %d: %.3f (0x%016lx)\n",__func__,2,prec.double_val,clparam[2]);
  )

  // set the arguments to the kernel
  BDA_DEBUG(1,printf("INFO: %s: setting kernel arguments.\n",__func__);)
  err = 0;
  err |= clSetKernelArg(kernel,  0, sizeof(cl_ulong), &clparam[0]);
  err |= clSetKernelArg(kernel,  1, sizeof(cl_ulong), &clparam[1]);
  err |= clSetKernelArg(kernel,  2, sizeof(cl_ulong), &clparam[2]);
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  err |= clSetKernelArg(kernel,  3, sizeof(cl_mem), &cldata[0]);
  err |= clSetKernelArg(kernel,  4, sizeof(cl_mem), &cldata[1]);
  err |= clSetKernelArg(kernel,  5, sizeof(cl_mem), &cldata[2]);
  err |= clSetKernelArg(kernel,  6, sizeof(cl_mem), &cldata[3]);
  err |= clSetKernelArg(kernel,  7, sizeof(cl_mem), &cldata[4]);
  err |= clSetKernelArg(kernel,  8, sizeof(cl_mem), &cldata[2]);
  err |= clSetKernelArg(kernel,  9, sizeof(cl_mem), &cldata[3]);
  err |= clSetKernelArg(kernel, 10, sizeof(cl_mem), &cldata[4]);
  err |= clSetKernelArg(kernel, 11, sizeof(cl_mem), &cldebug);
#else
  #error "Undefined"
#endif
  if (err != CL_SUCCESS) {
    printf("ERROR: %s: failed to set kernel arguments (%d)\n",__func__, err);
    return 1;
  }
  return 0;
}

// ----------------------------
// kernel invocation: execution
// ----------------------------

int fpga_kernel_run(cl_command_queue commands, cl_kernel kernel, double *time_elapsed_ms) {
  struct timespec time_start, time_end;
  int err;

  BDA_DEBUG(1,printf("INFO: %s: starting the kernel.\n",__func__);)
  clock_gettime(CLOCK_REALTIME, &time_start);
  err = clEnqueueTask(commands,kernel,0,NULL,NULL);
  if (err) {
    printf("ERROR: %s: failed to execute kernel (%d)\n",__func__, err);
    return 1;
  }
  clFinish(commands);
  clock_gettime(CLOCK_REALTIME, &time_end);
  *time_elapsed_ms = (double)(time_end.tv_sec - time_start.tv_sec)*1000 +
   (double)(time_end.tv_nsec - time_start.tv_nsec) / 1000000;
  BDA_DEBUG(1,
    printf("INFO: %s: kernel finished.\n",__func__);
    printf("INFO: %s: kernel execution time: %lf ms\n",__func__,*time_elapsed_ms);
  )
  return 0;
}

// ------------------------------------------------------------
// kernel invocation: query the kernel for limits/configuration
// WARNING: the debug buffer must be already setup before calling this function
// ------------------------------------------------------------

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
 unsigned short *hw_reset_cycles, unsigned short *hw_reset_settle) {
  int err;
  unsigned char *temp_dataBuffer[RW_BUF];
  unsigned int temp_dataBufferSize[RW_BUF];
  cl_ulong clparam[3];
  cl_mem temp_cldata[RW_BUF];

  if (debugBuffer == NULL) {
    printf("ERROR: %s: debugBuffer must already be allocated.\n",__func__);
    return 1;
  }

  // allocate a small set of buffers on host and device because kernel
  // parameters need valid pointers to work
  for (int b=0;b<RW_BUF;b++) {
    temp_dataBufferSize[b] = 4096;
    // SDx needs aligned memory when using CL_MEM_USE_HOST_PTR
    err=posix_memalign((void **)&temp_dataBuffer[b], SDX_MEM_ALIGNMENT, temp_dataBufferSize[b]);
    if (err) {
      printf("ERROR: %s: posix_memalign failed to allocate temp_dataBuffer %d.\n",__func__,b);
      return 1;
    }
    memset(temp_dataBuffer[b],0,temp_dataBufferSize[b]);
  }
  err = fpga_setup_device_datamem(context,
   temp_dataBufferSize, temp_dataBuffer, temp_cldata);
  if (err) {
    printf("ERROR: %s: fpga_setup_device_datamem failed to allocate temp_dataBuffer.\n",__func__);
    return 1;
  }

  // TODO: modify function fpga_set_kernel_parameters to set parameters for query
  // instead of using this duplicated code
  // compose kernel arguments
  clparam[0] = 0; // unused
  clparam[1] = ((unsigned long int)1 << 48) + ((unsigned long int)rst_settle_cycles << 16) + ((unsigned long int)rst_assert_cycles);  // set bit 48 to query kernel limits/config
  clparam[2] = 0; // unused
  BDA_DEBUG(1,
    for (int i=0;i<3;i++) printf("INFO: %s: CL scalar parameter %d: %ld (0x%016lx)\n",
     __func__,i,clparam[i],clparam[i]);)
  // set the arguments to the kernel
  // WARNING: as per Xilinx recommendations (see UG1393), this must be done before any host-device data movement
  BDA_DEBUG(1,printf("INFO: %s: setting kernel arguments.\n",__func__);)
  err = 0;
  err |= clSetKernelArg(kernel,  0, sizeof(cl_ulong), &clparam[0]);
  err |= clSetKernelArg(kernel,  1, sizeof(cl_ulong), &clparam[1]);
  err |= clSetKernelArg(kernel,  2, sizeof(cl_ulong), &clparam[2]);
#if PORTS_CONFIG == PORTS_2r_3r3w_ddr || PORTS_CONFIG == PORTS_2r_3r3w_hbm
  err |= clSetKernelArg(kernel,  3, sizeof(cl_mem), &temp_cldata[0]);
  err |= clSetKernelArg(kernel,  4, sizeof(cl_mem), &temp_cldata[1]);
  err |= clSetKernelArg(kernel,  5, sizeof(cl_mem), &temp_cldata[2]);
  err |= clSetKernelArg(kernel,  6, sizeof(cl_mem), &temp_cldata[3]);
  err |= clSetKernelArg(kernel,  7, sizeof(cl_mem), &temp_cldata[4]);
  err |= clSetKernelArg(kernel,  8, sizeof(cl_mem), &temp_cldata[2]);
  err |= clSetKernelArg(kernel,  9, sizeof(cl_mem), &temp_cldata[3]);
  err |= clSetKernelArg(kernel, 10, sizeof(cl_mem), &temp_cldata[4]);
  err |= clSetKernelArg(kernel, 11, sizeof(cl_mem), &cldebug);
#else
  #error "Undefined"
#endif
  if (err != CL_SUCCESS) {
    printf("ERROR: %s: failed to set kernel arguments (%d)\n",__func__,err);
    return 1;
  }

  // Start the kernel
  BDA_DEBUG(1,printf("INFO: %s: starting the kernel (configuration query).\n",__func__);)
  err = clEnqueueTask(commands,kernel,0,NULL,NULL);
  if (err) {
    printf("ERROR: %s: failed to execute kernel (configuration query) (%d)\n",__func__,err);
    return 1;
  }
  clFinish(commands);
  BDA_DEBUG(1,printf("INFO: %s: kernel configuration query finished.\n",__func__);)

  // remove temporary buffers
  for (int b=0;b<RW_BUF;b++) {
    clReleaseMemObject(temp_cldata[b]);
    temp_cldata[b] = NULL;
    free(temp_dataBuffer[b]);
  }

  // TODO: modify function fpga_copy_from_device_debugbuf to transfer debug and
  // parse the query info instead of using this duplicated code
  // Read back the debug buffers from the device
  BDA_DEBUG(1,printf("INFO: %s: transferring debug buffer (device -> host).\n",__func__);)
  err = clEnqueueMigrateMemObjects(commands, 1, &cldebug, CL_MIGRATE_MEM_OBJECT_HOST, 0, NULL, NULL);
  if (err != CL_SUCCESS){
    printf("ERROR: %s: failed to transfer debug buffers (%d)\n",__func__,err);
    return 1;
  }
  clFinish(commands);

  // debug output interpretation and check
  bool quiet = true;
  err = decode_debuginfo_bicgstab_query(quiet,
   debugBuffer, debug_outbuf_words, CACHELINE_DBL_WORDS,
   hw_x_vector_elem, hw_max_row_size, hw_max_column_size,
   hw_max_colors_size, hw_max_nnzs_per_row, hw_max_matrix_size,
   hw_use_uram, hw_write_ilu0_results,
   hw_dma_data_width, hw_mult_num,
   hw_x_vector_latency, hw_add_latency, hw_mult_latency, 
   hw_num_read_ports, hw_num_write_ports,
   hw_reset_cycles, hw_reset_settle);
  if (err) {
    printf("ERROR: %s: failed to query kernel for limits/configuration (%d)\n",__func__,err);
    return 1;
  }

  return 0;
}

