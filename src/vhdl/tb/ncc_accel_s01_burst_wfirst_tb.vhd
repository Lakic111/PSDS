-- Regresioni testbench za protokolarni bug u S01 (AXI-Full) upisnom FSM-u,
-- dokazan na fizickoj ploci: Faza 4 (CDMA burst prenos u S01) visi. CPU se
-- zaglavi toliko da ga debager ne moze zaustaviti, i ni CDMA registri se vise
-- ne mogu procitati -- cela PL magistrala je blokirana neizmirenom
-- transakcijom (deljena magistrala). Faza 2 (procesor, single-beat upisi/
-- citanja, 8100 reci) je PROSLA -- ovaj bug pogadja iskljucivo BURST (WLAST)
-- upise, i to samo S01 (AXI-Full), ne S00 (AXI-Lite, koji radi samo
-- jednobeat i vec je popravljen, commit 720d162).
--
-- Isti obrazac kao u S00: axi_wready je stajao na '1' od Idle nadalje, pa je
-- W beat koji stigne PRE AW (AXI4 to dozvoljava) prihvacen a nigde
-- zabelezen. Ako je medju izgubljenim beat-ovima bio i WLAST, FSM zauvek
-- ceka u Wdata na W koji se vec dogodio -- BVALID se nikad ne izdaje.
--
-- Dodatna zamka koju S00 nije imao (burst-specificna): proces koji pomera
-- adresu i broji beat-ove je PRETPOSTAVLJAO da se prvi W beat trosi u ISTOM
-- taktu kad je AW prihvacen (pre-inkrement na osnovu golog S_AXI_WVALID, bez
-- provere axi_wready). Sa novim FSM-om (axi_wready='0' u Waddr) to vise
-- nikad nije tacno -- popravka mora dirati i taj proces, inace burst tiho
-- upisuje na pomerene adrese bez ijedne AXI greske.
--
-- Cetiri scenarija, svaki sa TIMEOUT-om (TB nikad ne sme da visi, cak ni na
-- pokvarenom RTL-u koji bi hardverski master (CDMA/CPU) zaglavio zauvek):
--   1) AWLEN=7, AW pa W beat-ovi (razmak >= 2 takta)
--   2) AWLEN=7, SVI W beat-ovi (uklj. WLAST) poslati PRE AW -- slucaj sa ploce
--   3) AWLEN=7, AW i PRVI W beat u istom taktu -- hvata pre-inkrement zamku
--   4) dva UZASTOPNA bursta, BREADY stalno na '1' -- AW2 se drzi validan cim
--      se AW1 prihvati, pa stize tacno u taktu kad burst A vraca BVALID --
--      hvata "duh" BVALID (ista rupa nadjena u S00 recenziji).
-- Za svaki: upisi 0x10..0x17 (8 reci) pa procitaj nazad SVIH 8 reci
-- (single-beat citanjem, taj put bug ne pogadja) i potvrdi adrese/vrednosti
-- -- to hvata razilazenje brojaca/adrese koje ne bi dalo AXI gresku.
--
-- Instancira se ceo ncc_accel (kao ncc_accel_burst_tb.vhd) da bi upis/citanje
-- islo kroz pravi mem_subsystem/dp_bram sa registrovanim citanjem -- izbegava
-- potrebu da TB sam modelira memorijsku latenciju.

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity ncc_accel_s01_burst_wfirst_tb is end entity;
architecture beh of ncc_accel_s01_burst_wfirst_tb is
    constant OFF_IMG : integer := 16#00000#;   -- region slike u S01
    constant NB      : integer := 8;           -- beat-ova po burst-u (awlen = NB-1 = 7)

    -- Bazni indeksi reci (ne bajt-adrese) za svaki scenario -- razmaknuti
    -- da se burst-ovi ne preklapaju.
    constant S1_BASE : integer := 0;     -- Scenario 1
    constant S2_BASE : integer := 64;    -- Scenario 2
    constant S3_BASE : integer := 128;   -- Scenario 3
    constant S4A_BASE: integer := 192;   -- Scenario 4, prvi burst
    constant S4B_BASE: integer := 200;   -- Scenario 4, drugi burst (odmah posle prvog)

    constant AW_TIMEOUT : integer := 200;
    constant W_TIMEOUT   : integer := 500;
    constant B_TIMEOUT   : integer := 200;
    constant R_TIMEOUT   : integer := 200;

    signal clk : std_logic := '0';
    signal aresetn : std_logic := '0';
    -- S00 (AXI-Lite) -- nekoriscen u ovom TB-u, drzimo neaktivan
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

    -- Brojac BVALID ciklusa za Scenario 4, drzan van stim procesa da bi se
    -- brojalo tokom CELE dve-burst sekvence bez posebnog rucnog provera u
    -- svakoj stimulus petlji.
    signal count_bvalid : boolean := false;
    signal bvalid_count : integer := 0;
