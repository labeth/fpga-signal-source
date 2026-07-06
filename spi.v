// spi.v — SPI master (Mode 0) for the Alchitry Au, as the scope's protocol-decode
// ground truth for a 2-wire clock+data protocol. This is the reason C2 got wired:
//   c1 = SCLK -> ball G1 (Alchitry A20 = scope C1)
//   c2 = MOSI -> ball M6 (Alchitry A27 = scope C2)
// Mode 0: CPOL=0 (clock idle low), CPHA=0 (sample on the rising edge, data set up
// on the falling edge). MSB-first. Sends the same 8-byte message as uart.v with an
// idle gap (SCLK held low) between repeats so the decoder's gap-reset re-frames.
module sig (
    input  wire clk,   // 100 MHz, ball N14
    output wire c1,    // SCLK -> scope C1 (G1)
    output wire c2     // MOSI -> scope C2 (M6)
);
    localparam integer CDIV = 250; // half SCLK period in 100 MHz cycles -> 200 kHz
    localparam integer GAPB = 40;  // idle half-periods between message repeats (~20 bit-times)

    reg [8:0] cnt  = 0;      // cycle counter within a half-period (0..CDIV-1)
    reg       half = 0;      // 0 = SCLK-low half, 1 = SCLK-high half
    reg [2:0] bit  = 3'd7;   // current bit, MSB first (7..0)
    reg [2:0] bidx = 0;      // message byte index (0..7)
    reg [7:0] sh   = 8'h48;  // current byte
    reg       sclk = 0;
    reg       mosi = 0;
    reg       send = 1;      // 1 = clocking bytes, 0 = idle gap
    reg [7:0] gapc = 0;      // gap half-period counter
    reg [7:0] nb;            // next byte (blocking temp; Verilog can't bit-select a call)

    function [7:0] rom(input [2:0] k);
        case (k)
            3'd0: rom = 8'h48; // 'H'
            3'd1: rom = 8'h69; // 'i'
            3'd2: rom = 8'h20; // ' '
            3'd3: rom = 8'h55;
            3'd4: rom = 8'hAA;
            3'd5: rom = 8'h0F;
            3'd6: rom = 8'hF0;
            3'd7: rom = 8'h0A; // '\n'
            default: rom = 8'h00;
        endcase
    endfunction

    always @(posedge clk) begin
        if (cnt != CDIV-1) begin
            cnt <= cnt + 9'd1;
        end else begin
            cnt <= 0;
            if (send) begin
                if (half == 1'b0) begin
                    sclk <= 1'b1;      // rising edge: DATA is sampled here
                    half <= 1'b1;
                end else begin
                    sclk <= 1'b0;      // falling edge: advance to next bit
                    half <= 1'b0;
                    if (bit == 3'd0) begin      // byte complete (sampled sh[7..0])
                        bit <= 3'd7;
                        if (bidx == 3'd7) begin  // message complete -> idle gap
                            send <= 1'b0;
                            gapc <= 0;
                            bidx <= 0;
                            mosi <= 1'b0;
                        end else begin
                            nb   = rom(bidx + 3'd1);
                            bidx <= bidx + 3'd1;
                            sh   <= nb;
                            mosi <= nb[7];           // MSB of next byte
                        end
                    end else begin
                        bit  <= bit - 3'd1;
                        mosi <= sh[bit-3'd1];    // set up next bit on the falling edge
                    end
                end
            end else begin
                sclk <= 1'b0;          // idle: hold SCLK low
                if (gapc == GAPB) begin
                    nb   = rom(3'd0);
                    send <= 1'b1;
                    half <= 1'b0;
                    bit  <= 3'd7;
                    bidx <= 0;
                    sh   <= nb;
                    mosi <= nb[7];       // set up MSB before the first rising edge
                end else begin
                    gapc <= gapc + 8'd1;
                end
            end
        end
    end

    assign c1 = sclk;
    assign c2 = mosi;
endmodule
