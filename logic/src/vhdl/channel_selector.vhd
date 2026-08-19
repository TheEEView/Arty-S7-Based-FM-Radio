library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Channel selection for a synthesiser based local oscillator. Each debounced channel button
-- press moves one channel along a fixed raster, clamped at the ends of the band, and a change
-- pulse tells the PLL driver to reprogram.
--
-- With the ADF4351 frequency plan there is nothing to calibrate here: the channel index maps
-- straight onto the PLL feedback divider, so a channel is exactly one raster step and never
-- drifts.
entity channel_selector is
generic (
    CH_DW       : natural := 6;                                 --! Channel index width, must hold N_CHANNELS-1
    N_CHANNELS  : natural := 52;                                --! Channels in the band, 100.0 to 105.1 MHz on a 100 kHz raster
    CH_RST      : natural := 0                                  --! Channel selected out of reset
);
port (
    i_sysclk    : in    std_logic;
    i_rst       : in    std_logic;                              --! Synchronous active high reset
    i_ch_up     : in    std_logic;                              --! Single cycle pulse from the debounced channel up button
    i_ch_down   : in    std_logic;                              --! Single cycle pulse from the debounced channel down button
    o_channel   : out   std_logic_vector(CH_DW-1 downto 0);     --! Current channel index
    o_changed   : out   std_logic                               --! Single cycle pulse when o_channel actually moved
);
end channel_selector;

architecture rtl of channel_selector is

signal channel : unsigned(CH_DW-1 downto 0);

begin

assert N_CHANNELS >= 2
    report "channel_selector: need at least two channels" severity failure;
assert N_CHANNELS <= 2**CH_DW
    report "channel_selector: CH_DW is too narrow for N_CHANNELS" severity failure;
assert CH_RST < N_CHANNELS
    report "channel_selector: CH_RST is outside the band" severity failure;

o_channel <= std_logic_vector(channel);

process (i_sysclk)
begin
    if rising_edge(i_sysclk) then
        if i_rst = '1' then
            channel   <= to_unsigned(CH_RST, CH_DW);
            o_changed <= '0';
        else
            o_changed <= '0';

            -- Ignore both buttons pressed together.
            -- Clamping rather than wrapping stops a press at the top of the band reappearing at
            -- the bottom.
            if i_ch_up = '1' and i_ch_down = '0' then
                if channel < N_CHANNELS-1 then
                    channel   <= channel + 1;
                    o_changed <= '1';
                end if;

            elsif i_ch_down = '1' and i_ch_up = '0' then
                if channel > 0 then
                    channel   <= channel - 1;
                    o_changed <= '1';
                end if;
            end if;
        end if;
    end if;
end process;

end rtl;
