library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity mem_subsystem_tb is end entity;
architecture beh of mem_subsystem_tb is
    signal clk : std_logic := '0';
    signal mem_addr_a : std_logic_vector(16 downto 0) := (others=>'0');
    signal mem_wdata_a: std_logic_vector(31 downto 0) := (others=>'0');
    signal mem_we_a   : std_logic := '0';
    signal mem_rdata_a: std_logic_vector(31 downto 0);
    signal img_addr_b : std_logic_vector(12 downto 0) := (others=>'0');
    signal img_dout_b : std_logic_vector(7 downto 0);
    signal templ_addr_b : std_logic_vector(9 downto 0) := (others=>'0');
    signal templ_dout_b : std_logic_vector(7 downto 0);
    signal result_addr_b: std_logic_vector(12 downto 0) := (others=>'0');
    signal result_din_b : std_logic_vector(31 downto 0) := (others=>'0');
    signal result_we_b  : std_logic := '0';
    -- pomoc: byte adresa = region(2b) & word(13b) & "00"
    function ba(region: integer; word: integer) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(region,2)) &
               std_logic_vector(to_unsigned(word,13)) & "00";
    end function;
begin
    dut: entity work.mem_subsystem port map(
        clk, mem_addr_a, mem_wdata_a, mem_we_a, mem_rdata_a,
        img_addr_b, img_dout_b, templ_addr_b, templ_dout_b,
        result_addr_b, result_din_b, result_we_b);
    clk <= not clk after 5 ns;
    stim: process begin
        -- 1) S01 upise piksel 0x7E u sliku[5], pa ncc_core (port B) cita sliku[5]
        mem_addr_a<=ba(0,5); mem_wdata_a<=x"0000007E"; mem_we_a<='1';
        wait until rising_edge(clk); mem_we_a<='0';
        img_addr_b<=std_logic_vector(to_unsigned(5,13));
        wait until rising_edge(clk); wait until rising_edge(clk);
        assert img_dout_b=x"7E" report "FAIL: img port B" severity failure;
        -- 1b) provera sablona (region 01)
        mem_addr_a<=ba(1,7); mem_wdata_a<=x"00000042"; mem_we_a<='1';
        wait until rising_edge(clk); mem_we_a<='0';
        templ_addr_b<=std_logic_vector(to_unsigned(7,10));
        wait until rising_edge(clk); wait until rising_edge(clk);
        assert templ_dout_b=x"42" report "FAIL: templ port B" severity failure;
        -- 2) ncc_core upise rezultat 0x80000000 u rez[9], pa S01 cita rez[9]
        result_addr_b<=std_logic_vector(to_unsigned(9,13));
        result_din_b<=x"80000000"; result_we_b<='1';
        wait until rising_edge(clk); result_we_b<='0';
        mem_addr_a<=ba(2,9);   -- region rezultat
        wait until rising_edge(clk); wait until rising_edge(clk);
        assert mem_rdata_a=x"80000000" report "FAIL: result readback" severity failure;
        report "PASS: mem_subsystem" severity note;
        std.env.stop;
    end process;
end architecture;