begin
    clk <= not clk after 5 ns;

    bvalid_counter: process(clk)
    begin
        if rising_edge(clk) then
            if count_bvalid and s01_bvalid = '1' then
                bvalid_count <= bvalid_count + 1;
            end if;
        end if;
    end process;

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
        variable rd  : std_logic_vector(31 downto 0);
        variable got : integer;
        variable to_ctr : integer;
        variable nfail  : integer := 0;
        -- Scenario 2/3: pomocne promenljive za rucno interleaving-ovano
        -- vozenje AW/W kanala (ne mogu biti procedure jer AW i W moraju teci
        -- konkurentno u vremenu unutar iste sekvence takt-ova).
        variable beat      : integer;
        variable cyc2       : integer;
        variable aw_issued  : boolean;
        variable aw_done    : boolean;
        variable cyc3        : integer;

        -- single-beat citanje (poznato ispravno iz Koraka 6/8)
        procedure full_read1(addr : integer; res : out std_logic_vector(31 downto 0)) is
            variable c : integer := 0;
        begin
            s01_araddr  <= std_logic_vector(to_unsigned(addr,17));
            s01_arlen   <= (others=>'0'); s01_arsize <= "010"; s01_arburst <= "01";
            s01_arvalid <= '1'; s01_rready <= '1';
            wait until rising_edge(clk);
            s01_arvalid <= '0';
            loop
                wait until rising_edge(clk);
                exit when s01_rvalid='1';
                c := c + 1;
                assert c < R_TIMEOUT
                    report "FAIL: full_read1(addr=" & integer'image(addr) & ") RVALID timeout"
                    severity failure;
            end loop;
            res := s01_rdata;
            s01_rready <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- Ceka BVALID sa timeout-om -- TB nikad ne sme da visi, cak ni kad je
        -- DUT zaista zaglavljen (potpis bug-a sa ploce).
        procedure wait_bvalid(scenario : string) is
            variable c : integer := 0;
        begin
            loop
                wait until rising_edge(clk);
                exit when s01_bvalid = '1';
                c := c + 1;
                assert c < B_TIMEOUT
                    report "FAIL [" & scenario & "]: BVALID nije stigao u " &
                           integer'image(B_TIMEOUT) &
                           " taktova -- master (CDMA/CPU) bi ostao zaglavljen (potpis bug-a sa ploce)."
                    severity failure;
            end loop;
            wait until rising_edge(clk); -- BREADY='1' vec stoji, handshake se zavrsava ovde
        end procedure;

        -- Proveri svih NB reci burst-a (poznat niz 0x10+start..0x17+start) na
        -- ocekivanim adresama -- hvata razilazenje brojaca/adrese koje ne
        -- proizvodi AXI gresku, samo tihu korupciju.
        procedure verify_burst(base_word : integer; data_base : integer; scenario : string) is
            variable r : std_logic_vector(31 downto 0);
        begin
            for k in 0 to NB-1 loop
                full_read1(OFF_IMG + (base_word+k)*4, r);
                assert to_integer(unsigned(r)) = data_base + k
                    report "FAIL [" & scenario & "]: rec " & integer'image(k) &
                           " (adresa reci=" & integer'image(base_word+k) &
                           "): procitano " & integer'image(to_integer(unsigned(r))) &
                           ", ocekivano " & integer'image(data_base + k)
                    severity failure;
            end loop;
            report "PASS [" & scenario & "]: svih " & integer'image(NB) &
                   " reci na tacnim adresama." severity note;
        end procedure;

    begin
        aresetn <= '0';
        for i in 0 to 9 loop wait until rising_edge(clk); end loop;
        aresetn <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);

        ------------------------------------------------------------------
        -- Scenario 1: AWLEN=7, AW pa W beat-ovi (razmak >= 2 takta)
        ------------------------------------------------------------------
        report "=== Scenario 1: AW pa W beat-ovi (AWLEN=7) ===" severity note;
        s01_bready  <= '1';
        s01_awaddr  <= std_logic_vector(to_unsigned(OFF_IMG + S1_BASE*4, 17));
        s01_awlen   <= std_logic_vector(to_unsigned(NB-1, 8));
        s01_awsize  <= "010"; s01_awburst <= "01";
        s01_awvalid <= '1';
        to_ctr := 0;
        loop
            wait until rising_edge(clk);
            exit when s01_awready = '1';
            to_ctr := to_ctr + 1;
            assert to_ctr < AW_TIMEOUT report "FAIL [Scenario 1]: AWREADY timeout" severity failure;
        end loop;
        s01_awvalid <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk); -- razmak >= 2 takta pre W

        for k in 0 to NB-1 loop
            s01_wdata  <= std_logic_vector(to_unsigned(16#10#+k, 32));
            s01_wstrb  <= "1111";
            if k = NB-1 then s01_wlast <= '1'; else s01_wlast <= '0'; end if;
            s01_wvalid <= '1';
            to_ctr := 0;
            loop
                wait until rising_edge(clk);
                exit when s01_wready = '1';
                to_ctr := to_ctr + 1;
                assert to_ctr < W_TIMEOUT
                    report "FAIL [Scenario 1]: WREADY beat " & integer'image(k) & " timeout"
                    severity failure;
            end loop;
        end loop;
        s01_wvalid <= '0'; s01_wlast <= '0';

        wait_bvalid("Scenario 1: AW pa W");
        s01_bready <= '0';
        wait until rising_edge(clk);
        verify_burst(S1_BASE, 16#10#, "Scenario 1");

        ------------------------------------------------------------------
        -- Scenario 2: AWLEN=7, SVI W beat-ovi (uklj. WLAST) PRE AW --
        -- tacno slucaj koji je pukao na ploci. AW se izdaje tek posle
        -- NB+2 takta -- na originalnom (pokvarenom) RTL-u je axi_wready
        -- konstantno '1', pa ce svih 8 beat-ova (i WLAST) biti prihvaceno i
        -- "izgubljeno" pre nego sto AW uopste stigne -- FSM ostaje zauvek
        -- zaglavljen cekajuci W koji se vec dogodio. Na popravljenom RTL-u
        -- axi_wready ostaje '0' dok AW ne stigne (legitiman AXI
        -- backpressure), pa se prvi beat prihvata tek kad AW bude prihvacen.
        ------------------------------------------------------------------
        report "=== Scenario 2: SVI W beat-ovi PRE AW (AWLEN=7) -- slucaj sa ploce ===" severity note;
        s01_bready <= '1';
        s01_wdata  <= std_logic_vector(to_unsigned(16#10#, 32)); -- beat 0
        s01_wstrb  <= "1111";
        s01_wlast  <= '0';
        s01_wvalid <= '1';
        beat := 0;
        cyc2 := 0;
        aw_issued := false;
        loop
            wait until rising_edge(clk);
            cyc2 := cyc2 + 1;
            if s01_wvalid = '1' and s01_wready = '1' then
                beat := beat + 1;
                if beat <= NB-1 then
                    s01_wdata <= std_logic_vector(to_unsigned(16#10#+beat, 32));
                    if beat = NB-1 then s01_wlast <= '1'; end if;
                else
                    s01_wvalid <= '0'; s01_wlast <= '0';
                end if;
            end if;
            -- AW se izdaje ODMAH posto su svi beat-ovi (na pokvarenom RTL-u)
            -- vec davno drenirani; provera prihvatanja je namerno u
            -- odvojenoj (elsif) iteraciji -- videti komentar u
            -- ncc_accel_wfirst_tb.vhd (Scenario 2 za S00) za razlog.
            if (not aw_issued) and cyc2 >= NB+2 then
                s01_awaddr  <= std_logic_vector(to_unsigned(OFF_IMG + S2_BASE*4, 17));
                s01_awlen   <= std_logic_vector(to_unsigned(NB-1, 8));
                s01_awsize  <= "010"; s01_awburst <= "01";
                s01_awvalid <= '1';
                aw_issued := true;
            elsif aw_issued and s01_awvalid = '1' and s01_awready = '1' then
                s01_awvalid <= '0';
            end if;
            assert cyc2 < W_TIMEOUT
                report "FAIL [Scenario 2]: watchdog istekao pre nego sto su svi W beat-ovi poslati"
                severity failure;
            exit when beat = NB;
        end loop;

        wait_bvalid("Scenario 2: W pre AW");
        s01_bready <= '0';
        wait until rising_edge(clk);
        verify_burst(S2_BASE, 16#10#, "Scenario 2");

        ------------------------------------------------------------------
        -- Scenario 3: AWLEN=7, AW i PRVI W beat u istom taktu -- hvata
        -- pre-inkrement zamku (adresni proces ne sme pretpostaviti da je
        -- prvi beat potrosen u taktu prihvatanja AW).
        ------------------------------------------------------------------
        report "=== Scenario 3: AW i prvi W beat u istom taktu (AWLEN=7) ===" severity note;
        s01_bready  <= '1';
        s01_awaddr  <= std_logic_vector(to_unsigned(OFF_IMG + S3_BASE*4, 17));
        s01_awlen   <= std_logic_vector(to_unsigned(NB-1, 8));
        s01_awsize  <= "010"; s01_awburst <= "01";
        s01_awvalid <= '1';
        s01_wdata   <= std_logic_vector(to_unsigned(16#10#, 32)); -- beat 0
        s01_wstrb   <= "1111";
        s01_wlast   <= '0';
        s01_wvalid  <= '1';
        aw_done := false;
        beat := 0;
        cyc3 := 0;
        loop
            wait until rising_edge(clk);
            cyc3 := cyc3 + 1;
            if (not aw_done) and s01_awvalid = '1' and s01_awready = '1' then
                s01_awvalid <= '0';
                aw_done := true;
            end if;
            if s01_wvalid = '1' and s01_wready = '1' then
                beat := beat + 1;
                if beat <= NB-1 then
                    s01_wdata <= std_logic_vector(to_unsigned(16#10#+beat, 32));
                    if beat = NB-1 then s01_wlast <= '1'; end if;
                else
                    s01_wvalid <= '0'; s01_wlast <= '0';
                end if;
            end if;
            assert cyc3 < W_TIMEOUT
                report "FAIL [Scenario 3]: watchdog istekao" severity failure;
            exit when beat = NB;
        end loop;

        wait_bvalid("Scenario 3: AW+W isti takt");
        s01_bready <= '0';
        wait until rising_edge(clk);
        verify_burst(S3_BASE, 16#10#, "Scenario 3");

        ------------------------------------------------------------------
        -- Scenario 4: dva UZASTOPNA bursta, BREADY stalno na '1'. AW2 se
        -- drzi validan CIM se AW1 prihvati (pre nego prvi W1 beat uopste
        -- stigne) -- stize tacno u taktu kad se burst A vraca u Waddr i
        -- izdaje BVALID. Provera: svaki burst dobija TACNO jedan BVALID
        -- takt (ukupno 2), ne "duh" drugi.
        ------------------------------------------------------------------
        report "=== Scenario 4: dva uzastopna bursta, BREADY stalno na '1' ===" severity note;
        s01_bready    <= '1';
        count_bvalid  <= true;

        -- AW1
        s01_awaddr  <= std_logic_vector(to_unsigned(OFF_IMG + S4A_BASE*4, 17));
        s01_awlen   <= std_logic_vector(to_unsigned(NB-1, 8));
        s01_awsize  <= "010"; s01_awburst <= "01";
        s01_awvalid <= '1';
        to_ctr := 0;
        loop
            wait until rising_edge(clk);
            exit when s01_awready = '1';
            to_ctr := to_ctr + 1;
            assert to_ctr < AW_TIMEOUT report "FAIL [Scenario 4]: AW1 timeout" severity failure;
        end loop;
        s01_awvalid <= '0';

        -- AW2 se izdaje ODMAH i drzi validan dok ga slave ne prihvati -- ostace
        -- na cekanju (axi_awready='0') tokom cele Wdata faze burst-a A i biva
        -- prihvacen tacno kad automat vrati state_write u Waddr (isti takt kad
        -- se izdaje BVALID za A) -- tacan prozor koji je otkrila S00 recenzija.
        s01_awaddr  <= std_logic_vector(to_unsigned(OFF_IMG + S4B_BASE*4, 17));
        s01_awvalid <= '1'; -- awlen/awsize/awburst ostaju isti (NB-1, "010", "01")

        for k in 0 to NB-1 loop
            s01_wdata  <= std_logic_vector(to_unsigned(16#10#+k, 32));
            s01_wstrb  <= "1111";
            if k = NB-1 then s01_wlast <= '1'; else s01_wlast <= '0'; end if;
            s01_wvalid <= '1';
            to_ctr := 0;
            loop
                wait until rising_edge(clk);
                exit when s01_wready = '1';
                to_ctr := to_ctr + 1;
                assert to_ctr < W_TIMEOUT
                    report "FAIL [Scenario 4]: W1 beat " & integer'image(k) & " timeout"
                    severity failure;
            end loop;
        end loop;
        s01_wvalid <= '0'; s01_wlast <= '0';

        -- sacekaj prihvatanje AW2 (ocekivano odmah, u taktu povratka u Waddr)
        to_ctr := 0;
        loop
            wait until rising_edge(clk);
            exit when s01_awready = '1';
            to_ctr := to_ctr + 1;
            assert to_ctr < AW_TIMEOUT report "FAIL [Scenario 4]: AW2 timeout" severity failure;
        end loop;
        s01_awvalid <= '0';

        for k in 0 to NB-1 loop
            s01_wdata  <= std_logic_vector(to_unsigned(16#18#+k, 32));
            s01_wstrb  <= "1111";
            if k = NB-1 then s01_wlast <= '1'; else s01_wlast <= '0'; end if;
            s01_wvalid <= '1';
            to_ctr := 0;
            loop
                wait until rising_edge(clk);
                exit when s01_wready = '1';
                to_ctr := to_ctr + 1;
                assert to_ctr < W_TIMEOUT
                    report "FAIL [Scenario 4]: W2 beat " & integer'image(k) & " timeout"
                    severity failure;
            end loop;
        end loop;
        s01_wvalid <= '0'; s01_wlast <= '0';

        -- par dodatnih taktova repa da uhvatimo eventualni "duh" BVALID za B
        for i in 0 to 4 loop
            wait until rising_edge(clk);
        end loop;
        s01_bready   <= '0';
        count_bvalid <= false;
        wait until rising_edge(clk);

        assert bvalid_count = 2
            report "FAIL [Scenario 4]: BVALID aktivan " & integer'image(bvalid_count) &
                   " takta(ova), ocekivano tacno 2 (po jedan po burst-u) -- 'duh' BVALID."
            severity failure;
        report "PASS [Scenario 4]: tacno 2 BVALID takta za dva uzastopna bursta." severity note;

        verify_burst(S4A_BASE, 16#10#, "Scenario 4 - burst A");
        verify_burst(S4B_BASE, 16#18#, "Scenario 4 - burst B");

        report "PASS: sva cetiri scenarija upisa u S01 (AXI-Full) rade ispravno (AW-W, W-AW, AW+W, dva uzastopna sa BREADY='1')."
            severity note;
        std.env.stop;
    end process;
end architecture;
