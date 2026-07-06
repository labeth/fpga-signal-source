// sig.v — single-tone generator for the Alchitry Au (XC7A35T), driving one
// pin (C1 ← A20 = ball G1). Avoids ODDR (nextpnr-xilinx string-property
// crash). Two mechanisms:
//   - counter divide of the 100 MHz input (USE_PLL=0): a toggle FF gives
//     100/(2*DIV) MHz. Clean, jitter-free, for the low end (<= 50 MHz).
//   - PLLE2 direct (USE_PLL=1): PLLE2 makes CLKOUT0 = FMHZ and that clock is
//     forwarded straight to the output buffer, reaching up to ~464 MHz on
//     the Artix-7 -1 — enough to test above the scope's 250 MHz Nyquist.

module sig #(
    parameter FMHZ = 25,
    parameter USE_PLL = 0,
    parameter DIV = 2           // counter half-period (USE_PLL=0): out = 100/(2*DIV)
) (
    input  wire clk,            // 100 MHz, ball N14
    output wire sig             // to C1, ball G1
);
    generate
    if (USE_PLL) begin : gen_pll
        // PLLE2_BASE: VCO = 100 * CLKFBOUT_MULT (DIVCLK=1) in 800..1600 MHz;
        // CLKOUT0 = VCO / CLKOUT0_DIVIDE = FMHZ, forwarded to the pin.
        wire pll_fb, pll_out, outclk;
        PLLE2_BASE #(
            .CLKIN1_PERIOD(10.0),
            .CLKFBOUT_MULT(`PLL_MULT),
            .DIVCLK_DIVIDE(1),
            .CLKOUT0_DIVIDE(`PLL_DIV0),
            .CLKOUT0_PHASE(0.0),
            .STARTUP_WAIT("FALSE")
        ) pll (
            .CLKOUT0(pll_out),
            .CLKFBOUT(pll_fb), .CLKFBIN(pll_fb),
            .CLKIN1(clk),
            .LOCKED(), .PWRDWN(1'b0), .RST(1'b0)
        );
        BUFG bufg_out (.I(pll_out), .O(outclk));
        assign sig = outclk;    // clock forwarded straight to the output pin
    end else begin : gen_div
        reg tog = 1'b0;
        localparam CW = 20;
        reg [CW-1:0] cnt = 0;
        always @(posedge clk) begin
            if (cnt == (DIV-1)) begin
                cnt <= 0;
                tog <= ~tog;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
        assign sig = tog;
    end
    endgenerate
endmodule
