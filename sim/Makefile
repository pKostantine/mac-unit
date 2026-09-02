# Simulation driver for the MAC unit.
# Run from the project root:  make -f sim/Makefile sim
#
# Targets:
#   make -f sim/Makefile sim      compile and run the testbench
#   make -f sim/Makefile wave     run, then open the waveform in GTKWave
#   make -f sim/Makefile lint     syntax/width check the RTL on its own
#   make -f sim/Makefile solution run the TB against rtl/mac_ref.v, if present
#   make -f sim/Makefile clean    remove build products

RTL  := rtl/mac.v
TB   := tb/tb_mac.v
OUT  := sim/sim.vvp
VCD  := sim/dump.vcd

IVFLAGS := -Wall -g2001

.PHONY: sim wave lint solution clean

sim: $(OUT)
	@cd sim && vvp sim.vvp

$(OUT): $(RTL) $(TB)
	iverilog $(IVFLAGS) -o $(OUT) $(TB) $(RTL)

wave: sim
	gtkwave $(VCD) &

lint:
	iverilog $(IVFLAGS) -t null $(RTL)

solution:
	@test -f rtl/mac_ref.v || { echo "rtl/mac_ref.v not present"; exit 1; }
	iverilog $(IVFLAGS) -o sim/sim_ref.vvp $(TB) rtl/mac_ref.v
	@cd sim && vvp sim_ref.vvp

clean:
	rm -f sim/*.vvp sim/dump.vcd dump.vcd
