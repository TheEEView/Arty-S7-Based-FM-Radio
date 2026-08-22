library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Driver for the ADF4351 VCO used as the receiver local oscillator
-- Register field positions follow the ADF4351 data sheet as encoded in
-- the Analog Devices no-OS and Linux IIO drivers (adf4350.h).
--
-- Frequency plan, chosen so the part runs in integer-N mode:
--
--   REFIN / R_COUNTER = 3.2 MHz phase detector frequency
--   f_VCO             = 3.2 MHz * INT              (3196.8 to 3360.0 MHz)
--   f_LO              = f_VCO / 32                 (99.9 to 105.0 MHz)
--
-- Dividing the VCO by 32 makes the output exactly INT * 100 kHz, so INT is just the LO frequency
-- counted in 100 kHz steps and the channel index maps onto it with a single addition:
--
--   INT = INT_BASE + channel,  INT_BASE = 999  ->  LO 99.9 MHz  ->  station 100.0 MHz
--
-- Every channel in the 100.0 to 105.1 MHz band is an exact integer N. There is no
-- fractional modulus, no calibration table, and the IF stays pinned at 100 kHz instead of
-- drifting with temperature the way an open loop varactor does, which matters because the slope
-- detector in fm_demodulator is sensitive to where the IF actually sits.
--
-- Two constraints from the data sheet drive the fixed settings below. The VCO runs above 3 GHz,
-- which rules out the 4/5 prescaler and forces 8/9 (needing N >= 75, and N is about 1000 here).
-- The band select clock must stay at or below 125 kHz, so the divider of 32 puts it at 100 kHz.
--
-- Registers are written R5 first down to R0, as both vendor drivers do, because writing R0 is
-- what starts the VCO band selection and it has to see the rest of the configuration already in
-- place. All six are rewritten on every channel change: at 192 bits it costs tens of
-- microseconds and avoids reasoning about which registers are double buffered.
entity adf4351_driver is
generic (
    SYSCLK_FREQ_HZ  : natural := 60000000;                      --! System clock frequency in Hz
    CH_DW           : natural := 6;                             --! Channel index width
    INT_BASE        : natural := 999;                           --! Feedback divider for channel 0, LO in units of 100 kHz
    R_COUNTER       : natural := 4;                             --! Reference divider, REFIN/R gives the 3.2 MHz phase detector frequency (12.8 MHz reference)
    RF_DIV_SEL      : natural := 5;                             --! Output divider select, 5 means divide by 32
    BAND_SEL_DIV    : natural := 32;                            --! Band select clock divider, keeps PFD/this at or below 125 kHz
    MOD_VALUE       : natural := 2;                             --! Modulus, unused in integer-N but must be a legal value
    FRAC_VALUE      : natural := 0;                             --! Fractional word, zero for integer-N
    PHASE_VALUE     : natural := 1;                             --! Phase word, the data sheet recommends 1
    CP_CURRENT_SEL  : natural := 7;                             --! Charge pump current select, 7 is 2.50 mA with a 5.1 k resistor
    OUTPUT_POWER    : natural := 0;                             --! RF output power, 0 = -4 dBm through 3 = +5 dBm
    MUXOUT_SEL      : natural := 6;                             --! MUXOUT function, 6 is digital lock detect
    SPI_HALF_CYCLES : natural := 8;                             --! System clock cycles per SPI half period, 8 gives 3.75 MHz (ADF4351 limit is 20 MHz)
    STARTUP_CYCLES  : natural := 600000                         --! Settling delay before the first programming, 10 ms at 60 MHz
);
port (
    i_sysclk        : in    std_logic;
    i_rst           : in    std_logic;                          --! Synchronous active high reset
    i_channel       : in    std_logic_vector(CH_DW-1 downto 0); --! Channel index, INT = INT_BASE + this
    i_update        : in    std_logic;                          --! Single cycle pulse requesting a reprogram
    i_lock          : in    std_logic;                          --! ADF4351 MUXOUT configured as digital lock detect
    o_pll_clk       : out   std_logic;                          --! ADF4351 CLK
    o_pll_data      : out   std_logic;                          --! ADF4351 DATA, shifted MSB first
    o_pll_le        : out   std_logic;                          --! ADF4351 LE, pulsed after each 32 bit word
    o_locked        : out   std_logic;                          --! Synchronised lock detect
    o_busy          : out   std_logic                           --! High while a programming burst is in progress
);
end adf4351_driver;

architecture rtl of adf4351_driver is

-- Place a field at its bit position. Every field below is sized so nothing is shifted off the
-- top, which keeps this simple rather than needing a width check per call.
function fld(value : natural; shift : natural) return unsigned is
begin
    return shift_left(to_unsigned(value, 32), shift);
end function;

-- R1 to R5 depend only on generics. R0 carries INT so it is built at run time.
-- Bits 19 and 20 of R5 are reserved and must be written as ones, which is what makes the
-- familiar 0x00580005 value.
constant REG1 : unsigned(31 downto 0) := fld(1, 27)                 -- 8/9 prescaler, required above 3 GHz
                                      or fld(PHASE_VALUE, 15)
                                      or fld(MOD_VALUE, 3)
                                      or fld(1, 0);
constant REG2 : unsigned(31 downto 0) := fld(0, 29)                 -- low noise mode
                                      or fld(MUXOUT_SEL, 26)
                                      or fld(R_COUNTER, 14)
                                      or fld(CP_CURRENT_SEL, 9)
                                      or fld(1, 8)                  -- lock detect function, integer-N
                                      or fld(1, 7)                  -- lock detect precision 6 ns, integer-N
                                      or fld(1, 6)                  -- phase detector polarity positive
                                      or fld(2, 0);
