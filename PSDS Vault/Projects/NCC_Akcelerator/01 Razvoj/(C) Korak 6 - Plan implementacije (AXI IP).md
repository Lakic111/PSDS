# Korak 6 — Plan implementacije (AXI IP pakovanje)

> **Za izvršioca:** implementira se zadatak-po-zadatak; koraci su čekboksovi (`- [ ]`).
> Dizajn (merodavan): `01 Razvoj/(C) Korak 6 - Dizajn AXI omotača (IP pakovanje).md`.

> **STATUS: ZAVRŠENO (2026-07-24).** Svi zadaci 0–7 urađeni; integracioni TB PASS
> (peak `0x80000000 @ idx 956`); IP spakovan + `.zip` arhiva. Task 8 (git) na
> odobrenje korisnika.

> **⚠️ NAKNADNA IZMENA (Korak 7, 2026-07-25) — putanje u ovom dokumentu su istorijske:**
> `src/vhdl/ip/` **više ne postoji**. Izvori su konsolidovani u
> `src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/` (to je ono što `component.xml` referencira),
> jer su dve kopije istih fajlova bile rizik — popraviti jednu, zaboraviti drugu.
> Tekst zadataka ispod je zadržan kakav je bio (istorijski zapis šta se radilo),
> ali su **`xvhdl` komande ažurirane** na `$IP` putanje da se mogu kopirati.
> Mapiranje: `../ip/dp_bram.vhd` → `$IP/src/dp_bram.vhd`, isto za `mem_subsystem`;
> `../ip/ncc_accel_v1_0*.vhd` → `$IP/hdl/ncc_accel_slave_{lite,full}_v1_0_S0{0,1}_AXI.vhd`
> i `$IP/hdl/ncc_accel.vhd` (wizard je dao drugačija imena od plana).
> Takođe u Koraku 7 je **popravljen bug u `S01_AXI`**: burst čitanje je vraćalo
> prethodnu reč na svakom beat-u posle prvog. Videti `BUGS.md`.

**Cilj:** spakovati `ncc_core` (nepromenjen) u AXI IP `ncc_accel` = AXI-Lite slave
(kontrola) + AXI-Full slave (interne memorije slika/šablon/rezultat), verifikovan
simulacijom pre pakovanja.

**Arhitektura:** slave + interne memorije (matrix-multiply obrazac iz Vežbe 08-09).
Wizard generiše AXI kontrolere; mi ručno pišemo `dp_bram` + `mem_subsystem`,
modifikujemo generisane kontrolere i top wrapper, integracioni testbench je kapija
tačnosti, pa Package IP.

