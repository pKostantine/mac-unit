//=============================================================================
// mac_dsp.v -- experiment: does the full MAC unit map to an Artix-7 DSP48E1
// if the only Xilinx-hostile construct is removed?
//
// Identical to rtl/mac.v except:
//   1. (* use_dsp = "yes" *) asks Vivado to try the DSP block.
//   2. The reset is SYNCHRONOUS. The DSP48E1 has no asynchronous reset path
//      on any of its internal registers, so a register with "posedge clk or
//      negedge rst_n" can never be absorbed into one -- it is stuck in
//      fabric no matter what use_dsp says.
//
// This file is not part of the design. It exists to produce one number for
// the README's Artix-7 section.
//=============================================================================
`timescale 1ns / 1ps
`default_nettype none

(* use_dsp = "yes" *)
module mac_dsp #(
    parameter WIDTH     = 8,
    parameter ACC_WIDTH = 32,
    parameter FRAC_BITS = 7
) (
    input  wire                        clk,
    input  wire                        rst_n,     // SYNCHRONOUS here
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

    wire signed [PROD_WIDTH-1:0] product = a * b;
    wire signed [ACC_WIDTH-1:0]  sum     = acc_q + product;

    wire acc_ovf = (acc_q[ACC_WIDTH-1] == product[PROD_WIDTH-1]) &&
                   (sum[ACC_WIDTH-1]   != acc_q[ACC_WIDTH-1]);

    wire signed [ACC_WIDTH-1:0] rounded = acc_q + (1 <<< (FRAC_BITS-1));
    wire signed [ACC_WIDTH-1:0] scaled  = rounded >>> FRAC_BITS;

    wire in_range = (scaled[ACC_WIDTH-1:WIDTH-1] == {(ACC_WIDTH-WIDTH+1){1'b0}}) ||
                    (scaled[ACC_WIDTH-1:WIDTH-1] == {(ACC_WIDTH-WIDTH+1){1'b1}});

    // Synchronous reset -- the one change that matters for DSP inference.
    always @(posedge clk) begin
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

    assign acc      = acc_q;
    assign overflow = ovf_q;
    assign sat      = ~in_range;
    assign result   = in_range ? scaled[WIDTH-1:0]
                               : (scaled[ACC_WIDTH-1] ? RES_MIN : RES_MAX);

endmodule

`default_nettype wire
