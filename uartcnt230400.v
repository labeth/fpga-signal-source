// uartcnt230400.v - continuous UART counter for the scope's decoded-stream
// loss test: 8N1, LSB first, 230400 Bd (100 MHz / 434), bytes 00 01 02 ...
// FF 00 ... back to back with no idle time, so any missing, repeated or
// corrupted byte breaks the sequence. Same TX on both scope channels.
module sig (
    input  wire clk,   // 100 MHz, ball N14
    output wire c1,
    output wire c2
);
    localparam integer DIV = 434;
    reg [9:0] bt = 0;     // baud counter
    reg [3:0] ph = 4'd9;  // 9 = load + start bit, 0..7 data, 8 stop
    reg [7:0] sh = 0, n = 0;
    reg       tx = 1'b1;
    always @(posedge clk) begin
        if (bt == DIV-1) begin
            bt <= 0;
            if (ph == 4'd9) begin
                tx <= 1'b0; sh <= n; n <= n + 8'd1; ph <= 4'd0;
            end else if (ph <= 4'd7) begin
                tx <= sh[0]; sh <= {1'b0, sh[7:1]}; ph <= ph + 4'd1;
            end else begin
                tx <= 1'b1; ph <= 4'd9;   // stop bit, then straight to the next start
            end
        end else bt <= bt + 10'd1;
    end
    assign c1 = tx;
    assign c2 = tx;
endmodule
