# Fixed-Point MAC Unit

A parameterised signed multiply-accumulate datapath in Verilog-2001, with a
self-checking testbench and synthesis results on two different FPGA fabrics.

The multiply-accumulate is the atomic operation of neural network inference:
a dense layer, a convolution and a matrix multiply are all dot products, and
a dot product is a sequence of MACs. Accelerators are, at the bottom, large
arrays of these.

```
acc <- acc + (a * b)      one MAC per clock while en is asserted
```

## Status

- [x] RTL complete, simulation passing (16/16, ~150k checks)
- [x] Verified at four parameter configurations
- [x] Synthesised and timing-closed on iCE40 HX1K (Go Board, iCEcube2)
- [ ] Synthesised on Artix-7 (Vivado)
- [ ] Pipelined variant measured
- [ ] Running on hardware

## Design

| Port | Dir | Width | Purpose |
|---|---|---|---|
| `clk` | in | 1 | |
| `rst_n` | in | 1 | asynchronous assert, active low |
| `clear` | in | 1 | zero the accumulator, start a new dot product |
| `en` | in | 1 | accumulate this cycle; hold when low |
| `a`, `b` | in | `WIDTH` | signed operands |
| `acc` | out | `ACC_WIDTH` | full-precision accumulator |
| `result` | out | `WIDTH` | rounded, shifted and saturated output |
| `overflow` | out | 1 | sticky; accumulator left signed range |
| `sat` | out | 1 | combinational; `result` is currently clamped |

Parameters: `WIDTH = 8`, `ACC_WIDTH = 32`, `FRAC_BITS = 7`.

### Bit growth

Signed 8×8 needs exactly 16 bits: the extreme products are `-128 × -128 =
+16384` and `-128 × +127 = -16256`, both inside signed 16-bit range.

The accumulator is 32 bits, giving 16 guard bits above the product. Worst-case
product magnitude is 2^14 and the accumulator holds 2^31, so:

```
2^31 / 2^14 = 2^17 = 131,072 accumulations before overflow is possible
```

A 1024-input dense layer uses 1024 MACs, so there is 128× headroom. The
testbench pushes past 131,072 to confirm the overflow flag actually fires.

### Q-format

Q-format is an interpretation, not a circuit. With Q1.7 inputs the product is
Q2.14 and the accumulator is Q18.14; producing a Q1.7 output means an
arithmetic shift right by `FRAC_BITS`. Changing `FRAC_BITS` costs zero gates
in the multiplier — it only moves the shift.

The output path rounds to nearest before shifting. Plain truncation of a
two's-complement value always rounds toward −∞, a −0.5 LSB DC bias that
accumulates across a layer; adding half an LSB first removes it. The result
saturates rather than wraps, because wrapping turns +1.2 into −0.8 — a sign
flip — while clamping only loses magnitude.

## Verification

`tb/tb_mac.v` is self-checking: it decides pass/fail and prints one verdict.
No waveform inspection required unless something breaks.

- **Golden model** — the accumulator recomputed in 64 bits, so the model
  itself can never overflow and is always trustworthy.
- **Scoreboard** — `acc`, `result`, `sat` and `overflow` compared every cycle.
- **Directed tests** — the signed corners (`-128 × -128` above all), `clear`
  mid-sequence, `clear` versus `en` priority, `en` low holding the
  accumulator, saturation in both directions, and accumulator overflow.
- **Randomised** — 10,000 MACs with random operands, half of them with random
  `en` and `clear` too.

Roughly 150,000 checks per run.

`tb/tb_param.v` is a second, simpler testbench that runs at *any* parameter
set. It exists because `tb_mac.v` is pinned to `WIDTH=8` and therefore cannot
catch a hardcoded shift amount or bit slice in the output path. The design is
verified at four configurations:

| WIDTH | ACC_WIDTH | FRAC_BITS | Result |
|---|---|---|---|
| 8 | 32 | 7 | pass |
| 4 | 16 | 3 | pass |
| 6 | 24 | 5 | pass |
| 12 | 40 | 9 | pass |

This caught a real defect: an earlier revision hardcoded the output-path
widths, which passed every test at 8 bits and failed at all three of the
other configurations.

The testbench was validated by mutation: deliberately breaking the RTL
(unsigned multiply, ignoring `en`, dropping saturation, truncating instead of
rounding, wrong `clear`/`en` priority) makes it fail, each bug caught by the
test aimed at it. A testbench that has never caught a bug has not been tested.

## Building

### Simulation

```sh
make -f sim/Makefile sim      # compile and run
make -f sim/Makefile sweep    # run tb_param.v at four parameter sets
make -f sim/Makefile wave     # run, then open GTKWave
make -f sim/Makefile lint     # syntax and width check the RTL alone
```

