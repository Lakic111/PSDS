-- Regresioni testbench za protokolarni bug u S00 (AXI-Lite) upisnom FSM-u.
--
-- Bug (nadjen na ploci preko JTAG-a, Korak 9 faza 1, vidi BUGS.md "S00 (AXI-Lite)
-- upis VISI kad W stigne pre AW"): axi_wready se u starom RTL-u digne na '1' vec
-- u stanju Idle/Waddr, tj. pre nego sto je AW uopste prihvacen. AXI4 dozvoljava
-- da W stigne pre AW -- u tom slucaju stari automat prihvati W beat na kanalu
-- (WVALID='1' i WREADY='1'), ali ga interno nigde ne zabelezi jer ceka AW. Kad
-- AW kasnije stigne, automat predje u Wdata i ceka W koji se vec dogodio i
-- nece se ponoviti -- BVALID se nikad ne izda i master (npr. CPU) zauvek visi
-- na cekanju odgovora.
--
-- Ovaj TB proverava sva tri legalna redosleda AW/W upisa u kontrolni registar
-- IMG_W (offset 0x00):
--   1) AW pa W (razmak >= 2 takta)
--   2) W pa AW (razmak >= 2 takta)  -- ovo je tacno slucaj koji je pukao na ploci
--   3) AW i W u istom taktu
-- Za svaki: upisi poznatu vrednost, sacekaj BVALID SA TIMEOUT-OM (TB nikad ne
-- sme da visi), pa procitaj registar nazad preko AXI-Lite citanja (odvojen FSM,
-- njega bug ne pogadja) i potvrdi vrednost.
--
-- Scenario 4 (dodat u recenziji): dva UZASTOPNA upisa (IMG_W pa IMG_H) sa
-- BREADY stalno na '1' i BEZ pauze izmedju njih -- hvata drugu, suptilniju
-- rupu: Waddr grana (kad AW2 stigne dok automat jos drzi BVALID='1' za
-- prethodni upis) nije brisala BVALID na BREADY, pa bi master video "duh"
-- BVALID za transakciju koja jos nije zavrsena. Provera: BVALID sme biti
-- aktivan u tacno 2 takta u celom scenariju (jedan po upisu).
--
-- Instancira se DIREKTNO ncc_accel_slave_lite_v1_0_S00_AXI (ne ceo ncc_accel
-- omotac) jer je bug lokalizovan iskljucivo u tom fajlu.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ncc_accel_wfirst_tb is end entity;

