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

# Usage: Custom kernel level constraints can be added to this file.

# Example multicycle constraint on reset to inst_example:
# Multicycle paths can be used on the reset register to help with timing closure on designs with
# high reset fanouts.  To ensure the reset register is not optimized out, add a DONT_TOUCH = "yes"
# or KEEP = "yes" attribute to the register inside the RTL code.
# set_multicycle_path -setup 3 -hold 2 [get_cells inst_example/areset_reg]

# reset from the wrapper to the kernel
set_false_path -from [get_cells -hier kernel_ap_rst_reg]
