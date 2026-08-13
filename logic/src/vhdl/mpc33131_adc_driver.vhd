library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- MCP33131 ADC controller.
--
-- The MCP33131 is driven with a conversion strobe on CONVST and a 30 MHz serial clock
-- when the 60 MHz system clock is used.  The ADC output data is sampled on the serial
-- data input (SDO) while the clock is high, shifted into a 16-bit register, and made
-- available on o_adc_data together with a one-cycle ready pulse.
entity mpc33131_adc_driver is
port (
    i_sysclk    : in    std_logic;
    i_rst       : in    std_logic;
    o_sdi       : out   std_logic;
    o_sclk      : out   std_logic;
    i_sdo       : in    std_logic;
    o_convst    : out   std_logic;
    o_adc_data  : out   std_logic_vector(15 downto 0);
    o_ready     : out   std_logic
);
end entity mpc33131_adc_driver;

architecture rtl of mpc33131_adc_driver is

    type adc_state_t is (IDLE, CONVST, READ_DATA);

    signal state      : adc_state_t := IDLE;
    signal sclk_i     : std_logic := '0';
    signal sclk_half  : std_logic := '0';
    signal shift_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal bit_count  : natural range 0 to 15 := 0;
    signal ready_i    : std_logic := '0';

begin

    o_sdi   <= '0';
    o_sclk  <= sclk_i;
    o_ready <= ready_i;

    process (i_sysclk)
    begin
        if rising_edge(i_sysclk) then
            if i_rst = '1' then
                state      <= IDLE;
                sclk_i     <= '0';
                sclk_half  <= '0';
                shift_reg  <= (others => '0');
                bit_count  <= 0;
                ready_i    <= '0';
                o_convst   <= '0';
                o_adc_data <= (others => '0');
            else
                ready_i <= '0';

                case state is
                    when IDLE =>
                        o_convst  <= '0';
                        sclk_i    <= '0';
                        sclk_half <= '0';
                        bit_count <= 0;
                        shift_reg <= (others => '0');
                        state     <= CONVST;

                    when CONVST =>
                        -- One clock pulse on the ADC convert signal.
                        o_convst <= '1';
                        sclk_i   <= '0';
                        state    <= READ_DATA;

                    when READ_DATA =>
                        o_convst <= '0';

                        -- Generate a 30 MHz SCLK from the 60 MHz system clock.
                        if sclk_half = '0' then
                            sclk_i <= '1';

                            -- Capture the new SDO bit on the rising edge of the serial clock.
                            shift_reg <= shift_reg(14 downto 0) & i_sdo;

                            if bit_count = 15 then
                                o_adc_data <= shift_reg(14 downto 0) & i_sdo;
                                ready_i    <= '1';
                                state      <= IDLE;
                            else
                                bit_count <= bit_count + 1;
                            end if;
                        else
                            sclk_i <= '0';
                        end if;

                        sclk_half <= not sclk_half;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
