//=============================================================================
// mac.v -- parameterised signed fixed-point multiply-accumulate unit
//
//   acc <- acc + (a * b)      one MAC per clock while en is asserted
//
// The multiply-accumulate is the atomic operation of neural network
// inference: dense layers, convolutions and matrix multiplies are all dot
// products, and a dot product is a sequence of MACs.
//
// Verilog-2001 only -- no SystemVerilog constructs -- so this synthesises
// unchanged in iCEcube2 (LSE or Synplify Pro), Vivado, Quartus and Yosys.
//
// Measured on iCE40HX1K-VQ100 (iCEcube2 2020.12 / Synplify Pro, post-route):
//   132.64 MHz, 227/1280 logic cells, 224 LUT4s, 69 carry cells, 33 registers.
//   That part has no DSP blocks, so the multiplier is built entirely from
//   LUT4s and carry chains.
//
// Measured on Artix-7 XC7A35T-1L (Vivado 2026.1, post-route):
//   289.0 MHz, 146 LUTs, 33 FFs, 35 CARRY4s -- and zero DSP48E1s. Vivado
//   declines the hard multiplier here even when asked directly: the async
//   reset below cannot live inside a DSP48E1, and acc_ovf reads the adder
//   output before the register, which is not a node that exists inside one.
//   See the Artix-7 section of README.md for the full measurement.
//
// Verified by tb/tb_mac.v (16 directed and randomised tests, ~150k checks)
// and by tb/tb_param.v at WIDTH/ACC_WIDTH/FRAC_BITS of 8/32/7, 4/16/3,
// 6/24/5 and 12/40/9.
//=============================================================================
`timescale 1ns / 1ps
`default_nettype none

