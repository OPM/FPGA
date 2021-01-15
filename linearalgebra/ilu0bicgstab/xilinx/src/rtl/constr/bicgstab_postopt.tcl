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

# implementation constraints to be applied *after* the optimization step
# Example of usage on the v++ config file:
# [vivado]
# prop=run.impl_1.STEPS.OPT_DESIGN.TCL.POST={<this_script_with path.tcl>}

# reset in the ap_clk domain: pfm_top_i/dynamic_region/slr0/expanded_region_resets_slr0/psreset_gate_pr_kernel crossing two SLRs (0->2)
# apply the commands surrounded by catch because vivado would exit immediately if they fail
#if {[catch { set_false_path -from [get_pins -hierarchical -filter {NAME =~ *slr0*psreset_gate_pr_kernel*ACTIVE_LOW_PR_OUT* && REF_PIN_NAME == C}] } err]} {
#  puts "WARNING: could not apply false_path 1, error: $err"
#}
#if {[catch { set_false_path -from [get_cells -hierarchical -filter {NAME =~ *slr0*psreset_gate_pr_kernel*ACTIVE_LOW_PR_OUT*FDRE_PER_N}] } err]} {
#  puts "WARNING: could not apply false_path 2, error: $err"
#}
#if {[catch { set_false_path -from [get_cells -hierarchical -filter {NAME =~ *slr0*psreset_gate_pr_kernel*ACTIVE_LOW_PR_OUT*FDRE_PER_N*replica*}] } err]} {
#  puts "WARNING: could not apply false_path 3, error: $err"
#}

