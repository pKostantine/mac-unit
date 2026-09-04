//=============================================================================
// mac.v -- fixed-point signed multiply-accumulate unit
//
// Verilog-2001 only. No SystemVerilog constructs, so this synthesises in
// iCEcube2 (LSE or Synplify Pro), Vivado, Quartus and Yosys unchanged.
//
//   acc <- acc + (a * b)     one MAC per clock while en is high
//
// Q-format note: the hardware is pure integer arithmetic. Q-format is an
// interpretation, not a circuit. With Q1.7 inputs the product is Q2.14 and
// the accumulator is Q18.14, so producing a Q1.7 output means shifting
// right by FRAC_BITS. FRAC_BITS therefore only feeds a shift -- changing it
// costs zero gates in the multiplier.
//
// TODO markers below are yours to fill in. Everything else is plumbing.
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
    localparam PROD_WIDTH = 2*WIDTH;                            // 16 for WIDTH=8
    localparam signed [WIDTH-1:0] RES_MAX = {1'b0, {(WIDTH-1){1'b1}}};  // +127
    localparam signed [WIDTH-1:0] RES_MIN = {1'b1, {(WIDTH-1){1'b0}}};  // -128

    //-------------------------------------------------------------------------
    // State
    //-------------------------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] acc_q;
    reg                        ovf_q;

    //=========================================================================
    // TODO 1 -- the multiply
    //
    // Signed WIDTH x signed WIDTH needs exactly 2*WIDTH bits. Convince
    // yourself: the extreme products of two signed 8-bit numbers are
    // -128*-128 = +16384 and -128*+127 = -16256, both inside signed 16 bits.
    //
    // Watch the signedness. If ANY operand in a Verilog expression is
    // unsigned, the whole expression evaluates unsigned and your sign
    // extension silently breaks. a and b are declared signed above -- keep
    // it that way and the tools do the right thing.
    //=========================================================================
    wire signed [PROD_WIDTH-1:0] product = a * b;  // TODO: replace with the product

    //=========================================================================
    // TODO 2 -- the accumulate
    //
    // Add product to acc_q. Both are declared signed, so the narrower one is
    // sign-extended automatically. You do not need to write the extension
    // by hand -- but check the waveform and make sure it happened.
    //=========================================================================
    wire signed [ACC_WIDTH-1:0] sum = acc_q + product;  // TODO: replace with acc_q + product

    //=========================================================================
    // TODO 3 -- accumulator overflow detection
    //
    // Signed addition overflows when both operands share a sign and the
    // result has the opposite sign. Two operands, one result, three sign
    // bits: acc_q[ACC_WIDTH-1], product[PROD_WIDTH-1], sum[ACC_WIDTH-1].
    //
    // Sanity check on the sizing while you are here: |product| <= 2^14 and
    // the accumulator holds up to 2^31, so this cannot fire until roughly
    // 2^17 = 131072 worst-case accumulations. That number is your headroom
    // and it belongs in the report.
    //=========================================================================
    wire acc_ovf = (acc_q[ACC_WIDTH-1] == product[PROD_WIDTH-1]) && (sum[ACC_WIDTH-1] != acc_q[ACC_WIDTH-1]);

    //=========================================================================
    // TODO 4 -- scale the accumulator back down to WIDTH bits
    //
    // Two steps:
    //   rounded : add half an LSB of the outgoing format before shifting.
    //             Plain truncation of two's complement always rounds toward
    //             -infinity, a -0.5 LSB DC bias that accumulates across a
    //             layer. Adding (1 << (FRAC_BITS-1)) first removes it.
    //   scaled  : arithmetic shift right by FRAC_BITS. Use >>> and make sure
    //             the operand is declared signed, or you will shift in zeros
    //             and turn negative numbers into large positive ones.
    //=========================================================================
    wire signed [ACC_WIDTH-1:0] rounded = acc_q + (1 <<< (FRAC_BITS-1));
    wire signed [ACC_WIDTH-1:0] scaled  = rounded >>> FRAC_BITS;

    //=========================================================================
    // TODO 5 -- does the scaled value fit in WIDTH bits?
    //
    // It fits exactly when every bit above the sign position is a copy of
    // the sign bit. Compare scaled[ACC_WIDTH-1:WIDTH-1] against all-zeros
    // and against all-ones; if it matches either, it is in range.
    //
    // Saturation matters: wrapping turns +1.2 into -0.8, a sign flip that
    // wrecks a network's output. Clamping merely loses a little magnitude.
    // Every production DSP datapath saturates.
    //=========================================================================
    wire in_range = (scaled[ACC_WIDTH-1:WIDTH-1] == {(ACC_WIDTH-WIDTH+1){1'b0}}) ||
                    (scaled[ACC_WIDTH-1:WIDTH-1] == {(ACC_WIDTH-WIDTH+1){1'b1}});

    //=========================================================================
    // TODO 6 -- the register
    //
    // Reset branch is done. Fill in clear and en.
    //   clear : zero acc_q AND clear the sticky overflow flag
    //   en    : latch sum, and OR acc_ovf into the sticky flag
    // Note the priority order the testbench expects: reset > clear > en.
    // If neither clear nor en is asserted, acc_q must hold its value --
    // that is what "en low holds accumulator" checks, and it is the branch
    // people forget.
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_q <= {ACC_WIDTH{1'b0}};
            ovf_q <= 1'b0;
        end
        // TODO: clear branch
        // TODO: en branch
	else if (clear) begin
    acc_q <= {ACC_WIDTH{1'b0}};
    ovf_q <= 1'b0;
end
else if (en) begin
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
