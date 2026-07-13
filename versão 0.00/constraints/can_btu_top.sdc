# ####################################################################

#  Created by Genus(TM) Synthesis Solution 22.16-s078_1 on Thu Mar 26 18:28:05 -03 2026

# ####################################################################

set sdc_version 2.0

set_units -capacitance 1000fF
set_units -time 1000ps

# Set the current design
current_design can_btu_top

create_clock -name "clock" -period 10.0 -waveform {0.0 5.0} [get_ports clk]
set_clock_gating_check -setup 0.0 
set_max_dynamic_power 0.0
set_ideal_net [get_nets clk]
set_ideal_net [get_nets rst_n]
set_wire_load_mode "enclosed"
set_clock_latency  1.0 [get_clocks clock]
set_clock_uncertainty -setup 2.0 [get_clocks clock]
set_clock_uncertainty -hold 2.0 [get_clocks clock]
## List of unsupported SDC commands ##
set_max_dynamic_power 0.0
