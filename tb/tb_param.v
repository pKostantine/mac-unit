//=============================================================================
// tb_param.v -- proves the design is actually parameterised.
//
// tb_mac.v is the thorough testbench, but it is pinned to WIDTH=8. This one
// is deliberately simpler -- randomised operands, no directed corner cases --
// but it runs at ANY parameter set, so it catches hardcoded widths and shift
// amounts that tb_mac.v cannot see.
//
//   iverilog -g2001 -o p.vvp tb/tb_param.v rtl/mac.v && vvp p.vvp
//   iverilog -g2001 -DW=4 -DAW=16 -DFB=3 -o p.vvp tb/tb_param.v rtl/mac.v
//=============================================================================
`timescale 1ns / 1ps

`ifndef W
  `define W 8
`endif
`ifndef AW
  `define AW 32
`endif
`ifndef FB
  `define FB 7
`endif

module tb_param;

    localparam WIDTH     = `W;
    localparam ACC_WIDTH = `AW;
    localparam FRAC_BITS = `FB;

    localparam signed [63:0] RES_MAX =  (64'sd1 <<< (WIDTH-1)) - 64'sd1;
    localparam signed [63:0] RES_MIN = -(64'sd1 <<< (WIDTH-1));

    // Accumulations per burst. Worst-case |product| is 2^(2*WIDTH-2) and the
    // accumulator holds 2^(ACC_WIDTH-1), so anything below
    // 2^(ACC_WIDTH-2*WIDTH+1) cannot overflow. 200 is comfortably under that
    // for every configuration tested here.
    localparam BURST = 200;

    reg                         clk = 0, rst_n = 0, clear = 0, en = 0;
    reg  signed [WIDTH-1:0]     a = 0, b = 0;
    wire signed [ACC_WIDTH-1:0] acc;
    wire signed [WIDTH-1:0]     result;
    wire                        overflow, sat;

    mac #(.WIDTH(WIDTH), .ACC_WIDTH(ACC_WIDTH), .FRAC_BITS(FRAC_BITS)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .en(en), .a(a), .b(b),
        .acc(acc), .result(result), .overflow(overflow), .sat(sat)
    );

    always #5 clk = ~clk;

    reg signed [63:0] ref_acc;
    integer errors = 0, checks = 0, i, j;
    reg signed [WIDTH-1:0] ra, rb;

    function signed [63:0] exp_result;
        input signed [63:0] v;
        reg signed [63:0] r;
        begin
            r = (v + (64'sd1 <<< (FRAC_BITS-1))) >>> FRAC_BITS;
            if      (r > RES_MAX) exp_result = RES_MAX;
            else if (r < RES_MIN) exp_result = RES_MIN;
            else                  exp_result = r;
        end
    endfunction

    function exp_sat;
        input signed [63:0] v;
        reg signed [63:0] r;
        begin
            r = (v + (64'sd1 <<< (FRAC_BITS-1))) >>> FRAC_BITS;
            exp_sat = (r > RES_MAX) || (r < RES_MIN);
        end
    endfunction

    task check;
        reg signed [63:0] er;
        begin
            checks = checks + 1;
            er = exp_result(ref_acc);
            if (acc !== ref_acc[ACC_WIDTH-1:0]) begin
                errors = errors + 1;
                if (errors <= 8)
                    $display("   acc    mismatch: got %0d expected %0d",
                             acc, $signed(ref_acc[ACC_WIDTH-1:0]));
            end
            if (result !== er[WIDTH-1:0]) begin
                errors = errors + 1;
                if (errors <= 8)
                    $display("   result mismatch: got %0d expected %0d  (acc=%0d)",
                             result, $signed(er[WIDTH-1:0]), acc);
            end
            if (sat !== exp_sat(ref_acc)) begin
                errors = errors + 1;
                if (errors <= 8)
                    $display("   sat    mismatch: got %0b expected %0b  (acc=%0d)",
                             sat, exp_sat(ref_acc), acc);
            end
        end
    endtask

    initial begin
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1; @(posedge clk);
        ref_acc = 0;

        for (j = 0; j < 25; j = j + 1) begin
            en = 0; clear = 1; @(posedge clk); #1;
            ref_acc = 0; check();
            clear = 0;
            for (i = 0; i < BURST; i = i + 1) begin
                ra = $random; rb = $random;
                a = ra; b = rb; en = 1;
                @(posedge clk); #1;
                ref_acc = ref_acc + ($signed(ra) * $signed(rb));
                check();
            end
        end

        $display("  W=%0d ACC=%0d FRAC=%0d : %0d checks, %0d errors  -> %0s",
                 WIDTH, ACC_WIDTH, FRAC_BITS, checks, errors,
                 errors == 0 ? "PASS" : "FAIL");
        $finish;
    end

endmodule