constant REG3 : unsigned(31 downto 0) := fld(1, 22)                 -- 3 ns anti backlash pulse, integer-N
                                      or fld(1, 21)                 -- charge cancellation, integer-N
                                      or fld(150, 3)                -- clock divider, unused here
                                      or fld(3, 0);
constant REG4 : unsigned(31 downto 0) := fld(1, 23)                 -- feedback from the VCO fundamental
                                      or fld(RF_DIV_SEL, 20)
                                      or fld(BAND_SEL_DIV, 12)
                                      or fld(1, 10)                 -- mute until lock detect
                                      or fld(1, 5)                  -- RF output enabled
                                      or fld(OUTPUT_POWER, 3)
                                      or fld(4, 0);
constant REG5 : unsigned(31 downto 0) := fld(1, 22)                 -- lock detect pin shows digital lock detect
                                      or fld(3, 19)                 -- reserved, must be ones
                                      or fld(5, 0);

type state_t is (STARTUP, IDLE, SHIFT_LOW, SHIFT_HIGH, LATCH_HI, LATCH_LO);

signal state        : state_t;
signal start_cnt    : natural range 0 to STARTUP_CYCLES;
signal half_cnt     : natural range 0 to SPI_HALF_CYCLES-1;
signal tick         : std_logic;                            -- One system clock pulse per SPI half period
signal reg_idx      : natural range 0 to 5;
signal bit_cnt      : natural range 0 to 31;
signal shreg        : unsigned(31 downto 0);
signal pending      : std_logic;                            -- A reprogram was asked for while busy
signal int_value    : unsigned(15 downto 0);
signal reg0         : unsigned(31 downto 0);
signal lock_meta    : std_logic;
signal lock_sync    : std_logic;

begin

int_value <= to_unsigned(INT_BASE, 16) + resize(unsigned(i_channel), 16);
reg0      <= shift_left(resize(int_value, 32), 15) or fld(FRAC_VALUE, 3);

o_locked <= lock_sync;
o_busy   <= '0' when state = IDLE else '1';

-- Lock detect is asynchronous to this clock domain
process (i_sysclk)
begin
    if rising_edge(i_sysclk) then
        lock_meta <= i_lock;
        lock_sync <= lock_meta;
    end if;
end process;

-- SPI half period timebase, free running so the burst always starts on a clean boundary
process (i_sysclk)
begin
    if rising_edge(i_sysclk) then
        if i_rst = '1' then
            half_cnt <= 0;
            tick     <= '0';
        elsif half_cnt = SPI_HALF_CYCLES-1 then
            half_cnt <= 0;
            tick     <= '1';
        else
            half_cnt <= half_cnt + 1;
            tick     <= '0';
        end if;
    end if;
end process;

process (i_sysclk)
    -- Select the word for the register currently being shifted out
    function reg_word(idx : natural; r0 : unsigned) return unsigned is
    begin
        case idx is
            when 5      => return REG5;
            when 4      => return REG4;
            when 3      => return REG3;
            when 2      => return REG2;
            when 1      => return REG1;
            when others => return r0;
        end case;
    end function;
begin
    if rising_edge(i_sysclk) then
        if i_rst = '1' then
            state       <= STARTUP;
            start_cnt   <= 0;
            reg_idx     <= 5;
            bit_cnt     <= 31;
            shreg       <= (others => '0');
            pending     <= '0';
            o_pll_clk   <= '0';
            o_pll_data  <= '0';
            o_pll_le    <= '0';
        else
            -- Remember a request that arrives mid burst so no channel change is ever dropped
            if i_update = '1' and state /= IDLE then
                pending <= '1';
            end if;

            case state is
                when STARTUP =>
                    -- Let the supplies and the reference settle before the first word
                    if start_cnt = STARTUP_CYCLES then
                        reg_idx <= 5;
                        bit_cnt <= 31;
                        shreg   <= reg_word(5, reg0);
                        state   <= SHIFT_LOW;
                    else
                        start_cnt <= start_cnt + 1;
                    end if;

                when IDLE =>
                    o_pll_clk <= '0';
                    o_pll_le  <= '0';

                    if i_update = '1' or pending = '1' then
                        pending <= '0';
                        reg_idx <= 5;
                        bit_cnt <= 31;
                        shreg   <= reg_word(5, reg0);
                        state   <= SHIFT_LOW;
                    end if;

                when SHIFT_LOW =>
                    -- Present the bit with the clock low, giving a full half period of setup
                    -- before the ADF4351 samples it
                    if tick = '1' then
                        o_pll_clk  <= '0';
                        o_pll_data <= shreg(31);
                        state      <= SHIFT_HIGH;
                    end if;

                when SHIFT_HIGH =>
                    -- Rising edge, the part captures the bit here
                    if tick = '1' then
                        o_pll_clk <= '1';
                        shreg     <= shreg(30 downto 0) & '0';

                        if bit_cnt = 0 then
                            state <= LATCH_HI;
                        else
                            bit_cnt <= bit_cnt - 1;
                            state   <= SHIFT_LOW;
                        end if;
                    end if;

                when LATCH_HI =>
                    -- LE high transfers the shift register into the addressed latch
                    if tick = '1' then
                        o_pll_clk <= '0';
                        o_pll_le  <= '1';
                        state     <= LATCH_LO;
                    end if;

                when LATCH_LO =>
                    if tick = '1' then
                        o_pll_le <= '0';

                        if reg_idx = 0 then
                            state <= IDLE;
                        else
                            reg_idx <= reg_idx - 1;
                            bit_cnt <= 31;
                            shreg   <= reg_word(reg_idx - 1, reg0);
                            state   <= SHIFT_LOW;
                        end if;
                    end if;

            end case;
        end if;
    end if;
end process;

end rtl;
