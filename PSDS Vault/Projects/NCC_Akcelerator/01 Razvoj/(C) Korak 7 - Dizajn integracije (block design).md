# Korak 7 — Dizajn integracije IP-a u block design

> **Status:** DIZAJN ODOBREN (2026-07-25), implementacija nije počela.
> **Bodovi:** 5 (pravilnik: „Povezivanje IP jezgra sa okolnim komponentama u blok
> integrator (Zynq PS, Block memory generator, BRAM controller, DMA …)").
> **Ulaz:** IP `ncc_accel` iz Koraka 6 + ESL referenca (`common.hpp`, `tb.cpp`, `ncc.cpp`).
> **Izlaz:** validiran block design `ncc_system` + HDL wrapper, izgrađen reproducibilnom
> TCL skriptom `src/vhdl/script/create_bd.tcl`.
> **Napomena:** Vežba 08-09 pokriva SAMO pakovanje IP-a (Korak 6); ovaj korak je građen
> po standardnom Zynq toku, bez vežbe kao izvora.

---

## 0. Odluke ove sesije (fiksirane, ne re-litigirati)

| # | Odluka | Obrazloženje |
|---|---|---|
| 1 | **AXI CDMA u oba smera** (punjenje i čitanje rezultata) | Jedini DMA koji se veže na *slave* IP bez izmene interfejsa je mem-na-mem (CDMA). Standardni AXI DMA je MM↔Stream i zahtevao bi novi `S_AXIS` u IP-u. |
| 2 | **Popraviti read-burst u S01 pre BD-a** | Nađen stvarni defekt (§2). Bez popravke CDMA čitanje vraća pogrešne podatke. |
| 3 | **Fiksna adresna mapa po ESL `common.hpp`** | Kontrolne baze identične ESL-u → dokumentacija i Korak 9 kod nasleđuju konstante; mapa se ne menja pri rekonstrukciji BD-a (bitno za Korak 10). |
| 4 | **Part `xc7z010clg400-1`** (bilo `clg225-2`) | Svaka Digilent Zynq-7010 ploča je `clg400-1`; `clg225-2` iz ESL dokumentacije je bio Vitis HLS default, ne stvarna ploča (§7). |
| 5 | **`board_part digilentinc.com:zybo-z7-10:part0:1.2`** | NEPOTVRĐENA pretpostavka — korisnik nije imao ploču pred sobom. Part je isti za oba Zybo varijanteta, samo PS preset se razlikuje; promena je jedna linija. |
| 6 | **TCL skripta, batch, bez GUI-a** | Temelj za Korak 10 (10 bodova); reproducibilno; fiksna mapa ostaje fiksna. |
| 7 | **Bez prekida — polling** | `STATUS` polling odgovara ESL `hw_status` semantici, a `XAxiCdma_IsBusy` je dovoljan. Izbegava GIC inicijalizaciju u Koraku 9. |

Odbačeno: **AXI DMA + AXI-Stream slave u IP-u** (najbrže punjenje, ali menja i iznova
pakuje verifikovani IP iz Koraka 6 — ugrožava 10 osvojenih bodova za ~1% vremena);
**pun ESL obrazac** (BMG + BRAM controller + master port u IP-u — najveći posao, master
interfejs vežba ne razrađuje).

---

## 1. Šta se NE dira

- `ncc_core.vhd`, `ncc_pkg.vhd` — verifikovani u Koracima 4–5.
- `dp_bram.vhd`, `mem_subsystem.vhd` — verifikovani unit testovima.
- `ncc_accel_slave_lite_v1_0_S00_AXI.vhd` — kontrolni registri, ispravni.
- `ncc_accel.vhd` (top) — portovi i instancijacije nepromenjeni.
- Sinteza/implementacija integrisanog sistema = **Korak 8**, ne ovaj korak.

---

## 2. Pretkorak: popravka burst čitanja u S01

### 2.1 Nalaz

`ncc_accel_slave_full_v1_0_S01_AXI.vhd` je generisan Xilinx šablon u kome je interni
primer-RAM čitan **kombinaciono**. U Koraku 6 je zamenjen `mem_subsystem`-om sa
**registrovanim** `dp_bram` čitanjem (1 takt), a poravnanje je popravljeno **samo za
prvi beat** (`:507` — adresa se izdaje na ciklusu prihvata `ARVALID and arready`).

Za beat-ove ≥ 1 `mem_addr_o` uzima `axi_araddr`, koji se inkrementira u **istom** taktu
u kome se beat troši (`:444-445`) — pa podatak stiže jedan takt prekasno.

**Potvrđeno simulacijom** (`arlen=7`, INCR, xsim):

```
READ BURST beat 0: očekivano 0x32  dobijeno 0x32   ✓
READ BURST beat 1: očekivano 0x33  dobijeno 0x32   ✗
READ BURST beat 2: očekivano 0x34  dobijeno 0x33   ✗
...
READ BURST beat 7: očekivano 0x39  dobijeno 0x38   ✗   → 7 od 8 pogrešno
WRITE BURST: 8/8 PASS
```

Svaki beat vraća **prethodnu** reč; poslednja reč burst-a se nikad ne pojavi.

**Zašto nije uhvaćeno u Koraku 6:** `ncc_accel_tb` koristi `awlen=0`/`arlen=0` svuda
(`:146,167`) — plan je to i predvideo („za jednostavnost TB-a burst dužine 1"). Burst
put nije bio pokriven ni jednim testom.

**Zašto je bitno:** `Xil_In32`/`Xil_Out32` su single-beat pa CPU nikad ne pogodi bug —
ali svaki DMA radi duge INCR burst-ove.

### 2.2 Popravka

Adresa se izdaje **jedan takt unaprijed** dok se beat troši:

```vhdl
-- nov signal u deklaracijama arhitekture:
signal araddr_next : std_logic_vector(16 downto 0);

-- look-ahead: INCR uvećava, FIXED zadržava, WRAP nije podržan (dokumentovano)
araddr_next <= std_logic_vector(unsigned(axi_araddr(16 downto 0)) + 4)
               when axi_arburst = "01" else axi_araddr(16 downto 0);

mem_addr_o  <= S_AXI_ARADDR(16 downto 0)
                 when (S_AXI_ARVALID = '1' and axi_arready = '1') else
               araddr_next                                              -- NOVO
                 when (state_read = Rdata and axi_rvalid = '1' and S_AXI_RREADY = '1') else
               axi_araddr(16 downto 0)
                 when (state_read = Rdata) else
               S_AXI_AWADDR(16 downto 0)
                 when (S_AXI_AWVALID = '1' and S_AXI_WVALID = '1') else
               axi_awaddr(16 downto 0);
```

Trag ispravnosti: u taktu kad se beat *k* troši izdaje se adresa beat-a *k+1*, pa je
`dp_bram` podatak validan tačno u taktu kad `rvalid` nosi beat *k+1*. Pri zastoju
(`RREADY='0'`) adresa se drži, pa podatak beat-a *k* ostaje validan.

Na poslednjem beat-u (`rlast`) izdaje se adresa jedan iza opsega — bezopasno čitanje.

### 2.3 Usput: mrtav kod

Generisani primer-BRAM (`gen_mem_sel` `:473-478`, `BRAM_GEN`/`BYTE_BRAM_GEN` `:480-502`,
4× 256 B) je ostao instanciran. `mem_data_out` se nigde ne čita (RDATA ide iz
`mem_rdata_i`, `:258`) pa sinteza to izbaci — ali treba obrisati zajedno sa
`mem_address_read`, `mem_address_write`, `mem_data_out`, `word_array`, `BYTE_RAM_TYPE`,
`i`, `j`, `mem_byte_index`, `USER_NUM_MEM`, `OPT_MEM_ADDR_BITS`.

Zadržati: `ADDR_LSB` (adresni brojači) i `low` (`aw_wrap_en`/`ar_wrap_en`).

### 2.4 Uticaj na pakovanje

**Portovi i interfejsi se ne menjaju** → `component.xml` ostaje validan, IP se ne pakuje
iznova; dovoljan je `update_ip_catalog -rebuild`. `.zip` arhiva IP-a postaje zastarela —
regeneriše se u Koraku 10 kroz `package_ip.tcl`.

### 2.5 Duplikat izvora (rizik pri ovoj popravci)

Trenutno postoje dve kopije istih fajlova:

| Fajl | `src/vhdl/ip/` | `ip_repo/ncc_accel_1_0/src/` | `ip_repo/.../hdl/` |
|---|---|---|---|
| `dp_bram.vhd` | ✓ | ✓ | — |
| `mem_subsystem.vhd` | ✓ | ✓ | — |
| `ncc_core.vhd`, `ncc_pkg.vhd` | (u `src/vhdl/`) | ✓ | — |
| `S00_AXI`, `S01_AXI`, `ncc_accel.vhd` | — | — | ✓ |

`ip_repo/**` je ono što `component.xml` referencira → **postaje jedini merodavan izvor**.
Unit testbenchevi (`dp_bram_tb`, `mem_subsystem_tb`) se preusmere na `ip_repo/.../src/`,
pa `src/vhdl/ip/` odlazi. Bez ovoga se rizikuje popravka jedne kopije i zaboravljanje druge.

---

## 3. Block design `ncc_system`

### 3.1 Topologija

**Jedan SmartConnect, 2 mastera → 6 slave-ova.** Dva SmartConnect-a **ne rade**:
`ncc.S01` bi imao dva ulaza, a AXI slave interfejs može biti povezan samo na jedan
interkonekt.

```
processing_system7_0                          proc_sys_reset_0
  board preset (zybo-z7-10)                     slowest_sync_clk ◄─ FCLK_CLK0
  FCLK_CLK0 = 100 MHz ─────────────────────►    ext_reset_in     ◄─ FCLK_RESET0_N
  M_AXI_GP0  (enabled)                          peripheral_aresetn ──► svi aresetn
  S_AXI_HP0  (enabled, aclk = FCLK_CLK0)

  PS.M_AXI_GP0 ──┐                        ┌──► ncc0.S00_AXI  (Lite, kontrola)
                 │                        ├──► ncc0.S01_AXI  (Full, memorije)
                 ├──► smartconnect_0 ─────┼──► ncc1.S00_AXI
                 │      NUM_SI = 2        ├──► ncc1.S01_AXI
  cdma.M_AXI ────┘      NUM_MI = 6        ├──► axi_cdma_0.S_AXI_LITE
                 ▲                        └──► PS.S_AXI_HP0  (DDR)
                 │
  axi_cdma_0 ────┘
    C_INCLUDE_SG        = 0     (simple mode, bez scatter-gather)
    C_INCLUDE_DRE       = 0     (svi pristupi su 4B-poravnati)
    C_M_AXI_DATA_WIDTH  = 32
    C_M_AXI_MAX_BURST_LEN = 256 (256×4B = 1 KB, ne prelazi 4 KB granicu)
```

Sve na **jednom taktu FCLK_CLK0 = 100 MHz**, uključujući `S_AXI_HP0_ACLK` → **nema CDC**,
nema potrebe za `set_false_path`.

`ncc_core` je projektovan za 100 MHz (Korak 5: WNS +1,179 ns na `-2` delu; videti §7 za
rizik na `-1`).

### 3.2 Adresna mapa (fiksirana)

Po-master vidljivost kroz `assign_bd_address` + `exclude_bd_addr_seg`:

| Master | Slave | Baza | Opseg |
|---|---|---|---|
| PS M_AXI_GP0 | `ncc0.S00_AXI` | `0x5000_0000` | 4 K |
| PS M_AXI_GP0 | `ncc0.S01_AXI` | `0x5002_0000` | 128 K |
| PS M_AXI_GP0 | `ncc1.S00_AXI` | `0x5100_0000` | 4 K |
| PS M_AXI_GP0 | `ncc1.S01_AXI` | `0x5102_0000` | 128 K |
| PS M_AXI_GP0 | `axi_cdma_0.S_AXI_LITE` | `0x6000_0000` | 64 K |
| cdma M_AXI | `PS.S_AXI_HP0` (DDR) | `0x0000_0000` | (iz PS preseta) |
| cdma M_AXI | `ncc0.S01_AXI` | `0x5002_0000` | 128 K |
| cdma M_AXI | `ncc1.S01_AXI` | `0x5102_0000` | 128 K |

- CDMA **ne vidi** S00 portove (ne treba mu kontrola).
- PS **ne vidi** DDR kroz HP0 (ima direktan put kroz PS).
- `0x5002_0000` je egzaktno `131072 × 10241` → poravnato na 128 K, kako Vivado zahteva.
- **DDR opseg se ne kuca ručno** — prati DDR konfiguraciju iz PS board preseta:
  1 G za Zybo Z7-10, 512 M za originalni Zybo (videti §7.3). Skripta ga uzima iz
  `get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM`, ne kao konstantu.
- S00 opseg je 4 K jer je to Vivado minimum za AXI segment; IP dekodira samo donjih
  6 bita (`C_S00_AXI_ADDR_WIDTH = 6`) pa se registri alijasiraju unutar tog prozora —
  standardno i bezopasno.

**Poklapanje sa ESL `common.hpp`:**

| ESL konstanta | Vrednost | Preslikavanje |
|---|---|---|
| `ADDR_NCC` | `0x5000_0000` | `ncc0.S00_AXI` — **identično** |
| `ADDR_NCC1` | `0x5100_0000` | `ncc1.S00_AXI` — **identično** |
| `ADDR_DMA` | `0x6000_0000` | `axi_cdma_0.S_AXI_LITE` — **identično** |
| `ADDR_BRAM` | `0x4000_0000` | **ne postoji** — nema deljenog BRAM-a (slave/interni obrazac) |
| `ADDR_RESULTS` (`0x40`) | offset u NCC-u | postaje `S01 + 0x10000` (drugi interfejs) |
| `REG_IMG_ADDR`/`REG_TMP_ADDR` | `0x10`/`0x14` | **rezervisani** (bez značenja u slave obrascu) |

### 3.3 Regioni unutar S01 (iz Koraka 6, nepromenjeno)

Dekodovanje na `addr(16:15)`, indeks reči `addr(14:2)`, **jedan piksel po 32-bitnoj reči**:

| Region | `addr(16:15)` | Offset od S01 baze | Sadržaj | Širina × dubina |
|---|---|---|---|---|
| Slika | `00` | `+0x00000` | pikseli segmenta | 8-bit × 8192 |
| Šablon | `01` | `+0x08000` | pikseli šablona | 8-bit × 1024 |
| Rezultat | `10` | `+0x10000` | NCC² u Q1.31 | 32-bit × 8192 |

Burst nikad ne prelazi granicu regiona jer su regioni 32 K poravnati a max burst 1 KB —
uz uslov da softver ne startuje transfer duži od regiona.

---

## 4. Tok podataka (definiše interfejs za Korak 9)

Po polju table `(m,n)`, po NCC bloku. Segment ostaje u `img_mem` kroz sve šablone jer
`ncc_core` nema `img_dirty` — SAT se gradi na svaki `start` (cena 2·8100 = 16.200 od
3.776.210 taktova = **0,43%**), ali memorija se ne prazni.

1. **Provera praznog polja** — CPU čita centralnu zonu iz DDR-a (keširano, bez PL pristupa).
2. **Staging u DDR-u** — CPU sklopi bafer **1 piksel po `u32`**: coarse 45×45 = 2025 reči,
   pun 90×90 = 8100 reči. `Xil_DCacheFlushRange` nad oba.
3. **CDMA punjenje slike** — DDR → `ncc0.S01 + 0x00000`, pa DDR → `ncc1.S01 + 0x00000`.
4. **CDMA punjenje šablona** — šablon raspakovan u `u32` **jednom na startu** za svih
   12 punih + 12 coarse → `+0x08000`.
5. **Start** — CPU `Xil_Out32`: `IMG_W/H`, `TMP_W/H`, pa `CTRL=1` na S00 oba bloka.
6. **Čekanje** — polling `STATUS` bit0 (`done_sticky`) na oba.
7. **CDMA čitanje rezultata** — `+0x10000` → DDR → `Xil_DCacheInvalidateRange` → CPU
   traži maksimum.

### 4.1 Dva obavezna softverska pravila

**(a) `u32` poređenje, ne `int32`.** ESL `tb.cpp` drži skorove kao `int32_t` i traži
maksimum sa `mx = -1`. `0x80000000` (NCC² = 1,0) je kao `int32` **negativan** →
egzaktno poklapanje bi bilo odbačeno. Na realnim podacima se ne javlja (prag je
`0x48000000` = 0,5625), ali bare-metal port mora koristiti `u32`.

**(b) Nikad CDMA i CPU nad istim S01 istovremeno.** `mem_addr_o` daje prioritet čitanju
nad upisom (`:507-510`) i `mem_we_o` nije zabranjen tokom čitanja, pa bi istovremeni R+W
upisao na adresu čitanja. Održava se prirodno jer CPU čeka `XAxiCdma_IsBusy` — ali mora
biti zapisano. (Nije uvedena arbitracija: sa jednim CPU-om i jednim CDMA kanalom koji se
serijalizuju u softveru, arbitracija bi bila mrtav hardver.)

### 4.2 Zašto DMA nije performansni dobitak (izmereno iz `tb.cpp`)

Po polju: **23.400 upisa** (2×(2025 coarse segment + 675 coarse šabloni + 8100 pun
segment + 900 fini šablon)) i **13.208 čitanja** (`collect` čita celu mapu: 6×961 +
2×3721). Ukupno ~146 KB.

| Put | Vreme po polju | Od ukupnog (~48 ms računanja) |
|---|---|---|
| CPU `Xil_Out32`/`In32` | ~3,4 ms | ~7% |
| CDMA u oba smera | ~0,4 ms | ~1% |

**Preklapanje nije moguće** ni u jednom slučaju: memorije su jednostruko baferovane i
`ncc_core` ih čita dok računa, pa CPU/DMA mora čekati `done`. DMA je dakle **samo brži
transfer, ne skrivena latencija** — dobitak ~6% ukupnog vremena.

CDMA je izabran zbog pravilnika (DMA je nabrojan za ovaj korak) i zbog toga što popravka
iz §2 mora ionako da se uradi, a ne zbog performansi. To treba tako i reći na odbrani.

---

## 5. Kriterij završenosti

| # | Provera | Očekivano |
|---|---|---|
| 1 | `ncc_accel_tb` (zlatni, single-beat) | PASS, peak `0x80000000 @ idx 956` — **nepromenjeno** |
| 2 | `ncc_accel_burst_tb` (novi, `arlen`/`awlen` = 7) | PASS, 8/8 read **i** 8/8 write |
| 3 | `create_bd.tcl` u batch Vivado-u | `validate_design` bez grešaka |
| 4 | HDL wrapper | `ncc_system_wrapper` generisan i elaborira |

Sinteza, resursi, timing i throughput integrisanog sistema = **Korak 8**.

---

## 6. Fajlovi

| Akcija | Fajl |
|---|---|
| Menja se | `src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/ncc_accel_slave_full_v1_0_S01_AXI.vhd` |
| Dodaje se | `src/vhdl/tb/ncc_accel_burst_tb.vhd` |
| Dodaje se | `src/vhdl/script/create_bd.tcl` |
| Uklanja se | `src/vhdl/ip/` (duplikat; unit TB-ovi se preusmere na `ip_repo/.../src/`) |
| Ažurira se | `CLAUDE.md`, `(C) Plan implementacije (10 koraka).md`, `(C) Sljedeća sesija.md` |

---

## 7. Rizici i poluge

### 7.1 Timing na `-1` delu

Korak 5 je meren na **`xc7z010clg225-2`**; prelazimo na **`xc7z010clg400-1`**. Isti čip
(XC7Z010), **identičan kapacitet** — provereno kroz Vivado:

```
xc7z010clg400-1 : LUT=17600 FF=35200 DSP=80 BRAM=60 speed=-1
xc7z010clg225-2 : LUT=17600 FF=35200 DSP=80 BRAM=60 speed=-2
```

Resursni procenti iz Koraka 5 dakle **stoje** — potvrđeno merenjem (Task 9): na
`clg400-1` je identično 1526 LUT / 554 FF / 9 BRAM / 9 DSP.

**IZMERENO POST-ROUTE (2026-07-25) — timing NE zatvara 100 MHz na novom partu:**

| Part | WNS post-route | krši | putanja | logika / rutiranje |
|---|---|---|---|---|
| `xc7z010clg400-1` | **−0,754 ns** | 51/1444 | 10,701 ns | 6,132 / 4,569 |

**Fmax ≈ 93 MHz.** Kritična putanja: `sum_num_reg[19] → div_ncc/work_reg[82]`,
17 nivoa logike (CARRY4=9) — kvadriranje brojioca u 83-bitni delilac.

~~Na `-1` delu logika raste ~10–15% → očekivano WNS ~+0,1 do +0,3 ns.~~ — **odbačeno.**
~~Merenje je degenerisano zbog 118 IOB naspram 100 dostupnih.~~ — **odbačeno:**
`synth_design -mode out_of_context` (0 IOB) daje istu razliku (+1,277 ns na `clg225-2`
naspram −0,571 ns na `clg400-1`), a procjena rutiranja je identična u IOB i OOC režimu za
isti part → zavisi od uređaja, ne od razmeštaja. Puna hronologija oba pogrešna zaključka
je u `BUGS.md`.

**Takođe:** +1,179 ns iz Koraka 5 je bila **samo post-sintezna** brojka; pravilnik za
5b/8b traži „nakon sinteze **i implementacije**". Post-route na `clg225-2` nikad nije
pokrenut.

**Poluge:** (a) registar na putanji `sum_num → div_ncc` (`IDEJE.md`) = +1 takt po prozoru
od ~485 → **+0,2% latencije**, ali menja `ncc_core.vhd` pa oba TB-a iz Koraka 4 +
`ncc_accel_tb` moraju ponovo proći; (b) `FCLK_CLK0 = 90 MHz` — jedna linija u
`create_bd.tcl`, bez izmene RTL-a, košta 10% throughput-a (formalno u rubrici: 10%
odstupanja, granica 20%).

**Status:** `ncc_core.vhd` NIJE diran. Odluka čeka merenje **integrisanog sistema**
(Korak 8a/8b) da se donese sa punim podacima.

**Poluga (IDEJE.md):** preseći kritičnu putanju `sum_num_reg[16] → div_ncc/work_reg[78]`
registrom. Cena +1 takt po prozoru od ~485 → propusnost praktično nepromenjena, jer se
ta putanja izvršava jednom po poziciji prozora, ne u unutrašnjoj petlji.

**Dosledna dokumentacija:** re-pokrenuti `synth_design` za goli `ncc_core` na `clg400-1`
(par minuta, kod se ne menja) i ažurirati brojke u PDF-u, da Korak 5 i Korak 8 budu na
istom delu. Inače je neslaganje prvo što profesor primeti.

### 7.2 BRAM budžet

Procena (**nije mereno**, iz dizajna Koraka 6): ~19 RAMB36 po IP-u (9 `sat_mem` +
8 `result_mem` + 2 `img_mem` + ~0,5 `templ_mem`) → **~38-39 od 60 = ~65%** za 2 bloka.
Staje, ali bez velike rezerve. Meri se u Koraku 8.

**Poluge:** `sat_t` 32→21 bita (−3 po IP-u, IDEJE.md, jedna linija u `ncc_pkg.vhd` —
ali onda oba TB-a iz Koraka 4 moraju ponovo proći); `result_mem` 8192→4096 (−4 po IP-u,
ali ograničava minimalnu veličinu šablona).

### 7.3 `board_part` je pretpostavka

`digilentinc.com:zybo-z7-10:part0:1.2` je **nepotvrđeno**. Part je isti za oba Zybo
varijanteta, razlikuje se samo PS preset:

| | Zybo (originalni) | Zybo Z7-10 |
|---|---|---|
| `board_part` | `digilentinc.com:zybo:part0:2.0` | `digilentinc.com:zybo-z7-10:part0:1.2` |
| PS_CLK kristal | 50 MHz | 33,333 MHz |
| DDR3 | MT41K128M16 JT-125 (512 MB) | MT41K256M16 RE-125 (1 GB) |

Razlikovanje na ploči: originalni Zybo ima **VGA** + 1× HDMI i 6 Pmod; Zybo Z7-10 ima
**2× HDMI** (in/out, bez VGA), MIPI CSI konektor i 5 Pmod.

Pogrešan preset → pogrešna PLL konfiguracija → UART na pogrešnom baud rate-u i DDR koji
ne radi. **Ne utiče na Korak 7/8** (BD, sinteza, timing, resursi), samo na Korak 9.
Promena je jedna linija u `create_bd.tcl`.

### 7.4 Korak 8e — odstupanje ≤ 20%

Sa optimizacijama 1/3/4 u softveru (Korak 9) izlazimo na **~1,5–1,6 s** naspram ESL
reference **3,667 s** → odstupanje ~59% **u našu korist**, što formalno krši pravilo
„ne smeju odstupati više od 20%". DMA odluka ovo **ne menja** (±6%).

Ispravan pristup nije veštački zaspori, nego **rekalibrisati `K_CYC` u SystemC modelu**
našim izmerenim modelom latencije `T = 2·img_w·img_h + 2·N + res_w·res_h·(N + 110)`
i porediti jabuke sa jabukama: sistemski model i HW se onda moraju poklopiti u okviru
20%, a razlika prema originalnoj ESL brojci se objašnjava time što je naš RTL 2,74× brži
po piksel-operaciji od HLS reference (1,30 vs 3,09 takta). Odvojena tema za Korak 8.

---

## 8. Okruženje (provereno 2026-07-25)

```
part            xc7z010clg400-1
board_part      digilentinc.com:zybo-z7-10:part0:1.2   (+ zybo:part0:2.0 kao fallback)
board files     instalirani u C:\AMDDesignTools\2025.2\Vivado\data\boards\board_files\
                (zybo, zybo-z7-10, zybo-z7-20; izvor: github.com/Digilent/vivado-boards)
IP katalog      xilinx.com:ip:axi_cdma:4.1
                xilinx.com:ip:smartconnect:1.0
                xilinx.com:ip:processing_system7:5.5
                xilinx.com:ip:proc_sys_reset:5.0
ip_repo         src/vhdl_NCC_IP/ip_repo   (xilinx.com:user:ncc_accel:1.0)
batch Vivado    C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat -mode batch -source <tcl>
xsim            xvhdl -2008 / xelab / xsim  (isti tok kao Koraci 3-6)
```