module mac #(
    parameter WIDTH     = 8,    // operand width, signed
    parameter ACC_WIDTH = 32,   // accumulator width, signed
    parameter FRAC_BITS = 7     // fractional bits in each operand (Q1.7)
) (
    input  wire                        clk,
    input  wire                        rst_n,     // async assert, active low
    input  wire                        clear,     // zero the accumulator
    input  wire                        en,        // accumulate this cycle
    input  wire signed [WIDTH-1:0]     a,
    input  wire signed [WIDTH-1:0]     b,
    output wire signed [ACC_WIDTH-1:0] acc,       // full-precision accumulator
    output wire signed [WIDTH-1:0]     result,    // scaled + saturated output
    output wire                        overflow,  // sticky: accumulator overflowed
    output wire                        sat        // combinational: result is clamped
);

    //-------------------------------------------------------------------------
    // Derived constants
    //-------------------------------------------------------------------------
    localparam PROD_WIDTH = 2*WIDTH;                                    // 16 at WIDTH=8
    localparam signed [WIDTH-1:0] RES_MAX = {1'b0, {(WIDTH-1){1'b1}}};  // +127
    localparam signed [WIDTH-1:0] RES_MIN = {1'b1, {(WIDTH-1){1'b0}}};  // -128

    //-------------------------------------------------------------------------
    // State
    //-------------------------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] acc_q;
    reg                        ovf_q;

    //-------------------------------------------------------------------------
    // Multiply
    //
    // Signed WIDTH x signed WIDTH needs exactly 2*WIDTH bits: for 8-bit
    // operands the extreme products are -128 * -128 = +16384 and
    // -128 * +127 = -16256, both inside signed 16-bit range.
    //
    // Every operand here is declared signed. That matters: if any operand in
    // a Verilog expression is unsigned, the whole expression is evaluated as
    // unsigned and sign extension silently breaks, turning -2 into 254.
    //-------------------------------------------------------------------------
    wire signed [PROD_WIDTH-1:0] product = a * b;

    //-------------------------------------------------------------------------
    // Accumulate
    //
    // Both operands are signed, so the narrower one is sign-extended
    // automatically rather than by hand.
    //-------------------------------------------------------------------------
    wire signed [ACC_WIDTH-1:0] sum = acc_q + product;

    //-------------------------------------------------------------------------
    // Accumulator overflow detection
    //
    // Signed addition can only overflow when both operands share a sign, and
    // when it does the result carries the opposite sign. Adding numbers of
    // opposite sign always lands between them and cannot overflow.
    //
    // Sizing: |product| <= 2^(2*WIDTH-2) and the accumulator holds
    // 2^(ACC_WIDTH-1), so at the default parameters this cannot fire until
    // 2^31 / 2^14 = 2^17 = 131,072 worst-case accumulations. The 16 bits
    // above the product width are the guard band; a 1024-input dense layer
    // uses 1024 MACs, so there is 128x headroom.
    //
    // Note from synthesis: this logic sits on the critical path. It cannot
    // begin evaluating until the whole carry chain has resolved, then needs
    // two more LUT levels, so it finishes 1.8 ns after acc_q[31] does.
    // Registering acc_ovf and OR-ing it in a cycle later would remove it
    // from the critical path -- a sticky flag need not be correct in the
    // cycle it is raised.
    //-------------------------------------------------------------------------
    wire acc_ovf = (acc_q[ACC_WIDTH-1] == product[PROD_WIDTH-1]) &&
                   (sum[ACC_WIDTH-1]   != acc_q[ACC_WIDTH-1]);

    //-------------------------------------------------------------------------
    // Scale the accumulator back down to WIDTH bits
    //
    // Q-format is an interpretation, not a circuit -- the multiplier is
    // bit-identical whatever FRAC_BITS is set to. With Q1.7 inputs the
    // product is Q2.14 and the accumulator is Q18.14, so emitting a Q1.7
    // result means an arithmetic shift right by FRAC_BITS.
    //
    // The rounding term matters. Truncating a two's-complement value always
    // rounds toward minus infinity, a constant -0.5 LSB bias that accumulates
    // across a layer; adding half an LSB first makes it round to nearest.
    //-------------------------------------------------------------------------
    wire signed [ACC_WIDTH-1:0] rounded = acc_q + (1 <<< (FRAC_BITS-1));
    wire signed [ACC_WIDTH-1:0] scaled  = rounded >>> FRAC_BITS;

    //-------------------------------------------------------------------------
    // Range check for saturation
    //
    // A value fits in WIDTH signed bits exactly when every bit above the sign
    // position is a copy of the sign bit -- so the slice from the top down to
    // the sign position must be all zeros or all ones.
    //
    // Saturating rather than wrapping is not cosmetic. Wrapping turns +1.2
    // into -0.8, a sign flip that wrecks a network's output; clamping merely
    // loses magnitude. Every production DSP datapath saturates.
    //-------------------------------------------------------------------------
    wire in_range = (scaled[ACC_WIDTH-1:WIDTH-1] == {(ACC_WIDTH-WIDTH+1){1'b0}}) ||
                    (scaled[ACC_WIDTH-1:WIDTH-1] == {(ACC_WIDTH-WIDTH+1){1'b1}});

    //-------------------------------------------------------------------------
    // Accumulator register
    //
    // Priority is reset > clear > accumulate. Clear must outrank en so that a
    // running accumulator can be zeroed without first being stalled.
    //
    // When neither clear nor en is asserted the block assigns nothing, which
    // is what makes acc_q hold. Writing "acc_q <= acc_q" in an else branch
    // would describe the same hardware but obscure the intent.
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_q <= {ACC_WIDTH{1'b0}};
            ovf_q <= 1'b0;
        end else if (clear) begin
            acc_q <= {ACC_WIDTH{1'b0}};
            ovf_q <= 1'b0;
        end else if (en) begin
            acc_q <= sum;
            ovf_q <= ovf_q | acc_ovf;
        end
    end

    //-------------------------------------------------------------------------
    // Outputs
    //-------------------------------------------------------------------------
    assign acc      = acc_q;
    assign overflow = ovf_q;
    assign sat      = ~in_range;
    assign result   = in_range ? scaled[WIDTH-1:0]
                               : (scaled[ACC_WIDTH-1] ? RES_MIN : RES_MAX);

endmodule

`default_nettype wire
