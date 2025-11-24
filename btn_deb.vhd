library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Simple debounce component with generics to control the debounce count and button active level
entity btn_deb is
generic (
    DEB_CNT         : natural := 1000000;   --! Number of clock cycles the button needs to remain stable without switch bouncing
    ACTIVE_HIGH_BTN : boolean := true       --! Button logic state to check for, high meaning a logic high refers to the button being stable once bouncing has finished
);
port (
    i_sysclk_40     : in    std_logic;      --! Clock input
    i_rst           : in    std_logic;      --! Synchronous active high reset
    i_btn           : in    std_logic;      --! Button input
    o_pulse         : out   std_logic       --! Single clock cycle output pulse indicating a single button press
);
end btn_deb;

architecture rtl of btn_deb is
signal db_cnt : natural range 0 to DEB_CNT;
begin

process (i_sysclk_40)
begin
    if rising_edge(i_sysclk_40) then
        -- Clear counter and hold pulse low during reset
        if i_rst = '1' then
            db_cnt  <= 0;
            o_pulse <= '0';    
        else
            if ACTIVE_HIGH_BTN then
                -- While the button is '1' we increment a counter until we hit the debounce count
                -- at that point we send a one clock cycle active high output pulse
                if i_btn = '1' then
                    if db_cnt < DEB_CNT then
                        db_cnt <= db_cnt + 1;
                    end if;
                else
                    -- Reset the count if the button status toggles due to switch bouncing
                    db_cnt <= 0;
                end if;
            else
                -- While the button is '0' we increment a counter until we hit the debounce count
                -- at that point we send a one clock cycle active high output pulse
                if i_btn = '0' then
                    if db_cnt < DEB_CNT then
                        db_cnt <= db_cnt + 1;
                    end if;
                else
                    -- Reset the count if the button status toggles due to switch bouncing
                    db_cnt <= 0;
                end if;
            end if;
            -- Single clock cycle active high output pulse
            if db_cnt = DEB_CNT - 1 then
                o_pulse <= '1';
            else
                o_pulse <= '0';
            end if;
        end if;
    end if;
end process;

end rtl;
