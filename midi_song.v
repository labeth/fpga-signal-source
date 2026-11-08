// midi_song.v — MIDI song sequencer for the Alchitry Au: plays a ROM of
// {delay_ms, byte} entries (midi_song.hex, written by gen_midi_song.py) as a
// MIDI UART, 31250 Bd 8N1, LSB first, idle high, and loops. The ROM holds the
// opening of "Fuer Elise" (public domain): right hand on MIDI channel 1, left
// hand on channel 2, a string pad on channel 3, program changes at loop start.
//   c1 -> MIDI out (scope C1)
//   c2 -> held low  (scope C2)
//
// ROM word: [23] last entry (wrap to 0 after it), [22:8] delay in ms counted
// from the start of the previous byte, [7:0] the byte. A byte starts once its
// delay has passed and the previous byte has left the line (delay 0 = back to
// back), the rule gen_midi_song.py models when it rounds the delays.
module sig #(
    parameter integer DIV    = 3200,    // clk cycles per bit: 100e6 / 31250
    parameter integer MS_CYC = 100000,  // clk cycles per ms
    parameter integer DEPTH  = 2048
) (
    input  wire clk,   // 100 MHz, ball N14
    output wire c1,    // MIDI out
    output wire c2     // held low
);
    reg [23:0] rom [0:DEPTH-1];
    initial $readmemh("midi_song.hex", rom);

    reg [10:0] addr = 0;
    reg [23:0] word = 0;
    always @(posedge clk) word <= rom[addr];   // registered read -> block RAM

    reg [1:0]  prime = 0;       // wait for the first ROM read after configuration
    reg [16:0] sub = 0;         // cycles within the current ms
    reg [14:0] ms = 0;          // ms since the last byte started (saturates)
    reg [11:0] bt = 0;          // cycles within the current bit
    reg [3:0]  nbits = 0;       // bits left on the line (0 = idle)
    reg [9:0]  sh = 10'h3ff;    // {stop, d7..d0, start}, shifted out LSB first

    // The line is free once the stop bit's last cycle is under way, so a back
    // to back byte starts exactly 10 bits after the one before.
    wire free = nbits == 0 || (nbits == 4'd1 && bt == DIV-1);
    wire go = prime[1] && free && ms >= word[22:8];

    always @(posedge clk) begin
        if (!prime[1]) prime <= prime + 2'd1;

        if (go) begin               // this cycle is the first of ms 0
            sub <= 17'd1;
            ms  <= 0;
        end else if (sub == MS_CYC-1) begin
            sub <= 0;
            if (ms != 15'h7fff) ms <= ms + 15'd1;
        end else begin
            sub <= sub + 17'd1;
        end

        if (go) begin
            sh    <= {1'b1, word[7:0], 1'b0};
            nbits <= 4'd10;
            bt    <= 0;
            addr  <= word[23] ? 11'd0 : addr + 11'd1;
        end else if (nbits != 0) begin
            if (bt == DIV-1) begin
                bt    <= 0;
                sh    <= {1'b1, sh[9:1]};
                nbits <= nbits - 4'd1;
            end else begin
                bt <= bt + 12'd1;
            end
        end
    end

    assign c1 = sh[0];
    assign c2 = 1'b0;
endmodule
