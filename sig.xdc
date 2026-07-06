# Constraints for sig.v on the Alchitry Au (XC7A35T-ftg256), nextpnr-xilinx.
# Use LOC (not PACKAGE_PIN) and only IOSTANDARD — the nextpnr XDC parser
# recognizes LOC, IOSTANDARD, INTERNAL_VREF and create_clock.
#
# clk : 100 MHz oscillator, ball N14.
# sig : C1 ← Alchitry A20 = ball G1, bank 35, 3.3 V.

set_property LOC N14 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name clk [get_ports clk]

set_property LOC G1 [get_ports sig]
set_property IOSTANDARD LVCMOS33 [get_ports sig]
