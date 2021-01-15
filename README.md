# FPGA kernels for the Open Porous Media Simulators and Automatic Differentiation Library

CONTENT
-------

This module contains kernels that can be used to replace some software functions
with an hardware-accelerated version by using an FPGA platform.
The first kernel made available is the ILU0-BiCGSTAB solver, which can
be used in opm-simulators by the Flow reservoir simulator.
Due to the nature of the FPGA development (currently, mainly VHDL code
with some C/C++ integration libraries), these kernels are separated
from the opm-simulators module and placed into this repository.


LICENSE
-------

The library is distributed under the GNU General Public License,version 3 or
later (GPLv3+).


PLATFORMS
---------

The FPGA kernels are currently targeted at the Xilinx Alveo(tm) data center
acceleration cards, and they can be used both on premises or by using an
Alveo-enabled cloud platform.


REQUIREMENTS
------------

This module requires the specific software tools used to compile the hardware
kernels for the selected target platforms (e.g., Xilinx Vitis(tm)).
For further details, see
*(wiki link will be available soon)*


DOWNLOADING
-----------

For a read-only download:
git clone git://github.com/OPM/FPGA.git

If you want to contribute, fork OPM/FPGA on github.


DOCUMENTATION
-------------

See documentation, including building instructions, at
*(wiki link will be available soon)*


REPORTING ISSUES
----------------

Issues can be reported in the Git issue tracker online at:

    https://github.com/OPM/FPGA/issues
