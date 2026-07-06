// uart.v — UART transmitter for the Alchitry Au, as the scope's protocol-decode
// ground truth. 8N1, LSB-first, 115200 baud from the 100 MHz clock. Repeats a
// fixed message with an idle gap between repeats so the scope can frame it.
// Both channels carry the same TX so decode can be validated on C1 or C2:
//   c1 -> ball G1 (Alchitry A20 = scope C1)
//   c2 -> ball M6 (Alchitry A27 = scope C2)
module sig (
    input  wire clk,   // 100 MHz, ball N14
    output wire c1,    // scope C1 (G1)
    output wire c2     // scope C2 (M6)
);
    localparam integer DIV = 868; // 100e6 / 115200
    localparam integer GAP = 24;  // idle bit-times between message repeats

    reg [9:0]  bt = 0;    // baud counter (0..DIV-1)
    reg [5:0]  ph = 6'd63; // phase: 63=frame-start, 0..7=data d0..d7, 8=stop, 9.. = idle gap
    reg [2:0]  bi = 0;    // byte index within the message (0..7)
    reg [7:0]  sh = 0;    // TX shift register
    reg        tx = 1'b1; // idle high

    // 8-byte message: "Hi " + 0x55 0xAA 0x0F 0xF0 0x0A  (recognizable bit patterns)
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
        if (bt == DIV-1) begin
            bt <= 0;
            if (ph == 6'd63) begin        // frame start: emit the start bit, load byte
                tx <= 1'b0;               // START (low)
                sh <= rom(bi);
                ph <= 6'd0;
            end else if (ph <= 6'd7) begin // data bits d0..d7 (LSB first)
                tx <= sh[0];
                sh <= {1'b0, sh[7:1]};
                ph <= ph + 6'd1;
            end else if (ph == 6'd8) begin // STOP bit
                tx <= 1'b1;
                bi <= bi + 3'd1;
                ph <= (bi == 3'd7) ? 6'd9 : 6'd63; // after the last byte -> idle gap
            end else begin                 // idle gap (ph 9 .. 9+GAP)
                tx <= 1'b1;
                ph <= (ph >= 6'd9 + GAP) ? 6'd63 : ph + 6'd1;
            end
        end else begin
            bt <= bt + 10'd1;
        end
    end

    assign c1 = tx;
    assign c2 = tx;
endmodule
