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

#ifndef __BICGSTAB_UTILS_HPP__
#define __BICGSTAB_UTILS_HPP__

int decode_debuginfo_bicgstab(
 bool quiet, bool print_legend,
 unsigned long int *debugBuffer, unsigned int debug_outbuf_words,
 unsigned int cacheline_dbl_words, unsigned int abort_cycles,
 unsigned int *kernel_cycles, unsigned int *kernel_iterations,
 double norms[4], unsigned char *last_norm_idx,
 bool *kernel_aborted, bool *kernel_signature, bool *kernel_overflow,
 bool *kernel_noresults, bool *kernel_wrafterend, bool *kernel_dbgfifofull);

int decode_debuginfo_bicgstab_query(
 bool quiet,
 unsigned long int *debugBuffer, unsigned int debug_outbuf_words,
 unsigned int cacheline_dbl_words,
 unsigned int *x_vector_elem, unsigned int *max_row_size, unsigned int *max_column_size,
 unsigned int *max_colors_size, unsigned short *max_nnzs_per_row, unsigned int *max_matrix_size,
 bool *use_uram, bool *write_ilu0_results,
 unsigned short *dma_data_width, unsigned char *mult_num,
 unsigned char *x_vector_latency, unsigned char *add_latency, unsigned char *mult_latency,
 unsigned char *num_read_ports, unsigned char *num_write_ports,
 unsigned short *reset_cycles, unsigned short *reset_settle);

// for decode_debuginfo_<kernel> function
#define OVERFLOW_BUFFER 30
#define TRANS_BUFFER    20
#define STATES_BUFFER   20

#endif //__BICGSTAB_UTILS_HPP__

