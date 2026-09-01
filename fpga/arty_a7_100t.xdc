# Arty A7-100T Rev. D/E constraints used by arty_a7_100t_top.
# Pin names come from Digilent's Arty-A7-100-Master.xdc:
# https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-100-Master.xdc

set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5.000} [get_ports { CLK100MHZ }]

set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { ck_rst }]

set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]
