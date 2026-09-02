# Timing constraints for the MAC unit.
#
# iCEcube2: add this under Synthesis Tool -> Add Files (select Synplify Pro as
# the synthesis engine; the LSE default has weaker SystemVerilog and SDC
# handling). Pin assignments live in Go_Board_Constraints.pcf and are added
# separately under Place & Route -- .sdc is timing, .pcf is pins.
#
# Vivado: add as a constraint file (XDC syntax is close enough for a single
# create_clock; use create_clock -period 5.000 [get_ports clk] there).

# --- Go Board target: 25 MHz on-board oscillator = 40 ns period -------------
create_clock -name {clk} -period 40.000 [get_ports {clk}]

# Once it closes at 40 ns, tighten the period until it fails. The smallest
# period that still meets timing is your Fmax -- that number, and the path
# the tool reports as critical, are the two things the report needs.
#
# Expect the critical path to run:
#     acc_q  ->  multiplier  ->  32-bit adder  ->  acc_q
# On the iCE40 HX1K there are no DSP blocks, so the multiplier is built from
# LUT4s and carry chains and that path is long. If 25 MHz will not close,
# register the multiplier output to split the path into two stages: Fmax
# rises, throughput stays at one MAC per cycle, and you pay one cycle of
# latency. Measure both and put both in the table.

# --- I/O ---------------------------------------------------------------------
# This characterises the core datapath, not board-level I/O timing. Cutting
# the I/O paths keeps pad delays out of the reported Fmax. Say so in the
# report rather than quietly reporting a number that means something else.
set_false_path -from [all_inputs] -to [all_registers]
set_false_path -from [all_registers] -to [all_outputs]
