// dacgen.v — TLC7524CN 8-bit DAC driver for the Alchitry Au (XC7A35T).
//
// Streams waveform sample codes onto the DAC data bus DB0..DB7 (dac[7:0],
// LSB=dac[0]) at the 100 MHz update rate via a phase accumulator. On the DAC,
// WR and CS are grounded so its latches are transparent — the analog output at
// REF tracks the bus continuously, V_out = 2.5 V * code/256 (0..2.49 V).
//
// Output frequency = 100 MHz * INC / 2^32. WAVE picks the shape:
//   0 = sawtooth (ramp 0->255, sharp reset) — exercises every code linearly,
//       the best check that all 8 data bits are wired correctly.
//   1 = triangle (0->255->0)               — symmetric, linear ramps.
//   2 = square   (0 / 255)                 — sharp edges for trigger tests.
//   3 = sine     (256-entry LUT)           — smooth, single amplitude.
module dacgen #(
    parameter [31:0] INC  = 32'd42950, // ~1 kHz (100e6*INC/2^32)
    parameter        WAVE = 0          // 0 saw, 1 triangle, 2 square, 3 sine
) (
    input  wire       clk,             // 100 MHz, ball N14
    output wire [7:0] dac              // DB0..DB7  (LSB = dac[0])
);
    reg [31:0] phase = 32'd0;
    always @(posedge clk) phase <= phase + INC;

    wire [7:0] saw = phase[31:24];                               // 0..255 ramp
    wire [7:0] tria = phase[31] ? ~phase[30:23] : phase[30:23];  // fold to triangle
    wire [7:0] sq  = phase[31] ? 8'd255 : 8'd0;                  // full-scale square

    // Sine lookup, addressed by the top 8 phase bits. Registered read so it
    // maps to a block/distributed ROM.
    reg [7:0] sine_rom [0:255];
    initial $readmemh("sine256.hex", sine_rom);
    reg [7:0] sine;
    always @(posedge clk) sine <= sine_rom[phase[31:24]];

    reg [7:0] code;
    always @(*) begin
        case (WAVE)
            32'd1:   code = tria;
            32'd2:   code = sq;
            32'd3:   code = sine;
            default: code = saw;
        endcase
    end
    assign dac = code;
endmodule
