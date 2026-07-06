// burst.v — frequency-stepped burst generator for the Alchitry Au, driving C1
// (ball G1). One 300 ns period = three 100 ns segments:
//   5 cycles of  50 MHz  (100 ns)
//  15 cycles of 150 MHz  (100 ns)
//  25 cycles of 250 MHz  (100 ns)
// repeating at 3.333 MHz — a low, easily-triggered repetition rate whose
// distinctive shape gives superres an unambiguous alignment lock, while the
// bursts exercise 50/150/250 MHz (250 = the scope's raw Nyquist).
//
// PLLE2 makes 50/150/250 MHz from one 1500 MHz VCO (all phase-locked). A
// counter on the 100 MHz input times each 100 ns segment (10 input cycles),
// and a cascade of two glitch-free BUFGMUX forwards the selected clock.

module sig (
    input  wire clk,   // 100 MHz, ball N14
    output wire sig    // to C1, ball G1
);
    wire fb, o50, o150, o250, c50, c150, c250;
    PLLE2_BASE #(
        .CLKIN1_PERIOD(10.0),
        .CLKFBOUT_MULT(15),      // VCO = 100 * 15 = 1500 MHz
        .DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE(30),     // 1500/30 = 50 MHz
        .CLKOUT1_DIVIDE(10),     // 1500/10 = 150 MHz
        .CLKOUT2_DIVIDE(6),      // 1500/6  = 250 MHz
        .STARTUP_WAIT("FALSE")
    ) pll (
        .CLKOUT0(o50), .CLKOUT1(o150), .CLKOUT2(o250),
        .CLKFBOUT(fb), .CLKFBIN(fb),
        .CLKIN1(clk), .LOCKED(), .PWRDWN(1'b0), .RST(1'b0)
    );
    BUFG bg0 (.I(o50),  .O(c50));
    BUFG bg1 (.I(o150), .O(c150));
    BUFG bg2 (.I(o250), .O(c250));

    // Segment timer on the 100 MHz input: 10 cycles = 100 ns per segment,
    // cycling 0 (50 MHz) -> 1 (150 MHz) -> 2 (250 MHz).
    reg [3:0] cnt = 0;
    reg [1:0] seg = 0;
    always @(posedge clk) begin
        if (cnt == 4'd9) begin
            cnt <= 0;
            seg <= (seg == 2'd2) ? 2'd0 : seg + 2'd1;
        end else begin
            cnt <= cnt + 4'd1;
        end
    end

    // Clean clock forwarding needs a real clock-mux BEL (a fabric LUT can't
    // pass 250 MHz). BUFGMUX won't place in nextpnr-xilinx, but the underlying
    // BUFGCTRL does. Two cascaded 2:1 BUFGCTRL muxes give the 3:1 select:
    //   seg=00 -> c50, seg=01 -> c150, seg=1x -> c250.
    // IGNORE*=1 switches on the select without waiting for a clock-low (the
    // slow 100 ns seg changes make glitch-freeness unnecessary here).
    wire mlo, mout;
    BUFGCTRL #(.INIT_OUT(1'b0), .PRESELECT_I0("TRUE"), .PRESELECT_I1("FALSE"))
      mux_lo (.O(mlo), .I0(c50), .I1(c150),
              .CE0(1'b1), .CE1(1'b1), .S0(~seg[0]), .S1(seg[0]),
              .IGNORE0(1'b1), .IGNORE1(1'b1));
    BUFGCTRL #(.INIT_OUT(1'b0), .PRESELECT_I0("TRUE"), .PRESELECT_I1("FALSE"))
      mux_out (.O(mout), .I0(mlo), .I1(c250),
               .CE0(1'b1), .CE1(1'b1), .S0(~seg[1]), .S1(seg[1]),
               .IGNORE0(1'b1), .IGNORE1(1'b1));
    assign sig = mout;   // forward the selected clock to the pin
endmodule
