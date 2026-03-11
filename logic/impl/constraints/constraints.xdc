set_property -dict { PACKAGE_PIN F14   IOSTANDARD LVCMOS33 } [get_ports { i_clk_12 }]; #IO_L13P_T2_MRCC_15 Sch=uclk
create_clock -add -name sys_clk_pin -period 83.333 -waveform {0 41.667} [get_ports { i_clk_12 }];

set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports { i_rst }]; #IO_L18N_T2_A23_15 Sch=btn[0]

## High Speed PMOD Header JA
set_property -dict { PACKAGE_PIN L17   IOSTANDARD LVCMOS33 } [get_ports { o_adc_sdi }]; #IO_L4P_T0_D04_14 Sch=ja_p[1]
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { o_adc_sclk }]; #IO_L5P_T0_D06_14 Sch=ja_p[2]
set_property -dict { PACKAGE_PIN M16   IOSTANDARD LVCMOS33 } [get_ports { i_adc_sdo }]; #IO_L7P_T1_D09_14 Sch=ja_p[3]
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { o_adc_convst }]; #IO_L8P_T1_D11_14 Sch=ja_p[4]
set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports { o_pwm_tune }]; #IO_L8N_T1_D12_14 Sch=ja_n[4]