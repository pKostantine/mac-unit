# 200 MHz request -- same as synth/mac_a7.xdc, so the numbers are comparable.
create_clock -name clk -period 5.000 [get_ports clk]

# Port-list-agnostic: works for mac_dsp and mac_core alike.
set_false_path -from [remove_from_collection [all_inputs] [get_ports clk]]
set_false_path -to   [all_outputs]
