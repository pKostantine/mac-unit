//=============================================================================
// tb_mac.v -- self-checking testbench for the fixed-point MAC unit
//
// Structure (these are the pieces UVM formalises; here they are plain Verilog):
//   * stimulus     -- do_cycle() drives one clock's worth of inputs
//   * golden model -- ref_acc, computed in 64 bits so the model itself can
//                     never overflow and can always be trusted
//   * scoreboard   -- check() compares DUT vs model and counts errors
//   * verdict      -- a single PASSED / FAILED line at the end
//
// Run:  iverilog -o sim.vvp tb/tb_mac.v rtl/mac.v && vvp sim.vvp
//=============================================================================
`timescale 1ns / 1ps

module tb_mac;

    //-------------------------------------------------------------------------
    // Parameters -- must match the DUT instantiation below
    //-------------------------------------------------------------------------
    localparam WIDTH     = 8;
    localparam ACC_WIDTH = 32;
    localparam FRAC_BITS = 7;

    localparam signed [63:0] ACC_MAX =  (64'sd1 <<< (ACC_WIDTH-1)) - 64'sd1;
    localparam signed [63:0] ACC_MIN = -(64'sd1 <<< (ACC_WIDTH-1));
    localparam signed [63:0] RES_MAX =  (64'sd1 <<< (WIDTH-1)) - 64'sd1;
    localparam signed [63:0] RES_MIN = -(64'sd1 <<< (WIDTH-1));

    //-------------------------------------------------------------------------
    // DUT interface
    //-------------------------------------------------------------------------
    reg                         clk = 1'b0;
    reg                         rst_n = 1'b0;
    reg                         clear = 1'b0;
    reg                         en = 1'b0;
    reg  signed [WIDTH-1:0]     a = 0;
    reg  signed [WIDTH-1:0]     b = 0;

    wire signed [ACC_WIDTH-1:0] acc;
    wire signed [WIDTH-1:0]     result;
    wire                        overflow;
    wire                        sat;

    mac #(
        .WIDTH     (WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .FRAC_BITS (FRAC_BITS)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear),
        .en       (en),
        .a        (a),
        .b        (b),
        .acc      (acc),
        .result   (result),
        .overflow (overflow),
        .sat      (sat)
    );

    always #5 clk = ~clk;              // 100 MHz

    //-------------------------------------------------------------------------
    // Golden reference model -- 64 bits wide, so it is always exact
    //-------------------------------------------------------------------------
    reg signed [63:0] ref_acc;
    reg               ref_ovf;

    integer errors;
    integer checks;
    integer errors_at_start;
    reg [8*40:1] test_name;

    // Cap console spam: an empty skeleton fails every check, and you do not
    // want half a million lines scrolling past on your first run.
    localparam MAX_ERR_PRINT = 25;
    reg suppressed = 1'b0;

    task note_error;
        begin
            errors = errors + 1;
            if (errors == MAX_ERR_PRINT + 1 && !suppressed) begin
                suppressed = 1'b1;
                $display("  ... further per-check errors suppressed; see the summary below");
            end
        end
    endtask

    // Expected result output, derived from ref_acc:
    //   round-to-nearest, arithmetic shift down by FRAC_BITS, then saturate.
    function signed [63:0] expected_result;
        input signed [63:0] acc_in;
        reg signed [63:0] r;
        begin
            r = (acc_in + (64'sd1 <<< (FRAC_BITS-1))) >>> FRAC_BITS;
            if      (r > RES_MAX) expected_result = RES_MAX;
            else if (r < RES_MIN) expected_result = RES_MIN;
            else                  expected_result = r;
        end
    endfunction

    function expected_sat;
        input signed [63:0] acc_in;
        reg signed [63:0] r;
        begin
            r = (acc_in + (64'sd1 <<< (FRAC_BITS-1))) >>> FRAC_BITS;
            expected_sat = (r > RES_MAX) || (r < RES_MIN);
        end
    endfunction

    //-------------------------------------------------------------------------
    // Scoreboard
    //-------------------------------------------------------------------------
    task check;
        reg signed [63:0] exp_res;
        reg               exp_sat;
        begin
            checks = checks + 1;

            // Accumulator: the model is 64-bit, the DUT is ACC_WIDTH-bit.
            // Two's complement addition wraps identically, so the low
            // ACC_WIDTH bits must match even when the true sum overflows.
            if (acc !== ref_acc[ACC_WIDTH-1:0]) begin
                note_error();
                if (errors <= MAX_ERR_PRINT)
                    $display("  ERROR @%0t [%0s] acc: got %0d (0x%h), expected %0d",
                             $time, test_name, acc, acc, $signed(ref_acc[ACC_WIDTH-1:0]));
            end

            exp_res = expected_result($signed(ref_acc[ACC_WIDTH-1:0]));
            if (result !== exp_res[WIDTH-1:0]) begin
                note_error();
                if (errors <= MAX_ERR_PRINT)
                    $display("  ERROR @%0t [%0s] result: got %0d, expected %0d",
                             $time, test_name, result, $signed(exp_res[WIDTH-1:0]));
            end

            exp_sat = expected_sat($signed(ref_acc[ACC_WIDTH-1:0]));
            if (sat !== exp_sat) begin
                note_error();
                if (errors <= MAX_ERR_PRINT)
                    $display("  ERROR @%0t [%0s] sat: got %0b, expected %0b",
                             $time, test_name, sat, exp_sat);
            end

            if (overflow !== ref_ovf) begin
                note_error();
                if (errors <= MAX_ERR_PRINT)
                    $display("  ERROR @%0t [%0s] overflow: got %0b, expected %0b",
                             $time, test_name, overflow, ref_ovf);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Stimulus driver: one clock cycle, model update, then compare
    //-------------------------------------------------------------------------
    task do_cycle;
        input signed [WIDTH-1:0] ta;
        input signed [WIDTH-1:0] tb;
        input                    ten;
        input                    tclear;
        reg signed [63:0] prod;
        reg signed [63:0] next;
        begin
            a     = ta;
            b     = tb;
            en    = ten;
            clear = tclear;

            @(posedge clk);

            if (tclear) begin
                ref_acc = 64'sd0;
                ref_ovf = 1'b0;
            end else if (ten) begin
                prod = $signed(ta) * $signed(tb);
                next = ref_acc + prod;
                if (next > ACC_MAX || next < ACC_MIN) ref_ovf = 1'b1;
                ref_acc = next;
            end

            #1 check();
        end
    endtask

    task do_clear;
        begin
            do_cycle(0, 0, 1'b0, 1'b1);
        end
    endtask

    //-------------------------------------------------------------------------
    // Per-test bookkeeping
    //-------------------------------------------------------------------------
    task begin_test;
        input [8*40:1] name;
        begin
            test_name       = name;
            errors_at_start = errors;
        end
    endtask

    task end_test;
        begin
            if (errors == errors_at_start)
                $display("  [PASS] %0s", test_name);
            else
                $display("  [FAIL] %0s  (%0d errors)", test_name,
                         errors - errors_at_start);
        end
    endtask

    //-------------------------------------------------------------------------
    // Tests
    //-------------------------------------------------------------------------
    integer i;
    reg signed [WIDTH-1:0] ra, rb;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_mac);

        errors  = 0;
        checks  = 0;
        ref_acc = 0;
        ref_ovf = 0;

        $display("");
        $display("==================================================");
        $display(" MAC unit testbench");
        $display(" WIDTH=%0d  ACC_WIDTH=%0d  FRAC_BITS=%0d", WIDTH, ACC_WIDTH, FRAC_BITS);
        $display("==================================================");

        // ---- reset -----------------------------------------------------
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        begin_test("reset clears accumulator");
        if (acc !== 0)      begin note_error(); $display("  ERROR acc not 0 during reset"); end
        if (overflow !== 0) begin note_error(); $display("  ERROR overflow not 0 during reset"); end
        end_test();
        rst_n = 1'b1;
        @(posedge clk);

        // ---- directed: identities --------------------------------------
        begin_test("multiply by zero");
        do_clear();
        do_cycle(8'sd0,   8'sd100, 1'b1, 1'b0);
        do_cycle(8'sd100, 8'sd0,   1'b1, 1'b0);
        end_test();

        begin_test("multiply by one");
        do_clear();
        do_cycle(8'sd1,  8'sd42,  1'b1, 1'b0);
        do_cycle(8'sd1,  -8'sd42, 1'b1, 1'b0);
        end_test();

        // ---- directed: the signed corners ------------------------------
        // -128 * -128 = +16384 : max positive product from two max-negative
        // inputs. This is the case an unsigned multiplier gets wrong.
        begin_test("corner -128 * -128");
        do_clear();
        do_cycle(-8'sd128, -8'sd128, 1'b1, 1'b0);
        end_test();

        begin_test("corner -128 * 127");
        do_clear();
        do_cycle(-8'sd128, 8'sd127, 1'b1, 1'b0);
        end_test();

        begin_test("corner 127 * 127");
        do_clear();
        do_cycle(8'sd127, 8'sd127, 1'b1, 1'b0);
        end_test();

        begin_test("mixed signs accumulate to zero");
        do_clear();
        do_cycle(8'sd50,  8'sd50, 1'b1, 1'b0);
        do_cycle(-8'sd50, 8'sd50, 1'b1, 1'b0);
        end_test();

        // ---- directed: control signals ---------------------------------
        begin_test("en low holds accumulator");
        do_clear();
        do_cycle(8'sd10, 8'sd10, 1'b1, 1'b0);
        do_cycle(8'sd99, 8'sd99, 1'b0, 1'b0);   // must NOT accumulate
        do_cycle(8'sd99, 8'sd99, 1'b0, 1'b0);
        do_cycle(8'sd10, 8'sd10, 1'b1, 1'b0);
        end_test();

        begin_test("clear mid-sequence");
        do_clear();
        do_cycle(8'sd60, 8'sd60, 1'b1, 1'b0);
        do_cycle(8'sd60, 8'sd60, 1'b1, 1'b0);
        do_clear();
        do_cycle(8'sd1,  8'sd1,  1'b1, 1'b0);
        end_test();

        begin_test("clear has priority over en");
        do_clear();
        do_cycle(8'sd60, 8'sd60, 1'b1, 1'b0);
        do_cycle(8'sd60, 8'sd60, 1'b1, 1'b1);   // both asserted
        end_test();

        // ---- directed: output scaling and saturation -------------------
        // Q1.7 output can only represent [-1.0, +0.992]. Accumulate enough
        // that the scaled result must clamp.
        begin_test("result saturates high");
        do_clear();
        for (i = 0; i < 20; i = i + 1)
            do_cycle(8'sd127, 8'sd127, 1'b1, 1'b0);
        if (sat !== 1'b1) begin
            note_error();
            $display("  ERROR expected sat=1 after large positive accumulation");
        end
        end_test();

        begin_test("result saturates low");
        do_clear();
        for (i = 0; i < 20; i = i + 1)
            do_cycle(-8'sd128, 8'sd127, 1'b1, 1'b0);
        if (sat !== 1'b1) begin
            note_error();
            $display("  ERROR expected sat=1 after large negative accumulation");
        end
        end_test();

        // ---- directed: accumulator overflow ----------------------------
        // 2^31 / 16384 = 131072 accumulations of the worst-case product
        // before the 32-bit accumulator can overflow. Push past it.
        begin_test("accumulator overflow flag");
        do_clear();
        for (i = 0; i < 140000; i = i + 1)
            do_cycle(-8'sd128, -8'sd128, 1'b1, 1'b0);
        if (overflow !== 1'b1) begin
            note_error();
            $display("  ERROR expected overflow=1 after %0d accumulations", i);
        end
        end_test();

        begin_test("clear deasserts overflow");
        do_clear();
        if (overflow !== 1'b0) begin
            note_error();
            $display("  ERROR overflow still set after clear");
        end
        end_test();

        // ---- randomized ------------------------------------------------
        // Bounded so the 32-bit accumulator cannot overflow: any sequence
        // shorter than 131072 MACs is safe by construction.
        begin_test("random operands, 5000 MACs");
        do_clear();
        for (i = 0; i < 5000; i = i + 1) begin
            ra = $random;
            rb = $random;
            do_cycle(ra, rb, 1'b1, 1'b0);
        end
        end_test();

        begin_test("random operands and random control");
        do_clear();
        for (i = 0; i < 5000; i = i + 1) begin
            ra = $random;
            rb = $random;
            do_cycle(ra, rb, $random, ($random % 50 == 0));
        end
        end_test();

        // ---- verdict ----------------------------------------------------
        $display("--------------------------------------------------");
        $display(" checks: %0d    errors: %0d", checks, errors);
        if (errors == 0)
            $display(" *** TEST PASSED ***");
        else
            $display(" *** TEST FAILED ***");
        $display("==================================================");
        $display("");

        $finish;
    end

    // Watchdog
    initial begin
        #200000000;
        $display(" *** TIMEOUT -- testbench did not finish ***");
        $finish;
    end

endmodule
