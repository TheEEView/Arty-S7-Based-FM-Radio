library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Mono FM demodulator working straight off the MCP33131 ADC sample stream.
--
-- The analog front end mixes the wanted station down against the MAX2606 VCO and band limits
-- the result with a 320 kHz anti aliasing filter, so the ADC sees a single real valued low IF
-- copy of the station. This block turns that into mono audio with a slope detector:
--
--     ADC -> d/dt -> |x| -> CIC decimator -> DC block -> droop compensator -> de-emphasis
--
--   1. Differentiating an FM signal converts the frequency deviation into an amplitude
--      variation, because d/dt of a constant amplitude tone has an envelope proportional to
--      its instantaneous frequency. The five point central difference
--      (-x[n] + 8x[n-1] - 8x[n-3] + x[n-4]) / 12 is used rather than a plain two tap
--      difference, see the sample rate note below for why that matters here. It also rejects
--      the ADC DC offset for free, which is why the input coding only matters for the sign.
--   2. Taking the magnitude full wave rectifies that AM signal, giving the wanted envelope
--      plus a replica of it centred on twice the instantaneous frequency.
--   3. The CIC filters away that replica along with everything above the audio band and drops
--      the sample rate by DECIM_FACTOR down to the audio sample rate.
--   4. The rectified envelope sits on a large DC pedestal set by the IF carrier level, which a
--      leaky integrator tracks and subtracts. The output stays muted until that estimate has
--      settled, otherwise the startup transient arrives as a full scale thump.
--   5. A short symmetric filter flattens the CIC passband droop back out.
--   6. A single pole IIR applies the broadcast de-emphasis time constant, which doubles as the
--      final audio band limiting by rolling off the 19 kHz stereo pilot and everything above it.
--
-- Note on VCO placement. A slope detector needs the instantaneous frequency to stay above zero
-- across the whole modulation cycle, so the VCO has to sit an IF away from the station carrier
-- rather than exactly on top of it. Park the LO on the carrier and the deviation folds through
-- zero, which full wave rectifies the audio, a 1 kHz tone comes back out at 2 kHz.
--
-- Note on sample rate. The ADC runs at 779 ksps, so a +/-75 kHz deviation swings the
-- instantaneous frequency across a large fraction of Nyquist and no short differentiator stays
-- linear over that span. This is what drives the choice of kernel, the five point difference
-- tracks the ideal jw response roughly four times further up the band than a two tap difference
-- and cuts distortion by three to five times. The IF then wants to be as low as it can go while
-- still clearing the deviation: 100 to 110 kHz keeps the instantaneous frequency in the 25 to
-- 185 kHz range and models at 5 to 6 % distortion at full deviation, falling to about 2 % at the
-- deviation typical programme material runs. Pushing the IF up to 150 kHz triples that.
--
-- If better than that is wanted, the fix is architectural rather than a tuning change: mix to
-- complex baseband at fs/4 (where the LO reduces to the multiplier free sequence 1, 0, -1, 0)
-- and recover the phase with a CORDIC, which measures deviation exactly instead of relying on a
-- locally linear frequency response.
entity fm_demodulator is
generic (
    ADC_DW              : natural := 16;                                --! ADC sample width
    ADC_TWOS_COMPLEMENT : boolean := true;                              --! ADC output coding, true for two's complement as the MCP33131D uses
    AUDIO_DW            : natural := 16;                                --! Demodulated audio sample width
    DIFF_SHIFT          : natural := 3;                                 --! Right shift applied to the differentiator, trades audio level against clipping headroom
    CIC_STAGES          : natural := 3;                                 --! CIC integrator and comb stages
    DECIM_FACTOR        : natural := 16;                                --! ADC to audio sample rate ratio, 779.2 ksps / 16 = 48.70 kHz
    CIC_COMP_ALPHA      : natural := 3;                                 --! CIC droop compensator strength as sixteenths (0 to 31), 3 holds the response to +/-0.6 dB over 0 to 15 kHz, 0 bypasses it
    DC_BLOCK_SHIFT      : natural := 10;                                --! DC blocker time constant in audio samples as a power of two, 48.7 kHz / (2*pi*1024) gives a 7.6 Hz corner
    DEEMPHASIS_ALPHA    : natural := 15696                              --! De-emphasis coefficient in Q0.16, (1 - exp(-1/(fs*tau))) * 2**16, at 48.70 kHz use 15696 for 75 us or 22072 for 50 us
);
port (
    i_sysclk            : in    std_logic;
    i_rst               : in    std_logic;                              --! Synchronous active high reset
    i_adc_data          : in    std_logic_vector(ADC_DW-1 downto 0);    --! Sample from the MCP33131 ADC driver
    i_adc_ready         : in    std_logic;                              --! Single cycle strobe qualifying i_adc_data
    o_audio             : out   std_logic_vector(AUDIO_DW-1 downto 0);  --! Signed mono audio sample
    o_audio_valid       : out   std_logic                               --! Single cycle strobe qualifying o_audio, one per DECIM_FACTOR ADC samples
);
end fm_demodulator;

