library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Driver for the MCP33131D-10 16-bit 1 Msps SAR ADC in its three wire mode, where CNVST doubles
-- as chip select and conversion start. Timing follows Table 1-2 and Figure 7-2 of the device
-- data sheet (Microchip DS20005947B), all of it expressed as nanosecond generics so the frame
-- can be re-derived if the system clock or the fitted device speed grade changes.
--
-- One frame is:
--
--   1. Hold SDI high and pulse CNVST high for at least t_CNVH. The rising edge starts the
--      conversion, which then completes regardless of what CNVST does afterwards, so CNVST is
--      dropped again immediately to enable SDO.
--   2. Wait t_CNV + t_EN for the conversion to finish and SDO to leave high impedance.
--   3. Burst DATA_DW SCLK pulses. The device presents the MSB first and changes SDO on the
--      falling edge of SCLK, so SDO is sampled on the falling edge as the data sheet recommends,
--      which leaves a full SCLK period of settling rather than the sliver a rising edge capture
--      would get.
--   4. Idle for t_QUIET, and pad the frame out to t_CYC so the throughput rate stays inside the
--      device rating.
--
-- With the defaults below and a 60 MHz i_sysclk the frame is 77 clocks, giving a 30 MHz SCLK and
-- a 779.2 ksps sample rate. Reaching the full 1 Msps needs the 60 MHz SCLK the data sheet quotes
-- for that rate, which in turn needs ODDR clock forwarding and a tighter SDO capture, so the
-- conservative half rate clock is used here.
entity mpc33131_adc_driver is
generic (
    SYSCLK_FREQ_HZ      : natural := 60000000;  --! System clock frequency in Hz, must be a whole number of MHz
    DATA_DW             : natural := 16;        --! Device resolution in bits, 16 for the MCP33131D
    SCLK_HALF_CYCLES    : natural := 1;         --! System clock cycles per SCLK half period, 1 gives 30 MHz from a 60 MHz i_sysclk
    T_CNVH_NS           : natural := 10;        --! t_CNVH, minimum CNVST high pulse width
    T_CNV_NS            : natural := 710;       --! t_CNV maximum conversion time, 710 ns for -40 to +85 C and 750 ns above that
    T_EN_NS             : natural := 10;        --! t_EN maximum SDO output enable time measured from the end of conversion
    T_QUIET_NS          : natural := 10;        --! t_QUIET, minimum idle time after the last SCLK edge
    T_CYC_NS            : natural := 1000       --! t_CYC, minimum time between conversions, 1 us for the 1 Msps device
);
port (
    i_sysclk    : in    std_logic;
    i_rst       : in    std_logic;                                  --! Synchronous active high reset
    o_sdi       : out   std_logic;                                  --! Held high for the whole cycle as three wire mode requires
    o_sclk      : out   std_logic;                                  --! Serial clock to the ADC
    i_sdo       : in    std_logic;                                  --! Serial data from the ADC, MSB first
    o_convst    : out   std_logic;                                  --! Conversion start, also acts as chip select
    o_adc_data  : out   std_logic_vector(DATA_DW-1 downto 0);       --! Two's complement sample, valid when o_ready is high
    o_ready     : out   std_logic                                   --! Single cycle strobe qualifying o_adc_data
);
end entity mpc33131_adc_driver;

architecture rtl of mpc33131_adc_driver is

-- Convert a data sheet time in nanoseconds to a whole number of system clock cycles, rounding up
-- so the generated timing is never shorter than the device requires. Scaling by MHz rather than
-- Hz keeps every intermediate inside the 32 bit range VHDL guarantees for integer.
function ns_to_cycles(t_ns : natural; sysclk_hz : natural) return natural is
    constant SYSCLK_MHZ : natural := sysclk_hz / 1000000;
begin
    return (t_ns * SYSCLK_MHZ + 999) / 1000;
end function;

function max(a : natural; b : natural) return natural is
begin
    if a > b then return a; else return b; end if;
end function;