**Tech stack:** VHDL-2008, Vivado 2025.2 (`C:\AMDDesignTools\2025.2\`),
`xvhdl`/`xelab`/`xsim` (komandna linija, Git Bash), part `xc7z010clg225-2`.

## Global Constraints

- **`ncc_core.vhd` i `ncc_pkg.vhd` se NE menjaju.** Ako se ipak dirnu, oba
  testbencha iz Koraka 4 (`ncc_core_tb`, `ncc_core_real_tb`) moraju ponovo proći.
- Ime IP-a: **`ncc_accel`**, verzija **1.0**. Sve generisane entitete zadržava
  wizard sa prefiksom `ncc_accel_v1_0_`.
- Jedan takt (100 MHz), jedan reset. `ncc_core.rst` (active-high) = `not aresetn`.
- Realni podaci za TB: `src/vhdl/tb/seg90.txt` (90×90) i `src/vhdl/tb/crnitop.txt`
  (25×15) — **već postoje** iz Koraka 4. Zlatni rezultat: peak `0x80000000` na
  poziciji (u=32, v=14), tj. index `14*66+32 = 956` u mapi 66×76.
- Ručno pisani fajlovi žive u `src/vhdl/ip/` (git). Generisani (kontroleri, top)
  se uređuju u IP „Edit IP" projektu pa kopiraju u `src/vhdl/ip/` na kraju (Task 8).
- **Commit tek na odobrenje korisnika**; pre prvog commita napraviti granu
  `korak6-axi-ip` (repo je na `main`). Sign-off: `Co-Authored-By: Claude ...`.
- xsim build komanda (šablon, iz Koraka 4):
  ```bash
  export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
  cd "/c/Users/pc/Desktop/PSDS/src/vhdl" && mkdir -p work_ip && cd work_ip
  xvhdl -2008 <fajlovi> && xelab -debug typical <tb_top> -s <sim> && xsim <sim> -runall
  ```

---

### Task 0: Vivado projekat + generisanje AXI skeleta (GUI)

**Files:** kreira IP projekat na disku (van git-a za sad).

**Interfaces:**
- Produces: generisani `ncc_accel_v1_0.vhd`, `ncc_accel_v1_0_S00_AXI.vhd`,
  `ncc_accel_v1_0_S01_AXI.vhd` u IP „Edit IP" projektu.

- [ ] **Korak 1:** Nov Vivado projekat (RTL, part `xc7z010clg225-2`), ime `ncc_accel_prj`.
- [ ] **Korak 1b (KRITIČNO):** `Settings → Project Settings → General → Target language:
      **VHDL**` (i `Simulator language: Mixed`). **Ako je Verilog, AXI wizard generiše
      `.v` fajlove** — a ceo naš dizajn i vežba su VHDL. Postaviti PRE pokretanja wizarda.
- [ ] **Korak 2:** `Tools → Create and Package New IP… → Create a new AXI4 peripheral`.
- [ ] **Korak 3:** Peripheral Details: Name `ncc_accel`, Version `1.0`,
      Display name `ncc_accel_v1.0`, Description „NCC template-matching accelerator".
- [ ] **Korak 4:** Add Interfaces — dva interfejsa:
      - `S00_AXI`: Type **Lite**, Mode **Slave**, Data Width **32**, Number of Registers **16**.
      - `S01_AXI` (zeleni +): Type **Full**, Mode **Slave**, Data Width **32**,
        Memory Size **131072** (128 KB).
- [ ] **Korak 5:** Next → Create Peripheral → izabrati **Edit IP** → Finish.
      Vivado otvara privremeni projekat sa 3 generisana VHDL fajla.
- [ ] **Korak 6 (provera):** U Sources se vide `ncc_accel_v1_0`,
      `..._S00_AXI`, `..._S01_AXI`. Zapisati putanju IP lokacije (Root directory).

---

### Task 1: `dp_bram` — generički true-dual-port RAM

**Files:**
- Create: `src/vhdl/ip/dp_bram.vhd`
- Test: `src/vhdl/tb/dp_bram_tb.vhd`

**Interfaces:**
- Produces: `entity dp_bram generic(DATA_W:integer:=8; ADDR_W:integer:=13)` sa
  portovima `clka,ena,wea,addra,dia,doa, clkb,enb,web,addrb,dib,dob`
  (svi `std_logic`/`std_logic_vector`). Sinhroni čitanje (1-taktno kašnjenje),
  true dual-port (shared variable).

- [ ] **Step 1: Napisati failing test** `src/vhdl/tb/dp_bram_tb.vhd`

```vhdl
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
        -- upiši preko porta A na adresu 3 vrednost 0xAB
        ena<='1'; wea<='1'; addra<=std_logic_vector(to_unsigned(3,AW)); dia<=x"AB";
        wait until rising_edge(clk); wea<='0';
        -- pročitaj preko porta B adresu 3 (1-taktno kašnjenje)
        enb<='1'; addrb<=std_logic_vector(to_unsigned(3,AW));
        wait until rising_edge(clk); wait until rising_edge(clk);
        assert dob = x"AB" report "FAIL: dp_bram B read mismatch" severity failure;
        report "PASS: dp_bram" severity note;
        wait;
    end process;
end architecture;
```

- [ ] **Step 2: Pokreni — mora da PADNE** (entitet ne postoji)

```bash
export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
cd "/c/Users/pc/Desktop/PSDS/src/vhdl" && mkdir -p work_ip && cd work_ip
xvhdl -2008 ../tb/dp_bram_tb.vhd
```
Expected: FAIL — `xvhdl` javlja da `work.dp_bram` nije pronađen.

- [ ] **Step 3: Napisati** `src/vhdl/ip/dp_bram.vhd`

```vhdl
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
```

- [ ] **Step 4: Pokreni — mora da PROĐE**

```bash
IP="/c/Users/pc/Desktop/PSDS/src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0"
xvhdl -2008 "$IP/src/dp_bram.vhd" ../tb/dp_bram_tb.vhd
xelab -debug typical dp_bram_tb -s dp_bram_sim && xsim dp_bram_sim -runall
```
Expected: `PASS: dp_bram`.

- [ ] **Step 5: Commit** (na odobrenje) — `git add src/vhdl/ip/dp_bram.vhd src/vhdl/tb/dp_bram_tb.vhd`.

---

### Task 2: `mem_subsystem` — 3 memorije + adresni dekoder

**Files:**
- Create: `src/vhdl/ip/mem_subsystem.vhd`
- Test: `src/vhdl/tb/mem_subsystem_tb.vhd`

**Interfaces:**
- Consumes: `dp_bram` (Task 1).
- Produces: `entity mem_subsystem` sa portovima (S01 strana + ncc_core strana):
  ```
  clk : in std_logic;
  -- S01 strana (port A memorija)
  mem_addr_a  : in  std_logic_vector(16 downto 0);   -- byte adresa u S01 prostoru
  mem_wdata_a : in  std_logic_vector(31 downto 0);
  mem_we_a    : in  std_logic;
  mem_rdata_a : out std_logic_vector(31 downto 0);   -- region-muxovano, 1 takt kašnjenja
  -- ncc_core strana (port B)
  img_addr_b   : in  std_logic_vector(12 downto 0);
  img_dout_b   : out std_logic_vector(7 downto 0);
  templ_addr_b : in  std_logic_vector(9 downto 0);
  templ_dout_b : out std_logic_vector(7 downto 0);
  result_addr_b: in  std_logic_vector(12 downto 0);
  result_din_b : in  std_logic_vector(31 downto 0);
  result_we_b  : in  std_logic
  ```
  Region = `mem_addr_a(16 downto 15)`: `00`=slika, `01`=šablon, `10`=rezultat.
  Word index = `mem_addr_a(14 downto 2)`.

- [ ] **Step 1: Napisati failing test** `src/vhdl/tb/mem_subsystem_tb.vhd`

```vhdl
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
    -- pomoć: byte adresa = region(2b) & word(13b) & "00"
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
        -- 1) S01 upiše piksel 0x7E u sliku[5], pa ncc_core (port B) čita sliku[5]
        mem_addr_a<=ba(0,5); mem_wdata_a<=x"0000007E"; mem_we_a<='1';
        wait until rising_edge(clk); mem_we_a<='0';
        img_addr_b<=std_logic_vector(to_unsigned(5,13));
        wait until rising_edge(clk); wait until rising_edge(clk);
        assert img_dout_b=x"7E" report "FAIL: img port B" severity failure;
        -- 2) ncc_core upiše rezultat 0x80000000 u rez[9], pa S01 čita rez[9]
        result_addr_b<=std_logic_vector(to_unsigned(9,13));
        result_din_b<=x"80000000"; result_we_b<='1';
        wait until rising_edge(clk); result_we_b<='0';
        mem_addr_a<=ba(2,9);   -- region rezultat
        wait until rising_edge(clk); wait until rising_edge(clk);
        assert mem_rdata_a=x"80000000" report "FAIL: result readback" severity failure;
        report "PASS: mem_subsystem" severity note; wait;
    end process;
