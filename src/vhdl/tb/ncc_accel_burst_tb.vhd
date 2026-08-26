-- Provera multi-beat INCR burst-ova na S01 (AXI-Full).
-- ncc_accel_tb (Korak 6) koristi samo awlen=0/arlen=0 -> burst put nije pokriven,
-- a svaki DMA (CDMA) radi duge INCR burst-ove.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity ncc_accel_burst_tb is end entity;
architecture beh of ncc_accel_burst_tb is
    constant OFF_IMG : integer := 16#00000#;   -- region slike u S01
    constant NB      : integer := 8;           -- beat-ova u burst-u (arlen/awlen = NB-1)
    constant TIMEOUT : integer := 500;         -- takt-ova pre nego sto handshake petlja prijavi FAIL

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
        -- Drzi AWVALID dok AW ne bude prihvacen (AXI4: VALID stoji dok READY nije '1').
        procedure send_aw(addr : integer; len : integer) is
            variable cnt : integer := 0;
        begin
            s01_awaddr  <= std_logic_vector(to_unsigned(addr,17));
            s01_awlen   <= std_logic_vector(to_unsigned(len,8));
            s01_awsize  <= "010"; s01_awburst <= "01";
            s01_awvalid <= '1';
            loop
                wait until rising_edge(clk);
                cnt := cnt + 1;
                assert cnt < TIMEOUT
                    report "TIMEOUT: AWREADY se nije podiglo u " & integer'image(TIMEOUT) & " taktova"
                    severity failure;
                exit when s01_awready = '1';
            end loop;
            s01_awvalid <= '0';
        end procedure;

        -- Drzi WVALID dok W beat ne bude prihvacen (AXI4: VALID stoji dok READY nije '1').
        procedure send_w(data : integer; last : boolean; wstrb : std_logic_vector(3 downto 0) := "1111") is
            variable cnt : integer := 0;
        begin
            s01_wdata  <= std_logic_vector(to_unsigned(data,32));
            s01_wstrb  <= wstrb;
            if last then s01_wlast <= '1'; else s01_wlast <= '0'; end if;
            s01_wvalid <= '1';
            loop
                wait until rising_edge(clk);
                cnt := cnt + 1;
                assert cnt < TIMEOUT
                    report "TIMEOUT: WREADY se nije podiglo u " & integer'image(TIMEOUT) & " taktova"
                    severity failure;
                exit when s01_wready = '1';
            end loop;
            s01_wvalid <= '0'; s01_wlast <= '0';
        end procedure;

        -- single-beat upis; AW i W se salju sekvencijalno (AXI ne trazi da budu
        -- istovremeno prihvaceni), svaki drzi svoj VALID dok READY ne stigne.
        procedure full_write1(addr : integer; data : integer; wstrb : std_logic_vector(3 downto 0) := "1111") is
            variable cnt : integer := 0;
        begin
            send_aw(addr, 0);
            send_w(data, true, wstrb);
            s01_bready <= '1';
            cnt := 0;
            loop
                wait until rising_edge(clk);
                cnt := cnt + 1;
                assert cnt < TIMEOUT
                    report "TIMEOUT: BVALID se nije podiglo u " & integer'image(TIMEOUT) & " taktova"
                    severity failure;
                exit when s01_bvalid='1';
            end loop;
            s01_bready <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- single-beat citanje (poznato ispravno iz Koraka 6)
        procedure full_read1(addr : integer; res : out std_logic_vector(31 downto 0)) is
            variable cnt : integer := 0;
        begin
            s01_araddr  <= std_logic_vector(to_unsigned(addr,17));
            s01_arlen   <= (others=>'0'); s01_arsize <= "010"; s01_arburst <= "01";
            s01_arvalid <= '1'; s01_rready <= '1';
            loop
                wait until rising_edge(clk);
                cnt := cnt + 1;
                assert cnt < TIMEOUT
                    report "TIMEOUT: ARREADY se nije podiglo u " & integer'image(TIMEOUT) & " taktova"
                    severity failure;
                exit when s01_arready = '1';
            end loop;
            s01_arvalid <= '0';
            cnt := 0;
            loop
                wait until rising_edge(clk);
                cnt := cnt + 1;
                assert cnt < TIMEOUT
                    report "TIMEOUT: RVALID se nije podiglo u " & integer'image(TIMEOUT) & " taktova"
                    severity failure;
                exit when s01_rvalid='1';
            end loop;
            res := s01_rdata;
            s01_rready <= '0';
            wait until rising_edge(clk);
        end procedure;

        variable rd : std_logic_vector(31 downto 0);
        variable got : integer;
        variable nfail_rd, nfail_wr : integer := 0;
        variable nfail_last, nfail_strb, nfail_aw : integer := 0;
        variable tcnt : integer := 0;
        variable bvalid1_seen, awready2_seen : boolean;
    begin
        aresetn <= '0';
        for i in 0 to 9 loop wait until rising_edge(clk); end loop;
        aresetn <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);

        ------------------------------------------------------------------
        -- A) priprema: img[0..15] = 0x20+i (single-beat upisi)
        ------------------------------------------------------------------
        for i in 0 to 15 loop
            full_write1(OFF_IMG + i*4, 16#20# + i);
        end loop;
        report "A) img[i] = 0x20+i upisano (single-beat)" severity note;

        ------------------------------------------------------------------
        -- B) TEST 1: multi-beat INCR READ burst
        ------------------------------------------------------------------
        s01_araddr  <= std_logic_vector(to_unsigned(OFF_IMG, 17));
        s01_arlen   <= std_logic_vector(to_unsigned(NB-1, 8));
        s01_arsize  <= "010"; s01_arburst <= "01";
        s01_arvalid <= '1'; s01_rready <= '1';
        tcnt := 0;
        loop
            wait until rising_edge(clk);
            tcnt := tcnt + 1;
            assert tcnt < TIMEOUT
                report "TIMEOUT: ARREADY (TEST1) se nije podiglo u " & integer'image(TIMEOUT) & " taktova"
                severity failure;
            exit when s01_arready = '1';
        end loop;
        s01_arvalid <= '0';
        for k in 0 to NB-1 loop
            tcnt := 0;
            loop
                wait until rising_edge(clk);
                tcnt := tcnt + 1;
                assert tcnt < TIMEOUT
                    report "TIMEOUT: RVALID (TEST1, beat " & integer'image(k) & ") se nije podiglo"
                    severity failure;
                exit when s01_rvalid='1';
            end loop;
            got := to_integer(unsigned(s01_rdata));
            report "  READ  beat " & integer'image(k) &
                   ": ocekivano " & integer'image(16#20# + k) &
                   " dobijeno " & integer'image(got) &
                   "  rlast=" & std_logic'image(s01_rlast) severity note;
            if got /= 16#20# + k then nfail_rd := nfail_rd + 1; end if;
            -- RLAST sme biti '1' iskljucivo na poslednjem beat-u
            if (k = NB-1 and s01_rlast /= '1') or (k < NB-1 and s01_rlast /= '0') then
                report "  RLAST pogresan na beat-u " & integer'image(k) severity note;
                nfail_last := nfail_last + 1;
            end if;
        end loop;
        s01_rready <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);

        ------------------------------------------------------------------
        -- C) TEST 2: multi-beat INCR WRITE burst, provera single-beat citanjem
        ------------------------------------------------------------------
        send_aw(OFF_IMG + 64*4, NB-1);
        s01_bready <= '1';
        for k in 0 to NB-1 loop
            send_w(16#50# + k, k = NB-1);
        end loop;
        tcnt := 0;
        loop
            wait until rising_edge(clk);
            tcnt := tcnt + 1;
            assert tcnt < TIMEOUT
                report "TIMEOUT: BVALID (TEST2) se nije podiglo u " & integer'image(TIMEOUT) & " taktova"
                severity failure;
            exit when s01_bvalid='1';
        end loop;
        s01_bready <= '0';
        wait until rising_edge(clk);

        for k in 0 to NB-1 loop
            full_read1(OFF_IMG + (64+k)*4, rd);
            got := to_integer(unsigned(rd));
            report "  WRITE img[" & integer'image(64+k) &
                   "]: ocekivano " & integer'image(16#50# + k) &
                   " dobijeno " & integer'image(got) severity note;
            if got /= 16#50# + k then nfail_wr := nfail_wr + 1; end if;
        end loop;

        ------------------------------------------------------------------
        -- D) TEST 3: WSTRB -- upis sa iskljucenim bajt-lane-om 0 NE SME da
        -- promeni piksel (mem_subsystem pamti samo donji bajt).
        ------------------------------------------------------------------
        full_write1(OFF_IMG + 200*4, 16#3C#);          -- poznata polazna vrednost
        full_write1(OFF_IMG + 200*4, 16#AA#, "1110");  -- bajt 0 ISKLJUCEN

        full_read1(OFF_IMG + 200*4, rd);
        got := to_integer(unsigned(rd));
        report "  WSTRB img[200]: ocekivano 60 (=0x3C, nepromenjeno) dobijeno 0x" &
               integer'image(got) severity note;
        if got /= 16#3C# then nfail_strb := nfail_strb + 1; end if;

        ------------------------------------------------------------------
        -- E) TEST 4: rani AW sledece transakcije NE SME da otme adresu
        -- beat-ovima bursta koji jos tece. AXI dozvoljava masteru da drzi
        -- AWVALID za sledecu transakciju dok W beat-ovi tekuce jos idu.
        -- Sa popravljenim RTL-om AWREADY pada cim je AW1 prihvacen, pa
        -- drzanje AWVALID za AW2 tokom bursta je bezopasno; AW2 se prihvata
        -- tek kad se FSM vrati u Waddr (posto je BVALID za prvu transakciju
        -- vec izdato).
        ------------------------------------------------------------------
        s01_bready  <= '1';
        send_aw(OFF_IMG + 300*4, NB-1);
        send_w(16#60#, false);
        -- od sada drzimo AWVALID za DRUGU transakciju (img[400]) dok prva tece
        s01_awaddr  <= std_logic_vector(to_unsigned(OFF_IMG + 400*4, 17));
        s01_awlen   <= (others=>'0');
        s01_awvalid <= '1';
        for k in 1 to NB-1 loop
            send_w(16#60# + k, k = NB-1);
        end loop;
        -- prva transakcija gotova (BVALID) i AW2 prihvacen (AWREADY) mogu
        -- stici na razlicitim ili na istom taktu -- pratimo oba dok se oba
        -- ne dese.
        bvalid1_seen := false;
        awready2_seen := false;
        tcnt := 0;
        loop
            wait until rising_edge(clk);
            tcnt := tcnt + 1;
            assert tcnt < TIMEOUT
                report "TIMEOUT: BVALID(tx1)/AWREADY(tx2) (TEST4) se nisu podigli"
                severity failure;
            if s01_bvalid = '1' then bvalid1_seen := true; end if;
            if s01_awready = '1' and not awready2_seen then
                awready2_seen := true;
                s01_awvalid <= '0';
            end if;
            exit when bvalid1_seen and awready2_seen;
        end loop;
        send_w(16#E5#, true);
        tcnt := 0;
        loop
            wait until rising_edge(clk);
            tcnt := tcnt + 1;
            assert tcnt < TIMEOUT
                report "TIMEOUT: BVALID(tx2) (TEST4) se nije podiglo"
                severity failure;
            exit when s01_bvalid = '1';
        end loop;
        s01_bready <= '0';
        wait until rising_edge(clk);

        for k in 0 to NB-1 loop
            full_read1(OFF_IMG + (300+k)*4, rd);
            got := to_integer(unsigned(rd));
            if got /= 16#60# + k then
                report "  RANI-AW img[" & integer'image(300+k) &
                       "]: ocekivano " & integer'image(16#60# + k) &
                       " dobijeno " & integer'image(got) severity note;
                nfail_aw := nfail_aw + 1;
            end if;
        end loop;
        full_read1(OFF_IMG + 400*4, rd);
        report "  RANI-AW img[400] = " & integer'image(to_integer(unsigned(rd))) &
               " (ocekivano 229 = 0xE5)" severity note;
        if to_integer(unsigned(rd)) /= 16#E5# then nfail_aw := nfail_aw + 1; end if;

        ------------------------------------------------------------------
        -- F) tvrdnje na kraju (da se u RED prolazu vidi puna dijagnostika)
        ------------------------------------------------------------------
        assert nfail_last = 0
            report "FAIL: RLAST -- " & integer'image(nfail_last) & " beat-ova" severity failure;
        assert nfail_strb = 0
            report "FAIL: WSTRB -- upis sa iskljucenim bajtom 0 je promenio piksel"
            severity failure;
        assert nfail_aw = 0
            report "FAIL: rani AW -- " & integer'image(nfail_aw) & " reci pogresno"
            severity failure;
        assert nfail_rd = 0
            report "FAIL: read burst -- " & integer'image(nfail_rd) & " od " &
                   integer'image(NB) & " beat-ova pogresno" severity failure;
        assert nfail_wr = 0
            report "FAIL: write burst -- " & integer'image(nfail_wr) & " od " &
                   integer'image(NB) & " reci pogresno" severity failure;
        report "PASS: ncc_accel burst (read i write, arlen/awlen=7)" severity note;
        std.env.stop;
    end process;
end architecture;
