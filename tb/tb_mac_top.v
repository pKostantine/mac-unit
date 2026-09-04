//=============================================================================
// tb_mac_top.v -- exercise the Go Board wrapper before burning a bitstream.
//
// Presses the step button through the whole operand ROM and checks the
// displayed byte, the segment patterns, and the status LEDs against
// hand-computed expected values.
//
//   iverilog -g2001 -o t.vvp tb/tb_mac_top.v rtl/mac_top.v rtl/mac.v \
//            rtl/debounce.v rtl/hex7seg.v && vvp t.vvp
//=============================================================================
`timescale 1ns / 1ps

module tb_mac_top;

    localparam DB = 4;      // tiny debounce so the sim finishes quickly

    reg clk = 1'b0;
    reg sw1 = 1'b0, sw2 = 1'b0, sw3 = 1'b0, sw4 = 1'b0;

    wire led1, led2, led3, led4;
    wire s1a,s1b,s1c,s1d,s1e,s1f,s1g;
    wire s2a,s2b,s2c,s2d,s2e,s2f,s2g;

    mac_top #(.DEBOUNCE_LIMIT(DB), .HEARTBEAT_BIT(5)) dut (
        .i_Clk(clk),
        .i_Switch_1(sw1), .i_Switch_2(sw2), .i_Switch_3(sw3), .i_Switch_4(sw4),
        .o_LED_1(led1), .o_LED_2(led2), .o_LED_3(led3), .o_LED_4(led4),
        .o_Segment1_A(s1a), .o_Segment1_B(s1b), .o_Segment1_C(s1c),
        .o_Segment1_D(s1d), .o_Segment1_E(s1e), .o_Segment1_F(s1f),
        .o_Segment1_G(s1g),
        .o_Segment2_A(s2a), .o_Segment2_B(s2b), .o_Segment2_C(s2c),
        .o_Segment2_D(s2d), .o_Segment2_E(s2e), .o_Segment2_F(s2f),
        .o_Segment2_G(s2g)
    );

    always #5 clk = ~clk;

    integer errors = 0, checks = 0;

    // Independent copy of the decoder -- a golden model, not a shortcut.
    function [6:0] seg_of;
        input [3:0] n;
        begin
            case (n)
                4'h0: seg_of = 7'b1111110;  4'h1: seg_of = 7'b0110000;
                4'h2: seg_of = 7'b1101101;  4'h3: seg_of = 7'b1111001;
                4'h4: seg_of = 7'b0110011;  4'h5: seg_of = 7'b1011011;
                4'h6: seg_of = 7'b1011111;  4'h7: seg_of = 7'b1110000;
                4'h8: seg_of = 7'b1111111;  4'h9: seg_of = 7'b1111011;
                4'hA: seg_of = 7'b1110111;  4'hB: seg_of = 7'b0011111;
                4'hC: seg_of = 7'b1001110;  4'hD: seg_of = 7'b0111101;
                4'hE: seg_of = 7'b1001111;  4'hF: seg_of = 7'b1000111;
                default: seg_of = 7'b0000000;
            endcase
        end
    endfunction

    task press1; begin
        sw1 = 1'b1; repeat (DB+5) @(posedge clk);
        sw1 = 1'b0; repeat (DB+5) @(posedge clk);
    end endtask

    task press2; begin
        sw2 = 1'b1; repeat (DB+5) @(posedge clk);
        sw2 = 1'b0; repeat (DB+5) @(posedge clk);
    end endtask

    task do_reset; begin
        sw3 = 1'b1; repeat (DB+5) @(posedge clk);
        sw3 = 1'b0; repeat (DB+5) @(posedge clk);
    end endtask

    task check_state;
        input [8*10:1] label;
        input signed [7:0] exp_result;
        input exp_sat;
        input exp_ovf;
        reg [6:0] want_hi, want_lo;
        begin
            checks = checks + 1;
            want_hi = ~seg_of(exp_result[7:4]);   // active low on this board
            want_lo = ~seg_of(exp_result[3:0]);

            if (dut.result !== exp_result) begin
                errors = errors + 1;
                $display("  ERROR %0s: result = %0d (0x%02h), expected %0d (0x%02h)",
                         label, dut.result, dut.result, exp_result, exp_result);
            end
            if (led1 !== exp_sat) begin
                errors = errors + 1;
                $display("  ERROR %0s: sat LED = %b, expected %b", label, led1, exp_sat);
            end
            if (led2 !== exp_ovf) begin
                errors = errors + 1;
                $display("  ERROR %0s: overflow LED = %b, expected %b", label, led2, exp_ovf);
            end
            if ({s1a,s1b,s1c,s1d,s1e,s1f,s1g} !== want_hi) begin
                errors = errors + 1;
                $display("  ERROR %0s: Segment1 = %b, expected %b",
                         label, {s1a,s1b,s1c,s1d,s1e,s1f,s1g}, want_hi);
            end
            if ({s2a,s2b,s2c,s2d,s2e,s2f,s2g} !== want_lo) begin
                errors = errors + 1;
                $display("  ERROR %0s: Segment2 = %b, expected %b",
                         label, {s2a,s2b,s2c,s2d,s2e,s2f,s2g}, want_lo);
            end

            $display("   %-10s  display = %02h   acc = %0d   sat=%b ovf=%b wrap=%b",
                     label, dut.result, dut.acc, led1, led2, led3);
        end
    endtask

    initial begin
        $dumpfile("dump_top.vcd");
        $dumpvars(0, tb_mac_top);

        $display("");
        $display("  Go Board wrapper -- stepping through the operand ROM");
        $display("  ------------------------------------------------------------");

        do_reset();
        check_state("reset",   8'sd0,    1'b0, 1'b0);

        press1(); check_state("step 0",  8'sd32,   1'b0, 1'b0);  // 0.25
        press1(); check_state("step 1",  8'sd64,   1'b0, 1'b0);  // 0.50
        press1(); check_state("step 2",  8'sd96,   1'b0, 1'b0);  // 0.75
        press1(); check_state("step 3",  8'sd127,  1'b1, 1'b0);  // clamps
        press1(); check_state("step 4",  8'sd65,   1'b0, 1'b0);  // back in range
        press1(); check_state("step 5", -8'sd62,   1'b0, 1'b0);  // negative
        press1(); check_state("step 6", -8'sd128,  1'b1, 1'b0);  // clamps low
        press1(); check_state("step 7", -8'sd128,  1'b1, 1'b0);  // zero operands

        if (led3 !== 1'b1) begin
            errors = errors + 1;
            $display("  ERROR: wrap LED should be set after 8 steps");
        end

        press2(); check_state("clear",   8'sd0,    1'b0, 1'b0);
        if (led3 !== 1'b0) begin
            errors = errors + 1;
            $display("  ERROR: clear should reset the wrap LED");
        end

        // Switch 4 shows acc[7:0] instead of result.
        press1();
        sw4 = 1'b1; repeat (DB+5) @(posedge clk);
        if ({s2a,s2b,s2c,s2d,s2e,s2f,s2g} !== ~seg_of(dut.acc[3:0])) begin
            errors = errors + 1;
            $display("  ERROR: Switch 4 did not switch the display to acc");
        end
        checks = checks + 1;
        $display("   sw4 held   display = acc[7:0] = %02h", dut.acc[7:0]);

        $display("  ------------------------------------------------------------");
        $display("   checks: %0d   errors: %0d   -> %0s",
                 checks, errors, errors == 0 ? "PASS" : "FAIL");
        $display("");
        $finish;
    end

    initial begin
        #500000;
        $display("  *** TIMEOUT ***");
        $finish;
    end

endmodule