end architecture;
```

- [ ] **Step 2: Pokreni — mora da PADNE** (entitet ne postoji)

```bash
cd "/c/Users/pc/Desktop/PSDS/src/vhdl/work_ip"
IP="/c/Users/pc/Desktop/PSDS/src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0"
xvhdl -2008 "$IP/src/dp_bram.vhd" ../tb/mem_subsystem_tb.vhd
```
Expected: FAIL — `work.mem_subsystem` nije pronađen.

- [ ] **Step 3: Napisati** `src/vhdl/ip/mem_subsystem.vhd`

```vhdl
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity mem_subsystem is
    port (
        clk : in std_logic;
        mem_addr_a  : in  std_logic_vector(16 downto 0);
        mem_wdata_a : in  std_logic_vector(31 downto 0);
        mem_we_a    : in  std_logic;
        mem_rdata_a : out std_logic_vector(31 downto 0);
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
    -- register regiona za poravnanje sa 1-taktnim čitanjem dp_bram-a
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
```

- [ ] **Step 4: Pokreni — mora da PROĐE**

```bash
IP="/c/Users/pc/Desktop/PSDS/src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0"
xvhdl -2008 "$IP/src/dp_bram.vhd" "$IP/src/mem_subsystem.vhd" ../tb/mem_subsystem_tb.vhd
xelab -debug typical mem_subsystem_tb -s ms_sim && xsim ms_sim -runall
```
Expected: `PASS: mem_subsystem`.

- [ ] **Step 5: Commit** (na odobrenje).

---

### Task 3: Modifikacija generisanog `ncc_accel_v1_0_S00_AXI` (AXI-Lite kontrola)

**Files:**
- Modify: `ncc_accel_v1_0_S00_AXI.vhd` (u IP projektu; kasnije kopija u `src/vhdl/ip/`).

**Interfaces:**
- Produces (novi portovi entiteta, „-- Users to add ports here"):
  ```
  img_w, img_h, tmp_w, tmp_h : out std_logic_vector(7 downto 0);
  start_pulse : out std_logic;
  core_busy   : in  std_logic;
  core_done   : in  std_logic;
  ```

Generisani AXI-Lite već ima `slv_reg0..15`, `slv_reg_wren`, `loc_addr` i read mux
(`case loc_addr`). Modifikacije (mesta kao u Vežbi 08-09, str. 264–269):

- [ ] **Step 1:** Dodati 4 izlaza za dimenzije (žice iz drži-registara):
  ```vhdl
  img_w <= slv_reg0(7 downto 0);
  img_h <= slv_reg1(7 downto 0);
  tmp_w <= slv_reg2(7 downto 0);
  tmp_h <= slv_reg3(7 downto 0);
  ```

- [ ] **Step 2:** `start_pulse` iz upisa u CTRL (reg index 12 = 0x30, bit0=1).
  U procesu koji generiše `slv_reg_wren`/upis, dodati registrovani signal:
  ```vhdl
  -- default svaki takt:
  start_pulse <= '0';
  if slv_reg_wren = '1' and loc_addr = b"01100" and S_AXI_WDATA(0) = '1' then
      start_pulse <= '1';   -- tačno 1 takt
  end if;
  ```
  (`loc_addr` je word-index; 0x30/4 = 12 = `b"01100"`, širina zavisi od
  `OPT_MEM_ADDR_BITS` — poravnati.)

- [ ] **Step 3:** `done_sticky` (ESL `hw_status`):
  ```vhdl
  signal done_sticky : std_logic := '0';
  ...
  process(S_AXI_ACLK) begin
      if rising_edge(S_AXI_ACLK) then
          if S_AXI_ARESETN = '0' or start_pulse = '1' then done_sticky <= '0';
          elsif core_done = '1' then done_sticky <= '1';
          end if;
      end if;
  end process;
  ```

- [ ] **Step 4:** STATUS read (reg index 13 = 0x34) vraća status umesto `slv_reg13`.
  U read mux `case loc_addr`, granu za `b"01101"` zameniti:
  ```vhdl
  when b"01101" =>
      reg_data_out <= (0 => done_sticky, 1 => core_busy, others => '0');
  ```

- [ ] **Step 5 (verifikacija):** odloženo — S00 se proverava zajedno u Task 6
  (integracioni testbench). Sintaksa: `xvhdl -2008` prolazi bez greške.
  Commit posle Task 5.

---

### Task 4: Modifikacija generisanog `ncc_accel_v1_0_S01_AXI` (AXI-Full memorije)

**Files:**
- Modify: `ncc_accel_v1_0_S01_AXI.vhd`.

**Interfaces:**
- Consumes: `mem_subsystem` (Task 2).
- Produces (novi portovi entiteta):
  ```
  mem_addr_o  : out std_logic_vector(16 downto 0);
  mem_wdata_o : out std_logic_vector(31 downto 0);
  mem_we_o    : out std_logic;
  mem_rdata_i : in  std_logic_vector(31 downto 0);
  ```

Generisani AXI-Full ima burst adresne brojače (`axi_awaddr`, `axi_araddr`,
`awv_awr_flag`, `arv_arr_flag`). Modifikacije (Vežba 08-09, str. 276–277):

> **NAPOMENA (wizard cap):** „Memory Size" u wizardu staje na **1024 B** u Vivado
> 2025.2, pa generisani `C_S01_AXI_ADDR_WIDTH` bude mali (~10 bita). **Postaviti ga
> ručno na 17** (generic default u `..._S01_AXI.vhd` I u top-u `ncc_accel_v1_0.vhd`
> gde se prosleđuje), da adresni prostor pokrije 128 KB (naša 3 regiona). Sve
> ostalo u burst logici parametrizovano je na `C_S_AXI_ADDR_WIDTH`, pa se skalira.

- [ ] **Step 0:** U entitetu `..._S01_AXI` postaviti `C_S_AXI_ADDR_WIDTH : integer := 17;`
  (i u top-u `C_S01_AXI_ADDR_WIDTH := 17` u generic map instancе). `axi_araddr`/
  `axi_awaddr` postaju 17-bitni → `mem_addr_o <= axi_araddr` direktno (17 bita).

- [ ] **Step 1:** U „-- Add user logic here" (posle read/write FSM-a):
  ```vhdl
  mem_we_o    <= axi_wready and S_AXI_WVALID;
  mem_wdata_o <= S_AXI_WDATA;
  mem_addr_o  <= axi_araddr(C_S_AXI_ADDR_WIDTH-1 downto 0) when arv_arr_flag = '1'
            else axi_awaddr(C_S_AXI_ADDR_WIDTH-1 downto 0) when awv_awr_flag = '1'
            else (others => '0');
  ```
  (Ako je `C_S_AXI_ADDR_WIDTH` > 17, uzeti donjih 17 bita; ako je 17, direktno.)

- [ ] **Step 2:** Read data iz memorije umesto internog mux-a. U procesu koji drži
  `axi_rdata` (izlaz `S_AXI_RDATA <= axi_rdata`), zameniti dodelu podataka:
  ```vhdl
  -- umesto internog "user logic memory" mux-a:
  axi_rdata <= mem_rdata_i;
  ```
  Napomena: `mem_rdata_i` kasni 1 takt za `mem_addr_o` (dp_bram registrovano
  čitanje). Generisani read FSM već sekvencira `araddr` pa uzorkuje — proveriti u
  Task 6 da se `rvalid`/`rdata` poravnavaju (ako fali 1 takt, dodati 1 registar
  latencije na `mem_rdata_i` ili pomeriti `rvalid`).

- [ ] **Step 3 (verifikacija):** odloženo — proverava se u Task 6. `xvhdl -2008`
  prolazi bez greške.

---

### Task 5: Modifikacija generisanog top wrapper-a `ncc_accel_v1_0`

**Files:**
- Modify: `ncc_accel_v1_0.vhd`.

**Interfaces:**
- Consumes: S00 (Task 3), S01 (Task 4), `mem_subsystem` (Task 2), `ncc_core`.

Generisani top instancira S00 i S01 i provodi AXI portove. Dodati: instancu
`mem_subsystem` + `ncc_core`, i povezati sve.

- [ ] **Step 1:** U deklaracijama arhitekture dodati signale:
  ```vhdl
  signal rst_s : std_logic;
  signal img_w_s, img_h_s, tmp_w_s, tmp_h_s : std_logic_vector(7 downto 0);
  signal start_s, busy_s, done_s : std_logic;
  signal mem_addr_s : std_logic_vector(16 downto 0);
  signal mem_wdata_s, mem_rdata_s : std_logic_vector(31 downto 0);
  signal mem_we_s : std_logic;
  signal img_addr_s, res_addr_s : std_logic_vector(12 downto 0);
  signal img_dout_s : std_logic_vector(7 downto 0);
  signal templ_addr_s : std_logic_vector(9 downto 0);
  signal templ_dout_s : std_logic_vector(7 downto 0);
  signal res_din_s : std_logic_vector(31 downto 0);
  signal res_we_s : std_logic;
  ```

- [ ] **Step 2:** Prošriti port map generisanih instanci (`..._S00_AXI_inst`,
  `..._S01_AXI_inst`) novim „user" portovima:
  ```vhdl
  -- u S00 inst:
  img_w => img_w_s, img_h => img_h_s, tmp_w => tmp_w_s, tmp_h => tmp_h_s,
  start_pulse => start_s, core_busy => busy_s, core_done => done_s,
  -- u S01 inst:
  mem_addr_o => mem_addr_s, mem_wdata_o => mem_wdata_s,
  mem_we_o => mem_we_s, mem_rdata_i => mem_rdata_s,
  ```

- [ ] **Step 3:** Dodati instance `mem_subsystem`, `ncc_core` i reset:
  ```vhdl
  rst_s <= not s00_axi_aresetn;

  ms_inst: entity work.mem_subsystem port map(
      clk => s00_axi_aclk,
      mem_addr_a => mem_addr_s, mem_wdata_a => mem_wdata_s,
      mem_we_a => mem_we_s, mem_rdata_a => mem_rdata_s,
      img_addr_b => img_addr_s, img_dout_b => img_dout_s,
      templ_addr_b => templ_addr_s, templ_dout_b => templ_dout_s,
      result_addr_b => res_addr_s, result_din_b => res_din_s, result_we_b => res_we_s);

  core_inst: entity work.ncc_core port map(
      clk => s00_axi_aclk, rst => rst_s, start => start_s,
      busy => busy_s, done => done_s,
      img_w => unsigned(img_w_s), img_h => unsigned(img_h_s),
      tmp_w => unsigned(tmp_w_s), tmp_h => unsigned(tmp_h_s),
      img_addr_o => open,  -- vidi Step 4
      img_data_i => unsigned(img_dout_s),
      templ_addr_o => open,
      templ_data_i => unsigned(templ_dout_s),
      result_addr_o => open,
      result_data_o => open,
      result_wr_o => res_we_s);
  ```
  **Napomena:** `ncc_core` adresni izlazi su `integer range`. Pošto se ne mogu
  direktno vezati na `std_logic_vector`, koristiti međusignale tipa integer i
  konverziju (Step 4) — NE koristiti `open` za adrese.

- [ ] **Step 4:** Konverzija tipova (integer ↔ slv) za adresne/podatkovne portove.
  Deklarisati integer međusignale i konvertovati:
  ```vhdl
  signal img_addr_i, res_addr_i : integer range 0 to 8099;
  signal templ_addr_i : integer range 0 to 899;
  ...
  -- u core_inst port map:
  img_addr_o => img_addr_i, templ_addr_o => templ_addr_i,
  result_addr_o => res_addr_i, result_data_o => res_data_u,  -- res_data_u : result_t
  -- konverzije van instance:
  img_addr_s   <= std_logic_vector(to_unsigned(img_addr_i, 13));
  templ_addr_s <= std_logic_vector(to_unsigned(templ_addr_i, 10));
  res_addr_s   <= std_logic_vector(to_unsigned(res_addr_i, 13));
  res_din_s    <= std_logic_vector(res_data_u);
  ```
  (`res_data_u : result_t` deklarisati u signalima.)

- [ ] **Step 5 (kompilacija):** `xvhdl -2008` nad svim fajlovima prolazi bez greške.
  Kopirati generisane+modifikovane `S00/S01/top` u `src/vhdl/ip/`.

---

### Task 6: Integracioni testbench `ncc_accel_tb` (KAPIJA TAČNOSTI)

**Files:**
- Create: `src/vhdl/tb/ncc_accel_tb.vhd`
- Koristi: `src/vhdl/tb/seg90.txt`, `src/vhdl/tb/crnitop.txt` (postoje).

**Interfaces:**
- Consumes: top `ncc_accel_v1_0` (S00 + S01 AXI portovi), `seg90.txt`, `crnitop.txt`.

TB glumi CPU/DMA: pobuđuje `s00_axi_*` i `s01_axi_*`. Procedure: `lite_write`,
`lite_read`, `full_write` (INCR burst), `full_read` (INCR burst).

- [ ] **Step 1: Napisati** `src/vhdl/tb/ncc_accel_tb.vhd` (skelet + sekvenca):

```vhdl
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use std.textio.all;
entity ncc_accel_tb is end entity;
architecture beh of ncc_accel_tb is
    constant IMG_W : integer := 90; constant IMG_H : integer := 90;
    constant TMP_W : integer := 25; constant TMP_H : integer := 15;
    constant RES_W : integer := IMG_W-TMP_W+1;  -- 66
    constant RES_H : integer := IMG_H-TMP_H+1;  -- 76
    -- offset regiona (byte): slika 0x00000, šablon 0x08000, rezultat 0x10000
    constant OFF_IMG : integer := 16#00000#;
    constant OFF_TMP : integer := 16#08000#;
    constant OFF_RES : integer := 16#10000#;
    -- registri
    constant R_IMG_W:integer:=16#00#; constant R_IMG_H:integer:=16#04#;
    constant R_TMP_W:integer:=16#08#; constant R_TMP_H:integer:=16#0C#;
    constant R_CTRL:integer:=16#30#;  constant R_STATUS:integer:=16#34#;

    signal clk : std_logic := '0';
    signal aresetn : std_logic := '0';
    -- ... svi s00_axi_* i s01_axi_* signali (kao u portu top-a) ...
    -- (deklarisati sve prema entitetu ncc_accel_v1_0)
begin
    clk <= not clk after 5 ns;
    dut: entity work.ncc_accel_v1_0 port map( /* svi AXI portovi na signale */ );

    stim: process
        -- učitaj sliku/šablon iz fajla u nizove
        variable line_v : line; variable px : integer;
        type img_arr is array(0 to IMG_W*IMG_H-1) of integer;
        type tmp_arr is array(0 to TMP_W*TMP_H-1) of integer;
        variable seg : img_arr; variable tmpl : tmp_arr;
        file fseg : text; file ftmp : text;
        variable peak : unsigned(31 downto 0) := (others=>'0');
        variable peak_idx : integer := -1;
        variable rd : std_logic_vector(31 downto 0);
    begin
        -- reset 10 taktova
        aresetn <= '0'; for i in 0 to 9 loop wait until rising_edge(clk); end loop;
        aresetn <= '1'; wait until rising_edge(clk);

        -- učitaj podatke
        file_open(fseg, "../tb/seg90.txt", read_mode);
        for i in 0 to IMG_W*IMG_H-1 loop
            readline(fseg,line_v); read(line_v,px); seg(i):=px;
        end loop; file_close(fseg);
        file_open(ftmp, "../tb/crnitop.txt", read_mode);
        for i in 0 to TMP_W*TMP_H-1 loop
            readline(ftmp,line_v); read(line_v,px); tmpl(i):=px;
        end loop; file_close(ftmp);

        -- 1) dimenzije preko AXI-Lite
        lite_write(R_IMG_W, IMG_W); lite_write(R_IMG_H, IMG_H);
        lite_write(R_TMP_W, TMP_W); lite_write(R_TMP_H, TMP_H);

        -- 2) slika i šablon preko AXI-Full (jedan piksel/reč)
        for i in 0 to IMG_W*IMG_H-1 loop full_write(OFF_IMG + i*4, seg(i)); end loop;
        for i in 0 to TMP_W*TMP_H-1 loop full_write(OFF_TMP + i*4, tmpl(i)); end loop;

        -- 3) start
        lite_write(R_CTRL, 1); lite_write(R_CTRL, 0);

        -- 4) poll STATUS bit0
        loop
            lite_read(R_STATUS, rd);
            exit when rd(0) = '1';
            wait for 1000 ns;
        end loop;

        -- 5) čitaj rezultate, nađi peak
        for i in 0 to RES_W*RES_H-1 loop
            full_read(OFF_RES + i*4, rd);
            if unsigned(rd) > peak then peak := unsigned(rd); peak_idx := i; end if;
        end loop;

        -- 6) provera zlatne vrednosti
        assert peak = x"80000000"
            report "FAIL: peak != 0x80000000" severity failure;
        assert peak_idx = 14*RES_W + 32
            report "FAIL: peak na pogrešnoj poziciji" severity failure;
        report "PASS: ncc_accel golden peak 0x80000000 @ (32,14)" severity note;
        wait;
    end process;
