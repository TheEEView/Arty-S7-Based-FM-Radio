library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity toplevel is
port (
    i_clk_12                : in std_logic;                                 --! 12 MHz clock input to FPGA

    i_btn_vol_up            : in std_logic;                                 --! Active high volume up button
    i_btn_vol_down          : in std_logic;                                 --! Active high volume down button
    i_btn_ch_up             : in std_logic;                                 --! Active high channel up button
    i_btn_ch_down           : in std_logic;                                 --! Active high channel down button

    o_adc_sdi               : out std_logic;                                --! MCP33131 ADC SDI output to FPGA
    o_adc_sclk              : out std_logic;                                --! MCP33131 ADC SCLK output to FPGA
    i_adc_sdo               : in std_logic;                                 --! MCP33131 ADC SDO input to FPGA
    o_adc_convst            : out std_logic;                                --! MCP33131 ADC CONVST output to FPGA

    o_pll_clk               : out std_logic;                                --! ADF4351 LO synthesiser SPI clock
    o_pll_data              : out std_logic;                                --! ADF4351 LO synthesiser SPI data
    o_pll_le                : out std_logic;                                --! ADF4351 LO synthesiser latch enable
    i_pll_lock              : in  std_logic;                                --! ADF4351 MUXOUT, configured as digital lock detect

    o_monoaudio_pwm         : out std_logic;                                --! PMOD Amp2 Mono Audio PWM output
    o_monoaudio_gain        : out std_logic;                                --! PMOD Amp2 Mono Audio gain control
    o_monoaudio_nshutdown   : out std_logic                                 --! PMOD Amp2 Mono Audio shutdown control (active low)
);
end entity;

architecture rtl of toplevel is
constant SYSCLK_FREQ_HZ         : natural := 60000000;                      --! System clock frequency in Hz for debounce and ADC/VCO drivers
constant DEB_CNT_50MS           : natural := (50*SYSCLK_FREQ_HZ) / 1000;    --! Number of clock cycles the button needs to remain stable without switch bouncing
constant ADC_RESOLUTION_BITS    : natural := 16;                            --! ADC resolution in bits (MPC33131 is 16-bit)
constant CH_DW                  : natural := 6;                             --! Channel index width
constant N_CHANNELS             : natural := 52;                            --! 100.0 to 105.1 MHz inclusive on a 100 kHz raster
constant PLL_INT_BASE           : natural := 999;                           --! ADF4351 feedback divider for channel 0, the LO in units of 100 kHz
constant AUDIO_DW               : natural := 16;                            --! Demodulated mono audio sample resolution in bits
constant AUDIO_DECIM            : natural := 16;                            --! ADC to audio decimation, the ADC driver samples every 77 clocks so 60 MHz / 77 / 16 = 48.70 kHz audio

signal clk_60                   : std_logic;                                -- We use a 60 MHz clock for the 30 MHz ADC SCLK generation
signal mmcm_lock                : std_logic;                                -- MMCM lock signal to indicate stable clock output also used for reset button debounce reset input
signal mmcm_reset               : std_logic;

signal vol_up_pulse             : std_logic;
signal vol_down_pulse           : std_logic;
signal ch_up_pulse              : std_logic;
signal ch_down_pulse            : std_logic;
signal adc_data                 : std_logic_vector(ADC_RESOLUTION_BITS-1 downto 0);
signal adc_ready                : std_logic;
signal fm_demod_audio_data      : std_logic_vector(AUDIO_DW-1 downto 0);
signal fm_demod_audio_valid     : std_logic;
signal pll_channel              : std_logic_vector(CH_DW-1 downto 0);
signal pll_channel_changed      : std_logic;
signal pll_locked               : std_logic;
signal pll_unlocked             : std_logic;

component clk_wiz_60
port
(
    clk_out_60  : out   std_logic;
    locked      : out   std_logic;
    clk_in_12   : in    std_logic
);
end component;

begin

i_clk_wiz_60 : clk_wiz_60
port map (
    clk_in_12       => i_clk_12,
    clk_out_60      => clk_60,
    locked          => mmcm_lock
 );