-- CNVST must be high long enough to register, and at least one clock cycle to exist at all
constant CNVH_CYCLES    : natural := max(1, ns_to_cycles(T_CNVH_NS, SYSCLK_FREQ_HZ));
-- Cycles from the CNVST rising edge until SDO is guaranteed to be driving the MSB
constant READ_START     : natural := ns_to_cycles(T_CNV_NS + T_EN_NS, SYSCLK_FREQ_HZ);
constant CONV_CYCLES    : natural := READ_START - CNVH_CYCLES;
-- One SCLK period per bit, each period being a high half and a low half
constant READ_CYCLES    : natural := DATA_DW * 2 * SCLK_HALF_CYCLES;
constant QUIET_CYCLES   : natural := max(1, ns_to_cycles(T_QUIET_NS, SYSCLK_FREQ_HZ));
-- Pad the tail so the throughput rate never exceeds the device rating
constant FRAME_CYCLES   : natural := max(ns_to_cycles(T_CYC_NS, SYSCLK_FREQ_HZ),
                                         CNVH_CYCLES + CONV_CYCLES + READ_CYCLES + QUIET_CYCLES);
constant TAIL_CYCLES    : natural := FRAME_CYCLES - CNVH_CYCLES - CONV_CYCLES - READ_CYCLES;

type adc_state_t is (CONVST_PULSE, WAIT_CONV, READ_DATA, QUIET);

signal state        : adc_state_t;
signal delay_cnt    : natural range 0 to FRAME_CYCLES;
signal half_cnt     : natural range 0 to SCLK_HALF_CYCLES;
signal bit_cnt      : natural range 0 to DATA_DW;
signal sclk_high    : std_logic;
signal shift_reg    : std_logic_vector(DATA_DW-1 downto 0);
signal ready_i      : std_logic;

begin

-- Three wire mode keys off CNVST as chip select and requires SDI to sit high for the whole of
-- t_CYC, see Figure 7-2 note 1. Driving it low instead selects a different interface mode.
o_sdi   <= '1';
o_sclk  <= sclk_high;
o_ready <= ready_i;

process (i_sysclk)
begin
    if rising_edge(i_sysclk) then
        if i_rst = '1' then
            state       <= CONVST_PULSE;
            delay_cnt   <= 0;
            half_cnt    <= 0;
            bit_cnt     <= 0;
            sclk_high   <= '0';
            shift_reg   <= (others => '0');
            ready_i     <= '0';
            o_convst    <= '0';
            o_adc_data  <= (others => '0');
        else
            ready_i <= '0';

            case state is
                when CONVST_PULSE =>
                    -- Rising edge here starts the conversion
                    o_convst <= '1';

                    if delay_cnt = CNVH_CYCLES-1 then
                        delay_cnt <= 0;
                        state     <= WAIT_CONV;
                    else
                        delay_cnt <= delay_cnt + 1;
                    end if;

                when WAIT_CONV =>
                    -- Drop CNVST straight away, the conversion completes on its own and SDO only
                    -- leaves high impedance once CNVST is low
                    o_convst <= '0';

                    if delay_cnt = CONV_CYCLES-1 then
                        delay_cnt <= 0;
                        half_cnt  <= 0;
                        bit_cnt   <= 0;
                        sclk_high <= '0';
                        state     <= READ_DATA;
                    else
                        delay_cnt <= delay_cnt + 1;
                    end if;

                when READ_DATA =>
                    if half_cnt = SCLK_HALF_CYCLES-1 then
                        half_cnt  <= 0;
                        sclk_high <= not sclk_high;

                        -- Toggling a high SCLK low is the falling edge, and SDO still holds the
                        -- current bit until t_DO after it, so this is the capture point
                        if sclk_high = '1' then
                            shift_reg <= shift_reg(DATA_DW-2 downto 0) & i_sdo;

                            if bit_cnt = DATA_DW-1 then
                                o_adc_data <= shift_reg(DATA_DW-2 downto 0) & i_sdo;
                                ready_i    <= '1';
                                delay_cnt  <= 0;
                                state      <= QUIET;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        end if;
                    else
                        half_cnt <= half_cnt + 1;
                    end if;

                when QUIET =>
                    -- Hold SCLK still for t_QUIET and pad out to t_CYC before converting again
                    sclk_high <= '0';

                    if delay_cnt = TAIL_CYCLES-1 then
                        delay_cnt <= 0;
                        state     <= CONVST_PULSE;
                    else
                        delay_cnt <= delay_cnt + 1;
                    end if;

            end case;
        end if;
    end if;
end process;

end architecture rtl;
