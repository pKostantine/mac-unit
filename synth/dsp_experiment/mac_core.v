//=============================================================================
// mac_core.v -- experiment: the bare multiply-accumulate datapath, stripped of
// everything a DSP48E1 cannot swallow.
//
// No overflow detection (it reads the adder output before the register, which
// forces the adder back into fabric), no rounding, no saturation, no async
// reset. What is left is exactly the DSP48E1's accumulate mode: P <- P + A*B.
//
// This is the lower bound on what the MAC costs on Artix-7. The gap between
// this and rtl/mac.v is the price of the overflow, rounding and saturation
// logic -- which is most of the design.
//=============================================================================
`timescale 1ns / 1ps
`default_nettype none

(* use_dsp = "yes" *)
module mac_core #(
    parameter WIDTH     = 8,
    parameter ACC_WIDTH = 32
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        clear,
    input  wire                        en,
    input  wire signed [WIDTH-1:0]     a,
    input  wire signed [WIDTH-1:0]     b,
    output wire signed [ACC_WIDTH-1:0] acc
);

    reg signed [ACC_WIDTH-1:0] acc_q;

    wire signed [2*WIDTH-1:0] product = a * b;

    always @(posedge clk) begin
        if (!rst_n || clear) acc_q <= {ACC_WIDTH{1'b0}};
        else if (en)         acc_q <= acc_q + product;
    end

    assign acc = acc_q;

endmodule

`default_nettype wire
