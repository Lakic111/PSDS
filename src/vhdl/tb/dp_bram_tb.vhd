library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity dp_bram_tb is end entity;
architecture beh of dp_bram_tb is
    constant DW : integer := 8; constant AW : integer := 4;  -- mali za test
    signal clk : std_logic := '0';
    signal ena,wea,enb,web : std_logic := '0';
    signal addra,addrb : std_logic_vector(AW-1 downto 0) := (others=>'0');
    signal dia,dib,doa,dob : std_logic_vector(DW-1 downto 0) := (others=>'0');
begin
    dut: entity work.dp_bram generic map(DATA_W=>DW, ADDR_W=>AW)
        port map(clk,ena,wea,addra,dia,doa, clk,enb,web,addrb,dib,dob);
    clk <= not clk after 5 ns;
    stim: process
    begin
        -- upisi preko porta A na adresu 3 vrednost 0xAB
        ena<='1'; wea<='1'; addra<=std_logic_vector(to_unsigned(3,AW)); dia<=x"AB";
        wait until rising_edge(clk); wea<='0';
        -- procitaj preko porta B adresu 3 (1-taktno kasnjenje)
        enb<='1'; addrb<=std_logic_vector(to_unsigned(3,AW));
        wait until rising_edge(clk); wait until rising_edge(clk);
        assert dob = x"AB" report "FAIL: dp_bram B read mismatch" severity failure;
        report "PASS: dp_bram" severity note;
        std.env.stop;
    end process;
end architecture;
