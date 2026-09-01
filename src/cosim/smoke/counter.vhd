-- VHDL verzija Listinga 2.1 -- za Korak 3 Taska 1: da li xmsc_run prima VHDL
-- isto kao Verilog. Portovi su IDENTICNI (imena i redosled) da counter.hpp
-- omotac ne mora da se menja.
--
-- std_logic_vector za din/dout jer omotac koristi sc_lv<8>, i std_logic za
-- rst/load jer omotac koristi sc_logic. clk je sc_in<bool> u omotacu -- to
-- Xcelium mapira na std_logic ulaz.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
    port (
        dout : out std_logic_vector(7 downto 0);
        clk  : in  std_logic;
        rst  : in  std_logic;
        load : in  std_logic;
        din  : in  std_logic_vector(7 downto 0)
    );
end entity counter;

architecture rtl of counter is
    signal cnt : unsigned(7 downto 0);
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt <= (others => '0');
            else
                if load = '1' then
                    cnt <= unsigned(din);
                else
                    cnt <= cnt + 1;
                end if;
            end if;
        end if;
    end process;

    dout <= std_logic_vector(cnt);
end architecture rtl;
