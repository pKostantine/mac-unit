// debounce.v -- clean up a mechanical push-button and emit a one-cycle pulse
// on each press.
//
// A button contacts bounce for several milliseconds when pressed. Without
// this, one press looks like a burst of presses and you would run dozens of
// MACs per push. The counter here requires the input to hold a new value
// for LIMIT consecutive clocks before believing it.
//
// LIMIT is a parameter so the testbench can shrink it -- simulating 250,000
// clocks per button press is pointlessly slow.

`default_nettype none

module debounce #(
    parameter LIMIT = 250000        // 10 ms at 25 MHz
) (
    input  wire clk,
    input  wire i_raw,
    output wire o_level,            // debounced level
    output wire o_pulse             // one clock high on each rising edge
);

    reg [31:0] cnt   = 32'd0;
    reg        state = 1'b0;
    reg        prev  = 1'b0;

    always @(posedge clk) begin
        if (i_raw != state) begin
            if (cnt >= LIMIT) begin
                state <= i_raw;
                cnt   <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end else begin
            cnt <= 32'd0;
        end
        prev <= state;
    end

    assign o_level = state;
    assign o_pulse = state & ~prev;

endmodule

`default_nettype wire
