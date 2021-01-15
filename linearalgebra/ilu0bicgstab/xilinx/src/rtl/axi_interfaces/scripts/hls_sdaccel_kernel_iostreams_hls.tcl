#  Copyright 2020 Equinor ASA
#
#  This file is part of the Open Porous Media project (OPM).
#
#  OPM is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  OPM is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with OPM.  If not, see <http://www.gnu.org/licenses/>.

# ------------------------------------------------------------------------------
# Script to create an HLS project, synthesize the sources and cosimulate them
# ------------------------------------------------------------------------------

# Use "vivado_hls -f <script.tcl>" to run this script in batch mode.
# Use "vivado_hls -i -f <script.tcl>" to run this script in tcl (interactive) mode.

# In case the simulation hangs, the xsim/xsimk processes must be killed manually.

# ------------------------------------------------------------------------------

# --- setup

set EXPORT 1
set EXPORT_SDACCEL 0
set PRJ_NAME hls_sdaccel_kernel_iostreams_hls
set TOP hls_sdaccel_kernel_iostreams_hls
set XO_NAME hls_sdaccel_kernel_iostreams_hls.xo

# adjust this variable to the sources location
set SRC_DIR ..
# adjust this variable to the output location
set OUT_DIR kernel_bin
# adjust this variable to the location of QuestaSim compiled libraries (if using it)
set QUESTASIMLIB simlib_questa

# ---

# create a new project or remove all data if one already exists
open_project -reset $PRJ_NAME
cd $PRJ_NAME

if { $EXPORT == 1 } {
  set EXPORT_FLAG "EXPORT_DESIGN"
} else {
  set EXPORT_FLAG "DONT_EXPORT_DESIGN"
}
set_top $TOP
add_files $SRC_DIR/hls_sdaccel_kernel_iostreams_hls.cpp -cflags "-DBDA_DEBUG_LEVEL=1 -D${EXPORT_FLAG}"
add_files -tb $SRC_DIR/hls_sdaccel_kernel_iostreams_hls_tb.cpp -cflags "-DBDA_DEBUG_LEVEL=1 -D${EXPORT_FLAG} -Wno-unknown-pragmas"

open_solution "solution1" -reset

# device for AlphaData 7v3 card
#set_part {xc7vx690tffg1157-2} -tool vivado
# device for Xilinx Alveo 200 card
#set_part {xcu200-fsgd2104-2-e} -tool vivado
# device for Xilinx Alveo 280 card
#set_part {xcu280-fsvh2892-2L-e} -tool vivado
# generic Virtex Ultrascale+ device (e.g. all Alveo boards)
set_part {virtexuplus} -tool vivado

create_clock -period 4 -name default
set_clock_uncertainty 10%

if { $EXPORT_SDACCEL == 1 } {
  config_sdx -optimization_level 3 -target xocc -profile true
  config_rtl -prefix ip
}
config_bind -effort high
config_compile -name_max_length 256 -pipeline_loops 8
config_dataflow -default_channel fifo
config_schedule -effort high -enable_dsp_full_reg
config_export -display_name "$PRJ_NAME" -description "Test for integration of HLS in SDAccel" -vendor "BDA" -version "1.0" -vivado_phys_opt none
config_interface -m_axi_addr64

# --- run

csim_design -clean

csynth_design
exec grep -A19 "Utilization Estimates" solution1/syn/report/read_input_csynth.rpt > resources.txt
exec grep -A19 "Utilization Estimates" solution1/syn/report/write_output_csynth.rpt >> resources.txt

# cosimulate using Xsim
cosim_design -trace_level all -rtl vhdl -tool xsim
# cosimulate using QuestaSim
#cosim_design -trace_level all -rtl vhdl -tool modelsim -compiled_library_dir $QUESTASIMLIB

# all cosim options:
#-O
#-argv <string>
#-compiled_library_dir <string>
#-coverage
#-disable_pipeline_flush ( *false* | true )
#-ldflags <string>
#-mflags <string>
#-reduce_diskspace
#-rtl ( *verilog* | vhdl )
#-setup : create scripts but won't start simulation
#-tool ( *auto* | vcs | modelsim | riviera | isim | xsim | ncsim | xcelium )
#-trace_level ( *none* | all | port | port_hier )

# --- export

if { $EXPORT == 1 } {
  if { $EXPORT_SDACCEL == 1 } {
    puts "Exporting design to IP Catalog (SDAccel)"

    # -xo works only since 2018.3
    export_design -rtl vhdl -format ip_catalog -xo $OUT_DIR/$XO_NAME
    #export_design -rtl verilog -format ip_catalog -xo $OUT_DIR/$XO_NAME

    # hack the IP to enable debug mode
    # this is required to run co-simulation with waveforms in SDAccel
    cd $OUT_DIR
    exec  rm -rf $PRJ_NAME
    exec  unzip $XO_NAME -d $PRJ_NAME
    exec  mv -f $XO_NAME $XO_NAME.bak
    cd $PRJ_NAME
    exec  sed -i "s|debug=\"false\"|debug=\"true\"|" $TOP/kernel.xml
    exec  zip -r ../$XO_NAME .
    cd ..
    exec  rm -rf $PRJ_NAME
  } else {
    puts "Exporting design to System Generator"

    export_design -rtl vhdl -format sysgen
  }
}

# --- done

close_solution
close_project
quit