end architecture;
```

- [ ] **Step 2: Dopuniti BFM procedure** (`lite_write`, `lite_read`, `full_write`,
  `full_read`) po talasnim oblicima iz Vežbe (str. 241–242 Lite, 287–293 Full).
  Ključni handshake: Lite upis = `awaddr+awvalid` i `wdata+wvalid+wstrb="1111"`
  istovremeno → čekaj `awready`/`wready` → `bvalid` → spusti. Full = INCR burst,
  ali za jednostavnost TB-a koristiti **burst dužine 1** (`awlen=0`) po pristupu
  (korektno, sporije — dovoljno za verifikaciju).

- [ ] **Step 3: Pokreni — mora da PADNE prvo** (top još nekonzistentan / procedure prazne)

```bash
cd "/c/Users/pc/Desktop/PSDS/src/vhdl/work_ip"
IP="/c/Users/pc/Desktop/PSDS/src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0"
xvhdl -2008 "$IP/src/ncc_pkg.vhd" "$IP/src/ncc_core.vhd" "$IP/src/dp_bram.vhd" \
  "$IP/src/mem_subsystem.vhd" \
  "$IP/hdl/ncc_accel_slave_lite_v1_0_S00_AXI.vhd" \
  "$IP/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd" \
  "$IP/hdl/ncc_accel.vhd" ../tb/ncc_accel_tb.vhd
