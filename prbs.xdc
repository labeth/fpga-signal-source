# Constraints for prbs.v on the Alchitry Au (XC7A35T-ftg256), nextpnr-xilinx.
# clk : 100 MHz oscillator, ball N14.
# c1  : scope C1 <- Alchitry A20 = ball G1  (bank 35, 3.3 V).
# c2  : scope C2 <- Alchitry A27 = ball M6  (IO_L19P_T3_A10_D26_14, 3.3 V).

set_property LOC N14 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name clk [get_ports clk]

set_property LOC G1 [get_ports c1]
set_property IOSTANDARD LVCMOS33 [get_ports c1]

set_property LOC M6 [get_ports c2]
set_property IOSTANDARD LVCMOS33 [get_ports c2]
