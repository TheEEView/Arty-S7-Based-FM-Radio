library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Cascaded Integrator Comb (CIC) Decimating Low Pass Filter. STAGES integrator sections run at
-- the input sample rate, the sample rate is then dropped by DECIM_FACTOR and STAGES comb
-- sections run at the decimated rate. A CIC needs no multipliers and no coefficient storage
-- which makes it the cheapest way to take the large rate reduction from the ADC sample rate
-- down to the audio sample rate.
--
-- The filter has a gain of (DECIM_FACTOR*M)**STAGES with the differential delay M fixed at 1,
-- so the registers are widened by that many bits and the output is taken from the top
-- DATA_OUT_DW bits of the last comb, which normalises the gain back to roughly unity. Sizing
-- the registers this way is what stops the integrators, which on their own have infinite DC
-- gain, from losing data when they wrap around.
--
-- The price of the cheap implementation is passband droop, the response sags towards the band
-- edge rather than staying flat. The FM demodulator flattens that back out with a short
-- compensating filter running at the decimated rate.
entity cic_decimator is
generic (
    DATA_IN_DW      : natural := 18;                                    --! Input sample width
    DATA_OUT_DW     : natural := 18;                                    --! Output sample width, taken from the top of the last comb register
    STAGES          : natural := 3;                                     --! Number of integrator and comb stages, more stages give a steeper roll off and more droop
    DECIM_FACTOR    : natural := 40                                     --! Input to output sample rate ratio
);
port (
    i_sysclk        : in    std_logic;
    i_rst           : in    std_logic;                                  --! Synchronous active high reset
    i_data          : in    std_logic_vector(DATA_IN_DW-1 downto 0);    --! Signed input sample
    i_valid         : in    std_logic;                                  --! Single cycle strobe qualifying i_data
    o_data          : out   std_logic_vector(DATA_OUT_DW-1 downto 0);   --! Signed decimated output sample
    o_valid         : out   std_logic                                   --! Single cycle strobe qualifying o_data
);
end cic_decimator;

architecture rtl of cic_decimator is

-- Number of bits of gain the filter introduces, ceil(log2((DECIM_FACTOR*M)**STAGES)) with M of
-- 1. Worked out by repeated integer multiplication and halving so that no floating point is
-- needed at elaboration time. DECIM_FACTOR**STAGES has to stay inside the range of natural,
-- which it comfortably does for any sensible audio decimation.
function cic_gain_bits(decim : natural; stages : natural) return natural is
    variable gain : natural := 1;
    variable bits : natural := 0;
begin
    for i in 1 to stages loop
        gain := gain * decim;
    end loop;

    while gain > 1 loop
        gain := (gain + 1) / 2;
        bits := bits + 1;
    end loop;

    return bits;
end function;

constant GAIN_BITS  : natural := cic_gain_bits(DECIM_FACTOR, STAGES);
constant REG_DW     : natural := DATA_IN_DW + GAIN_BITS;            -- Hogenauer register width, wide enough that the integrator wrap around is harmless

type cic_reg_array_t is array (natural range <>) of signed(REG_DW-1 downto 0);

signal integrator   : cic_reg_array_t(0 to STAGES-1);               -- Integrator accumulators running at the input sample rate
signal comb         : cic_reg_array_t(0 to STAGES-1);               -- Comb outputs running at the decimated sample rate
signal comb_delay   : cic_reg_array_t(0 to STAGES-1);               -- One decimated sample delay feeding each comb subtraction

signal decim_cnt    : natural range 0 to DECIM_FACTOR-1;            -- Counts input samples to pick the ones that make it through the decimator
signal comb_en      : std_logic;                                    -- Set on the input sample that lands on a decimated output
signal comb_en_d    : std_logic;                                    -- comb_en delayed so the integrators have settled before the combs sample them

begin

process (i_sysclk)
begin
    if rising_edge(i_sysclk) then
        if i_rst = '1' then
            integrator  <= (others => (others => '0'));
            comb        <= (others => (others => '0'));
            comb_delay  <= (others => (others => '0'));
            decim_cnt   <= 0;
            comb_en     <= '0';
            comb_en_d   <= '0';
            o_valid     <= '0';
        else
            comb_en   <= '0';
            comb_en_d <= comb_en;
            o_valid   <= '0';

            -- Integrator cascade, each stage accumulates the previous stage. Reading the
            -- previous stage as a signal means every stage adds one input sample of delay,
            -- which pipelines the cascade without changing the frequency response.
            if i_valid = '1' then
                integrator(0) <= integrator(0) + resize(signed(i_data), REG_DW);

                for s in 1 to STAGES-1 loop
                    integrator(s) <= integrator(s) + integrator(s-1);
                end loop;

                if decim_cnt = DECIM_FACTOR-1 then
                    decim_cnt <= 0;
                    comb_en   <= '1';
                else
                    decim_cnt <= decim_cnt + 1;
                end if;
            end if;

            -- Comb cascade, each stage subtracts the previous decimated sample to undo the
            -- integrators. Only the samples surviving decimation are clocked through here.
            if comb_en_d = '1' then
                comb_delay(0) <= integrator(STAGES-1);
                comb(0)       <= integrator(STAGES-1) - comb_delay(0);

                for s in 1 to STAGES-1 loop
                    comb_delay(s) <= comb(s-1);
                    comb(s)       <= comb(s-1) - comb_delay(s);
                end loop;

                o_valid <= '1';
            end if;
        end if;
    end if;
end process;

-- Taking the top DATA_OUT_DW bits divides by 2**GAIN_BITS which cancels the filter gain
o_data <= std_logic_vector(comb(STAGES-1)(REG_DW-1 downto REG_DW-DATA_OUT_DW));

end rtl;