-- Use inverted mmcm lock signal as a power on reset before the MMCM is ready
mmcm_reset <= not mmcm_lock;

-- Keep the audio silent until the LO synthesiser has locked, so retuning cannot burst noise
pll_unlocked <= not pll_locked;

i_btn_vol_up_deb : entity work.btn_deb
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

i_btn_vol_down_deb : entity work.btn_deb
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

i_btn_ch_up_deb : entity work.btn_deb
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

i_btn_ch_down_deb : entity work.btn_deb
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
generic map (
    SYSCLK_FREQ_HZ  => SYSCLK_FREQ_HZ,
    DATA_DW         => ADC_RESOLUTION_BITS
)
port map (
    i_sysclk        => clk_60,
    i_rst           => mmcm_reset,
    o_sdi           => o_adc_sdi,
    o_sclk          => o_adc_sclk,
    i_sdo           => i_adc_sdo,
    o_convst        => o_adc_convst,
    o_adc_data      => adc_data,
    o_ready         => adc_ready
);

-- Slope detector based mono demodulator, it consumes the ADC stream directly and hands back
-- audio samples at 1/AUDIO_DECIM of the ADC sample rate. It assumes the VCO has already put
-- the wanted station at the front end low IF, see the notes in fm_demodulator.vhd
i_fm_demodulator : entity work.fm_demodulator
generic map (
    ADC_DW          => ADC_RESOLUTION_BITS,
    AUDIO_DW        => AUDIO_DW,
    DECIM_FACTOR    => AUDIO_DECIM
)
port map (
    i_sysclk        => clk_60,
    i_rst           => mmcm_reset,
    i_adc_data      => adc_data,
    i_adc_ready     => adc_ready,
    o_audio         => fm_demod_audio_data,
    o_audio_valid   => fm_demod_audio_valid
);

-- Channel up/down walk a 100 kHz raster across the 100.0 to 105.1 MHz band. With the ADF4351
-- the channel index is the whole story: it maps straight onto the PLL feedback divider, so a
-- press is exactly one channel with nothing to calibrate.
i_channel_selector : entity work.channel_selector
generic map (
    CH_DW           => CH_DW,
    N_CHANNELS      => N_CHANNELS,
    CH_RST          => 0
)
port map (
    i_sysclk        => clk_60,
    i_rst           => mmcm_reset,
    i_ch_up         => ch_up_pulse,
    i_ch_down       => ch_down_pulse,
    o_channel       => pll_channel,
    o_changed       => pll_channel_changed
);

-- ADF4351 local oscillator, programmed over its three wire SPI port. Runs integer-N so there
-- are no fractional spurs, and holds the IF at exactly 100 kHz, see adf4351_driver.vhd
i_adf4351_driver : entity work.adf4351_driver
generic map (
    SYSCLK_FREQ_HZ  => SYSCLK_FREQ_HZ,
    CH_DW           => CH_DW,
    INT_BASE        => PLL_INT_BASE
)
port map (
    i_sysclk        => clk_60,
    i_rst           => mmcm_reset,
    i_channel       => pll_channel,
    i_update        => pll_channel_changed,
    i_lock          => i_pll_lock,
    o_pll_clk       => o_pll_clk,
    o_pll_data      => o_pll_data,
    o_pll_le        => o_pll_le,
    o_locked        => pll_locked,
    o_busy          => open
);

-- The audio samples are carried to the PmodAMP2 as a one bit sigma delta stream rather than a
-- plain PWM, see the notes in pmodamp2_ssm2377_audio_driver.vhd
i_pmodamp2_ssm2377_audio_driver : entity work.pmodamp2_ssm2377_audio_driver
generic map (
    AUDIO_DW        => AUDIO_DW
)
port map (
    i_sysclk        => clk_60,
    i_rst           => mmcm_reset,
    i_audio         => fm_demod_audio_data,
    i_audio_valid   => fm_demod_audio_valid,
    i_mute          => pll_unlocked,
    o_audio_pwm     => o_monoaudio_pwm,
    o_audio_gain    => o_monoaudio_gain,
    o_nshutdown     => o_monoaudio_nshutdown
);

end rtl;
