//=============================================================================
// mac_top.v -- Nandland Go Board wrapper for the MAC unit.
//
// Port names match Go_Board_Constraints.pcf exactly; that file supplies the
// pin numbers. iCE40HX1K-VQ100, 25 MHz oscillator.
//
//   Switch 1   step: run ONE multiply-accumulate from the operand ROM
//   Switch 2   clear the accumulator and rewind the ROM to the start
//   Switch 3   reset (held low internally as rst_n)
//   Switch 4   hold to show acc[7:0] instead of result
//
//   LED 1      sat       -- the result is being clamped
//   LED 2      overflow  -- sticky accumulator overflow
//   LED 3      the ROM sequence has wrapped back to the start
//   LED 4      heartbeat -- proves the board is configured and clocking
//
//   7-segment  the displayed byte in hex: Segment1 = high nibble
//
// The accumulator is deliberately NOT brought out to pins. Exposing all 32
// bits costs 62 of the 72 available I/O and fills three I/O banks, leaving
// nothing for the LEDs and display.
//=============================================================================
`default_nettype none

module mac_top #(
    // Shrunk by the testbench. 250000 = 10 ms at 25 MHz.
    parameter DEBOUNCE_LIMIT = 250000,
    // Heartbeat divider bit. 2^23 / 25 MHz ~ 0.34 s per half period.
    parameter HEARTBEAT_BIT  = 23
) (
    input  wire i_Clk,

    input  wire i_Switch_1,
    input  wire i_Switch_2,
    input  wire i_Switch_3,
    input  wire i_Switch_4,

    output wire o_LED_1,
    output wire o_LED_2,
    output wire o_LED_3,
    output wire o_LED_4,

    output wire o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D,
    output wire o_Segment1_E, o_Segment1_F, o_Segment1_G,
    output wire o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D,
    output wire o_Segment2_E, o_Segment2_F, o_Segment2_G
);

    //-------------------------------------------------------------------------
    // Display polarity.
    //
    // If the digits come up as the photographic negative of what they should
    // be -- every segment lit except the right ones -- flip this to 1'b0.
    // That is the only change needed.
    //-------------------------------------------------------------------------
    localparam SEG_ACTIVE_LOW = 1'b1;

    //-------------------------------------------------------------------------
    // Buttons
    //-------------------------------------------------------------------------
    wire step_pulse, clear_pulse, rst_level, show_acc;

    debounce #(.LIMIT(DEBOUNCE_LIMIT)) u_db_step (
        .clk(i_Clk), .i_raw(i_Switch_1), .o_level(), .o_pulse(step_pulse));

    debounce #(.LIMIT(DEBOUNCE_LIMIT)) u_db_clear (
        .clk(i_Clk), .i_raw(i_Switch_2), .o_level(), .o_pulse(clear_pulse));

    debounce #(.LIMIT(DEBOUNCE_LIMIT)) u_db_rst (
        .clk(i_Clk), .i_raw(i_Switch_3), .o_level(rst_level), .o_pulse());

    debounce #(.LIMIT(DEBOUNCE_LIMIT)) u_db_show (
        .clk(i_Clk), .i_raw(i_Switch_4), .o_level(show_acc), .o_pulse());

    // Switches read high when pressed, so pressing Switch 3 must pull the
    // active-low reset down.
    wire rst_n = ~rst_level;

    //-------------------------------------------------------------------------
    // Operand ROM -- eight Q1.7 pairs chosen to walk through the interesting
    // behaviour. Values are the raw 8-bit integers; divide by 128 for the
    // real value they represent.
    //
    //  #  a     b      product   running acc   result   what it shows
    //  0   64    64     0.25       0.25         0x20    plain accumulate
    //  1   64    64     0.25       0.50         0x40
    //  2   64    64     0.25       0.75         0x60
    //  3   64    64     0.25       1.00         0x7F    SATURATES, LED1 on
    //  4  -64   127    -0.496      0.504        0x41    back in range
    //  5 -128   127    -0.992     -0.488        0xC2    negative
    //  6 -128   127    -0.992     -1.480        0x80    saturates negative
    //  7    0     0     0         -1.480        0x80    en with zero operands
    //-------------------------------------------------------------------------
    reg signed [7:0] rom_a, rom_b;
    reg        [2:0] idx = 3'd0;

    always @(*) begin
        case (idx)
            3'd0: begin rom_a =  8'sd64;  rom_b =  8'sd64;  end
            3'd1: begin rom_a =  8'sd64;  rom_b =  8'sd64;  end
            3'd2: begin rom_a =  8'sd64;  rom_b =  8'sd64;  end
            3'd3: begin rom_a =  8'sd64;  rom_b =  8'sd64;  end
            3'd4: begin rom_a = -8'sd64;  rom_b =  8'sd127; end
            3'd5: begin rom_a = -8'sd128; rom_b =  8'sd127; end
            3'd6: begin rom_a = -8'sd128; rom_b =  8'sd127; end
            default: begin rom_a = 8'sd0; rom_b = 8'sd0;    end
        endcase
    end

    reg wrapped = 1'b0;

    always @(posedge i_Clk or negedge rst_n) begin
        if (!rst_n) begin
            idx     <= 3'd0;
            wrapped <= 1'b0;
        end else if (clear_pulse) begin
            idx     <= 3'd0;
            wrapped <= 1'b0;
        end else if (step_pulse) begin
            idx <= idx + 3'd1;
            if (idx == 3'd7) wrapped <= 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // The design under test
    //-------------------------------------------------------------------------
    wire signed [31:0] acc;
    wire signed [7:0]  result;
    wire               overflow, sat;

    mac #(.WIDTH(8), .ACC_WIDTH(32), .FRAC_BITS(7)) u_mac (
        .clk      (i_Clk),
        .rst_n    (rst_n),
        .clear    (clear_pulse),
        .en       (step_pulse),
        .a        (rom_a),
        .b        (rom_b),
        .acc      (acc),
        .result   (result),
        .overflow (overflow),
        .sat      (sat)
    );

    //-------------------------------------------------------------------------
    // Display
    //-------------------------------------------------------------------------
    wire [7:0] shown = show_acc ? acc[7:0] : result;

    wire [6:0] seg_hi, seg_lo;
    hex7seg u_hi (.i_nibble(shown[7:4]), .o_seg(seg_hi));
    hex7seg u_lo (.i_nibble(shown[3:0]), .o_seg(seg_lo));

    wire [6:0] drv_hi = SEG_ACTIVE_LOW ? ~seg_hi : seg_hi;
    wire [6:0] drv_lo = SEG_ACTIVE_LOW ? ~seg_lo : seg_lo;

    assign {o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D,
            o_Segment1_E, o_Segment1_F, o_Segment1_G} = drv_hi;
    assign {o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D,
            o_Segment2_E, o_Segment2_F, o_Segment2_G} = drv_lo;

    //-------------------------------------------------------------------------
    // Heartbeat -- if this LED is not blinking, the bitstream did not load.
    //-------------------------------------------------------------------------
    reg [HEARTBEAT_BIT:0] hb = 0;
    always @(posedge i_Clk) hb <= hb + 1'b1;

    assign o_LED_1 = sat;
    assign o_LED_2 = overflow;
    assign o_LED_3 = wrapped;
    assign o_LED_4 = hb[HEARTBEAT_BIT];

endmodule

`default_nettype wire
