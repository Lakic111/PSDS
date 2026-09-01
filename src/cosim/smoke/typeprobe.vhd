-- Provera SVIH tipova portova koje ncc_core koristi, na jednom malom entitetu.
-- Ako ovo elaborira i daje smislene vrednosti, omotac sa 17 portova iz Taska 2
-- je zagarantovano ispravan po tipovima.
--
--   std_logic              -> clk, rst, start / busy, done, result_wr_o
--   unsigned(7 downto 0)   -> dim_t (img_w/h, tmp_w/h), pixel_t (img_data_i)
--   integer range 0 to N   -> img_addr_o, templ_addr_o, result_addr_o
--   unsigned(31 downto 0)  -> result_t (result_data_o)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity typeprobe is
    port (
        clk  : in  std_logic;
        rst  : in  std_logic;
        dim  : in  unsigned(7 downto 0);
        addr : out integer range 0 to 8099;
        res  : out unsigned(31 downto 0);
        wr   : out std_logic
    );
end entity typeprobe;

architecture rtl of typeprobe is
    signal a : integer range 0 to 8099 := 0;
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                a <= 0;
            else
                a <= a + 1;
            end if;
        end if;
    end process;

    addr <= a;
    -- res zavisi od ULAZNOG unsigned porta: ako se dim ne prenese ispravno,
    -- res nece imati ocekivanu vrednost i to cemo odmah videti
    res  <= resize(dim, 32) + to_unsigned(a, 32);
    wr   <= '1' when (a mod 2) = 0 else '0';
end architecture rtl;
