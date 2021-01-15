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
  Library of functions specific to the kernel
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bda_utils.hpp"
#include "bicgstab_utils.hpp"

static void bicgstab_unit_states(unsigned int unit, unsigned int state, char *state_str) {
  switch (unit) {
    case 0: // encoded solver state
      switch (state) {
        case 0:  strcpy(state_str,"idle"); break;
        case 1:  strcpy(state_str,"init_read"); break;
        case 2:  strcpy(state_str,"read_x"); break;
        case 3:  strcpy(state_str,"SpMV"); break;
        case 4:  strcpy(state_str,"wait_write"); break;
        case 5:  strcpy(state_str,"ILU0_L_fs"); break;
        case 6:  strcpy(state_str,"ILU0_U_bs"); break;
        case 7:  strcpy(state_str,"calc_p"); break;
        case 8:  strcpy(state_str,"dot1"); break;
        case 9:  strcpy(state_str,"dot2"); break;
        case 10: strcpy(state_str,"axpy1"); break;
        case 11: strcpy(state_str,"axpy2"); break;
        case 12: strcpy(state_str,"wait_debug"); break;
        default: strcpy(state_str,"*UNKNOWN*"); break;
      }
      break;
    case 1: // encoded dot_axpy1/2 state
    case 2:
      switch (state) {
        case 0:  strcpy(state_str,"idle"); break;
        case 1:  strcpy(state_str,"dot"); break;
        case 2:  strcpy(state_str,"axpy"); break;
        default: strcpy(state_str,"*UNKNOWN*"); break;
      }
      break;
    case 3: // encoded sparstition state
      switch (state) {
        case 0:  strcpy(state_str,"idle"); break;
        case 1:  strcpy(state_str,"wait_sizes_read"); break;
        case 2:  strcpy(state_str,"wait_first_vec_read"); break;
        case 3:  strcpy(state_str,"wait_transfer"); break;
        case 4:  strcpy(state_str,"wait_P_vector_read"); break;
        case 5:  strcpy(state_str,"running"); break;
        case 6:  strcpy(state_str,"init_U"); break;
        case 7:  strcpy(state_str,"finished"); break;
        default: strcpy(state_str,"*UNKNOWN*"); break;
      }
      break;
    case 4: // encoded sparstition mode state
      switch (state) {
        case 1:  strcpy(state_str,"fwd_subst"); break;
        case 2:  strcpy(state_str,"bck_subst"); break;
        case 3:  strcpy(state_str,"SpMV"); break;
        default: strcpy(state_str,"*UNKNOWN*"); break;
      }
      break;
    case 5: // state change information
      // print order is bit 6..0
      strcpy(state_str,"       ");
      for (int i=0;i<=6;i++) state_str[6-i] = (state & (1<<i)) ? 'x' : '.';
      break;
    default: strcpy(state_str,"*UNKNOWN_UNIT*"); break;
  }
}