Windows, or without `make`:

```
run.bat
run.bat wave
run_param.bat
```

Or by hand:

```sh
iverilog -Wall -g2001 -o sim.vvp tb/tb_mac.v rtl/mac.v
vvp sim.vvp
```

### Synthesis — iCE40 HX1K (Go Board, iCEcube2)

1. New project, device iCE40 HX1K, package VQ100.
2. Set the synthesis engine to **Synplify Pro** (Project → Select Implementation Tool).
3. Add `rtl/mac.v` to Synthesis, and `synth/mac.sdc` as the timing constraint.
4. Add `Go_Board_Constraints.pcf` under Place & Route for pin assignments.
   `.sdc` is timing, `.pcf` is pins — two different files.
5. Run synthesis and place-and-route; read Fmax off the timing report.
6. Program with Diamond Programmer Standalone; the bitstream lands in
   `sbt/outputs/bitmap/`.

The HX1K has no DSP blocks, so the multiplier is built entirely from LUT4s
and carry chains. That is the interesting part, not a limitation.

### Synthesis — Artix-7 (Vivado)

No board required. Create a project targeting any Artix-7 part, add
`rtl/mac.v`, run synthesis and implementation, and read the utilisation and
timing reports. The multiply should infer a DSP48; confirm it did rather than
assuming — a LUT-built multiplier here means something went wrong.

## Results

### iCE40 HX1K, VQ100 — iCEcube2 2020.12, Synplify Pro, post-route

| Metric | Value |
|---|---|
| **Fmax** | **132.64 MHz** |
| Target (Go Board oscillator) | 25 MHz |
| Slack at 25 MHz | +32.46 ns |
| Logic cells | 227 / 1280 (17.7%) |
| &nbsp;&nbsp;combinational | 194 |
| &nbsp;&nbsp;sequential | 33 |
| LUT4s | 224 |
| Carry cells | 69 |
| Registers | 33 (32 accumulator + 1 sticky overflow) |
| Logic tiles (PLBs) | 46 / 160 (28.8%) |
| Block RAM | 0 / 16 |
| DSP blocks | none — the HX1K has no hard multipliers |
| I/O | 62 / 72 |

The multiplier is built entirely from LUT4s and carry chains, since this part
has no DSP blocks. At 25 MHz the design has 5.3x frequency headroom, so the
pipelined variant is not needed for this board — it remains an experiment
rather than a fix.

Synthesis-time estimate was 85.3 MHz and post-placement was 122.35 MHz, both
conservative against the 132.64 MHz post-route result. Quote the post-route
number; the earlier two are estimates against modelled routing.

### Critical path

```
acc_q[0]  ->  31-stage carry chain (the multiply-accumulate)
          ->  un1_product_2_cry_30_c_RNIDP2L2H   (SB_LUT4)
          ->  ovf_q_RNO_0                        (SB_LUT4)
          ->  ovf_q / D
```

| | ps |
|---|---|
| Clock-to-Q | 540 |
| Data path | 6628 |
| Setup | 372 |
| **Register-to-register total** | **7540** |

The path ends at the **overflow flag**, not at the accumulator. `acc_ovf`
compares the sign bits of `acc_q`, `product` and `sum`, so it cannot begin
evaluating until the entire carry chain has resolved, and then needs two more
LUT levels on top. `acc_q[31]` finishes with 1.8 ns more slack than `ovf_q`
does.

Three gates that look free in the source turn out to set Fmax, because they
sit downstream of everything else. A sticky flag does not need to be correct
in the same cycle it is raised, so registering `acc_ovf` and OR-ing it in one
cycle later would take this logic off the critical path entirely, at the cost
of the flag lagging by one cycle.

### Note on I/O

Exposing the full 32-bit `acc` as a top-level port consumes 62 of the 72
available pins and saturates three of the four I/O banks. That is fine for a
synthesis measurement, but a board-level wrapper driving the LEDs and
seven-segment display must keep `acc` internal.

## Next

A 4×4 systolic array — sixteen of these in a grid, operands flowing
left-to-right and weights top-to-bottom, which is how a matrix engine
actually works. `mac.v` is parameterised and drops in unchanged.

## Layout

```
rtl/mac.v          the design
tb/tb_mac.v        self-checking testbench (WIDTH=8)
tb/tb_param.v      parameter-sweep testbench (any WIDTH)
sim/Makefile       simulation driver
synth/mac.sdc      timing constraints
run.bat            Windows simulation script
run_param.bat      Windows parameter sweep
docs/              report, screenshots
```
