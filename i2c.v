// i2c.v - I2C generator for the Alchitry Au, protocol-decode ground truth.
// A fixed transaction played from a (SCL,SDA) quarter-period ROM at ~200 kHz SCL:
//   START, addr 0x24 +W, ACK, data 0x55 0xAA 0x0F 0xF0 (each ACKed), STOP, idle.
//   c1 = SCL -> ball G1 (Alchitry A20 = scope C1)
//   c2 = SDA -> ball M6 (Alchitry A27 = scope C2)
// Quarter-period grid: SDA only ever changes mid-SCL-low, so it is stable across
// both SCL edges (no false START/STOP). ACK bits are driven low. Open-drain lines
// are modelled as pushed levels -- fine for a decode source.
module sig (
    input  wire clk,   // 100 MHz, ball N14
    output wire c1,    // SCL -> scope C1 (G1)
    output wire c2     // SDA -> scope C2 (M6)
);
    localparam integer QTR = 125;    // 100 MHz cycles per quarter -> 200 kHz SCL
    localparam integer N   = 200;    // ROM phases

    reg [8:0]      div = 0;
    reg [8:0]      idx = 0;
    reg [N-1:0] SCL = 200'b11111111110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011111111;
    reg [N-1:0] SDA = 200'b11111111100000000000000000000001111111111111111000011111111111111110000000000000000000000001111000011110000111100001111000011110000111100001111000011110000000000000000000011110000000011110000000111111;

    always @(posedge clk) begin
        if (div == QTR-1) begin
            div <= 0;
            idx <= (idx == N-1) ? 9'd0 : idx + 9'd1;
        end else begin
            div <= div + 9'd1;
        end
    end

    assign c1 = SCL[idx];
    assign c2 = SDA[idx];
endmodule
