## Arty S7-50 (xc7s50csga324-1) constraints for the FM radio
## Package pins and schematic names taken from Digilent/digilent-xdc Arty-S7-50-Master.xdc

## 12 MHz onboard oscillator
set_property -dict { PACKAGE_PIN F14   IOSTANDARD LVCMOS33 } [get_ports { i_clk_12 }]; #IO_L13P_T2_MRCC_15 Sch=uclk
create_clock -add -name sys_clk_pin -period 83.333 -waveform {0 41.667} [get_ports { i_clk_12 }];

## Buttons
set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports { i_btn_vol_up }];   #IO_L18N_T2_A23_15 Sch=btn[0]
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { i_btn_vol_down }]; #IO_L19P_T3_A22_15 Sch=btn[1]
set_property -dict { PACKAGE_PIN J16   IOSTANDARD LVCMOS33 } [get_ports { i_btn_ch_up }];    #IO_L19N_T3_A21_VREF_15 Sch=btn[2]
set_property -dict { PACKAGE_PIN H13   IOSTANDARD LVCMOS33 } [get_ports { i_btn_ch_down }];  #IO_L20P_T3_A20_15 Sch=btn[3]

## High Speed Pmod Header JA - analog front end board (MCP33131 ADC and ADF4351 LO synthesiser)
set_property -dict { PACKAGE_PIN L17   IOSTANDARD LVCMOS33 } [get_ports { o_adc_sdi }];      #IO_L4P_T0_D04_14 Sch=ja_p[1]
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { o_adc_sclk }];     #IO_L5P_T0_D06_14 Sch=ja_p[2]
set_property -dict { PACKAGE_PIN M16   IOSTANDARD LVCMOS33 } [get_ports { i_adc_sdo }];      #IO_L7P_T1_D09_14 Sch=ja_p[3]
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { o_adc_convst }];   #IO_L8P_T1_D11_14 Sch=ja_p[4]

## ADF4351 LO synthesiser, three wire SPI plus lock detect, on the remaining JA pins.
## CE is expected to be tied high on the analog front end board rather than driven from here.
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { o_pll_clk }];      #IO_L4N_T0_D05_14 Sch=ja_n[1]
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { o_pll_data }];     #IO_L5N_T0_D07_14 Sch=ja_n[2]
set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { o_pll_le }];       #IO_L7N_T1_D10_14 Sch=ja_n[3]
set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports { i_pll_lock }];     #IO_L8N_T1_D12_14 Sch=ja_n[4]

## Pmod Header JD - PmodAMP2 mono audio amplifier, plugged into the top row
## PmodAMP2 pin 1 AIN, pin 2 GAIN, pin 3 NC, pin 4 active low shutdown (PmodAMP2 reference
## manual Table 1), so pin 3 of the header is deliberately left unassigned
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { o_monoaudio_pwm }];       #IO_L20N_T3_A07_D23_14 Sch=jd1/ck_io[33]
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { o_monoaudio_gain }];      #IO_L21P_T3_DQS_14 Sch=jd2/ck_io[32]
set_property -dict { PACKAGE_PIN T12   IOSTANDARD LVCMOS33 } [get_ports { o_monoaudio_nshutdown }]; #IO_L22P_T3_A05_D21_14 Sch=jd4/ck_io[30]

## TODO: source synchronous timing constraints for the ADC interface.
##
## o_adc_sclk is a 30 MHz divide by two of the 60 MHz MMCM output generated in fabric, and
## i_adc_sdo is launched by the ADC on the SCLK falling edge (t_DO max 9.5 ns at DVIO 3.3 V,
## MCP33131D data sheet Table 1-2). The driver captures SDO one 60 MHz cycle after the SCLK
## rising edge, so the launch to capture path spans two 60 MHz cycles.
##
## Constraining that properly needs a generated clock on o_adc_sclk sourced from the clk_wiz
## output pin, then an input delay on i_adc_sdo referenced to its falling edge, along the lines
## of:
##
##   create_generated_clock -name adc_sclk -source <clk_wiz clk_out_60 pin> -divide_by 2 \
##       [get_ports o_adc_sclk]
##   set_input_delay -clock adc_sclk -clock_fall -max 11.0 [get_ports i_adc_sdo]
##   set_input_delay -clock adc_sclk -clock_fall -min 1.0  [get_ports i_adc_sdo]
##
## The source pin only exists once the clk_wiz IP has been generated, so this is left as a TODO
## rather than committed with a guessed hierarchical path. Until it is in place these pins carry
## no timing check. The capture point was chosen to sit a full 33 ns SCLK period away from the
## ADC launch edge, so there is a lot of margin by construction, but it is not being verified.
