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
  Modules: buffered memory read and write
  Variant: using streams to/from compute module, using 512-bit memory elements
*/

#include <hls_stream.h>
#include <string.h>
#include <ap_int.h>
#include <stdio.h>
#include "hls_sdaccel_kernel_iostreams_hls.hpp"

// *****************************************************************************

static void read_input(
 const ap_uint<512> *in,
 unsigned long long address,
 unsigned int data_len,
 hls::stream <ap_uint<512> > &elemStream)  {
#pragma HLS INLINE off
  int rounds,leftovers;
  static ap_uint<512> buffer[INPUT_BUF_LEN] = {0};

  BDA_DEBUG_SW(1,
    printf("%s: data_len=%u, address=%llu, read buffer size=%u\n",
      __func__,data_len,address,INPUT_BUF_LEN);
    printf("%s: [before] elemStream elem=%d\n",__func__,elemStream.size());
    printf("%s: [before] elemStream empty=%d\n",__func__,elemStream.empty());
  )

  // compute how many times the buffer will be fully filled and how many elements
  // will be left over
  rounds = data_len / INPUT_BUF_LEN;
  leftovers = data_len % INPUT_BUF_LEN;
  BDA_DEBUG_SW(1,printf("%s: rounds=%u, leftover=%u\n",__func__,rounds,leftovers);)

  if (leftovers) rounds++;
  for (int j = 0; j<rounds; j++) {
    unsigned int elem = INPUT_BUF_LEN;
    if (leftovers && j==(rounds-1)) elem = leftovers;
    #pragma HLS DATAFLOW
    BDA_DEBUG_SW(1,printf("%s: read memory (len=%u, address=%llu, offset=%llu)\n",
      __func__,elem,address,INPUT_BUF_LEN*j);)
    read_memory: for (int i=0; i<elem; i++) {
      #pragma HLS PIPELINE II=1
      buffer[i] = in[address + (INPUT_BUF_LEN*j) + i];
    }
    BDA_DEBUG_SW(1,printf("%s: write stream (len=%u)\n",__func__,elem);)
    write_stream: for (int i=0;i<elem;i++) {
      #pragma HLS PIPELINE II=1
      elemStream.write(buffer[i]);
    }
  }

  BDA_DEBUG_SW(1,
    printf("%s: [after] elemStream elem=%d\n",__func__,elemStream.size());
    printf("%s: [after] elemStream empty=%d\n",__func__,elemStream.empty());
  )
}

// *****************************************************************************

static void dummy_compute(
 hls::stream <ap_uint<512> > &elemStream,
 unsigned int data_len,
 hls::stream <ap_uint<512> > &resultStream) {
#pragma HLS INLINE off

  BDA_DEBUG_SW(1,
    printf("%s: [before] elemStream elem=%d, resultStream elem=%d\n",
      __func__,elemStream.size(),resultStream.size());
    printf("%s: [before] elemStream empty=%d, resultStream empty=%d\n",
      __func__,elemStream.empty(),resultStream.empty());
  )

  for (int elem=0; elem<data_len; elem++) {
    #pragma HLS PIPELINE II=1
    ap_uint<512> e = elemStream.read();
    resultStream.write(e);
  }

  BDA_DEBUG_SW(1,
    printf("%s: [after] elemStream elem=%d, resultStream elem=%d\n",
      __func__,elemStream.size(),resultStream.size());
    printf("%s: [after] elemStream empty=%d, resultStream empty=%d\n",
      __func__,elemStream.empty(),resultStream.empty());
  )
}

union double2int {
  unsigned long long int_val;
  double double_val;
};

static void dummy_compute_vadd1(
 hls::stream <ap_uint<512> > &elemStream,
 unsigned int data_len,
 hls::stream <ap_uint<512> > &resultStream) {
#pragma HLS INLINE off

  BDA_DEBUG_SW(1,
    printf("%s: [before] elemStream elem=%d, resultStream elem=%d\n",
      __func__,elemStream.size(),resultStream.size());
    printf("%s: [before] elemStream empty=%d, resultStream empty=%d\n",
      __func__,elemStream.empty(),resultStream.empty());
  )

  for (int elem=0; elem<data_len; elem++) {
    #pragma HLS PIPELINE II=1
    // read from input stream
    ap_uint<512> e = elemStream.read();
    // unpack -> add -> repack
    for (int i=0;i<8;i++) {
      #pragma HLS PIPELINE II=1
      union double2int conv;
      switch (i) {
        case 0: conv.int_val = e.range(63,0);    break;
        case 1: conv.int_val = e.range(127,64);  break;
        case 2: conv.int_val = e.range(191,128); break;
        case 3: conv.int_val = e.range(255,192); break;
        case 4: conv.int_val = e.range(319,256); break;
        case 5: conv.int_val = e.range(383,320); break;
        case 6: conv.int_val = e.range(447,384); break;
        case 7: conv.int_val = e.range(511,448); break;
      }
      conv.double_val += 1.0;
      switch (i) {
        case 0: e.range(63,0)    = conv.int_val; break;
        case 1: e.range(127,64)  = conv.int_val; break;
        case 2: e.range(191,128) = conv.int_val; break;
        case 3: e.range(255,192) = conv.int_val; break;
        case 4: e.range(319,256) = conv.int_val; break;
        case 5: e.range(383,320) = conv.int_val; break;
        case 6: e.range(447,384) = conv.int_val; break;
        case 7: e.range(511,448) = conv.int_val; break;
      }
    }
    // write to output stream
    resultStream.write(e);
  }

  BDA_DEBUG_SW(1,
    printf("%s: [after] elemStream elem=%d, resultStream elem=%d\n",
      __func__,elemStream.size(),resultStream.size());
    printf("%s: [after] elemStream empty=%d, resultStream empty=%d\n",
      __func__,elemStream.empty(),resultStream.empty());
  )
}

