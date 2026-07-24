-- Memorijski podsistem NCC IP omotaca (Korak 6): 3 dp_bram-a + adresni dekoder.
-- Port A (memorija) <-> AXI-Full S01 (CPU/DMA), port B <-> ncc_core.
-- Region = mem_addr_a(16:15): 00=slika, 01=sablon, 10=rezultat. Word = (14:2).
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity mem_subsystem is
    port (
        clk : in std_logic;
        -- S01 strana (port A memorija)
        mem_addr_a  : in  std_logic_vector(16 downto 0);
        mem_wdata_a : in  std_logic_vector(31 downto 0);
        mem_we_a    : in  std_logic;
        mem_rdata_a : out std_logic_vector(31 downto 0);
        -- ncc_core strana (port B)
        img_addr_b   : in  std_logic_vector(12 downto 0);
        img_dout_b   : out std_logic_vector(7 downto 0);
        templ_addr_b : in  std_logic_vector(9 downto 0);
        templ_dout_b : out std_logic_vector(7 downto 0);
        result_addr_b: in  std_logic_vector(12 downto 0);
        result_din_b : in  std_logic_vector(31 downto 0);
        result_we_b  : in  std_logic
    );
end entity;
architecture rtl of mem_subsystem is
    signal region   : std_logic_vector(1 downto 0);
    signal region_d : std_logic_vector(1 downto 0) := "00";
    signal word     : std_logic_vector(12 downto 0);
    signal img_we, templ_we : std_logic;
    signal img_doa, templ_doa : std_logic_vector(7 downto 0);
    signal result_doa : std_logic_vector(31 downto 0);
begin
    region <= mem_addr_a(16 downto 15);
    word   <= mem_addr_a(14 downto 2);
    img_we   <= mem_we_a when region = "00" else '0';
    templ_we <= mem_we_a when region = "01" else '0';
    -- register regiona za poravnanje sa 1-taktnim citanjem dp_bram-a
    process(clk) begin
        if rising_edge(clk) then region_d <= region; end if;
    end process;

    img_mem: entity work.dp_bram generic map(DATA_W=>8, ADDR_W=>13)
        port map(
            clka=>clk, ena=>'1', wea=>img_we, addra=>word,
            dia=>mem_wdata_a(7 downto 0), doa=>img_doa,
            clkb=>clk, enb=>'1', web=>'0', addrb=>img_addr_b,
            dib=>(others=>'0'), dob=>img_dout_b);

    templ_mem: entity work.dp_bram generic map(DATA_W=>8, ADDR_W=>10)
        port map(
            clka=>clk, ena=>'1', wea=>templ_we, addra=>word(9 downto 0),
            dia=>mem_wdata_a(7 downto 0), doa=>templ_doa,
            clkb=>clk, enb=>'1', web=>'0', addrb=>templ_addr_b,
            dib=>(others=>'0'), dob=>templ_dout_b);

    result_mem: entity work.dp_bram generic map(DATA_W=>32, ADDR_W=>13)
        port map(
            clka=>clk, ena=>'1', wea=>'0', addra=>word,
            dia=>(others=>'0'), doa=>result_doa,
            clkb=>clk, enb=>'1', web=>result_we_b, addrb=>result_addr_b,
            dib=>result_din_b, dob=>open);

    with region_d select
        mem_rdata_a <= x"000000" & img_doa   when "00",
                       x"000000" & templ_doa when "01",
                       result_doa            when "10",
                       (others=>'0')         when others;
end architecture;
