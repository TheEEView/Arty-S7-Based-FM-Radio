library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity toplevel is
port (
    i_clk_12        : in std_logic;     --! 12 MHz clock input to FPGA
    i_rst           : in std_logic;     --! Active high reset input to FPGA
    -- TODO: Add volume up/down and channel selection button inputs
    o_adc_sdi       : out std_logic;    --! MCP33131 ADC SDI output to FPGA
    o_adc_sclk      : out std_logic;    --! MCP33131 ADC SCLK output to FPGA
    i_adc_sdo       : in std_logic;     --! MCP33131 ADC SDO input from FPGA
    o_adc_convst    : out std_logic;    --! MCP33131 ADC CONVST output to FPGA
    o_pwm_tune      : out std_logic     --! MAX2606 VCO PWM TUNE output to FPGA
);
end entity;

architecture rtl of toplevel is
signal clk_60               : std_logic; -- We use a 60 MHz clock for the 30 MHz ADC SCLK generation
signal mmcm_lock            : std_logic; -- MMCM lock signal to indicate stable clock output also used for reset button debounce reset input
signal inverted_mmcm_lock   : std_logic;
begin

-- TODO: Add MMCM here to generate 60 MHz clock from 12 MHz input clock

inverted_mmcm_lock <= not mmcm_lock;

-- Debounce reset button synchronized to 60 MHz sysclk to generate a 1 clock cycle high pulse for fan out to all reset inputs
i_rst_btn_deb : btn_deb
generic map (
    DEB_CNT         => 1000000,
    ACTIVE_HIGH_BTN => true
)
port map (
    i_sysclk        => clk_60,
    i_rst           => inverted_mmcm_lock, -- This will be in reset before sys clk is ready
    i_btn           => i_rst_btn_deb.o_pulse,
    o_pulse         => rst_pulse
);

-- TODO: Add debouncing for other buttons here

i_mpc33131_adc_driver : entity work.mpc33131_adc_driver
port map (
    i_clk_60        => clk_60,
    i_rst           => rst_pulse,
    o_sdi           => o_adc_sdi,
    o_sclk          => o_adc_sclk,
    i_sdo           => i_adc_sdo,
    o_convst        => o_adc_convst
    -- TODO: Add serial->parallel ADC outputs and ready pulse for use downstream
);

i_max2606_vco_driver : entity work.max2606_vco_driver
port map (
    i_clk_60        => clk_60,
    i_rst           => rst_pulse,
    -- TODO: Add PWM value input to control the VCO frequency
    o_pwm_tune      => o_pwm_tune
);

end rtl;