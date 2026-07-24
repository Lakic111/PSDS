-- Genericki true-dual-port RAM za NCC IP omotac (Korak 6).
-- Oba porta: sinhrono citanje (1-taktno kasnjenje) + upis, shared variable.
-- Potpuno sinhrono u dva procesa -> BRAM inference (pouka iz Koraka 3).
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity dp_bram is
    generic ( DATA_W : integer := 8; ADDR_W : integer := 13 );
    port (
        clka : in std_logic; ena : in std_logic; wea : in std_logic;
        addra: in std_logic_vector(ADDR_W-1 downto 0);
        dia  : in std_logic_vector(DATA_W-1 downto 0);
        doa  : out std_logic_vector(DATA_W-1 downto 0);
        clkb : in std_logic; enb : in std_logic; web : in std_logic;
        addrb: in std_logic_vector(ADDR_W-1 downto 0);
        dib  : in std_logic_vector(DATA_W-1 downto 0);
        dob  : out std_logic_vector(DATA_W-1 downto 0)
    );
end entity;
architecture rtl of dp_bram is
    type ram_t is array (0 to 2**ADDR_W - 1) of std_logic_vector(DATA_W-1 downto 0);
    shared variable ram : ram_t := (others => (others => '0'));
begin
    process(clka) begin
        if rising_edge(clka) then
            if ena = '1' then
                if wea = '1' then ram(to_integer(unsigned(addra))) := dia; end if;
                doa <= ram(to_integer(unsigned(addra)));
            end if;
        end if;
    end process;
    process(clkb) begin
        if rising_edge(clkb) then
            if enb = '1' then
                if web = '1' then ram(to_integer(unsigned(addrb))) := dib; end if;
                dob <= ram(to_integer(unsigned(addrb)));
            end if;
        end if;
    end process;
end architecture;