// *****************************************************************************

static void write_output(
 hls::stream <ap_uint<512> > &resultStream,
 ap_uint<512> *out,
 unsigned long long address,
 unsigned int data_len){
#pragma HLS INLINE off
  int rounds,leftovers;
  static ap_uint<512> buffer[RESULTS_BUF_LEN] = {0};

  BDA_DEBUG_SW(1,
    printf("%s: data_len=%u, address=%llu, write buffer size=%u\n",
      __func__,data_len,address,RESULTS_BUF_LEN);
    printf("%s: [before] resultStream elem=%d\n",__func__,resultStream.size());
    printf("%s: [before] resultStream empty=%d\n",__func__,resultStream.empty());
  )

  // compute how many times the buffer will be fully filled and how many elements
  // will be left over
  rounds = data_len / RESULTS_BUF_LEN;
  leftovers = data_len % RESULTS_BUF_LEN;
  BDA_DEBUG_SW(1,printf("%s: rounds=%u, leftover=%u\n",__func__,rounds,leftovers);)

  // avoid read dependencies on buffer and write on output port by splitting the
  // read operations (i.e. pre-computing rounds instead of counting the elements
  // and dumping when buffer is full)

  if (leftovers) rounds++;
  for (int j = 0; j<rounds; j++) {
    unsigned int elem = RESULTS_BUF_LEN;
    if (leftovers && j==(rounds-1)) elem = leftovers;
//    #pragma HLS DATAFLOW
    BDA_DEBUG_SW(1,printf("%s: read stream (len=%u)\n",__func__,elem);)
    read_stream: for (int i=0; i<elem; i++) {
      #pragma HLS PIPELINE II=1
      buffer[i] = resultStream.read();
    }
    BDA_DEBUG_SW(1,printf("%s: write memory (len=%u, address=%llu, offset=%llu)\n",
      __func__,elem,address,RESULTS_BUF_LEN*j);)
    write_memory: for (int i=0; i<elem; i++) {
      #pragma HLS PIPELINE II=1
      out[address + (RESULTS_BUF_LEN*j) + i] = buffer[i];
    }
  }

  BDA_DEBUG_SW(1,
    printf("%s: [after] resultStream elem=%d\n",__func__,resultStream.size());
    printf("%s: [after] resultStream empty=%d\n",__func__,resultStream.empty());
  )
}

// =============================================================================

static void flow_in_compute_out(const ap_uint<512> *in, ap_uint<512> *out,
 const unsigned long long mem_in_address, const unsigned long long mem_out_address,
 unsigned int data_len){
#if defined(USE_DATAFLOW)
  #pragma HLS DATAFLOW
#endif

  hls::stream <ap_uint<512> > elemStream;
  hls::stream <ap_uint<512> > resultStream;
#if defined(EXPORT_DESIGN)
  #pragma HLS STREAM variable=elemStream depth=512
  #pragma HLS STREAM variable=resultStream depth=512
#else
  // make streams big enough to avoid deadlocks when testing with multiple rounds
  #pragma HLS STREAM variable=elemStream depth=2048
  #pragma HLS STREAM variable=resultStream depth=2048
  #warning "Using increased stream sizes to avoid deadlock"
#endif

  read_input(in, mem_in_address, data_len, elemStream);
#if defined(DUMMY_COMPUTE_VADD1)
  dummy_compute_vadd1(elemStream, data_len, resultStream);
#else
  dummy_compute(elemStream, data_len, resultStream);
#endif
  write_output(resultStream, out, mem_out_address, data_len);
}

// =============================================================================

extern "C"
void hls_sdaccel_kernel_iostreams_hls(
 const ap_uint<512> *mem_in,
 ap_uint<512> *mem_out,
 const unsigned long long mem_in_address,
 const unsigned long long mem_out_address,
 unsigned int data_len) {
#if defined(EXPORT_DESIGN)
  #pragma HLS INTERFACE m_axi     port=mem_in     offset=slave bundle=gmem0    depth=512
  #pragma HLS INTERFACE m_axi     port=mem_out    offset=slave bundle=gmem1    depth=512
#else
  #pragma HLS INTERFACE m_axi     port=mem_in     offset=slave bundle=gmem0    depth=2048
  #pragma HLS INTERFACE m_axi     port=mem_out    offset=slave bundle=gmem1    depth=2048
#endif
  #pragma HLS INTERFACE s_axilite port=mem_in     bundle=control
  #pragma HLS INTERFACE s_axilite port=mem_out    bundle=control
  #pragma HLS INTERFACE s_axilite port=mem_in_address bundle=control
  #pragma HLS INTERFACE s_axilite port=mem_out_address bundle=control
  #pragma HLS INTERFACE s_axilite port=data_len   bundle=control
  #pragma HLS INTERFACE s_axilite port=return     bundle=control

  flow_in_compute_out(mem_in, mem_out, mem_in_address, mem_out_address, data_len);

  return;
}

