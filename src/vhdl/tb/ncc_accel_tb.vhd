-- Integracioni testbench za NCC AXI IP (Korak 6).
-- TB glumi CPU/DMA: pise dimenzije preko AXI-Lite, sliku/sablon preko AXI-Full,
-- startuje, poluje STATUS, cita rezultate i proverava zlatni peak 0x80000000 @ (32,14).
-- Realni podaci: tb/seg90.txt (90x90) + tb/crnitop.txt (25x15) -- isti kao Korak 4.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use std.textio.all;
entity ncc_accel_tb is end entity;
architecture beh of ncc_accel_tb is
    constant IMG_W : integer := 90; constant IMG_H : integer := 90;
    constant TMP_W : integer := 25; constant TMP_H : integer := 15;
    constant RES_W : integer := IMG_W-TMP_W+1;   -- 66
    constant RES_H : integer := IMG_H-TMP_H+1;   -- 76
    constant N_RES : integer := RES_W*RES_H;     -- 5016
    constant PEAK_IDX : integer := 14*RES_W + 32; -- 956
    constant OFF_IMG : integer := 16#00000#;
    constant OFF_TMP : integer := 16#08000#;
    constant OFF_RES : integer := 16#10000#;
    constant R_IMG_W : integer := 16#00#; constant R_IMG_H : integer := 16#04#;
    constant R_TMP_W : integer := 16#08#; constant R_TMP_H : integer := 16#0C#;
    constant R_CTRL  : integer := 16#30#; constant R_STATUS: integer := 16#34#;

    signal clk : std_logic := '0';
    signal aresetn : std_logic := '0';
    -- S00 (AXI-Lite)
    signal s00_awaddr : std_logic_vector(5 downto 0) := (others=>'0');
    signal s00_awprot : std_logic_vector(2 downto 0) := (others=>'0');
    signal s00_awvalid, s00_awready : std_logic := '0';
    signal s00_wdata : std_logic_vector(31 downto 0) := (others=>'0');
    signal s00_wstrb : std_logic_vector(3 downto 0) := (others=>'0');
    signal s00_wvalid, s00_wready : std_logic := '0';
    signal s00_bresp : std_logic_vector(1 downto 0);
    signal s00_bvalid : std_logic; signal s00_bready : std_logic := '0';
    signal s00_araddr : std_logic_vector(5 downto 0) := (others=>'0');
    signal s00_arprot : std_logic_vector(2 downto 0) := (others=>'0');
    signal s00_arvalid, s00_arready : std_logic := '0';
    signal s00_rdata : std_logic_vector(31 downto 0);
    signal s00_rresp : std_logic_vector(1 downto 0);
    signal s00_rvalid : std_logic; signal s00_rready : std_logic := '0';
    -- S01 (AXI-Full)
    signal s01_awid : std_logic_vector(0 downto 0) := (others=>'0');
    signal s01_awaddr : std_logic_vector(16 downto 0) := (others=>'0');
    signal s01_awlen : std_logic_vector(7 downto 0) := (others=>'0');
    signal s01_awsize : std_logic_vector(2 downto 0) := (others=>'0');
    signal s01_awburst : std_logic_vector(1 downto 0) := (others=>'0');
    signal s01_awlock : std_logic := '0';
    signal s01_awcache : std_logic_vector(3 downto 0) := (others=>'0');
    signal s01_awprot : std_logic_vector(2 downto 0) := (others=>'0');
    signal s01_awqos : std_logic_vector(3 downto 0) := (others=>'0');
    signal s01_awregion : std_logic_vector(3 downto 0) := (others=>'0');
    signal s01_awuser : std_logic_vector(-1 downto 0);
    signal s01_awvalid, s01_awready : std_logic := '0';
    signal s01_wdata : std_logic_vector(31 downto 0) := (others=>'0');
    signal s01_wstrb : std_logic_vector(3 downto 0) := (others=>'0');
    signal s01_wlast : std_logic := '0';
    signal s01_wuser : std_logic_vector(-1 downto 0);
    signal s01_wvalid, s01_wready : std_logic := '0';
    signal s01_bid : std_logic_vector(0 downto 0);
    signal s01_bresp : std_logic_vector(1 downto 0);
    signal s01_buser : std_logic_vector(-1 downto 0);
    signal s01_bvalid : std_logic; signal s01_bready : std_logic := '0';
    signal s01_arid : std_logic_vector(0 downto 0) := (others=>'0');
    signal s01_araddr : std_logic_vector(16 downto 0) := (others=>'0');
    signal s01_arlen : std_logic_vector(7 downto 0) := (others=>'0');
    signal s01_arsize : std_logic_vector(2 downto 0) := (others=>'0');
    signal s01_arburst : std_logic_vector(1 downto 0) := (others=>'0');
    signal s01_arlock : std_logic := '0';
    signal s01_arcache : std_logic_vector(3 downto 0) := (others=>'0');
    signal s01_arprot : std_logic_vector(2 downto 0) := (others=>'0');
    signal s01_arqos : std_logic_vector(3 downto 0) := (others=>'0');
    signal s01_arregion : std_logic_vector(3 downto 0) := (others=>'0');
    signal s01_aruser : std_logic_vector(-1 downto 0);
    signal s01_arvalid, s01_arready : std_logic := '0';
    signal s01_rid : std_logic_vector(0 downto 0);
    signal s01_rdata : std_logic_vector(31 downto 0);
    signal s01_rresp : std_logic_vector(1 downto 0);
    signal s01_rlast : std_logic;
    signal s01_ruser : std_logic_vector(-1 downto 0);
    signal s01_rvalid : std_logic; signal s01_rready : std_logic := '0';