int decode_debuginfo_bicgstab(
 bool quiet, bool print_legend,
 unsigned long int *debugBuffer, unsigned int debug_outbuf_words,
 unsigned int cacheline_dbl_words, unsigned int abort_cycles,
 unsigned int *kernel_cycles, unsigned int *kernel_iterations,
 double norms[4], unsigned char *last_norm_idx,
 bool *kernel_aborted, bool *kernel_signature, bool *kernel_overflow,
 bool *kernel_noresults, bool *kernel_wrafterend, bool *kernel_dbgfifofull) {
    unsigned int overflow[OVERFLOW_BUFFER] = {0};
    unsigned int trans[TRANS_BUFFER] = {0};
    unsigned int states[STATES_BUFFER] = {0};
    unsigned int itrcount = 0, dbgcount = 0, dbgcount_max = 0;
    char str_states[STATES_BUFFER][50];
    int ret = 0;
    union double2int conv;
    double cur_norms[4];
    bool legend_printed = false;

    *kernel_aborted = false;
    *kernel_signature = false;
    *kernel_overflow = false;
    *kernel_noresults = false; // kernel didn't return results because precision is already met
    *kernel_wrafterend = false;
    *kernel_dbgfifofull = false;

    *kernel_cycles = 0;
    *kernel_iterations = 0;
    for (int l = 0; l < (int)debug_outbuf_words; l++){
      if (l==0) {
        // general status
        if ( (unsigned int)(( debugBuffer[7+l*cacheline_dbl_words] >> 40) & 0xFFFFFF) != 0x414442 ) {
          *kernel_signature = true;
          ret = 1;
          printf("ERROR: %s: HW kernel did not return the correct signature.\n",__func__);
        } else {
          if (debugBuffer[0+l*cacheline_dbl_words] & 1) {
            *kernel_aborted = true;
            ret = 1;
            printf("ERROR: %s: HW kernel was aborted because it ran for more than %u clock cycles.\n",
             __func__,abort_cycles);
          } else {
            *kernel_cycles = (unsigned int)(debugBuffer[1+l*cacheline_dbl_words] & 0xFFFFFFFF);
          }
          *kernel_noresults = (bool)(debugBuffer[0+l*cacheline_dbl_words] >> 1) & 1;
          *kernel_wrafterend = (bool)(debugBuffer[0+l*cacheline_dbl_words] >> 2) & 1;
          *kernel_dbgfifofull = (bool)(debugBuffer[0+l*cacheline_dbl_words] >> 3) & 1;
        }
      } else {
        // kernel-specific status
        unsigned long int val = debugBuffer[0+l*cacheline_dbl_words]; // bit 0..63
        if (val != 0x5a5a5a5a5a5a5a5aUL) {
          unsigned long int word0 = val;
          overflow[0]  = (unsigned int)((val >> 0) & 1);      // reduce unit overflow (no. nnz values per column too large)
          overflow[1]  = (unsigned int)((val >> 4) & 1);      // ilu0 fifo overflow (unable to use ilu0 results as inputs during the next color)
          overflow[2]  = (unsigned int)((val >> 8) & 0xFF);   // merge2 modules of write_merge unit overflow
          overflow[3]  = (unsigned int)((val >> 16) & 0xF);   // split2 modules of write_merge unit overflow
          overflow[4]  = (unsigned int)((val >> 20) & 0xF);   // out fifos of write_merge unit overflow
          overflow[5]  = (unsigned int)((val >> 24) & 0xF);   // spmv results BRAMs of write unit overflow
          overflow[6]  = (unsigned int)((val >> 32) & 1);     // read0 port fifo underflow
          overflow[7]  = (unsigned int)((val >> 33) & 1);     // read1 port fifo underflow
          overflow[8]  = (unsigned int)((val >> 34) & 1);     // read2 port fifo underflow
          overflow[9]  = (unsigned int)((val >> 35) & 1);     // read3 port fifo underflow
          overflow[10] = (unsigned int)((val >> 36) & 1);     // read4 port fifo underflow
          overflow[11] = (unsigned int)((val >> 40) & 1);     // vect fifo 0 overflow
          overflow[12] = (unsigned int)((val >> 41) & 1);     // vect fifo 1 overflow
          overflow[13] = (unsigned int)((val >> 42) & 1);     // vect fifo 2 overflow
          overflow[14] = (unsigned int)((val >> 44) & 1);     // vect fifo 0 underflow
          overflow[15] = (unsigned int)((val >> 45) & 1);     // vect fifo 1 underflow
          overflow[16] = (unsigned int)((val >> 46) & 1);     // vect fifo 2 underflow
          overflow[17] = (unsigned int)((val >> 48) & 0x1F);  // read requests on ports 0..4 given before previous read request finished
          overflow[18] = (unsigned int)((val >> 53) & 0x7);   // write requests on ports 0..2 given before previous write request finished
          overflow[19] = (unsigned int)((val >> 56) & 0xF);   // overwritten dot_axpy inputs
          overflow[20] = (unsigned int)((val >> 60) & 0xF);   // result on one of the spmvp outputs has a lower address than the done-up-to address

          int of = 0;
          for (int i = 0; i < OVERFLOW_BUFFER; i++) of += overflow[i];
          if (of) {
            *kernel_overflow = true;
            ret = 1;
            printf("ERROR: %s: HW kernel reported execution failure:\n",__func__);
            printf("  o/u-flow: nnzvn ilu0f mrge2 splt2 wrmgf wuBRA rd0uf rd1uf rd2uf rd3uf rd4uf vf0of vf1of vf2of vf0uf vf1uf vf2uf rdbef wrbef daiov spadr\n");
            printf("           ");
            for (int i = 0; i <= 20; i++) {
              if (i==2 || i==3 || i==4 || i==5 || i==17 || i==18 || i==19 || i==20)
                printf(" %5d",overflow[i]);
//            else if (i==4) {
//              printf("  ");
//              for (int j=7;j>=0;j--) printf("%c", (overflow[i] & (1<<j)) ? j+48 : '.');
//            }
              else
                printf("     %d",overflow[i]);
            }
            printf("\n");
            if (print_legend && !legend_printed) {
              printf("  LEGEND\n");
              printf("   nnzvn.......: reduce unit overflow (no. nnz values per column too large)\n");
              printf("   ilu0f.......: ilu0 fifo overflow (unable to use ilu0 results as inputs during the next color)\n");
              printf("   mrge2.......: overflows in the merge2 modules of the write_merge unit (1 bit per stage)\n");
              printf("   splt2.......: overflows in the split2 modules of the write_merge unit (1 bit per stage)\n");
              printf("   wrmgf.......: overflows in the output fifos of the write_merge unit\n");
              printf("   wuBRA.......: overflows of the spmv results BRAMs in the write unit\n");
              printf("   rd0uf..rd4uf: read fifo underflows for ports 0..4\n");
              printf("   vf0of..vf2of: vector fifo overflows for vectors 0..2\n");
              printf("   vf0uf..vf2uf: vector fifo underflows for vector reads 0..2\n");
              printf("   rdbef.......: read requests on ports 0..4 given before previous read request finished\n");
              printf("   wrbef.......: write requests on ports 0..2 given before previous write request finished\n");
              printf("   daiov.......: overwritten dot_axpy inputs\n");
              printf("   spadr.......: result on one of the spmvp outputs has a lower address than the done-up-to address\n");
              legend_printed = true; // if enabled, print legend only once
            }
          }
          if (l==1 && !quiet) {
            printf("INFO:                                                                                                                             read0 done-+\n");
            printf("INFO:                                                                                                                      read fifo0 empty-+|\n");
            printf("INFO:                                                                                                                   vector fifo0 empty-+||\n");
            printf("INFO:                                                                                                                          read1 done-+|||\n");
            printf("INFO:                                                                                                                   read fifo1 empty-+||||\n");
            printf("INFO:                                                                                                                vector fifo1 empty-+|||||\n");
            printf("INFO:                                                                                                                   dot_axpy1 done-+||||||\n");
            printf("INFO:  count kiter read0 read1 read2 read3 writ0 writ1 writ2   solver       axpy1       axpy2       sparstition           sp.mode      |||||||      | o/u-flow + err\n");
          }
          val = debugBuffer[1+l*cacheline_dbl_words]; // bit 64..127
          trans[0] = (unsigned int)((val >> 0) & 0xFFFF);    // number of reads on port read0 in current state
          trans[1] = (unsigned int)((val >> 16) & 0xFFFF);   // number of reads on port read1 in current state
          trans[2] = (unsigned int)((val >> 32) & 0xFFFF);   // number of reads on port read2 in current state
          trans[3] = (unsigned int)((val >> 48) & 0xFFFF);   // number of reads on port read3 in current state
          val = debugBuffer[2+l*cacheline_dbl_words]; // bit 128..191
          trans[4] = (unsigned int)((val >> 0) & 0xFFFF);    // number of writes on port write0 in current state
          trans[5] = (unsigned int)((val >> 16) & 0xFFFF);   // number of writes on port write1 in current state
          trans[6] = (unsigned int)((val >> 32) & 0xFFFF);   // number of writes on port write2 in current state
          states[0] = (unsigned int)((val >> 48) & 0xF);     // encoded solver state
          states[1] = (unsigned int)((val >> 56) & 0x3);     // encoded dot_axpy1 state
          states[2] = (unsigned int)((val >> 60) & 0x3);     // encoded dot_axpy2 state
          val = debugBuffer[3+l*cacheline_dbl_words]; // bit 192..255
          states[3] = (unsigned int)((val >> 0) & 0x7);      // encoded sparstition state
          states[4] = (unsigned int)((val >> 4) & 0x3);      // encoded sparstition mode state
          states[5] = (unsigned int)((val >> 8) & 0x7F);     // state change information
          dbgcount = (unsigned int)((val >> 16) & 0xFFFF);   // number of times a debug line has been written (including the current one, so starts at 1)
          itrcount = (unsigned int)((val >> 32) & 0xFFFF);   // kernel iterations count
          val = debugBuffer[4+l*cacheline_dbl_words]; // bit 256..319
          conv.int_val = val;
          cur_norms[0] = conv.double_val; // one of the four most recent norm results
          val = debugBuffer[5+l*cacheline_dbl_words]; // bit 320..383
          conv.int_val = val;
          cur_norms[1] = conv.double_val; // one of the four most recent norm results
          val = debugBuffer[6+l*cacheline_dbl_words]; // bit 384..447
          conv.int_val = val;
          cur_norms[2] = conv.double_val; // one of the four most recent norm results
          val = debugBuffer[7+l*cacheline_dbl_words]; // bit 448..511
          conv.int_val = val;
          cur_norms[3] = conv.double_val; // one of the four most recent norm results
          if (!quiet) {
            for (int i=0;i<6;i++) bicgstab_unit_states(i,states[i],str_states[i]); // get strings for states
            printf("INFO: %6d:%5d|%5d|%5d|%5d|%5d|%5d|%5d|%5d|| %-10s | %-9s | %-9s | %-19s | %-9s || %s 0x%02x | 0x%016lx",
             dbgcount,itrcount,trans[0],trans[1],trans[2],trans[3],trans[4],trans[5],trans[6],
             str_states[0],str_states[1],str_states[2],str_states[3],str_states[4],str_states[5],states[5],word0);
            printf(" %13le %13le %13le %13le\n",cur_norms[0],cur_norms[1],cur_norms[2],cur_norms[3]);
          }
          // kernel iterations and norms should be saved for the last (highest)
          // debug count line, because debug lines are wrapped around in the
          // limited-size debug buffer
          if (dbgcount > dbgcount_max || debug_outbuf_words<3) {
            dbgcount_max = dbgcount;
            *kernel_iterations = itrcount;
            // cur_norms[0] always contains the initial norm
            // cur_norms[1..3] are written like a circular buffer
            memcpy(norms,cur_norms,4 * sizeof(double));
            // index of the newest norm
            *last_norm_idx = (itrcount % 3)+1;
          }
        }
      }
    }

    BDA_DEBUG(2,
      // dump raw debug buffer lines
      for (int l = 0; l < (int)debug_outbuf_words; l++) {
        unsigned long int val = debugBuffer[0+l*cacheline_dbl_words];
        if (val != 0x5a5a5a5a5a5a5a5aUL) {
          printf("INFO: debug[%3d]: 0x",l);
          for (int i = cacheline_dbl_words-1; i>=0; i--){
            val = debugBuffer[i+l*cacheline_dbl_words];
            printf("%016lx ",val);
          }
          printf("\n");
        }
      }
    )

    return ret;
}

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
 unsigned short *reset_cycles, unsigned short *reset_settle) {
    int l = 0; // read only debug cacheline 0
    unsigned long int val;

    BDA_DEBUG(2,
      // dump raw debug buffer lines
      for (int l = 0; l < (int)debug_outbuf_words; l++) {
        unsigned long int val = debugBuffer[0+l*cacheline_dbl_words];
        if (val != 0x5a5a5a5a5a5a5a5aUL) {
          printf("INFO: debug[%3d]: 0x",l);
          for (int i = cacheline_dbl_words-1; i>=0; i--){
            val = debugBuffer[i+l*cacheline_dbl_words];
            printf("%016lx ",val);
          }
          printf("\n");
        }
      }
    )

    // check signature (must be "BDA")
    if ( (unsigned int)(( debugBuffer[7+l*cacheline_dbl_words] >> 40) & 0xFFFFFF) != 0x414442 ) {
      printf("ERROR: %s: HW kernel did not return the correct signature.\n",__func__);
      return 1;
    }
    // kernel-specific limits/configuration
    val = debugBuffer[0+l*cacheline_dbl_words]; // cl bit 0..63
    if (val != 0x5a5a5a5a5a5a5a5aUL) {
      *x_vector_elem = (unsigned int)((val >> 0) & 0xFFFFFFFF);
      *max_row_size  = (unsigned int)((val >> 32) & 0xFFFFFFFF);
      val = debugBuffer[1+l*cacheline_dbl_words]; // cl bit 64..127
      *max_column_size = (unsigned int)((val >> 0) & 0xFFFFFFFF);
      *max_colors_size = (unsigned int)((val >> 32) & 0xFFFFFFFF);
      val = debugBuffer[2+l*cacheline_dbl_words]; // cl bit 128..191
      *max_nnzs_per_row = (unsigned int)((val >> 0) & 0xFFFF);
      *max_matrix_size = (unsigned int)((val >> 16) & 0xFFFFFFFF);
      //val = debugBuffer[3+l*cacheline_dbl_words]; // cl bit 192..255 (currently unused)
      //val = debugBuffer[4+l*cacheline_dbl_words]; // cl bit 256..319 (currently unused)
      val = debugBuffer[5+l*cacheline_dbl_words]; // cl bit 320..383
      *reset_cycles = (unsigned short)((val >> 0) & 0xFFFF);
      *reset_settle = (unsigned short)((val >> 16) & 0xFFFF);
      val = debugBuffer[6+l*cacheline_dbl_words]; // cl bit 384..447
      *use_uram           = (bool)((val >> 0) & 0x1);
      *write_ilu0_results = (bool)((val >> 1) & 0x1);
      *dma_data_width     = (unsigned short)((val >> 16) & 0xFFFF);
      *x_vector_latency   = (unsigned char)((val >> 32) & 0xFF);
      *add_latency        = (unsigned char)((val >> 40) & 0xFF);
      *mult_latency       = (unsigned char)((val >> 48) & 0xFF);
      *mult_num           = (unsigned char)((val >> 56) & 0xFF);
      val = debugBuffer[7+l*cacheline_dbl_words]; // cl bit 448..511 (signature 63..40)
      *num_read_ports     = (unsigned char)((val >> 0) & 0xF);
      *num_write_ports    = (unsigned char)((val >> 4) & 0xF);
      if (!quiet) {
        printf("INFO: %s: kernel limits/configuration:\n",__func__);
        printf("INFO:  x_vector_elem=%u, max_row_size=%u, max_column_size=%u\n"
         "INFO:  max_colors_size=%u, max_nnzs_per_row=%u, max_matrix_size=%u\n"
         "INFO:  use_uram=%d, write_ilu0_results=%d\n"
         "INFO:  dma_data_width=%u, mult_num=%u\n"
         "INFO:  x_vector_latency=%u\n"
         "INFO:  add_latency=%u, mult_latency=%u\n"
         "INFO:  num_read_ports=%u, num_write_ports=%u\n"
         "INFO:  reset_cycles=%u, reset_settle=%u\n",
         *x_vector_elem, *max_row_size, *max_column_size,
         *max_colors_size, *max_nnzs_per_row, *max_matrix_size,
         (int)*use_uram, (int)*write_ilu0_results,
         *dma_data_width, *mult_num,
         *x_vector_latency,
         *add_latency, *mult_latency,
         *num_read_ports, *num_write_ports,
         *reset_cycles, *reset_settle);
      }
    } else {
      printf("ERROR: %s: HW kernel did not return valid configuration data.\n",__func__);
      return 1;
    }

    return 0;
}

