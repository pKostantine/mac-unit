# Timing constraints for the Go Board build.
#
# The board oscillator is 25 MHz = 40 ns. The core closed at 132.64 MHz in
# the standalone build, so this has roughly 5x margin.
create_clock -name {i_Clk} -period 40.000 [get_ports {i_Clk}]

# Buttons, LEDs and the seven-segment display are asynchronous and have no
# timing requirement -- a human cannot press a button on a clock edge, and an
# LED does not care when in the cycle it changes. Cutting these paths keeps
# the timing report about the datapath, which is the part that matters.
set_false_path -from [all_inputs] -to [all_registers]
set_false_path -from [all_registers] -to [all_outputs]
