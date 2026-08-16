library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Driver for the Digilent PmodAMP2, an SSM2377 mono class D amplifier on a six pin GPIO header.
-- Pin 1 is the audio input, pin 2 selects the gain, pin 3 is not connected and pin 4 is an
-- active low shutdown (PmodAMP2 reference manual, Table 1).
--
-- The audio input is analog, but the module has a reconstruction filter in front of it and the
-- SSM2377 runs its own sigma delta modulator internally, so a one bit oversampled stream is
-- exactly what it wants. A plain PWM is not usable here: carrying the full AUDIO_DW resolution
-- as a duty cycle would put the carrier at 60 MHz / 2**16, about 915 Hz, right in the middle of
-- the audio band. A second order sigma delta instead keeps one bit of output resolution but
-- pushes its quantisation noise up out of the audio band, which is what buys back the dynamic
-- range. Modelled in band signal to noise is about 69 dB at the default 3.75 MHz modulator
-- rate, comfortably past what broadcast FM itself delivers.
--
-- The modulator is second order for the extra noise shaping, which is only conditionally stable,
-- so the input is scaled down by INPUT_SHIFT and both integrators saturate rather than wrap. At
-- the defaults the integrators were never seen to reach their limits even on full scale input.
entity pmodamp2_ssm2377_audio_driver is
generic (
    AUDIO_DW        : natural := 16;                                --! Audio sample width
    MOD_CLK_DIV     : natural := 16;                                --! System clock cycles per modulator step, 16 gives 3.75 MHz from a 60 MHz i_sysclk
    INPUT_SHIFT     : natural := 1;                                 --! Input attenuation as a right shift, buys the second order loop its stability headroom
    ACC_GUARD_BITS  : natural := 4;                                 --! Extra bits on the integrators above the sample width
    GAIN_6DB        : boolean := true;                              --! true drives GAIN high for 6 dB, false drives it low for 12 dB
    UNMUTE_CYCLES   : natural := 6000000                            --! Cycles to hold the amplifier shut down after reset, 100 ms at 60 MHz, covers the demodulator DC blocker settling
);
port (
    i_sysclk        : in    std_logic;
    i_rst           : in    std_logic;                              --! Synchronous active high reset
    i_audio         : in    std_logic_vector(AUDIO_DW-1 downto 0);  --! Signed mono audio sample
    i_audio_valid   : in    std_logic;                              --! Single cycle strobe qualifying i_audio
    o_audio_pwm     : out   std_logic;                              --! One bit sigma delta stream to the PmodAMP2 audio input
    o_audio_gain    : out   std_logic;                              --! PmodAMP2 gain select
    o_nshutdown     : out   std_logic                               --! PmodAMP2 active low shutdown
);
end pmodamp2_ssm2377_audio_driver;

architecture rtl of pmodamp2_ssm2377_audio_driver is

constant ACC_DW     : natural := AUDIO_DW + ACC_GUARD_BITS;
-- The one bit feedback is worth full scale of the sample width
constant FB_LEVEL   : signed(ACC_DW-1 downto 0) := to_signed(2**(AUDIO_DW-1), ACC_DW);

-- Clip rather than wrap, a wrapped integrator would turn a loud passage into a burst of noise
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

signal audio_hold   : signed(AUDIO_DW-1 downto 0);              -- Latched sample, held across the many modulator steps per audio sample
signal mod_cnt      : natural range 0 to MOD_CLK_DIV-1;         -- Divides i_sysclk down to the modulator rate
signal acc1         : signed(ACC_DW-1 downto 0);                -- First integrator
signal acc2         : signed(ACC_DW-1 downto 0);                -- Second integrator
signal sdm_q        : std_logic;                                -- One bit modulator output, also the feedback selector
signal unmute_cnt   : natural range 0 to UNMUTE_CYCLES;         -- Holds the amplifier down until the audio chain has settled

begin

-- Driving GAIN high selects 6 dB, low selects 12 dB
o_audio_gain <= '1' when GAIN_6DB else '0';
o_audio_pwm  <= sdm_q;

process (i_sysclk)
    variable audio_in : signed(ACC_DW-1 downto 0);
    variable feedback : signed(ACC_DW-1 downto 0);
    variable acc1_sum : signed(ACC_DW+1 downto 0);
    variable acc1_sat : signed(ACC_DW-1 downto 0);
    variable acc2_sum : signed(ACC_DW+1 downto 0);
begin
    if rising_edge(i_sysclk) then
        if i_rst = '1' then
            audio_hold  <= (others => '0');
            mod_cnt     <= 0;
            acc1        <= (others => '0');
            acc2        <= (others => '0');
            sdm_q       <= '0';
            unmute_cnt  <= 0;
            o_nshutdown <= '0';
        else
            -- Keep the amplifier shut down until the upstream chain has settled, so the
            -- demodulator DC blocker charging up never reaches the speaker
            if unmute_cnt = UNMUTE_CYCLES then
                o_nshutdown <= '1';
            else
                unmute_cnt  <= unmute_cnt + 1;
                o_nshutdown <= '0';
            end if;

            -- Hold the most recent audio sample for the modulator to chew on
            if i_audio_valid = '1' then
                audio_hold <= signed(i_audio);
            end if;

            if mod_cnt = MOD_CLK_DIV-1 then
                mod_cnt <= 0;

                audio_in := resize(shift_right(audio_hold, INPUT_SHIFT), ACC_DW);

                if sdm_q = '1' then
                    feedback := FB_LEVEL;
                else
                    feedback := -FB_LEVEL;
                end if;

                -- Second order loop, both integrators fed by the same one bit feedback. The
                -- comparator on the second integrator is the one bit quantiser.
                acc1_sum := resize(acc1, ACC_DW+2) + resize(audio_in, ACC_DW+2) - resize(feedback, ACC_DW+2);
                acc1_sat := saturate(acc1_sum, ACC_DW);
                acc1     <= acc1_sat;

                acc2_sum := resize(acc2, ACC_DW+2) + resize(acc1_sat, ACC_DW+2) - resize(feedback, ACC_DW+2);
                acc2     <= saturate(acc2_sum, ACC_DW);

                if acc2_sum >= 0 then
                    sdm_q <= '1';
                else
                    sdm_q <= '0';
                end if;
            else
                mod_cnt <= mod_cnt + 1;
            end if;
        end if;
    end if;
end process;

end rtl;
