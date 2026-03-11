library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adf43609_vco_driver is
generic (
    INPUT_DW : integer := 24
);
port ( 
    i_sysclk_40 : in  std_logic;
    i_rst       : in  std_logic;                               --! Synchronous active high reset
    i_start     : in  std_logic;                               --! Trigger send of data
    i_data      : in  std_logic_vector(INPUT_DW-1 downto 0);   --! 24-bit word to send
    o_busy      : out std_logic;                               --! Set busy HIGH while sending
    o_data      : out std_logic;                               --! DATA pin to ADF4360
    o_clk_10    : out std_logic;                               --! CLOCK pin to ADF4360, use 10 MHz for safe setup/hold time margin
    o_le        : out std_logic                                --! LE pin to ADF4360
);
end adf43609_vco_driver;

architecture rtl of adf43609_vco_driver is
signal bit_counter : integer range 0 to INPUT_DW := 0;
signal shift_reg   : std_logic_vector(INPUT_DW-1 downto 0) := (others => '0');

-- Clock divider signals
signal clk_div_cnt : unsigned(2 downto 0) := (others => '0');  -- 3-bit counter for divide by 8
signal old_spi_clk : std_logic := '0';
signal spi_clk     : std_logic := '0';

signal sending     : std_logic := '0';
signal le_reg      : std_logic := '0';
signal data_reg    : std_logic := '0';

begin

-- Divide 40 MHz clock by 8 to get 5 MHz SPI clock
process(i_sysclk_40)
begin
    if rising_edge(i_sysclk_40) then
        if i_rst = '1' then
            clk_div_cnt <= (others => '0');
            spi_clk     <= '0';
        else
            if clk_div_cnt = "111" then  -- count 7 (0 to 7 = 8 cycles)
                clk_div_cnt <= (others => '0');
                spi_clk     <= not spi_clk;  -- toggle spi_clk every 8 clk cycles -> 5 MHz
            else
                clk_div_cnt <= clk_div_cnt + 1;
            end if;
        end if;
        old_spi_clk <= spi_clk;
    end if;
end process;

process(i_sysclk_40)
begin
    if rising_edge(i_sysclk_40) then
        if i_rst = '1' then
            bit_counter <= 0;
            shift_reg   <= (others => '0');
            sending     <= '0';
            le_reg      <= '0';
            data_reg    <= '0';
        else
            if i_start = '1' and sending = '0' then
                -- Load new data to send
                shift_reg   <= i_data;
                bit_counter <= 0;
                sending     <= '1';
                le_reg      <= '0';
            elsif sending = '1' then
                -- Send bits on spi_clk edges
                if spi_clk = '1' and old_spi_clk = '0' then
                    -- Output MSB on DATA line at rising edge of spi_clk
                    data_reg <= shift_reg(INPUT_DW-1);
                    -- Shift left
                    if bit_counter < INPUT_DW-1 then
                        shift_reg   <= shift_reg(INPUT_DW-2 downto 0) & '0';
                        bit_counter <= bit_counter + 1;
                    else
                        -- Finished sending all bits
                        sending <= '0';
                        le_reg  <= '1';  -- pulse LE to latch data
                    end if;
                else
                    le_reg <= '0';  -- LE low except when latching
                end if;
            else
                -- Idle outputs
                data_reg    <= '0';
                le_reg      <= '0';
            end if;
        end if;
    end if;
end process;

o_data      <= data_reg;
o_clk_10    <= spi_clk;
o_le        <= le_reg;
o_busy      <= sending;

end rtl;