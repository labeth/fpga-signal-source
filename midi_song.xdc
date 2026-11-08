# midi_song.v on the scope bench: scope C1 <- Alchitry A11 (ball L2) carries the
# MIDI; scope C2 <- A2 (ball T8) is held low.
set_property LOC N14 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name clk [get_ports clk]
set_property LOC L2 [get_ports c1]
set_property IOSTANDARD LVCMOS33 [get_ports c1]
set_property LOC T8 [get_ports c2]
set_property IOSTANDARD LVCMOS33 [get_ports c2]
