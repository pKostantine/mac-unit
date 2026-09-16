//=============================================================================
// mac_ovf_reg.v -- experiment: does deferring overflow detection by one cycle
// actually take it off the critical path?
//
// rtl/mac.v computes acc_ovf from `sum`, the adder output BEFORE the register.
// That makes the flag's arrival time depend on the entire 32-bit carry chain
// plus two more LUT levels, and it is what sets Fmax on both target devices.
//
// Simply registering acc_ovf does NOT fix this: the carry chain is still in
// the path, only the destination flop changes. The fix has to remove the
// dependency on `sum` entirely.
//
// This variant does that. It latches the two operand signs at the same edge
// the accumulator updates, and performs the comparison one cycle later against
// the REGISTERED accumulator:
//
//   at edge N:      acc_q      <- acc_q + product      (= sum_N)
//                   sign_acc_q <- acc_q[MSB]           (pre-add sign)
//                   sign_prd_q <- product[MSB]
//
//   after edge N:   acc_q holds sum_N, so the standard signed-overflow test
//                   (sign_acc_q == sign_prd_q) && (acc_q[MSB] != sign_acc_q)
//                   is exactly the overflow condition for operation N, and
//                   every term is a flip-flop output.
//
// The resulting path is flop -> one small LUT -> flop. The carry chain is gone
// from the overflow path; whether that raises Fmax, and by how much, is the
// number this file exists to produce.
//
// FUNCTIONAL DIFFERENCE: `overflow` now asserts one cycle after the operation
// that caused it, rather than in the same cycle. For a sticky flag that is
// acceptable, but it is a real interface change -- tb/tb_mac.v checks overflow
// timing and will report failures against this variant. This is a
// synthesis-only measurement, not a drop-in replacement for rtl/mac.v.
//
// Everything else -- async reset, rounding, saturation, parameters -- is
// identical to rtl/mac.v so the Fmax comparison is like for like.
//=============================================================================
`timescale 1ns / 1ps
`default_nettype none

module mac_ovf_reg #(
    parameter WIDTH     = 8,
    parameter ACC_WIDTH = 32,
    parameter FRAC_BITS = 7
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        clear,
    input  wire                        en,
    input  wire signed [WIDTH-1:0]     a,
    input  wire signed [WIDTH-1:0]     b,
    output wire signed [ACC_WIDTH-1:0] acc,
    output wire signed [WIDTH-1:0]     result,
    output wire                        overflow,
    output wire                        sat
);

    localparam PROD_WIDTH = 2*WIDTH;
    localparam signed [WIDTH-1:0] RES_MAX = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] RES_MIN = {1'b1, {(WIDTH-1){1'b0}}};

    reg signed [ACC_WIDTH-1:0] acc_q;
    reg                        ovf_q;
    reg                        sign_acc_q;   // accumulator sign before the add
    reg                        sign_prd_q;   // product sign

    wire signed [PROD_WIDTH-1:0] product = a * b;
    wire signed [ACC_WIDTH-1:0]  sum     = acc_q + product;

    // Overflow test on registered values only. No dependency on `sum`.
    wire ovf_detect = (sign_acc_q == sign_prd_q) &&
                      (acc_q[ACC_WIDTH-1] != sign_acc_q);

    wire signed [ACC_WIDTH-1:0] rounded = acc_q + (1 <<< (FRAC_BITS-1));
    wire signed [ACC_WIDTH-1:0] scaled  = rounded >>> FRAC_BITS;

    wire in_range = (scaled[ACC_WIDTH-1:WIDTH-1] == {(ACC_WIDTH-WIDTH+1){1'b0}}) ||
                    (scaled[ACC_WIDTH-1:WIDTH-1] == {(ACC_WIDTH-WIDTH+1){1'b1}});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_q      <= {ACC_WIDTH{1'b0}};
            ovf_q      <= 1'b0;
            sign_acc_q <= 1'b0;
            sign_prd_q <= 1'b0;
        end else if (clear) begin
            acc_q      <= {ACC_WIDTH{1'b0}};
            ovf_q      <= 1'b0;
            sign_acc_q <= 1'b0;
            sign_prd_q <= 1'b0;
        end else begin
            // ovf_q updates unconditionally so that an overflow on the final
            // enabled cycle is still captured after en deasserts. While en is
            // low the detect term is stable, so re-OR-ing it is harmless.
            ovf_q <= ovf_q | ovf_detect;
            if (en) begin
                acc_q      <= sum;
                sign_acc_q <= acc_q[ACC_WIDTH-1];
                sign_prd_q <= product[PROD_WIDTH-1];
            end
        end
    end

    assign acc      = acc_q;
    assign overflow = ovf_q;
    assign sat      = ~in_range;
    assign result   = in_range ? scaled[WIDTH-1:0]
                               : (scaled[ACC_WIDTH-1] ? RES_MIN : RES_MAX);

endmodule

`default_nettype wire
