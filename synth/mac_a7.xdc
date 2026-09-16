# mac_a7.xdc -- timing constraints for the Artix-7 comparison build (Vivado).
#
# XDC is Vivado's constraint format. It is close enough to the SDC used for
# the iCE40 build that the two runs stay comparable.
#
# 5 ns = 200 MHz. The iCE40 build closed at 132.64 MHz with a LUT-built
# multiplier; a fabric with hard DSP blocks should beat that comfortably, so
# start well above it and tighten until it fails.
create_clock -name clk -period 5.000 [get_ports clk]

# Cut the I/O paths, exactly as the iCE40 build does. This characterises the
# core register-to-register datapath rather than pad delays, which is the only
# way the two Fmax numbers mean the same thing.
#
# clk is deliberately excluded from the input cut -- it is a clock, not data.
set_false_path -from [get_ports {a[*] b[*] en clear rst_n}]
set_false_path -to   [get_ports {acc[*] result[*] overflow sat}]
