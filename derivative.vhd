library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity derivative is
generic (
    DATA_WIDTH          : natural := 16
);
port ( 
    i_sysclk_40         : in    std_logic;
    i_rst               : in    std_logic;
    i_data              : in    unsigned(DATA_WIDTH - 1 downto 0);
    o_derivative_data   : out   unsigned(DATA_WIDTH - 1 downto 0)
);
end derivative;

architecture rtl of derivative is
signal data_buffered1   : unsigned(DATA_WIDTH - 1 downto 0);
signal data_buffered2   : unsigned(DATA_WIDTH - 1 downto 0);
signal derivative_data  : unsigned(DATA_WIDTH - 1 downto 0);
begin

process (i_sysclk_40)
begin
    if rising_edge (i_sysclk_40) then
        if i_rst = '1' then
            data_buffered2  <= (others => '0');
            data_buffered1  <= (others => '0');
            derivative_data <= (others => '0');
        else
            -- Calculate di(t-1)/dt.
            data_buffered2  <= data_buffered1;
            data_buffered1  <= i_data;
            derivative_data <= i_data - data_buffered2;
        end if;
    end if;
end process;

o_derivative_data <= derivative_data;
end rtl;