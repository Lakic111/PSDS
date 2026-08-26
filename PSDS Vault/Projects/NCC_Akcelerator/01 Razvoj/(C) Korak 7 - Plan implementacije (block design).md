# Korak 7 — Plan implementacije (block design)

> **Za izvršioca:** implementira se zadatak-po-zadatak; koraci su čekboksovi (`- [ ]`).
> Dizajn (merodavan): `01 Razvoj/(C) Korak 7 - Dizajn integracije (block design).md`.

> **STATUS: Taskovi 1–9 IZVRŠENI (2026-07-25).** Task 10 (ovaj upis) u toku.
> Ništa nije komitovano — korisnik je rekao da commit nije bitan.
>
> **Tri greške u ovom planu, nađene pri izvršavanju (ispravljeno u skripti, ovde
> zapisano da se ne ponove):**
> 1. **Task 5/6 podela je bila pogrešna.** Task 5 uključuje `PCW_USE_M_AXI_GP0` i
>    `PCW_USE_S_AXI_HP0`, a njihove `M_AXI_GP0_ACLK`/`S_AXI_HP0_ACLK` pinove je vezivao
>    Task 6 → `validate_bd_design` u Tasku 5 pada sa `ERROR [BD 41-758] clock pins are
>    not connected to a valid clock source`. Popravka: ta dva takta se vežu odmah u
>    Tasku 5 (sekcija reseta), a Task 6 ih ne dira.
> 2. **`exclude_bd_addr_seg` MORA ići posle svih `assign_bd_address`.** Plan je isključivao
>    PS→DDR pre nego što je dodelio CDMA→DDR; posledica je bila da DDR segment tiho
>    **nestane iz CDMA mape** (bez ERROR-a) → CDMA bez pristupa DDR-u. Popravka: svi
>    assign-ovi, pa svi exclude-ovi.
> 3. **`report_utilization -hierarchical_depth 1`** ne radi bez `-hierarchical`
>    (`ERROR [Common 17-69]`). Za flat izveštaj koristiti golo `report_utilization`.
>
> **Očekivano-a-nije-greška:** `CRITICAL WARNING [PSU-1..4]` (negativan
> `PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_*`) dolazi iz Digilent board preseta;
> `CRITICAL WARNING [Designutils 20-1275]` (XDC po IP-u se ne čita) je artefakt
> `synth_design -rtl` režima.
>
> **Task 9 rezultat je obrnuo pretpostavku dizajna:** WNS na `clg400-1` je **−0,660 ns**,
> ali je merenje degenerisano (118 IOB naspram 54/100 dostupnih). Videti `BUGS.md`.
> `ncc_core.vhd` NIJE diran.

**Cilj:** povezati dva `ncc_accel` IP-a i AXI CDMA sa Zynq PS-om u block design
`ncc_system`, izgrađen reproducibilnom TCL skriptom, sa fiksnom adresnom mapom po ESL
`common.hpp`. Pretkorak: popraviti burst čitanje u S01 (bez toga CDMA čitanje ne radi).

**Arhitektura:** jedan SmartConnect sa 2 mastera (PS `M_AXI_GP0`, CDMA `M_AXI`) i
6 slave-ova (`ncc0/1.S00_AXI`, `ncc0/1.S01_AXI`, `cdma.S_AXI_LITE`, `PS.S_AXI_HP0`).
Jedan takt 100 MHz (`FCLK_CLK0`) na sve — nema CDC. Podatkovni put ide DDR ⇄ CDMA ⇄
`ncc.S01`, kontrolni CPU → `ncc.S00`.

**Tech stack:** VHDL-2008, Vivado 2025.2 batch (`vivado.bat -mode batch -source`),
`xvhdl`/`xelab`/`xsim` iz Git Bash-a.

## Global Constraints

- **Part:** `xc7z010clg400-1` (bilo `clg225-2` do Koraka 6 — videti dizajn §7.1).
- **board_part:** `digilentinc.com:zybo-z7-10:part0:1.2`. Fallback za originalni Zybo:
  `digilentinc.com:zybo:part0:2.0`. Board files instalirani u
  `C:\AMDDesignTools\2025.2\Vivado\data\boards\board_files\`.
- **Ne diraju se:** `ncc_core.vhd`, `ncc_pkg.vhd`, `dp_bram.vhd`, `mem_subsystem.vhd`,
  `ncc_accel_slave_lite_v1_0_S00_AXI.vhd`, `ncc_accel.vhd` (top).
- **Merodavan izvor IP-a:** `src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/` (to referencira
  `component.xml`). Sve simulacije se kompajliraju iz njega.
- **Zlatna vrednost koja se NE SME promeniti:** `ncc_accel_tb` daje peak `0x80000000`
  na indeksu `956` (= `14*66 + 32`, tj. u=32, v=14).
- **Adresna mapa je fiksna** (ne Vivado auto): `0x5000_0000` / `0x5002_0000` /
  `0x5100_0000` / `0x5102_0000` / `0x6000_0000`.
- **Commit tek na odobrenje korisnika.** Grana: nastaviti na `korak6-axi-ip` ili
  napraviti `korak7-block-design` (pitati). Sign-off: `Co-Authored-By: Claude ...`.
- **Sinteza/implementacija integrisanog sistema je Korak 8**, ne ovaj plan.

**xsim build šablon** (koristi se u Taskovima 1–4):

```bash
export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
IP="/c/Users/pc/Desktop/PSDS/src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0"
cd "/c/Users/pc/Desktop/PSDS/src/vhdl" && mkdir -p work_ip && cd work_ip
xvhdl -2008 "$IP/src/ncc_pkg.vhd" "$IP/src/ncc_core.vhd" "$IP/src/dp_bram.vhd" \
  "$IP/src/mem_subsystem.vhd" \
  "$IP/hdl/ncc_accel_slave_lite_v1_0_S00_AXI.vhd" \
  "$IP/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd" \
  "$IP/hdl/ncc_accel.vhd" ../tb/<tb>.vhd