architecture rtl of fm_demodulator is

-- The differentiator taps sum to 18 in magnitude, so the raw kernel output needs five bits more
-- than the ADC sample. Shifting it back down by DIFF_SHIFT gives back that many bits, and the
-- 18 < 2**5 headroom is what makes taking abs() at this width safe.
constant RAW_DW         : natural := ADC_DW + 5;
constant ENV_DW         : natural := RAW_DW - DIFF_SHIFT;
constant DC_ACC_DW      : natural := ENV_DW + DC_BLOCK_SHIFT + 1;       -- Leaky integrator settles at 2**DC_BLOCK_SHIFT times the mean, plus a guard bit
constant COMP_SHIFT     : natural := 4;                                 -- Droop compensator coefficients are sixteenths
constant COMP_DW        : natural := ENV_DW + 8;                        -- Widest compensator partial product plus headroom for the three tap sum
constant DEEMPH_FRAC    : natural := 16;                                -- Fractional bits of DEEMPHASIS_ALPHA
constant DEEMPH_ACC_DW  : natural := ENV_DW + DEEMPH_FRAC + 2;          -- De-emphasis state carried at full precision plus two guard bits
-- Hold the output at zero until the DC estimate has settled, four time constants is plenty
constant MUTE_SAMPLES   : natural := 4 * 2**DC_BLOCK_SHIFT;

constant COMP_ALPHA     : signed(5 downto 0) := to_signed(CIC_COMP_ALPHA, 6);