xelab -debug typical ncc_accel_tb -s accel_sim && xsim accel_sim -runall
```
Expected (prvi prolaz): FAIL/assert — dijagnostikovati (AXI handshake, 1-taktna
latencija čitanja, region dekoder). Ovo je debug faza (systematic-debugging).

- [ ] **Step 4: Debug do GREEN.** Poravnati AXI handshake i read latenciju dok se
  ne dobije `PASS: ncc_accel golden peak 0x80000000 @ (32,14)`. Uporediti latenciju
  `busy` taktova sa Korakom 4 (~2.451.212) radi provere da jezgro radi identično.

- [ ] **Step 5: Commit** (na odobrenje) — svi `src/vhdl/ip/*` + `ncc_accel_tb.vhd`.

---

### Task 7: Pakovanje IP-a (Package IP, GUI)

**Files:** IP „Edit IP" projekat (Package IP kartica).

- [ ] **Step 1:** U IP projekat dodati sve sorse (`Add Sources`): `ncc_pkg`,
  `ncc_core`, `dp_bram`, `mem_subsystem` (+ modifikovani S00/S01/top su već tu).
- [ ] **Step 2:** Package IP → **Identification**: Vendor, Library `user`,
  Categories `AXI_Peripheral` + (npr. `Image_Processing`).
- [ ] **Step 3: Compatibility** → familija **Zynq**.
- [ ] **Step 4: File Groups** → **„Merge changes from File Groups Wizard"**
  (uvlači ručno dodate fajlove u `VHDL Synthesis`/`Simulation`).
- [ ] **Step 4b: Addressing and Memory** → opseg S01 postaviti na **128 KB**
  (jer je wizard u Task 0 dozvolio samo 1024 B; `C_S01_AXI_ADDR_WIDTH=17` iz Task 4
  mora se odraziti i na deklarisani adresni opseg IP-a).
- [ ] **Step 5: Customization Parameters** → AXI parametri ostaju Hidden
  (Merge changes ako fali).
- [ ] **Step 6: Review and Package** → uključiti **„Create archive of IP"**
  (edit packaging settings → Project Settings → IP → Packager) → **Package IP**.
- [ ] **Step 7 (provera):** `.zip` postoji; iz `IP Catalog` instancirati `ncc_accel`
  u praznom test projektu → `Customize IP` → `Generate` prolazi bez greške.

---

### Task 8: Sinhronizacija sa git-om + status

**Files:**
- Modify (na pitanje): `CLAUDE.md`, plan/sesija beleške (status Koraka 6).

- [ ] **Step 1:** Kopirati finalne `src/vhdl/ip/*.vhd` (uklj. modifikovane generisane)
  u git repo ako već nisu, + `.zip` arhivu IP-a u `06 Prilozi/` (opciono).
- [ ] **Step 2:** Grana `korak6-axi-ip`, commit (na odobrenje korisnika).
- [ ] **Step 3 (na pitanje):** ažurirati status Koraka 6 u `CLAUDE.md`,
  `(C) Plan implementacije (10 koraka).md`, `(C) Sljedeća sesija.md`.

---

## Self-Review (pisac plana)

- **Pokrivenost dizajna:** §2 struktura → Task 0/5; §3 Lite → Task 3; §4 Full →
  Task 4; §5 mem_subsystem → Task 2 (+ dp_bram Task 1); §6 TB → Task 6;
  §7 pakovanje → Task 7; §8 resursi → implicitno (sinteza posle Koraka 6). ✓
- **Placeholderi:** procedure u Task 6 Step 2 su namerno opisane preko izvora
  (Vežba str. 241/287) jer je pun BFM kod dugačak; handshake pravila su data
  eksplicitno. Ostali kod je kompletan.
- **Konzistentnost tipova:** `mem_addr_a(16:0)`, region `(16:15)`, word `(14:2)`,
  `img_addr_b(12:0)`, `templ_addr_b(9:0)` — isto u Task 2, 4, 5. Offseti regiona
  (0x00000/0x08000/0x10000) isti u dizajnu §4 i Task 6. ✓
- **Rizici (za systematic-debugging u Task 6):** (a) 1-taktna latencija
  `mem_rdata_i` vs AXI `rvalid`; (b) `loc_addr` širina za CTRL/STATUS dekod;
  (c) integer↔slv konverzije na `ncc_core` adresama.
