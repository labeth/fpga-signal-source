# Constraints for dacgen.v on the Alchitry Au (XC7A35T-ftg256), nextpnr-xilinx.
# clk : 100 MHz oscillator, ball N14.
# dac[7:0] -> TLC7524CN DB0..DB7, Alchitry Bank C, FPGA I/O bank 14 (3.3 V).
#   dac[0]=DB0(LSB)=C42=N13   dac[1]=DB1=C43=P13   dac[2]=DB2=C45=N11
#   dac[3]=DB3=C46=N12        dac[4]=DB4=C48=P10   dac[5]=DB5=C49=P11
#   dac[6]=DB6=C8 =R11        dac[7]=DB7(MSB)=C9=R10

set_property LOC N14 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name clk [get_ports clk]

set_property LOC N13 [get_ports {dac[0]}]
set_property LOC P13 [get_ports {dac[1]}]
set_property LOC N11 [get_ports {dac[2]}]
set_property LOC N12 [get_ports {dac[3]}]
set_property LOC P10 [get_ports {dac[4]}]
set_property LOC P11 [get_ports {dac[5]}]
set_property LOC R11 [get_ports {dac[6]}]
set_property LOC R10 [get_ports {dac[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac[7]}]