-- Recentre the raw ADC code on zero so that either output coding ends up as a signed sample.
-- For straight binary this is just an inversion of the top bit.
function adc_to_signed(data : std_logic_vector) return signed is
begin
    if ADC_TWOS_COMPLEMENT then
        return signed(data);
    else
        return signed(unsigned(data) - to_unsigned(2**(data'length-1), data'length));
    end if;
end function;

-- Clip to width bits instead of letting the datapath wrap around. A wrap turns a loud passage
-- into full scale noise whereas clipping only flat tops it. Requires data to be wider than
-- width, which every call below satisfies.
function saturate(data : signed; width : natural) return signed is
    constant MAX_VAL : signed(data'length-1 downto 0) := to_signed(2**(width-1)-1, data'length);
    constant MIN_VAL : signed(data'length-1 downto 0) := to_signed(-(2**(width-1)), data'length);
begin
    if data > MAX_VAL then
        return resize(MAX_VAL, width);
    elsif data < MIN_VAL then
        return resize(MIN_VAL, width);
    else
        return resize(data, width);
    end if;
end function;

signal adc_sample       : signed(ADC_DW-1 downto 0);                    -- Current ADC sample recentred on zero
signal adc_d1           : signed(ADC_DW-1 downto 0);                    -- Four sample delay line feeding the differentiator kernel
signal adc_d2           : signed(ADC_DW-1 downto 0);
signal adc_d3           : signed(ADC_DW-1 downto 0);
signal adc_d4           : signed(ADC_DW-1 downto 0);
signal diff             : signed(ENV_DW-1 downto 0);                    -- Differentiated IF signal, FM deviation now shows up as amplitude
signal diff_valid       : std_logic;
signal env              : signed(ENV_DW-1 downto 0);                    -- Rectified envelope, always non negative
signal env_valid        : std_logic;

signal cic_data         : std_logic_vector(ENV_DW-1 downto 0);          -- Envelope at the audio sample rate, still sitting on its DC pedestal
signal cic_valid        : std_logic;

signal dc_acc           : signed(DC_ACC_DW-1 downto 0);                 -- Leaky integrator holding 2**DC_BLOCK_SHIFT times the envelope mean
signal dc_mean          : signed(ENV_DW-1 downto 0);                    -- Envelope mean, the DC pedestal to subtract

signal comp_d1          : signed(ENV_DW-1 downto 0);                    -- Droop compensator delay line at the audio sample rate
signal comp_d2          : signed(ENV_DW-1 downto 0);

signal deemph_acc       : signed(DEEMPH_ACC_DW-1 downto 0);             -- De-emphasis state with DEEMPH_FRAC fractional bits
signal deemph_state     : signed(ENV_DW-1 downto 0);                    -- Integer part of the de-emphasis state, the previous output sample

signal mute_cnt         : natural range 0 to MUTE_SAMPLES;              -- Counts audio samples until the DC estimate has settled

begin

adc_sample <= adc_to_signed(i_adc_data);

-- Differentiate and rectify at the ADC sample rate
process (i_sysclk)
    variable kernel : signed(RAW_DW-1 downto 0);
begin
    if rising_edge(i_sysclk) then
        if i_rst = '1' then
            adc_d1          <= (others => '0');
            adc_d2          <= (others => '0');
            adc_d3          <= (others => '0');
            adc_d4          <= (others => '0');
            diff            <= (others => '0');
            diff_valid      <= '0';
            env             <= (others => '0');
            env_valid       <= '0';
        else
            -- One pipeline stage per arithmetic step so the strobe tracks the data
            diff_valid <= i_adc_ready;
            env_valid  <= diff_valid;

            if i_adc_ready = '1' then
                -- Five point central difference. Everything is resized before the arithmetic
                -- because numeric_std returns the width of the wider operand, not a bit more.
                kernel := shift_left(resize(adc_d1, RAW_DW) - resize(adc_d3, RAW_DW), 3)
                          - resize(adc_sample, RAW_DW)
                          + resize(adc_d4, RAW_DW);
                diff   <= resize(shift_right(kernel, DIFF_SHIFT), ENV_DW);

                adc_d1 <= adc_sample;
                adc_d2 <= adc_d1;
                adc_d3 <= adc_d2;
                adc_d4 <= adc_d3;
            end if;

            if diff_valid = '1' then
                -- Full wave rectify to recover the envelope of the differentiated signal
                env <= abs(diff);
            end if;
        end if;
    end if;
end process;

-- Anti alias and drop from the ADC sample rate to the audio sample rate
i_cic_decimator : entity work.cic_decimator
generic map (
    DATA_IN_DW      => ENV_DW,
    DATA_OUT_DW     => ENV_DW,
    STAGES          => CIC_STAGES,
    DECIM_FACTOR    => DECIM_FACTOR
)
port map (
    i_sysclk        => i_sysclk,
    i_rst           => i_rst,
    i_data          => std_logic_vector(env),
    i_valid         => env_valid,
    o_data          => cic_data,
    o_valid         => cic_valid
);

dc_mean      <= dc_acc(DC_ACC_DW-2 downto DC_BLOCK_SHIFT);
deemph_state <= deemph_acc(DEEMPH_FRAC+ENV_DW-1 downto DEEMPH_FRAC);

-- Audio rate post processing, one pass per decimated sample
process (i_sysclk)
    variable env_dc_free : signed(ENV_DW-1 downto 0);
    variable comp_acc    : signed(COMP_DW-1 downto 0);
    variable comp_out    : signed(ENV_DW-1 downto 0);
    variable deemph_err  : signed(ENV_DW downto 0);
    variable deemph_next : signed(DEEMPH_ACC_DW-1 downto 0);
begin
    if rising_edge(i_sysclk) then
        if i_rst = '1' then
            dc_acc          <= (others => '0');
            comp_d1         <= (others => '0');
            comp_d2         <= (others => '0');
            deemph_acc      <= (others => '0');
            mute_cnt        <= 0;
            o_audio         <= (others => '0');
            o_audio_valid   <= '0';
        else
            o_audio_valid <= '0';

            if cic_valid = '1' then
                -- Strip the rectifier DC pedestal. Feeding the error back into the integrator
                -- makes dc_acc settle at 2**DC_BLOCK_SHIFT times the envelope mean, so dc_mean
                -- is that mean and the result swings symmetrically about zero.
                env_dc_free := signed(cic_data) - dc_mean;
                dc_acc      <= dc_acc + resize(env_dc_free, DC_ACC_DW);

                comp_d1 <= env_dc_free;
                comp_d2 <= comp_d1;

                -- Three tap symmetric compensator (-a, 16 + 2a, -a) / 16 across x[n], x[n-1]
                -- and x[n-2], which lifts the top of the audio band by just enough to cancel
                -- the CIC droop. The taps sum to 16 so it leaves DC untouched.
                comp_acc := shift_left(resize(comp_d1, COMP_DW), COMP_SHIFT)
                          + resize(COMP_ALPHA * (shift_left(resize(comp_d1, ENV_DW+2), 1)
                                                 - resize(env_dc_free, ENV_DW+2)
                                                 - resize(comp_d2, ENV_DW+2)), COMP_DW);
                comp_out := saturate(comp_acc(COMP_DW-1 downto COMP_SHIFT), ENV_DW);

                -- Single pole de-emphasis y[n] = y[n-1] + alpha * (x[n] - y[n-1]). The state is
                -- kept with DEEMPH_FRAC fractional bits so that alpha, which is well under one,
                -- is not quantised away to nothing on quiet passages.
                deemph_err  := resize(comp_out, ENV_DW+1) - resize(deemph_state, ENV_DW+1);
                deemph_next := deemph_acc + resize(deemph_err * to_signed(DEEMPHASIS_ALPHA, DEEMPH_FRAC+1), DEEMPH_ACC_DW);
                deemph_acc  <= deemph_next;

                -- The DC estimate starts at zero and has to charge up to the carrier level, so
                -- stay muted until it is there rather than emit the settling ramp
                if mute_cnt < MUTE_SAMPLES then
                    mute_cnt <= mute_cnt + 1;
                    o_audio  <= (others => '0');
                else
                    o_audio  <= std_logic_vector(saturate(deemph_next(DEEMPH_FRAC+ENV_DW-1 downto DEEMPH_FRAC), AUDIO_DW));
                end if;

                o_audio_valid <= '1';
            end if;
        end if;
    end if;
end process;

end rtl;
