library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- The MAX2606 is tuned by the analog voltage on its TUNE pin, so this driver generates a
-- single bit PWM stream which is turned back into a DC tuning voltage by the RC low pass
-- filter on the analog front end board. The tuning voltage is therefore
-- (i_tune / 2**TUNE_DW) * VCCO, so a larger i_tune value means a higher VCO frequency.
--
-- The PWM period is 2**TUNE_DW system clock cycles, giving a carrier of
-- SYSCLK_FREQ_HZ / 2**TUNE_DW (14.65 kHz with a 60 MHz i_sysclk and the default 12-bit
-- resolution). Reducing TUNE_DW trades tuning resolution for a higher PWM carrier which is
-- easier for the RC filter to remove.
entity max2606_vco_driver is
generic (
    TUNE_DW     : natural := 12;                                --! PWM duty cycle resolution in bits
    TUNE_RST    : natural := 2**(TUNE_DW-1)                     --! Duty cycle held during reset, defaults to mid scale so the VCO starts mid band
);
port (
    i_sysclk    : in    std_logic;
    i_rst       : in    std_logic;                              --! Synchronous active high reset
    i_tune      : in    std_logic_vector(TUNE_DW-1 downto 0);   --! Unsigned PWM duty cycle setting the VCO tuning voltage
    o_pwm_tune  : out   std_logic                               --! PWM output driving the MAX2606 TUNE pin RC filter
);
end max2606_vco_driver;

architecture rtl of max2606_vco_driver is
constant PWM_CNT_MAX    : unsigned(TUNE_DW-1 downto 0) := (others => '1');

signal pwm_cnt          : unsigned(TUNE_DW-1 downto 0);  -- Free running PWM period counter
signal duty             : unsigned(TUNE_DW-1 downto 0);  -- Duty cycle in use for the current PWM period
begin

process (i_sysclk)
begin
    if rising_edge(i_sysclk) then
        if i_rst = '1' then
            pwm_cnt     <= (others => '0');
            duty        <= to_unsigned(TUNE_RST, TUNE_DW);
            o_pwm_tune  <= '0';
        else
            pwm_cnt <= pwm_cnt + 1;

            -- Only sample i_tune at the end of a PWM period so that a duty cycle change part
            -- way through a period cannot shorten or stretch the pulse currently being output
            if pwm_cnt = PWM_CNT_MAX then
                duty <= unsigned(i_tune);
            end if;

            -- Registered PWM output which is high for duty clock cycles of every PWM period,
            -- delayed by one clock cycle by the output register. Note an all ones i_tune gives
            -- a (2**TUNE_DW-1)/2**TUNE_DW duty cycle rather than a full scale tuning voltage
            if pwm_cnt < duty then
                o_pwm_tune <= '1';
            else
                o_pwm_tune <= '0';
            end if;
        end if;
    end if;
end process;

end rtl;
