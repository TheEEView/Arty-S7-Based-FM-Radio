library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity toplevel is
port (
    i_clk_12        : in std_logic;     --! 12 MHz clock input to FPGA
    i_rst           : in std_logic;     --! Active high reset input to FPGA
    o_adc_sdi       : out std_logic;    --! MCP33131 ADC SDI output to FPGA
    o_adc_sclk      : out std_logic;    --! MCP33131 ADC SCLK output to FPGA
    i_adc_sdo       : in std_logic;     --! MCP33131 ADC SDO input from FPGA
    o_adc_convst    : out std_logic;    --! MCP33131 ADC CONVST output to FPGA
    o_pwm_tune      : out std_logic     --! MAX2606 VCO PWM TUNE output to FPGA
);
end entity;