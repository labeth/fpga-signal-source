// steps.v — stepped low-frequency square wave for the Alchitry Au, to watch
// the scope's slow-timebase roll mode: 50, 20, 10, 5, 2, 1, 0.5, 0.2 Hz, each
// held 10 s (an 80 s cycle), from the 100 MHz clock. The same square drives
// every pin the scope benches have used (steps.xdc), so C1 and C2 both show it
// whichever wiring is in place.
module sig (
    input  wire clk,   // 100 MHz, ball N14
    output wire [4:0] p // A20/G1, A27/M6, A2/T8, A8/R8, A11/L2
);
    localparam integer STEP_CYCLES = 1_000_000_000; // 10 s per step
    localparam integer NSTEPS = 8;

    // Half period in 100 MHz clocks: 100e6 / (2 f).
    function [27:0] half(input [2:0] k);
        case (k)
            3'd0: half = 27'd1_000_000;   // 50 Hz
            3'd1: half = 27'd2_500_000;   // 20 Hz
            3'd2: half = 27'd5_000_000;   // 10 Hz
            3'd3: half = 27'd10_000_000;  // 5 Hz
            3'd4: half = 27'd25_000_000;  // 2 Hz
            3'd5: half = 27'd50_000_000;  // 1 Hz
            3'd6: half = 27'd100_000_000; // 0.5 Hz
            default: half = 28'd250_000_000; // 0.2 Hz
        endcase
    endfunction

    reg [29:0] dwell = 0;  // clocks into the current step
    reg [2:0]  step = 0;
    reg [27:0] cnt = 0;    // clocks into the current half period
    reg        sq = 0;

    always @(posedge clk) begin
        if (dwell == STEP_CYCLES - 1) begin
            dwell <= 0;
            step  <= (step == NSTEPS - 1) ? 3'd0 : step + 3'd1;
            cnt   <= 0;       // each step starts on a fresh half period
            sq    <= 1'b1;
        end else begin
            dwell <= dwell + 30'd1;
            if (cnt == half(step) - 1) begin
                cnt <= 0;
                sq  <= ~sq;
            end else
                cnt <= cnt + 28'd1;
        end
    end

    assign p = {5{sq}};
endmodule
