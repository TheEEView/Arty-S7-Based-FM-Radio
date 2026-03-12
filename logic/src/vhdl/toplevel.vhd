library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity toplevel is
port (
    i_clk_12        : in std_logic;     --! 12 MHz clock input to FPGA
    i_btn_vol_up    : in std_logic;     --! Active high volume up button
    i_btn_vol_down  : in std_logic;     --! Active high volume down button
    i_btn_ch_up     : in std_logic;     --! Active high channel up button
    i_btn_ch_down   : in std_logic;     --! Active high channel down button
    o_adc_sdi       : out std_logic;    --! MCP33131 ADC SDI output to FPGA
    o_adc_sclk      : out std_logic;    --! MCP33131 ADC SCLK output to FPGA
    i_adc_sdo       : in std_logic;     --! MCP33131 ADC SDO input from FPGA
    o_adc_convst    : out std_logic;    --! MCP33131 ADC CONVST output to FPGA
    o_pwm_tune      : out std_logic     --! MAX2606 VCO PWM TUNE output to FPGA
);
end entity;

architecture rtl of toplevel is
constant SYSCLK_FREQ_HZ     : natural := 60000000; --! System clock frequency in Hz for debounce and ADC/VCO drivers
constant DEB_CNT_50MS       : natural := (50*SYSCLK_FREQ_HZ) / 1000; --! Number of clock cycles the button needs to remain stable without switch bouncing

signal clk_60               : std_logic; -- We use a 60 MHz clock for the 30 MHz ADC SCLK generation
signal mmcm_lock            : std_logic; -- MMCM lock signal to indicate stable clock output also used for reset button debounce reset input
signal mmcm_reset           : std_logic;

signal vol_up_pulse         : std_logic;
signal vol_down_pulse       : std_logic;
signal ch_up_pulse          : std_logic;
signal ch_down_pulse        : std_logic;
begin

-- TODO: Add MMCM here to generate 60 MHz clock from 12 MHz input clock

-- Use inverted mmcm lock signal as a power on reset before the MMCM is ready
mmcm_reset <= not mmcm_lock;

i_btn_vol_up_deb : btn_deb
generic map (
    DEB_CNT         => DEB_CNT_50MS,
    ACTIVE_HIGH_BTN => true
)
port map (
    i_sysclk        => clk_60,
    i_rst           => mmcm_reset,
    i_btn           => i_btn_vol_up,
    o_pulse         => vol_up_pulse
);

i_btn_vol_down_deb : btn_deb
generic map (
    DEB_CNT         => DEB_CNT_50MS,
    ACTIVE_HIGH_BTN => true
)
port map (
    i_sysclk        => clk_60,
    i_rst           => mmcm_reset,
    i_btn           => i_btn_vol_down,
    o_pulse         => vol_down_pulse
);

i_btn_ch_up_deb : btn_deb
generic map (
    DEB_CNT         => DEB_CNT_50MS,
    ACTIVE_HIGH_BTN => true
)
port map (
    i_sysclk        => clk_60,
    i_rst           => mmcm_reset,
    i_btn           => i_btn_ch_up,
    o_pulse         => ch_up_pulse
);

i_btn_ch_down_deb : btn_deb
generic map (
    DEB_CNT         => DEB_CNT_50MS,
    ACTIVE_HIGH_BTN => true
)
port map (
    i_sysclk        => clk_60,
    i_rst           => mmcm_reset,
    i_btn           => i_btn_ch_down,
    o_pulse         => ch_down_pulse
);

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