begin
    clk <= not clk after 5 ns;
    dut: entity work.ncc_accel
        port map (
            s00_axi_aclk=>clk, s00_axi_aresetn=>aresetn,
            s00_axi_awaddr=>s00_awaddr, s00_axi_awprot=>s00_awprot,
            s00_axi_awvalid=>s00_awvalid, s00_axi_awready=>s00_awready,
            s00_axi_wdata=>s00_wdata, s00_axi_wstrb=>s00_wstrb,
            s00_axi_wvalid=>s00_wvalid, s00_axi_wready=>s00_wready,
            s00_axi_bresp=>s00_bresp, s00_axi_bvalid=>s00_bvalid, s00_axi_bready=>s00_bready,
            s00_axi_araddr=>s00_araddr, s00_axi_arprot=>s00_arprot,
            s00_axi_arvalid=>s00_arvalid, s00_axi_arready=>s00_arready,
            s00_axi_rdata=>s00_rdata, s00_axi_rresp=>s00_rresp,
            s00_axi_rvalid=>s00_rvalid, s00_axi_rready=>s00_rready,
            s01_axi_aclk=>clk, s01_axi_aresetn=>aresetn,
            s01_axi_awid=>s01_awid, s01_axi_awaddr=>s01_awaddr, s01_axi_awlen=>s01_awlen,
            s01_axi_awsize=>s01_awsize, s01_axi_awburst=>s01_awburst, s01_axi_awlock=>s01_awlock,
            s01_axi_awcache=>s01_awcache, s01_axi_awprot=>s01_awprot, s01_axi_awqos=>s01_awqos,
            s01_axi_awregion=>s01_awregion, s01_axi_awuser=>s01_awuser,
            s01_axi_awvalid=>s01_awvalid, s01_axi_awready=>s01_awready,
            s01_axi_wdata=>s01_wdata, s01_axi_wstrb=>s01_wstrb, s01_axi_wlast=>s01_wlast,
            s01_axi_wuser=>s01_wuser, s01_axi_wvalid=>s01_wvalid, s01_axi_wready=>s01_wready,
            s01_axi_bid=>s01_bid, s01_axi_bresp=>s01_bresp, s01_axi_buser=>s01_buser,
            s01_axi_bvalid=>s01_bvalid, s01_axi_bready=>s01_bready,
            s01_axi_arid=>s01_arid, s01_axi_araddr=>s01_araddr, s01_axi_arlen=>s01_arlen,
            s01_axi_arsize=>s01_arsize, s01_axi_arburst=>s01_arburst, s01_axi_arlock=>s01_arlock,
            s01_axi_arcache=>s01_arcache, s01_axi_arprot=>s01_arprot, s01_axi_arqos=>s01_arqos,
            s01_axi_arregion=>s01_arregion, s01_axi_aruser=>s01_aruser,
            s01_axi_arvalid=>s01_arvalid, s01_axi_arready=>s01_arready,
            s01_axi_rid=>s01_rid, s01_axi_rdata=>s01_rdata, s01_axi_rresp=>s01_rresp,
            s01_axi_rlast=>s01_rlast, s01_axi_ruser=>s01_ruser,
            s01_axi_rvalid=>s01_rvalid, s01_axi_rready=>s01_rready
        );

    stim: process
        procedure lite_write(addr : integer; data : integer) is
        begin
            s00_awaddr  <= std_logic_vector(to_unsigned(addr,6));
            s00_awvalid <= '1';
            s00_wdata   <= std_logic_vector(to_unsigned(data,32));
            s00_wstrb   <= "1111";
            s00_wvalid  <= '1';
            s00_bready  <= '1';
            wait until rising_edge(clk);
            s00_awvalid <= '0';
            s00_wvalid  <= '0';
            loop wait until rising_edge(clk); exit when s00_bvalid='1'; end loop;
            s00_bready  <= '0';
            wait until rising_edge(clk);
        end procedure;

        procedure lite_read(addr : integer; res : out std_logic_vector(31 downto 0)) is
        begin
            s00_araddr  <= std_logic_vector(to_unsigned(addr,6));
            s00_arvalid <= '1';
            s00_rready  <= '1';
            wait until rising_edge(clk);
            s00_arvalid <= '0';
            loop wait until rising_edge(clk); exit when s00_rvalid='1'; end loop;
            res := s00_rdata;
            s00_rready  <= '0';
            wait until rising_edge(clk);
        end procedure;

        procedure full_write(addr : integer; data : integer) is
        begin
            s01_awaddr  <= std_logic_vector(to_unsigned(addr,17));
            s01_awlen   <= (others=>'0');
            s01_awsize  <= "010";
            s01_awburst <= "01";
            s01_awvalid <= '1';
            s01_wdata   <= std_logic_vector(to_unsigned(data,32));
            s01_wstrb   <= "1111";
            s01_wlast   <= '1';
            s01_wvalid  <= '1';
            s01_bready  <= '1';
            wait until rising_edge(clk);
            s01_awvalid <= '0';
            s01_wvalid  <= '0';
            s01_wlast   <= '0';
            loop wait until rising_edge(clk); exit when s01_bvalid='1'; end loop;
            s01_bready  <= '0';
            wait until rising_edge(clk);
        end procedure;

        procedure full_read(addr : integer; res : out std_logic_vector(31 downto 0)) is
        begin
            s01_araddr  <= std_logic_vector(to_unsigned(addr,17));
            s01_arlen   <= (others=>'0');
            s01_arsize  <= "010";
            s01_arburst <= "01";
            s01_arvalid <= '1';
            s01_rready  <= '1';
            wait until rising_edge(clk);
            s01_arvalid <= '0';
            loop wait until rising_edge(clk); exit when s01_rvalid='1'; end loop;
            res := s01_rdata;
            s01_rready  <= '0';
            wait until rising_edge(clk);
        end procedure;

        variable line_v : line;
        variable px : integer;
        type int_arr is array(natural range <>) of integer;
        variable seg  : int_arr(0 to IMG_W*IMG_H-1);
        variable tmpl : int_arr(0 to TMP_W*TMP_H-1);
        file fseg : text; file ftmp : text;
        variable rd : std_logic_vector(31 downto 0);
        variable peak : unsigned(31 downto 0) := (others=>'0');
        variable peak_idx : integer := -1;
        variable poll : integer := 0;
    begin
        -- reset 10 taktova
        aresetn <= '0';
        for i in 0 to 9 loop wait until rising_edge(clk); end loop;
        aresetn <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- ucitaj podatke
        file_open(fseg, "../tb/seg90.txt", read_mode);
        for i in 0 to IMG_W*IMG_H-1 loop
            readline(fseg, line_v); read(line_v, px); seg(i) := px;
        end loop;
        file_close(fseg);
        file_open(ftmp, "../tb/crnitop.txt", read_mode);
        for i in 0 to TMP_W*TMP_H-1 loop
            readline(ftmp, line_v); read(line_v, px); tmpl(i) := px;
        end loop;
        file_close(ftmp);

        -- 1) dimenzije preko AXI-Lite + brza readback provera
        lite_write(R_IMG_W, IMG_W); lite_write(R_IMG_H, IMG_H);
        lite_write(R_TMP_W, TMP_W); lite_write(R_TMP_H, TMP_H);
        lite_read(R_IMG_W, rd);
        assert to_integer(unsigned(rd)) = IMG_W
            report "FAIL: lite readback IMG_W=" & integer'image(to_integer(unsigned(rd)))
            severity failure;
        report "OK: AXI-Lite write/read (IMG_W=90)" severity note;

        -- 2) slika + sablon preko AXI-Full + brza readback provera
        for i in 0 to IMG_W*IMG_H-1 loop full_write(OFF_IMG + i*4, seg(i)); end loop;
        for i in 0 to TMP_W*TMP_H-1 loop full_write(OFF_TMP + i*4, tmpl(i)); end loop;
        full_read(OFF_IMG + 5*4, rd);
        assert to_integer(unsigned(rd)) = seg(5)
            report "FAIL: full readback img[5]=" & integer'image(to_integer(unsigned(rd)))
            severity failure;
        report "OK: AXI-Full write/read (img[5])" severity note;

        -- 3) start
        lite_write(R_CTRL, 1);
        lite_write(R_CTRL, 0);
        report "OK: start izdat, cekam done..." severity note;

        -- 4) poll STATUS bit0
        poll := 0;
        loop
            lite_read(R_STATUS, rd);
            exit when rd(0) = '1';
            poll := poll + 1;
            assert poll < 100000 report "FAIL: done timeout" severity failure;
            wait for 20 us;
        end loop;
        report "OK: obrada zavrsena (done=1)" severity note;

        -- 5) citaj rezultate, nadji peak
        for i in 0 to N_RES-1 loop
            full_read(OFF_RES + i*4, rd);
            if unsigned(rd) > peak then peak := unsigned(rd); peak_idx := i; end if;
        end loop;

        -- 6) provera zlatne vrednosti
        assert peak = x"80000000"
            report "FAIL: peak != 0x80000000 (peak_idx=" & integer'image(peak_idx) & ")"
            severity failure;
        assert peak_idx = PEAK_IDX
            report "FAIL: peak_idx=" & integer'image(peak_idx) & " != " & integer'image(PEAK_IDX)
            severity failure;
        report "PASS: ncc_accel golden peak 0x80000000 @ idx " & integer'image(peak_idx)
            severity note;
        std.env.stop;
    end process;
end architecture;