architecture beh of ncc_accel_wfirst_tb is
    constant CLK_PERIOD      : time    := 10 ns;
    constant BVALID_TIMEOUT  : integer := 100;

    signal clk     : std_logic := '0';
    signal aresetn : std_logic := '0';

    signal s_awaddr  : std_logic_vector(5 downto 0)  := (others => '0');
    signal s_awprot  : std_logic_vector(2 downto 0)  := (others => '0');
    signal s_awvalid : std_logic := '0';
    signal s_awready : std_logic;
    signal s_wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_wstrb   : std_logic_vector(3 downto 0)  := (others => '0');
    signal s_wvalid  : std_logic := '0';
    signal s_wready  : std_logic;
    signal s_bresp   : std_logic_vector(1 downto 0);
    signal s_bvalid  : std_logic;
    signal s_bready  : std_logic := '1'; -- master je uvek spreman da primi odgovor
    signal s_araddr  : std_logic_vector(5 downto 0)  := (others => '0');
    signal s_arprot  : std_logic_vector(2 downto 0)  := (others => '0');
    signal s_arvalid : std_logic := '0';
    signal s_arready : std_logic;
    signal s_rdata   : std_logic_vector(31 downto 0);
    signal s_rresp   : std_logic_vector(1 downto 0);
    signal s_rvalid  : std_logic;
    signal s_rready  : std_logic := '0';

    signal img_w_o, img_h_o, tmp_w_o, tmp_h_o : std_logic_vector(7 downto 0);
    signal start_pulse_o : std_logic;
    signal core_busy_i   : std_logic := '0';
    signal core_done_i   : std_logic := '0';
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.ncc_accel_slave_lite_v1_0_S00_AXI
        generic map (
            C_S_AXI_DATA_WIDTH => 32,
            C_S_AXI_ADDR_WIDTH => 6
        )
        port map (
            img_w       => img_w_o,
            img_h       => img_h_o,
            tmp_w       => tmp_w_o,
            tmp_h       => tmp_h_o,
            start_pulse => start_pulse_o,
            core_busy   => core_busy_i,
            core_done   => core_done_i,

            S_AXI_ACLK    => clk,
            S_AXI_ARESETN => aresetn,

            S_AXI_AWADDR  => s_awaddr,
            S_AXI_AWPROT  => s_awprot,
            S_AXI_AWVALID => s_awvalid,
            S_AXI_AWREADY => s_awready,

            S_AXI_WDATA   => s_wdata,
            S_AXI_WSTRB   => s_wstrb,
            S_AXI_WVALID  => s_wvalid,
            S_AXI_WREADY  => s_wready,

            S_AXI_BRESP   => s_bresp,
            S_AXI_BVALID  => s_bvalid,
            S_AXI_BREADY  => s_bready,

            S_AXI_ARADDR  => s_araddr,
            S_AXI_ARPROT  => s_arprot,
            S_AXI_ARVALID => s_arvalid,
            S_AXI_ARREADY => s_arready,

            S_AXI_RDATA   => s_rdata,
            S_AXI_RRESP   => s_rresp,
            S_AXI_RVALID  => s_rvalid,
            S_AXI_RREADY  => s_rready
        );

    stim: process
        variable rd       : std_logic_vector(31 downto 0);
        variable aw_done   : boolean;
        variable w_done    : boolean;
        variable cyc2      : integer;
        variable aw_issued : boolean;
        -- Scenario 4
        variable ph4       : integer; -- faza automata koji vozi stimulus
        variable cyc4      : integer; -- ukupan broj taktova u scenariju (watchdog)
        variable bcount4   : integer; -- broj taktova gde je BVALID='1' (ocekivano tacno 2)
        variable done_at4  : integer;

        procedure lite_read(addr : integer; res : out std_logic_vector(31 downto 0)) is
            variable to_ctr : integer := 0;
        begin
            s_araddr  <= std_logic_vector(to_unsigned(addr, 6));
            s_arvalid <= '1';
            s_rready  <= '1';
            wait until rising_edge(clk);
            s_arvalid <= '0';
            loop
                wait until rising_edge(clk);
                exit when s_rvalid = '1';
                to_ctr := to_ctr + 1;
                assert to_ctr < 100
                    report "FAIL: AXI-Lite citanje (adresa=" & integer'image(addr) &
                           ") nikad nije vratilo RVALID"
                    severity failure;
            end loop;
            res := s_rdata;
            s_rready <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- Ceka BVALID najvise BVALID_TIMEOUT taktova. Ako ne stigne, prijavljuje
        -- FAIL i zaustavlja simulaciju (severity failure) -- TB nikad ne sme da
        -- visi, cak ni na pokvarenom RTL-u koji bi hardverski master zaglavio.
        procedure wait_bvalid(scenario : string) is
            variable to_ctr : integer := 0;
        begin
            loop
                wait until rising_edge(clk);
                exit when s_bvalid = '1';
                to_ctr := to_ctr + 1;
                assert to_ctr < BVALID_TIMEOUT
                    report "FAIL [" & scenario & "]: BVALID nije stigao u " &
                           integer'image(BVALID_TIMEOUT) &
                           " taktova -- master bi ostao zaglavljen (potpis bug-a sa ploce)."
                    severity failure;
            end loop;
            wait until rising_edge(clk); -- BREADY='1' vec stoji, handshake se zavrsava ovde
        end procedure;

    begin
        -- reset, 10 taktova
        aresetn <= '0';
        for i in 0 to 9 loop wait until rising_edge(clk); end loop;
        aresetn <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -----------------------------------------------------------------
        -- Scenario 1: AW pa W, razmak >= 2 takta
        -----------------------------------------------------------------
        report "=== Scenario 1: AW pa W (razmak >= 2 takta) ===" severity note;
        s_awaddr  <= std_logic_vector(to_unsigned(0, 6));
        s_awvalid <= '1';
        loop
            wait until rising_edge(clk);
            exit when s_awready = '1';
        end loop;
        s_awvalid <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk); -- razmak od 2 takta pre W

        s_wdata  <= std_logic_vector(to_unsigned(16#5A#, 32));
        s_wstrb  <= "1111";
        s_wvalid <= '1';
        loop
            wait until rising_edge(clk);
            exit when s_wready = '1';
        end loop;
        s_wvalid <= '0';

        wait_bvalid("Scenario 1: AW pa W");

        lite_read(0, rd);
        assert to_integer(unsigned(rd)) = 16#5A#
            report "FAIL [Scenario 1]: procitano " & integer'image(to_integer(unsigned(rd))) &
                   ", ocekivano 90"
            severity failure;
        report "PASS [Scenario 1]: AW pa W -- upis/citanje OK (IMG_W=90)" severity note;

        -----------------------------------------------------------------
        -- Scenario 2: W pa AW, razmak >= 2 takta -- SLUCAJ KOJI JE PUKAO NA PLOCI
        -----------------------------------------------------------------
        report "=== Scenario 2: W pa AW (razmak >= 2 takta) -- slucaj sa ploce ===" severity note;
        -- Master ne sme da ceka WREADY pre nego sto uopste posalje AW -- na
        -- popravljenom RTL-u WREADY se ne dize dok AW nije prihvacen, pa bi
        -- takvo cekanje bilo kruzna zavisnost (deadlock u samom TB-u, ne u
        -- DUT-u). Zato W drzimo asertovan i NEZAVISNO, posle 2 takta razmaka,
        -- izdajemo AW -- tacno kako bi se ponasao realan master koji salje W
        -- pre AW po unapred zadatom rasporedu, ne cekajuci slave.
        s_wdata  <= std_logic_vector(to_unsigned(16#3C#, 32));
        s_wstrb  <= "1111";
        s_wvalid <= '1';
        aw_done   := false;
        w_done    := false;
        cyc2      := 0;
        aw_issued := false;
        loop
            wait until rising_edge(clk);
            cyc2 := cyc2 + 1;
            if (not w_done) and s_wready = '1' then
                s_wvalid <= '0';
                w_done := true;
            end if;
            -- Izdavanje AW i provera prihvatanja MORAJU biti u razlicitim
            -- iteracijama (elsif, ne dva odvojena if-a): AWREADY u Waddr stanju
            -- stoji na '1' i pre nego sto je AWVALID uopste podignut, pa bi
            -- provera u ISTOM koraku kad se AWVALID izdaje pogresno pomislila
            -- da je handshake vec zavrsen (procitala bi staru vrednost AWREADY
            -- pre nego sto ju je DUT uopste video) i odmah spustila AWVALID --
            -- pa ga DUT nikad ne bi ni registrovao (beskonacna petlja).
            if (not aw_issued) and cyc2 >= 2 then
                s_awaddr  <= std_logic_vector(to_unsigned(0, 6));
                s_awvalid <= '1';
                aw_issued := true;
            elsif aw_issued and (not aw_done) and s_awready = '1' then
                s_awvalid <= '0';
                aw_done := true;
            end if;
            exit when w_done and aw_done;
        end loop;

        wait_bvalid("Scenario 2: W pa AW");

        lite_read(0, rd);
        assert to_integer(unsigned(rd)) = 16#3C#
            report "FAIL [Scenario 2]: procitano " & integer'image(to_integer(unsigned(rd))) &
                   ", ocekivano 60"
            severity failure;
        report "PASS [Scenario 2]: W pa AW -- upis/citanje OK" severity note;

        -----------------------------------------------------------------
        -- Scenario 3: AW i W u istom taktu
        -----------------------------------------------------------------
        report "=== Scenario 3: AW i W u istom taktu ===" severity note;
        s_awaddr  <= std_logic_vector(to_unsigned(0, 6));
        s_awvalid <= '1';
        s_wdata   <= std_logic_vector(to_unsigned(16#7F#, 32));
        s_wstrb   <= "1111";
        s_wvalid  <= '1';
        aw_done := false;
        w_done  := false;
        loop
            wait until rising_edge(clk);
            if (not aw_done) and s_awready = '1' then
                s_awvalid <= '0';
                aw_done := true;
            end if;
            if (not w_done) and s_wready = '1' then
                s_wvalid <= '0';
                w_done := true;
            end if;
            exit when aw_done and w_done;
        end loop;

        wait_bvalid("Scenario 3: AW+W isti takt");

        lite_read(0, rd);
        assert to_integer(unsigned(rd)) = 16#7F#
            report "FAIL [Scenario 3]: procitano " & integer'image(to_integer(unsigned(rd))) &
                   ", ocekivano 127"
            severity failure;
        report "PASS [Scenario 3]: AW+W isti takt -- upis/citanje OK" severity note;

        -----------------------------------------------------------------
        -- Scenario 4: dva uzastopna upisa (IMG_W=90 pa IMG_H=45), BREADY
        -- stalno na '1', BEZ pauze izmedju upisa. AW za drugi upis se izdaje
        -- CIM se prihvati W prvog upisa -- tacno u taktu kad se automat vraca
        -- u Waddr sa BVALID='1' za prvi upis. To je tacan prozor u kome je
        -- recenzija nasla rupu: Waddr grana (AWVALID='1') nije cistila BVALID,
        -- pa bi master video "duh" drugog BVALID-a za transakciju koja jos
        -- nije zavrsena. Provera: bvalid mora biti '1' u TACNO 2 takta u celom
        -- scenariju (jedan po upisu), i oba registra moraju procitati tacne
        -- vrednosti.
        -----------------------------------------------------------------
        report "=== Scenario 4: dva uzastopna upisa, BREADY stalno na '1' (bez pauze) ===" severity note;
        ph4      := 0;
        cyc4     := 0;
        bcount4  := 0;
        done_at4 := -1;

        s_awaddr  <= std_logic_vector(to_unsigned(0, 6)); -- IMG_W
        s_awvalid <= '1';

        loop
            wait until rising_edge(clk);
            cyc4 := cyc4 + 1;
            if s_bvalid = '1' then
                bcount4 := bcount4 + 1;
            end if;

            case ph4 is
                when 0 => -- ceka se prihvatanje AW1
                    if s_awready = '1' then
                        s_awvalid <= '0';
                        s_wdata   <= std_logic_vector(to_unsigned(90, 32)); -- IMG_W
                        s_wstrb   <= "1111";
                        s_wvalid  <= '1';
                        ph4 := 1;
                    end if;
                when 1 => -- ceka se prihvatanje W1; AW2 se izdaje ODMAH po prihvatanju
                    if s_wready = '1' then
                        s_wvalid  <= '0';
                        s_awaddr  <= std_logic_vector(to_unsigned(4, 6)); -- IMG_H
                        s_awvalid <= '1';
                        ph4 := 2;
                    end if;
                when 2 => -- ceka se prihvatanje AW2
                    if s_awready = '1' then
                        s_awvalid <= '0';
                        s_wdata   <= std_logic_vector(to_unsigned(45, 32)); -- IMG_H
                        s_wstrb   <= "1111";
                        s_wvalid  <= '1';
                        ph4 := 3;
                    end if;
                when 3 => -- ceka se prihvatanje W2
                    if s_wready = '1' then
                        s_wvalid <= '0';
                        ph4 := 4;
                    end if;
                when 4 => -- ceka se BVALID za drugi upis
                    if s_bvalid = '1' then
                        ph4      := 5;
                        done_at4 := cyc4;
                    end if;
                when others => null; -- ph4 = 5: jos par taktova repa da uhvatimo eventualni "duh" BVALID
            end case;

            assert cyc4 < 200
                report "FAIL [Scenario 4]: watchdog istekao (verovatno hang ili automat zaglavljen)"
                severity failure;
            exit when ph4 = 5 and cyc4 >= done_at4 + 3;
        end loop;

        assert bcount4 = 2
            report "FAIL [Scenario 4]: BVALID je bio aktivan " & integer'image(bcount4) &
                   " takta(ova), ocekivano tacno 2 -- 'duh' BVALID (rupa u brisanju BVALID-a u Waddr grani)."
            severity failure;

        lite_read(0, rd);
        assert to_integer(unsigned(rd)) = 90
            report "FAIL [Scenario 4]: IMG_W procitano " & integer'image(to_integer(unsigned(rd))) &
                   ", ocekivano 90"
            severity failure;
        lite_read(4, rd);
        assert to_integer(unsigned(rd)) = 45
            report "FAIL [Scenario 4]: IMG_H procitano " & integer'image(to_integer(unsigned(rd))) &
                   ", ocekivano 45"
            severity failure;
        report "PASS [Scenario 4]: dva uzastopna upisa, tacno 2 BVALID takta, oba registra tacna."
            severity note;

        report "PASS: sva cetiri scenarija upisa u S00 (AXI-Lite) rade ispravno (AW-W, W-AW, AW+W, dva uzastopna sa BREADY='1')."
            severity note;
        std.env.stop;
    end process;
end architecture;