xelab -debug typical <tb> -s <sim> && xsim <sim> -runall
```

Napomena: `work_ip` je u `.gitignore`. `ncc_accel_tb` čita `../tb/seg90.txt` i
`../tb/crnitop.txt` relativno, pa se **mora** pokretati iz `src/vhdl/work_ip`.

---

## Struktura fajlova

| Fajl | Odgovornost | Akcija |
|---|---|---|
| `src/vhdl/tb/ncc_accel_burst_tb.vhd` | Provera multi-beat INCR burst-ova na S01 (read i write). Jedini test koji pokriva burst put. | **Create** (Task 1) |
| `src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd` | AXI-Full slave kontroler → `mem_subsystem`. Popravka look-ahead adrese + brisanje mrtvog primera. | **Modify** (Task 2, 3) |
| `src/vhdl/ip/` (`dp_bram.vhd`, `mem_subsystem.vhd`) | Duplikat `ip_repo/.../src/`. Rizik: popraviti jednu kopiju, zaboraviti drugu. | **Delete** (Task 4) |
| `src/vhdl/script/create_bd.tcl` | Gradi ceo block design od nule: projekat, PS7, 2×IP, SmartConnect, CDMA, adresna mapa, wrapper. Temelj za Korak 10. | **Create** (Task 5–8) |
| `src/vhdl/script/run_synth_core.tcl` | Samostalna sinteza golog `ncc_core` za par metriku (doslednost Koraka 5 na novom partu). | **Create** (Task 9) |

---

### Task 1: Burst testbench (RED — mora da padne)

**Files:**
- Create: `src/vhdl/tb/ncc_accel_burst_tb.vhd`

**Interfaces:**
- Consumes: top `ncc_accel` (S00 + S01 AXI portovi, iz Koraka 6).
- Produces: simulacioni top `ncc_accel_burst_tb` (bez portova). Ispisuje po beat-u
  `očekivano`/`dobijeno`, pa na kraju `assert nfail_rd = 0` i `assert nfail_wr = 0`
  sa `severity failure`.

Testira ono što `ncc_accel_tb` ne pokriva: `awlen`/`arlen = 7` (8 beat-ova, INCR).
Brojači grešaka se sabiraju pa se tvrdnja proverava **na kraju**, da se u RED prolazu
vidi puna dijagnostika (koliko beat-ova i kako je pomereno), a ne samo prvi pad.

- [ ] **Step 1: Napisati** `src/vhdl/tb/ncc_accel_burst_tb.vhd`

```vhdl
-- Provera multi-beat INCR burst-ova na S01 (AXI-Full).
-- ncc_accel_tb (Korak 6) koristi samo awlen=0/arlen=0 -> burst put nije pokriven,
-- a svaki DMA (CDMA) radi duge INCR burst-ove.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity ncc_accel_burst_tb is end entity;
architecture beh of ncc_accel_burst_tb is
    constant OFF_IMG : integer := 16#00000#;   -- region slike u S01
    constant NB      : integer := 8;           -- beat-ova u burst-u (arlen/awlen = NB-1)

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
        -- single-beat upis (poznato ispravan iz Koraka 6)
        procedure full_write1(addr : integer; data : integer) is
        begin
            s01_awaddr  <= std_logic_vector(to_unsigned(addr,17));
            s01_awlen   <= (others=>'0'); s01_awsize <= "010"; s01_awburst <= "01";
            s01_awvalid <= '1';
            s01_wdata   <= std_logic_vector(to_unsigned(data,32));
            s01_wstrb   <= "1111"; s01_wlast <= '1'; s01_wvalid <= '1'; s01_bready <= '1';
            wait until rising_edge(clk);
            s01_awvalid <= '0'; s01_wvalid <= '0'; s01_wlast <= '0';
            loop wait until rising_edge(clk); exit when s01_bvalid='1'; end loop;
            s01_bready <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- single-beat citanje (poznato ispravno iz Koraka 6)
        procedure full_read1(addr : integer; res : out std_logic_vector(31 downto 0)) is
        begin
            s01_araddr  <= std_logic_vector(to_unsigned(addr,17));
            s01_arlen   <= (others=>'0'); s01_arsize <= "010"; s01_arburst <= "01";
            s01_arvalid <= '1'; s01_rready <= '1';
            wait until rising_edge(clk);
            s01_arvalid <= '0';
            loop wait until rising_edge(clk); exit when s01_rvalid='1'; end loop;
            res := s01_rdata;
            s01_rready <= '0';
            wait until rising_edge(clk);
        end procedure;

        variable rd : std_logic_vector(31 downto 0);
        variable got : integer;
        variable nfail_rd, nfail_wr : integer := 0;
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
        wait until rising_edge(clk);           -- arready je '1' -> handshake ovde
        s01_arvalid <= '0';
        for k in 0 to NB-1 loop
            loop wait until rising_edge(clk); exit when s01_rvalid='1'; end loop;
            got := to_integer(unsigned(s01_rdata));
            report "  READ  beat " & integer'image(k) &
                   ": ocekivano 0x" & integer'image(16#20# + k) &
                   " dobijeno 0x" & integer'image(got) &
                   "  rlast=" & std_logic'image(s01_rlast) severity note;
            if got /= 16#20# + k then nfail_rd := nfail_rd + 1; end if;
        end loop;
        s01_rready <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);

        ------------------------------------------------------------------
        -- C) TEST 2: multi-beat INCR WRITE burst, provera single-beat citanjem
        ------------------------------------------------------------------
        s01_awaddr  <= std_logic_vector(to_unsigned(OFF_IMG + 64*4, 17));
        s01_awlen   <= std_logic_vector(to_unsigned(NB-1, 8));
        s01_awsize  <= "010"; s01_awburst <= "01";
        s01_awvalid <= '1';
        s01_wdata   <= std_logic_vector(to_unsigned(16#50#, 32));
        s01_wstrb   <= "1111"; s01_wvalid <= '1'; s01_wlast <= '0'; s01_bready <= '1';
        wait until rising_edge(clk);           -- beat 0 (aw + w istovremeno)
        s01_awvalid <= '0';
        for k in 1 to NB-1 loop
            s01_wdata <= std_logic_vector(to_unsigned(16#50# + k, 32));
            if k = NB-1 then s01_wlast <= '1'; end if;
            wait until rising_edge(clk);
        end loop;
        s01_wvalid <= '0'; s01_wlast <= '0';
        loop wait until rising_edge(clk); exit when s01_bvalid='1'; end loop;
        s01_bready <= '0';
        wait until rising_edge(clk);

        for k in 0 to NB-1 loop
            full_read1(OFF_IMG + (64+k)*4, rd);
            got := to_integer(unsigned(rd));
            report "  WRITE img[" & integer'image(64+k) &
                   "]: ocekivano 0x" & integer'image(16#50# + k) &
                   " dobijeno 0x" & integer'image(got) severity note;
            if got /= 16#50# + k then nfail_wr := nfail_wr + 1; end if;
        end loop;

        ------------------------------------------------------------------
        -- D) tvrdnje na kraju (da se u RED prolazu vidi puna dijagnostika)
        ------------------------------------------------------------------
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
```

- [ ] **Step 2: Pokreni — READ mora da PADNE, WRITE da prođe**

```bash
export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
IP="/c/Users/pc/Desktop/PSDS/src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0"
cd "/c/Users/pc/Desktop/PSDS/src/vhdl" && mkdir -p work_ip && cd work_ip
xvhdl -2008 "$IP/src/ncc_pkg.vhd" "$IP/src/ncc_core.vhd" "$IP/src/dp_bram.vhd" \
  "$IP/src/mem_subsystem.vhd" \
  "$IP/hdl/ncc_accel_slave_lite_v1_0_S00_AXI.vhd" \
  "$IP/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd" \
  "$IP/hdl/ncc_accel.vhd" ../tb/ncc_accel_burst_tb.vhd
xelab -debug typical ncc_accel_burst_tb -s burst_sim && xsim burst_sim -runall
```

Expected (RED — potvrđeno probnim pokretanjem 2026-07-25):

```
READ  beat 0: ocekivano 0x32 dobijeno 0x32   rlast='0'
READ  beat 1: ocekivano 0x33 dobijeno 0x32   rlast='0'
READ  beat 2: ocekivano 0x34 dobijeno 0x33   rlast='0'
...
READ  beat 7: ocekivano 0x39 dobijeno 0x38   rlast='1'
WRITE img[64..71]: sve tacno
FAILURE: FAIL: read burst -- 7 od 8 beat-ova pogresno
```

Ako READ prođe → nešto je već popravljeno, **stani i proveri** pre nastavka.

- [ ] **Step 3: Commit** (na odobrenje)

```bash
git add src/vhdl/tb/ncc_accel_burst_tb.vhd
git commit -m "test(korak7): burst testbench za S01 -- otkriva off-by-one u read burstu"
```

---

### Task 2: Popravka read-burst u S01 (GREEN)

**Files:**
- Modify: `src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd`
  (deklaracije arhitekture ~`:241`, i blok `mem_addr_o` na `:504-512`)

**Interfaces:**
- Consumes: `ncc_accel_burst_tb` (Task 1), `ncc_accel_tb` (Korak 6).
- Produces: nema izmene portova ni generika → `component.xml` ostaje validan, IP se ne
  pakuje iznova.

**Uzrok:** originalni Xilinx šablon čita interni primer-RAM **kombinaciono**; u Koraku 6
je zamenjen registrovanim `dp_bram` čitanjem (1 takt) i poravnanje je popravljeno samo za
prvi beat. Za beat-ove ≥1 `mem_addr_o` uzima `axi_araddr`, koji se inkrementira u istom
taktu kad se beat troši (`:444-445`) → podatak stiže takt prekasno.

**Popravka:** u taktu kad se beat *k* troši izdati adresu beat-a *k+1*.

- [ ] **Step 1: Dodati signal u deklaracije arhitekture**

Odmah posle `signal state_write: std_logic_vector(1 downto 0);` (~`:241`) dodati:

```vhdl
	-- look-ahead adresa citanja: registrovano dp_bram citanje trazi adresu
	-- jedan takt pre nego sto beat izadje na rdata
	signal araddr_next : std_logic_vector(16 downto 0);
```

- [ ] **Step 2: Zameniti blok `mem_addr_o`**

Zameniti postojeće (`:504-512`):

```vhdl
	-- === NCC omotac: veza AXI-Full <-> mem_subsystem ===
	-- Citanje: adresa na ciklusu prihvata (S_AXI_ARADDR) da 1-taktno registrovano
	-- dp_bram citanje bude poravnato sa rvalid (single-beat pristupi).
	mem_addr_o  <= S_AXI_ARADDR(16 downto 0) when (S_AXI_ARVALID = '1' and axi_arready = '1') else
	               axi_araddr(16 downto 0)   when (state_read = Rdata) else
	               S_AXI_AWADDR(16 downto 0) when (S_AXI_AWVALID = '1' and S_AXI_WVALID = '1') else
	               axi_awaddr(16 downto 0);
	mem_wdata_o <= S_AXI_WDATA;
	mem_we_o    <= axi_wready and S_AXI_WVALID;
```

sa:

```vhdl
	-- === NCC omotac: veza AXI-Full <-> mem_subsystem ===
	-- dp_bram citanje je registrovano (1 takt), pa adresa mora ici JEDAN TAKT
	-- unaprijed. Prvi beat: adresa na ciklusu prihvata (S_AXI_ARADDR). Beat k>0:
	-- u taktu kad se beat k trosi izdaje se adresa beat-a k+1 (araddr_next).
	-- Pri zastoju (RREADY='0') adresa se drzi pa podatak beat-a k ostaje validan.
	-- INCR uvecava; FIXED zadrzava adresu; WRAP nije podrzan (nije ni bio).
	araddr_next <= std_logic_vector(unsigned(axi_araddr(16 downto 0)) + 4)
	                 when axi_arburst = "01" else
	               axi_araddr(16 downto 0);

	mem_addr_o  <= S_AXI_ARADDR(16 downto 0)
	                 when (S_AXI_ARVALID = '1' and axi_arready = '1') else
	               araddr_next
	                 when (state_read = Rdata and axi_rvalid = '1' and S_AXI_RREADY = '1') else
	               axi_araddr(16 downto 0)
	                 when (state_read = Rdata) else
	               S_AXI_AWADDR(16 downto 0)
	                 when (S_AXI_AWVALID = '1' and S_AXI_WVALID = '1') else
	               axi_awaddr(16 downto 0);
	mem_wdata_o <= S_AXI_WDATA;
	mem_we_o    <= axi_wready and S_AXI_WVALID;
```

- [ ] **Step 3: Pokreni burst TB — mora da PROĐE**

```bash
export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
IP="/c/Users/pc/Desktop/PSDS/src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0"
cd "/c/Users/pc/Desktop/PSDS/src/vhdl/work_ip"
xvhdl -2008 "$IP/src/ncc_pkg.vhd" "$IP/src/ncc_core.vhd" "$IP/src/dp_bram.vhd" \
  "$IP/src/mem_subsystem.vhd" \
  "$IP/hdl/ncc_accel_slave_lite_v1_0_S00_AXI.vhd" \
  "$IP/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd" \
  "$IP/hdl/ncc_accel.vhd" ../tb/ncc_accel_burst_tb.vhd
xelab -debug typical ncc_accel_burst_tb -s burst_sim && xsim burst_sim -runall
```

Expected: `PASS: ncc_accel burst (read i write, arlen/awlen=7)` — svi READ beat-ovi
`ocekivano == dobijeno`, `rlast='1'` na beat-u 7.

- [ ] **Step 4: Pokreni zlatni TB — mora da PROĐE NEPROMENJEN (regresija)**

```bash
cd "/c/Users/pc/Desktop/PSDS/src/vhdl/work_ip"
xvhdl -2008 ../tb/ncc_accel_tb.vhd
xelab -debug typical ncc_accel_tb -s accel_sim && xsim accel_sim -runall
```

Expected: `PASS: ncc_accel golden peak 0x80000000 @ idx 956`. Single-beat put nije
diran, pa mora biti bit-identično Koraku 6. **Ako se promenilo — popravka je pogrešna,
vrati i preispitaj.**

- [ ] **Step 5: Commit** (na odobrenje)

```bash
git add src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd
git commit -m "fix(korak7): S01 read burst -- look-ahead adresa za registrovano dp_bram citanje"
```

---

### Task 3: Obrisati mrtav generisani primer-BRAM iz S01

**Files:**
- Modify: `src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd`

**Interfaces:**
- Consumes: `ncc_accel_burst_tb`, `ncc_accel_tb`.
- Produces: isti entitet, bez mrtvog koda.

Generisani primer-RAM (4× 256 B) je ostao instanciran. `mem_data_out` se nigde ne čita
(RDATA ide iz `mem_rdata_i`, `:258`) pa ga sinteza izbaci — ali zbunjuje pri čitanju i
lažno sugeriše da IP ima interni RAM u AXI kontroleru.

- [ ] **Step 1: Obrisati blokove `gen_mem_sel` i `BRAM_GEN`** (`:473-502`)

Obrisati ceo blok od komentara `---- Example code to access user logic memory region`
do `end generate BRAM_GEN;` uključivo:

```vhdl
	---- ------------------------------------------
	---- -- Example code to access user logic memory region
	---- ------------------------------------------
	 gen_mem_sel: if (USER_NUM_MEM >= 1) generate
	   ...
	 end generate BRAM_GEN;
```

- [ ] **Step 2: Obrisati nekorišćene deklaracije**

Iz deklaracija arhitekture obrisati (svi su bili u službi obrisanog bloka):

```vhdl
	constant OPT_MEM_ADDR_BITS : integer := 7;
	constant USER_NUM_MEM: integer := 1;
	signal mem_address_read : std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
	signal mem_address_write : std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
	type word_array is array (0 to USER_NUM_MEM-1) of std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal mem_data_out : word_array;
	signal i : integer;
	signal j : integer;
	signal mem_byte_index : integer;
	type BYTE_RAM_TYPE is array (0 to 255) of std_logic_vector(7 downto 0);
```

**ZADRŽATI:** `constant ADDR_LSB` (koriste ga adresni brojači na `:398,414-415,452-453`)
i `constant low` (koriste ga `aw_wrap_en`/`ar_wrap_en` na `:261-262`).

- [ ] **Step 3: Pokreni oba TB-a — moraju PROĆI nepromenjeno**

```bash
export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
IP="/c/Users/pc/Desktop/PSDS/src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0"
cd "/c/Users/pc/Desktop/PSDS/src/vhdl/work_ip"
xvhdl -2008 "$IP/src/ncc_pkg.vhd" "$IP/src/ncc_core.vhd" "$IP/src/dp_bram.vhd" \
  "$IP/src/mem_subsystem.vhd" \
  "$IP/hdl/ncc_accel_slave_lite_v1_0_S00_AXI.vhd" \
  "$IP/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd" \
  "$IP/hdl/ncc_accel.vhd" ../tb/ncc_accel_burst_tb.vhd ../tb/ncc_accel_tb.vhd
xelab -debug typical ncc_accel_burst_tb -s burst_sim && xsim burst_sim -runall
xelab -debug typical ncc_accel_tb      -s accel_sim && xsim accel_sim -runall
```

Expected: `PASS: ncc_accel burst ...` i `PASS: ncc_accel golden peak 0x80000000 @ idx 956`.
`xvhdl` bez upozorenja o nekorišćenim deklaracijama.

- [ ] **Step 4: Commit** (na odobrenje)

```bash
git add src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd
git commit -m "chore(korak7): obrisan mrtav generisani primer-BRAM iz S01 kontrolera"
```

---

### Task 4: Konsolidacija izvora — jedan merodavan izvor

**Files:**
- Delete: `src/vhdl/ip/dp_bram.vhd`, `src/vhdl/ip/mem_subsystem.vhd`

**Interfaces:**
- Consumes: `dp_bram_tb`, `mem_subsystem_tb` (Korak 6) — u fajlovima nema putanja
  (koriste `entity work.dp_bram`), pa se **ne menjaju**; menja se samo `xvhdl` komanda.
- Produces: `ip_repo/ncc_accel_1_0/{src,hdl}/` kao jedini izvor.

`dp_bram.vhd` i `mem_subsystem.vhd` postoje u dve kopije (`src/vhdl/ip/` i
`ip_repo/.../src/`). `component.xml` referencira `ip_repo`, pa je to merodavno; druga
kopija je rizik (popraviti jednu, zaboraviti drugu).

- [ ] **Step 1: Potvrditi da su kopije identične** (ako nisu — stani i uporedi ručno)

```bash
cd "/c/Users/pc/Desktop/PSDS"
diff src/vhdl/ip/dp_bram.vhd       src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/src/dp_bram.vhd
diff src/vhdl/ip/mem_subsystem.vhd src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/src/mem_subsystem.vhd
diff src/vhdl/ncc_core.vhd         src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/src/ncc_core.vhd
diff src/vhdl/ncc_pkg.vhd          src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/src/ncc_pkg.vhd
```

Expected: nijedan izlaz (sve identično).

Napomena: `src/vhdl/ncc_core.vhd` i `ncc_pkg.vhd` **ostaju** — to su izvori Koraka 3–5
i koriste ih `ncc_core_tb`/`ncc_core_real_tb`. Briše se samo `src/vhdl/ip/`.

- [ ] **Step 2: Obrisati duplikat**

```bash
cd "/c/Users/pc/Desktop/PSDS"
git rm src/vhdl/ip/dp_bram.vhd src/vhdl/ip/mem_subsystem.vhd
```

- [ ] **Step 3: Pokrenuti sva 4 IP testbencha iz `ip_repo` izvora**

```bash
export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
IP="/c/Users/pc/Desktop/PSDS/src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0"
cd "/c/Users/pc/Desktop/PSDS/src/vhdl" && rm -rf work_ip && mkdir -p work_ip && cd work_ip
xvhdl -2008 "$IP/src/ncc_pkg.vhd" "$IP/src/ncc_core.vhd" "$IP/src/dp_bram.vhd" \
  "$IP/src/mem_subsystem.vhd" \
  "$IP/hdl/ncc_accel_slave_lite_v1_0_S00_AXI.vhd" \
  "$IP/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd" \
  "$IP/hdl/ncc_accel.vhd" \
  ../tb/dp_bram_tb.vhd ../tb/mem_subsystem_tb.vhd \
  ../tb/ncc_accel_burst_tb.vhd ../tb/ncc_accel_tb.vhd
for t in dp_bram_tb mem_subsystem_tb ncc_accel_burst_tb ncc_accel_tb; do
  xelab -debug typical $t -s ${t}_sim && xsim ${t}_sim -runall
done
```

Expected: `PASS: dp_bram`, `PASS: mem_subsystem`,
`PASS: ncc_accel burst (read i write, arlen/awlen=7)`,
`PASS: ncc_accel golden peak 0x80000000 @ idx 956`.

- [ ] **Step 4: Ažurirati dokumentovane build komande**

U `01 Razvoj/(C) Korak 6 - Plan implementacije (AXI IP).md` zameniti sve pojave
`../ip/dp_bram.vhd` i `../ip/mem_subsystem.vhd` putanjama u `ip_repo` (`$IP/src/...`),
i dodati jednu rečenicu na vrh: „Izvori su konsolidovani u `ip_repo` (Korak 7, Task 4);
`src/vhdl/ip/` više ne postoji."

- [ ] **Step 5: Commit** (na odobrenje)

```bash
git add -A src/vhdl/ip "PSDS Vault/Projects/NCC_Akcelerator/01 Razvoj/(C) Korak 6 - Plan implementacije (AXI IP).md"
git commit -m "chore(korak7): konsolidovani izvori -- ip_repo je jedini merodavan"
```

---

### Task 5: `create_bd.tcl` — projekat + Zynq PS + reset

**Files:**
- Create: `src/vhdl/script/create_bd.tcl`

**Interfaces:**
- Produces: Vivado projekat `src/vhdl/result/ncc_system/ncc_system.xpr` sa block
  design-om `ncc_system` koji sadrži `processing_system7_0` (board preset, FCLK_CLK0 =
  100 MHz, `M_AXI_GP0` i `S_AXI_HP0` uključeni) i `proc_sys_reset_0`.
  Imena pinova koja koriste Taskovi 6–7: `processing_system7_0/FCLK_CLK0`,
  `/FCLK_RESET0_N`, `/M_AXI_GP0`, `/M_AXI_GP0_ACLK`, `/S_AXI_HP0`, `/S_AXI_HP0_ACLK`;
  `proc_sys_reset_0/peripheral_aresetn`; master adresni prostor
  `processing_system7_0/Data`; DDR segment
  `processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM` (range `0x40000000` = 1 GB).

- [ ] **Step 1: Napisati** `src/vhdl/script/create_bd.tcl`

```tcl
# ============================================================================
# Korak 7 -- block design ncc_system: Zynq PS + 2x ncc_accel + AXI CDMA.
# Pokretanje (iz korena repoa):
#   vivado.bat -mode batch -source src/vhdl/script/create_bd.tcl
# Skripta je idempotentna (-force) -- brise i pravi projekat od nule.
# Dizajn: PSDS Vault/.../01 Razvoj/(C) Korak 7 - Dizajn integracije (block design).md
# ============================================================================

set REPO      [file normalize [file join [file dirname [info script]] ../../..]]
set PROJ_DIR  [file join $REPO src/vhdl/result/ncc_system]
set IP_REPO   [file join $REPO src/vhdl_NCC_IP/ip_repo]
set PART      xc7z010clg400-1
# Zybo Z7-10. Za originalni Zybo: digilentinc.com:zybo:part0:2.0 (PS_CLK 50 MHz,
# DDR3 MT41K128M16 JT-125 512 MB). Videti dizajn 7.3 -- NEPOTVRDJENA pretpostavka.
set BOARD     digilentinc.com:zybo-z7-10:part0:1.2
set BD_NAME   ncc_system

puts "### repo    = $REPO"
puts "### part    = $PART"
puts "### board   = $BOARD"

# --- projekat ---------------------------------------------------------------
create_project $BD_NAME $PROJ_DIR -part $PART -force
set_property board_part      $BOARD  [current_project]
set_property target_language VHDL    [current_project]
set_property ip_repo_paths   $IP_REPO [current_project]
update_ip_catalog -rebuild

if {[get_ipdefs -quiet xilinx.com:user:ncc_accel:1.0] eq ""} {
    error "ncc_accel 1.0 nije u katalogu -- proveri ip_repo_paths: $IP_REPO"
}
puts "### ncc_accel u katalogu: OK"

# --- block design ----------------------------------------------------------
create_bd_design $BD_NAME

# Zynq PS: board preset daje tacan DDR/MIO/PS_CLK; FIXED_IO i DDR izlaze na pinove.
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" \
             Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]

set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0            {1}   \
    CONFIG.PCW_USE_S_AXI_HP0            {1}   \
] [get_bd_cells processing_system7_0]

# Provera da je preset stvarno primenjen (a ne Vivado default).
set ps [get_bd_cells processing_system7_0]
puts "### PS preset: PS_CLK=[get_property CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ $ps]\
 DDR=[get_property CONFIG.PCW_UIPARAM_DDR_PARTNO $ps]\
 FCLK0=[get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $ps]"

# --- reset -----------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
               [get_bd_pins proc_sys_reset_0/ext_reset_in]

# --- validacija ------------------------------------------------------------
save_bd_design
validate_bd_design
puts "### TASK 5 OK: PS + reset validirani"
```

- [ ] **Step 2: Pokreni — `validate_bd_design` bez grešaka**

```bash
cd "/c/Users/pc/Desktop/PSDS"
/c/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -nolog -notrace \
  -source src/vhdl/script/create_bd.tcl 2>&1 | grep -E "^###|ERROR|CRITICAL"
```

Expected:

```
### ncc_accel u katalogu: OK
### PS preset: PS_CLK=33.333333 DDR=MT41K256M16 RE-125 FCLK0=100
### TASK 5 OK: PS + reset validirani
```

Bez `ERROR` i bez `CRITICAL WARNING`. Ako `PS_CLK` nije `33.333333` → board preset nije
primenjen (proveri `board_part`).

- [ ] **Step 3: Commit** (na odobrenje)

```bash
git add src/vhdl/script/create_bd.tcl
git commit -m "feat(korak7): create_bd.tcl -- Zynq PS + proc_sys_reset, validate OK"
```

---

### Task 6: `create_bd.tcl` — 2× `ncc_accel` + SmartConnect + fiksne adrese

**Files:**
- Modify: `src/vhdl/script/create_bd.tcl` (dodati sekciju pre `--- validacija ---`)

**Interfaces:**
- Consumes: Task 5 (PS pinovi, `proc_sys_reset_0/peripheral_aresetn`).
- Produces: `ncc0`, `ncc1` (`xilinx.com:user:ncc_accel:1.0`), `smartconnect_0`
  (`NUM_SI=1`, `NUM_MI=4`). Adresni segmenti (imena potvrđena kroz Vivado):
  `ncc0/S00_AXI/S00_AXI_reg`, `ncc0/S01_AXI/S01_AXI_mem`, isto za `ncc1`.

- [ ] **Step 1: Dodati sekciju u `create_bd.tcl`**

Umetnuti **pre** `# --- validacija ---`:

```tcl
# --- 2x ncc_accel ----------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:user:ncc_accel:1.0 ncc0
create_bd_cell -type ip -vlnv xilinx.com:user:ncc_accel:1.0 ncc1

# --- SmartConnect: 1 master (PS GP0) -> 4 slave-a --------------------------
# (Task 7 ga siri na NUM_SI=2 / NUM_MI=6 kad se doda CDMA.)
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {4}] \
    [get_bd_cells smartconnect_0]

connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
                    [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] \
                    [get_bd_intf_pins ncc0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M01_AXI] \
                    [get_bd_intf_pins ncc0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M02_AXI] \
                    [get_bd_intf_pins ncc1/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M03_AXI] \
                    [get_bd_intf_pins ncc1/S01_AXI]

# --- jedan takt, jedan reset na sve ----------------------------------------
set CLK  [get_bd_pins processing_system7_0/FCLK_CLK0]
set RSTN [get_bd_pins proc_sys_reset_0/peripheral_aresetn]

connect_bd_net $CLK \
    [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
    [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] \
    [get_bd_pins smartconnect_0/aclk] \
    [get_bd_pins ncc0/s00_axi_aclk] [get_bd_pins ncc0/s01_axi_aclk] \
    [get_bd_pins ncc1/s00_axi_aclk] [get_bd_pins ncc1/s01_axi_aclk]

connect_bd_net $RSTN \
    [get_bd_pins smartconnect_0/aresetn] \
    [get_bd_pins ncc0/s00_axi_aresetn] [get_bd_pins ncc0/s01_axi_aresetn] \
    [get_bd_pins ncc1/s00_axi_aresetn] [get_bd_pins ncc1/s01_axi_aresetn]

# --- fiksna adresna mapa (PS master) --------------------------------------
# Poklapa se sa ESL common.hpp: ADDR_NCC=0x50000000, ADDR_NCC1=0x51000000.
# S00 opseg je 4K (Vivado minimum za AXI segment); IP dekodira samo donjih 6 bita.
set PSDATA [get_bd_addr_spaces processing_system7_0/Data]
assign_bd_address -offset 0x50000000 -range 4K   -target_address_space $PSDATA \
    [get_bd_addr_segs ncc0/S00_AXI/S00_AXI_reg] -force
assign_bd_address -offset 0x50020000 -range 128K -target_address_space $PSDATA \
    [get_bd_addr_segs ncc0/S01_AXI/S01_AXI_mem] -force
assign_bd_address -offset 0x51000000 -range 4K   -target_address_space $PSDATA \
    [get_bd_addr_segs ncc1/S00_AXI/S00_AXI_reg] -force
assign_bd_address -offset 0x51020000 -range 128K -target_address_space $PSDATA \
    [get_bd_addr_segs ncc1/S01_AXI/S01_AXI_mem] -force

# PS ne rutira ka svom DDR-u kroz PL -- ima direktan put.
exclude_bd_addr_seg -target_address_space $PSDATA \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM]

puts "### adresna mapa (PS master):"
foreach s [get_bd_addr_segs -of_objects $PSDATA] {
    puts [format "###   %-56s %s  %s" $s \
        [get_property OFFSET $s] [get_property RANGE $s]]
}
```

- [ ] **Step 2: Ažurirati poruku validacije**

Zameniti `puts "### TASK 5 OK: PS + reset validirani"` sa:

```tcl
puts "### TASK 6 OK: PS + reset + 2x ncc_accel + SmartConnect validirani"
```

- [ ] **Step 3: Pokreni — provera adresa i `validate_bd_design`**

```bash
cd "/c/Users/pc/Desktop/PSDS"
/c/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -nolog -notrace \
  -source src/vhdl/script/create_bd.tcl 2>&1 | grep -E "^###|ERROR|CRITICAL"
```

Expected — tačno ove četiri adrese (offset heksadecimalno, range simbolički):

```
### adresna mapa (PS master):
###   /processing_system7_0/Data/SEG_ncc0_S00_AXI_reg    0x50000000  4K
###   /processing_system7_0/Data/SEG_ncc0_S01_AXI_mem    0x50020000  128K
###   /processing_system7_0/Data/SEG_ncc1_S00_AXI_reg    0x51000000  4K
###   /processing_system7_0/Data/SEG_ncc1_S01_AXI_mem    0x51020000  128K
### TASK 6 OK: PS + reset + 2x ncc_accel + SmartConnect validirani
```

Imena segmenata (`SEG_*`) generiše Vivado — bitne su **adrese i opsezi**. Bez `ERROR`.

- [ ] **Step 4: Commit** (na odobrenje)

```bash
git add src/vhdl/script/create_bd.tcl
git commit -m "feat(korak7): 2x ncc_accel + SmartConnect + fiksna adresna mapa po ESL"
```

---

### Task 7: `create_bd.tcl` — AXI CDMA kao drugi master

**Files:**
- Modify: `src/vhdl/script/create_bd.tcl`

**Interfaces:**
- Consumes: Task 6 (`smartconnect_0`, `ncc0/1`, PS pinovi, `$CLK`, `$RSTN`).
- Produces: `axi_cdma_0` (`xilinx.com:ip:axi_cdma:4.1`, simple mode). Adresni prostori i
  segmenti (potvrđeni kroz Vivado): master prostor `axi_cdma_0/Data`, segment kontrolnih
  registara `axi_cdma_0/S_AXI_LITE/Reg`. `smartconnect_0` postaje `NUM_SI=2`, `NUM_MI=6`.

Zašto jedan SmartConnect a ne dva: AXI slave interfejs može biti povezan na **samo jedan**
interkonekt, a `ncc.S01` mora biti dostupan i PS-u i CDMA-u.

- [ ] **Step 1: Promeniti veličinu SmartConnect-a**

Zameniti u sekciji iz Taska 6:

```tcl
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {4}] \
    [get_bd_cells smartconnect_0]
```

sa:

```tcl
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {6}] \
    [get_bd_cells smartconnect_0]
```

- [ ] **Step 2: Dodati CDMA sekciju** (posle veza `ncc1/S01_AXI`, pre sekcije takta)

```tcl
# --- AXI CDMA (mem-na-mem): podatkovni put DDR <-> ncc.S01 -----------------
# Simple mode (bez scatter-gather), bez DRE (svi pristupi su 4B-poravnati).
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_cdma:4.1 axi_cdma_0
set_property -dict [list \
    CONFIG.C_INCLUDE_SG          {0}   \
    CONFIG.C_INCLUDE_DRE         {0}   \
    CONFIG.C_M_AXI_DATA_WIDTH    {32}  \
    CONFIG.C_M_AXI_MAX_BURST_LEN {256} \
] [get_bd_cells axi_cdma_0]

puts "### CDMA config: SG=[get_property CONFIG.C_INCLUDE_SG [get_bd_cells axi_cdma_0]]\
 DRE=[get_property CONFIG.C_INCLUDE_DRE [get_bd_cells axi_cdma_0]]\
 DW=[get_property CONFIG.C_M_AXI_DATA_WIDTH [get_bd_cells axi_cdma_0]]\
 BURST=[get_property CONFIG.C_M_AXI_MAX_BURST_LEN [get_bd_cells axi_cdma_0]]"

# CDMA kontrolni registri = 5. slave; CDMA master = 2. master.
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M04_AXI] \
                    [get_bd_intf_pins axi_cdma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_cdma_0/M_AXI] \
                    [get_bd_intf_pins smartconnect_0/S01_AXI]
# DDR kao 6. slave (CDMA ga koristi; PS-u je iskljucen iz mape).
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M05_AXI] \
                    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]
```

- [ ] **Step 3: Dodati CDMA na takt i reset**

U `connect_bd_net $CLK ...` dodati na kraj liste:

```tcl
    [get_bd_pins axi_cdma_0/m_axi_aclk] [get_bd_pins axi_cdma_0/s_axi_lite_aclk]
```

U `connect_bd_net $RSTN ...` dodati na kraj liste:

```tcl
    [get_bd_pins axi_cdma_0/s_axi_lite_aresetn]
```

- [ ] **Step 4: Dodati adresnu mapu CDMA mastera** (posle PS `exclude_bd_addr_seg`)

```tcl
# --- adresna mapa: PS vidi i CDMA kontrolu ---------------------------------
assign_bd_address -offset 0x60000000 -range 64K -target_address_space $PSDATA \
    [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] -force

# --- adresna mapa: CDMA master --------------------------------------------
# CDMA vidi DDR (izvor/odrediste) i memorije oba NCC-a. NE vidi kontrolne
# registre -- ne treba mu, a suzavanje mape smanjuje sansu za slucajan upis.
set CDMADATA [get_bd_addr_spaces axi_cdma_0/Data]
assign_bd_address -target_address_space $CDMADATA \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
assign_bd_address -offset 0x50020000 -range 128K -target_address_space $CDMADATA \
    [get_bd_addr_segs ncc0/S01_AXI/S01_AXI_mem] -force
assign_bd_address -offset 0x51020000 -range 128K -target_address_space $CDMADATA \
    [get_bd_addr_segs ncc1/S01_AXI/S01_AXI_mem] -force

foreach seg {ncc0/S00_AXI/S00_AXI_reg ncc1/S00_AXI/S00_AXI_reg axi_cdma_0/S_AXI_LITE/Reg} {
    if {[get_bd_addr_segs -quiet $seg] ne ""} {
        catch { exclude_bd_addr_seg -target_address_space $CDMADATA \
                    [get_bd_addr_segs $seg] }
    }
}

puts "### adresna mapa (CDMA master):"
foreach s [get_bd_addr_segs -of_objects $CDMADATA] {
    puts [format "###   %-56s %s  %s" $s \
        [get_property OFFSET $s] [get_property RANGE $s]]
}
```

Napomena: DDR segment se dodeljuje **bez** `-offset`/`-range` — opseg dolazi iz PS
board preseta (1 GB za Zybo Z7-10, 512 MB za originalni Zybo), pa se ne kuca kao
konstanta.

- [ ] **Step 5: Ažurirati poruku validacije**

```tcl
puts "### TASK 7 OK: ceo BD (PS + reset + 2x ncc_accel + SmartConnect + CDMA) validiran"
```

- [ ] **Step 6: Pokreni — cela mapa i `validate_bd_design`**

```bash
cd "/c/Users/pc/Desktop/PSDS"
/c/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -nolog -notrace \
  -source src/vhdl/script/create_bd.tcl 2>&1 | grep -E "^###|ERROR|CRITICAL"
```

Expected:

```
### CDMA config: SG=0 DRE=0 DW=32 BURST=256
### adresna mapa (PS master):
###   ...SEG_ncc0_S00_AXI_reg    0x50000000  4K
###   ...SEG_ncc0_S01_AXI_mem    0x50020000  128K
###   ...SEG_ncc1_S00_AXI_reg    0x51000000  4K
###   ...SEG_ncc1_S01_AXI_mem    0x51020000  128K
###   ...SEG_axi_cdma_0_Reg      0x60000000  64K
### adresna mapa (CDMA master):
###   ...SEG_processing_system7_0_HP0_DDR_LOWOCM   0x00000000  1G
###   ...SEG_ncc0_S01_AXI_mem                      0x50020000  128K
###   ...SEG_ncc1_S01_AXI_mem                      0x51020000  128K
### TASK 7 OK: ceo BD (...) validiran
```

Ako neko `CONFIG.C_*` ime CDMA-e nije prihvaćeno, `set_property` javi grešku odmah —
tada proveriti tačno ime sa `report_property [get_bd_cells axi_cdma_0]` i ispraviti.

- [ ] **Step 7: Commit** (na odobrenje)

```bash
git add src/vhdl/script/create_bd.tcl
git commit -m "feat(korak7): AXI CDMA kao drugi master + po-master adresna mapa"
```

---

### Task 8: HDL wrapper + elaboracija

**Files:**
- Modify: `src/vhdl/script/create_bd.tcl`

**Interfaces:**
- Consumes: Task 7 (validiran BD `ncc_system`).
- Produces: `ncc_system_wrapper.vhd` (generisan) postavljen kao top modul projekta.

- [ ] **Step 1: Dodati generisanje wrapper-a na kraj `create_bd.tcl`**

```tcl
# --- wrapper + top ---------------------------------------------------------
set BD_FILE [get_files ${BD_NAME}.bd]
generate_target all $BD_FILE
make_wrapper -files $BD_FILE -top -import
set_property top ${BD_NAME}_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "### top modul: [get_property top [current_fileset]]"

# Elaboracija: uhvati sintaksne/hijerarhijske greske bez pune sinteze.
synth_design -rtl -name rtl_check -top ${BD_NAME}_wrapper
puts "### TASK 8 OK: wrapper generisan, RTL elaboracija prosla"
```

- [ ] **Step 2: Pokreni — wrapper i elaboracija**

```bash
cd "/c/Users/pc/Desktop/PSDS"
/c/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -nolog -notrace \
  -source src/vhdl/script/create_bd.tcl 2>&1 | grep -E "^###|ERROR|CRITICAL"
```

Expected:

```
### top modul: ncc_system_wrapper
### TASK 8 OK: wrapper generisan, RTL elaboracija prosla
```

Bez `ERROR`. Elaboracija traje nekoliko minuta (generisanje IP izlaza za PS7, SmartConnect
i CDMA-u je prvi put najduže).

- [ ] **Step 3: Commit** (na odobrenje)

```bash
git add src/vhdl/script/create_bd.tcl
git commit -m "feat(korak7): HDL wrapper + RTL elaboracija u create_bd.tcl -- Korak 7 gotov"
```

Napomena: `src/vhdl/result/` je u `.gitignore` — projekat se ne komituje, regeneriše se
skriptom. To je i poenta za Korak 10.

---

### Task 9: Doslednost Koraka 5 — re-sinteza `ncc_core` na `clg400-1`

**Files:**
- Create: `src/vhdl/script/run_synth_core.tcl`

**Interfaces:**
- Consumes: `src/vhdl/ncc_pkg.vhd`, `src/vhdl/ncc_core.vhd` (nepromenjeni).
- Produces: brojke resursa i timinga za `ncc_core` na `xc7z010clg400-1`, za ažuriranje
  Koraka 5 u PDF dokumentaciji.

Korak 5 je meren na `xc7z010clg225-2`. Kapacitet je identičan (LUT 17600 / FF 35200 /
DSP 80 / BRAM 60 — provereno kroz Vivado), pa **procenti resursa stoje**; timing ne, jer
je `-2` brži od `-1`. Bez ovoga bi Korak 5 i Korak 8 bili na različitim delovima, što je
prvo što profesor primeti.

- [ ] **Step 1: Napisati** `src/vhdl/script/run_synth_core.tcl`

```tcl
# Samostalna sinteza golog ncc_core -- par metrika za Korak 5 na novom partu.
# Pokretanje (iz korena repoa):
#   vivado.bat -mode batch -source src/vhdl/script/run_synth_core.tcl
set REPO [file normalize [file join [file dirname [info script]] ../../..]]
set PART xc7z010clg400-1

read_vhdl -vhdl2008 [list \
    [file join $REPO src/vhdl/ncc_pkg.vhd] \
    [file join $REPO src/vhdl/ncc_core.vhd] ]
synth_design -top ncc_core -part $PART

# Clock constraint je OBAVEZAN -- bez njega report_timing_summary daje WNS = inf.
create_clock -period 10.000 -name clk [get_ports clk]

puts "### ==== RESURSI (ncc_core @ $PART) ===="
report_utilization -hierarchical_depth 1
puts "### ==== TIMING ===="
report_timing_summary -delay_type max -max_paths 1
report_timing -delay_type max -max_paths 1 -nworst 1 -significant_digits 3
```

- [ ] **Step 2: Pokreni i zabeleži brojke**

```bash
cd "/c/Users/pc/Desktop/PSDS"
/c/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -nolog -notrace \
  -source src/vhdl/script/run_synth_core.tcl 2>&1 | tee /tmp/synth_core_clg400.txt \
  | grep -E "^###|Slice LUTs|Slice Registers|DSP|Block RAM Tile|LUT as Memory|WNS|WHS|ERROR"
```

Expected: sinteza prođe; LUT / FF / DSP / BRAM **isti kao Korak 5** (1526 / 554 / 9 / 9),
`LUT as Memory = 0`, a **WNS niži** od +1.179 ns (očekivano ~+0.1 do +0.3 ns na `-1`).

Ako je **WNS negativan**: primeniti polugu iz `IDEJE.md` — preseći kritičnu putanju
`sum_num_reg[16] → div_ncc/work_reg[78]` registrom (+1 takt po prozoru od ~485,
propusnost praktično nepromenjena). To je izmena `ncc_core.vhd` → **oba testbencha iz
Koraka 4 moraju ponovo proći** (`ncc_core_tb`, `ncc_core_real_tb`) pre nastavka.

- [ ] **Step 3: Ažurirati Korak 5 u dokumentaciji**

U `02 Dokumentacija/(C) Korak 5 - Analiza sinteze.md` i u `.html` izvoru PDF-a dodati
kolonu/odeljak sa brojkama za `clg400-1` i rečenicu: „Korak 5 je prvobitno meren na
`xc7z010clg225-2` (part iz ESL dokumentacije). Ciljni deo je `xc7z010clg400-1` (svaka
Digilent Zynq-7010 ploča) — isti čip, identičan kapacitet, ali speed grade `-1`.
Resursi su nepromenjeni; timing je re-izmeren." Regenerisati PDF (headless Edge, videti
`(C) Sljedeća sesija.md`).

- [ ] **Step 4: Commit** (na odobrenje)

```bash
git add src/vhdl/script/run_synth_core.tcl \
        "PSDS Vault/Projects/NCC_Akcelerator/02 Dokumentacija/"
git commit -m "docs(korak7): re-sinteza ncc_core na clg400-1, Korak 5 brojke uskladjene"
```

---

### Task 10: Ažuriranje statusa u vault-u

**Files:**
- Modify: `PSDS Vault/Projects/NCC_Akcelerator/CLAUDE.md`
- Modify: `PSDS Vault/Projects/NCC_Akcelerator/01 Razvoj/(C) Plan implementacije (10 koraka).md`
- Modify: `PSDS Vault/Projects/NCC_Akcelerator/(C) Sljedeća sesija.md`
- Modify: `PSDS Vault/Projects/NCC_Akcelerator/BUGS.md`

- [ ] **Step 1: `BUGS.md`** — upisati nađeni i popravljeni bug

```markdown
## S01 (AXI-Full) burst čitanje — off-by-one  [POPRAVLJENO, Korak 7 Task 2]

`ncc_accel_slave_full_v1_0_S01_AXI.vhd` je vraćao **prethodnu** reč na svakom beat-u
posle prvog (7 od 8 pogrešno na `arlen=7`); poslednja reč burst-a se nikad nije pojavila.
Write burst-ovi su radili (8/8).

**Uzrok:** generisani Xilinx šablon čita interni primer-RAM kombinaciono. U Koraku 6 je
zamenjen registrovanim `dp_bram` čitanjem (1 takt), a poravnanje je popravljeno samo za
prvi beat (adresa na ciklusu prihvata). Za beat-ove ≥1 se koristio `axi_araddr`, koji se
inkrementira u istom taktu kad se beat troši → podatak takt prekasno.

**Zašto nije uhvaćeno u Koraku 6:** `ncc_accel_tb` koristi `awlen=0`/`arlen=0` (single
beat) — burst put nije bio pokriven. `Xil_In32`/`Xil_Out32` su takođe single-beat pa CPU
nikad ne pogodi bug; svaki DMA ga pogodi.

**Popravka:** look-ahead adresa — u taktu kad se beat *k* troši izdaje se adresa *k+1*.
**Test:** `src/vhdl/tb/ncc_accel_burst_tb.vhd` (`arlen`/`awlen` = 7).
**Pouka:** kad se kombinaciono čitanje u generisanom AXI šablonu zameni registrovanim,
mora se popraviti **ceo** burst, ne samo prvi beat — i testirati sa `len > 0`.
```

- [ ] **Step 2: `CLAUDE.md`** — Korak 7 na `[x]`, part i board files ažurirani

Izmene:
- „Trenutni status" → `Koraci 1-7 ZAVRŠENI` (65 bodova), sledeće Korak 8.
- U „Stack / okruženje": part `xc7z010clg400-1` (bilo `clg225-2`), sa objašnjenjem iz
  dizajna §7.1; board files instalirani; `board_part digilentinc.com:zybo-z7-10:part0:1.2`
  kao **nepotvrđena** pretpostavka.
- Dodati odeljak „Korak 7 — Integracija u block design (ZAVRŠENO)": topologija, adresna
  mapa, i napomena da je usput popravljen S01 burst bug.
- U registarskoj mapi zameniti ESL PL adrese stvarnom mapom iz dizajna §3.2.

- [ ] **Step 3: `(C) Plan implementacije (10 koraka).md`** — Korak 7 `[x]` + rezime

- [ ] **Step 4: `(C) Sljedeća sesija.md`** — novi zapis na vrh

Sadržaj: Korak 7 završen; odluke (CDMA u oba smera, fiksna mapa, TCL); nađen i popravljen
S01 burst bug; part prebačen na `clg400-1`; board files instalirani; **otvoreno za Korak 8:**
(a) potvrditi koji je Zybo (VGA → originalni, 2× HDMI → Z7-10), (b) rekalibracija `K_CYC`
u SystemC modelu za Korak 8e (izlazimo ~1,5 s vs referenca 3,667 s), (c) BRAM ~65% se meri
prvi put, poluge u `IDEJE.md`.

- [ ] **Step 5: Commit** (na odobrenje)

```bash
git add "PSDS Vault/"
git commit -m "docs(korak7): status Koraka 7 u vault-u + BUGS zapis o S01 burst bugu"
```

---

## Self-Review (pisac plana)

**Pokrivenost dizajna:**
- §2.1 nalaz → Task 1 (test koji ga dokazuje); §2.2 popravka → Task 2; §2.3 mrtav kod →
  Task 3; §2.4 pakovanje → Task 2 „Produces" (nema izmene portova); §2.5 duplikat → Task 4.
- §3.1 topologija → Task 5 (PS+reset), 6 (IP+SmartConnect), 7 (CDMA); §3.2 adresna mapa →
  Task 6 + 7; §3.3 regioni S01 → nasleđeno iz Koraka 6, ne dira se.
- §4 tok podataka → definiše Korak 9; ovde je fiksiran samo interfejs (adresna mapa) ✓.
  §4.1 dva softverska pravila → prenesena u Task 10 Step 4 (za Korak 9), nisu HW zadatak.
- §5 kriterij završenosti → Task 2/3/4 (TB-ovi 1 i 2), Task 7 (validate), Task 8 (wrapper) ✓.
- §7.1 timing na `-1` → Task 9 (uz polugu ako WNS padne u minus); §7.2 BRAM → meri se u
  Koraku 8, ovde samo zabeleženo; §7.3 board_part → Task 5 (komentar u skripti) + Task 10;
  §7.4 Korak 8e → Task 10 Step 4 (otvoreno za Korak 8) ✓.
- §8 okruženje → Global Constraints ✓.

**Placeholderi:** nema TBD/TODO; svaki korak sa kodom nosi ceo kod; sve komande su
konkretne sa očekivanim izlazom. Task 10 Step 2/3 opisuju *sadržaj* izmena dokumentacije
umesto doslovnog teksta — to je namerno (tekst zavisi od stvarnih brojki iz Taska 9), ali
je nabrojano tačno šta se menja.

**Konzistentnost imena** (sva potvrđena kroz Vivado 2026-07-25, ne pretpostavljena):
`ncc0/S00_AXI/S00_AXI_reg`, `ncc0/S01_AXI/S01_AXI_mem`, `axi_cdma_0/S_AXI_LITE/Reg`,
`axi_cdma_0/Data`, `processing_system7_0/Data`,
`processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM`, `FCLK_CLK0`, `FCLK_RESET0_N`,
`M_AXI_GP0_ACLK`, `S_AXI_HP0_ACLK`, `proc_sys_reset_0/peripheral_aresetn`.
`smartconnect_0` ide `NUM_SI 1→2` / `NUM_MI 4→6` između Taska 6 i 7 — Task 7 Step 1
eksplicitno menja tu jednu liniju, ne dodaje drugu.

**Nesigurno (jedina mesta gde plan može pući):** imena `CONFIG.C_*` parametara
`axi_cdma:4.1` (Task 7 Step 2). Zato Step 2 ispisuje pročitane vrednosti a Step 6 nosi
uputstvo za `report_property` ako `set_property` javi grešku.
