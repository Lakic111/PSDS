-- Provera br. 1 iz plana: kako Xcelium mapira VHDL `integer range` port na
-- SystemC tip. ncc_core ima cetiri takva porta (img_addr_o, templ_addr_o,
-- result_addr_o su `integer range 0 to N-1`), a Mesovita.pdf pokriva samo
-- std_logic / std_logic_vector.
library ieee;
use ieee.std_logic_1164.all;

entity intport is
    port (
        clk  : in  std_logic;
        aout : out integer range 0 to 255
    );
end entity intport;

architecture rtl of intport is
    signal c : integer range 0 to 255 := 0;
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if c = 255 then
                c <= 0;
            else
                c <= c + 1;
            end if;
        end if;
    end process;

    aout <= c;
end architecture rtl;
