// prbs.v — PRBS7 NRZ serial source for eye-diagram / jitter validation.
//   c1 (ball G1, scope C1): PRBS7 data at 100/DIV Mbps
//   c2 (ball M6, scope C2): the IDEAL (unjittered) bit clock — CDR ground truth
//
// Jitter injection (deterministic, ANALYTICALLY known): square-wave PHASE
// modulation. Each data edge is placed at its ideal bit boundary plus an
// offset that alternates 0 <-> 2*JA sysclk cycles every JP/2 bits:
//   TIE(t)      = square wave, period JP bits, peak-peak = 2*JA*10 ns
//   f_jitter    = bitrate / JP
//   fundamental = (4/pi)*JA*10 ns (zero-to-peak)
// The offset is applied at the OUTPUT stage only — the underlying bit counter
// and LFSR run uninjured, so the injected TIE is bounded (no random-walk).
// JA=0 disables injection (clean source). Constraint: 2*JA < DIV.
module sig #(
    parameter integer DIV = 20, // sysclk cycles per bit: 20 -> 5 Mbps @100 MHz
    parameter integer JA  = 0,  // jitter amplitude in sysclk cycles (10 ns each)
    parameter integer JP  = 32  // jitter period in BITS (power of two)
) (
    input  wire clk, // 100 MHz, ball N14
    output wire c1,  // PRBS data  -> scope C1 (G1)
    output wire c2   // bit clock  -> scope C2 (M6)
);
    reg [15:0] bt    = 0;      // cycle counter within the bit (0..DIV-1)
    reg [6:0]  lfsr  = 7'h7f;  // PRBS7: x^7 + x^6 + 1 (127-bit sequence)
    reg [15:0] jbits = 0;      // bit counter (jitter phase)
    reg        dnext = 0;      // next bit value, loaded at the ideal boundary
    reg        data  = 0;      // output register (edge placed at bt == offs)
    reg        bclk  = 0;      // ideal bit clock

    // Square-wave phase offset: bit log2(JP/2) of the bit counter toggles with
    // period JP bits. Constant within each bit (jbits advances at bt==DIV-1).
    wire [15:0] offs = (JA == 0) ? 16'd0
                     : (((jbits & (JP / 2)) != 0) ? (2 * JA) : 16'd0);

    always @(posedge clk) begin
        if (bt == DIV - 1) begin
            bt    <= 0;
            dnext <= lfsr[6];
            // Zero-escape: FF init values are unreliable through the open
            // yosys/nextpnr flow; if the LFSR comes up all-zeros the plain XOR
            // feedback locks up forever (flat data). Injecting a 1 from the
            // zero state makes the sequence self-starting from ANY power-up.
            lfsr  <= {lfsr[5:0], lfsr[6] ^ lfsr[5] ^ (lfsr == 7'd0)};
            jbits <= jbits + 16'd1;
        end else begin
            bt <= bt + 16'd1;
        end
        if (bt == offs) data <= dnext;   // delayed edge placement (the jitter)
        if (bt == 0) bclk <= 1'b1;       // ideal clock: rise at the boundary,
        else if (bt == DIV / 2) bclk <= 1'b0; // fall mid-bit (DIV even)
    end

    assign c1 = data;
    assign c2 = bclk;
endmodule
