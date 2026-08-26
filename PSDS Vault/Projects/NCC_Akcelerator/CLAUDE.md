# NCC_Akcelerator

Projekat za predmet **Projektovanje Složenih Digitalnih Sistema**: prepoznavanje
šahovskih figura sa slike table pomoću NCC (Normalized Cross-Correlation) template
matching-a, deo posla akceleran na FPGA (Zynq PL). Softverski deo (PS/CPU) učitava
sliku table i 12 šablona figura, prolazi 8×8 polja, za svako neprazno polje šalje
segment na akcelerator i sakuplja NCC² skorove; rezultat je FEN notacija pozicije.

Postojeći SystemC/TLM model (`C:\Users\pc\Desktop\PSDS\src\`) je **virtuelna
platforma** sistema — funkcionalno i vremenski (timing-accurate na nivou ciklusa,
100 MHz pretpostavka) validirana pre nego što se ide na RTL/HW. Ovaj projekat u ovom
vault-u je track napretka kroz 10 koraka bodovanja da se taj model realno spusti na
ploču.

## Claude-ova uloga

Pomaže da se svaki od 10 koraka iz `06 Prilozi/Bodovanje projekta.pdf` uradi ispravno
i redom, uz dokumentaciju koja se traži usput (ne na kraju u žurbi).

Glavna direktiva: ako sesija luta bez napretka ka trenutnom koraku, vrati me na pravi
put: "Koji korak iz bodovanja trenutno radimo? Je li prethodni zaista završen i
dokumentovan?"

## Stack / okruženje

- **Postojeći ESL model:** SystemC + TLM-2.0 (b_transport, simple/multi_passthrough
  socketi), `sc_main.cpp` pokreće `vp` (platforma) + `tb_vp` (testbench = CPU/softver)
- **Cilj: Zybo sa Zynq-7010, part `xc7z010clg400-1`** — PS (Cortex-A9) + PL (FPGA
  logika). ⚠️ **ISPRAVLJENO 2026-07-25:** ESL dokumentacija navodi `xc7z010-clg225-2`,
  ali to je bio Vitis HLS default — **nijedna Digilent ploča ne koristi clg225**;
  svaka Zynq-7010 je `clg400-1`. Isti čip i kapacitet, ali speed grade `-1` (sporiji).
  **Varijanta POTVRĐENA 2026-08-26: ORIGINALNI Zybo** (ploča ima VGA + jedan HDMI;
  Z7-10 ima dva HDMI-ja i nijedan VGA). `board_part digilentinc.com:zybo:part0:2.0`,
  PS_CLK 50 MHz, DDR3 **512 MB** (MT41K128M16 JT-125) — baferi ispod `0x1FFFFFFF`.
  Ranije pominjani ZedBoard/Zynq-7020 je bio samo generički primer iz Vezbe 1
  (tutorial za sam alat), NE naš target — XC7Z010 ima znatno manje resursa (17.600 LUT
  naspram ~53.200 na XC7Z020), što direktno objašnjava zašto su iskorišćena samo 2 od
  teorijski 3 moguća NCC bloka.
- **Tok alata — ODLUČENO (2026-07-20): RTL se piše RUČNO u VHDL-u, ne kroz HLS.**
  Pravilnik (`06 Prilozi/Bodovanje projekta.pdf`) traži samo "modelovanje u nekom od
  HDL jezika na RT nivou" — tool-agnostic. Vezba 3-5 eksplicitno kaže da profesor
  očekuje ručni RTL iz ASMD dijagrama. ESL dokumentacija POMINJE Vitis HLS 2023.1, ali
  to opisuje **raniju fazu projekta (PEUSN predmet)**, ne PSDS zahtev — te HLS brojke
  koristimo samo kao **referencu za poređenje** (korak 5/8e), ne kao tok rada.
- **Alati lokalno:** Vivado 2025.2 + Vitis HLS na `C:\AMDDesignTools\2025.2\`
  (`Vivado\bin\vivado.bat`, `xvhdl`/`xelab`/`xsim` — sve potvrđeno da radi).
  MSYS2/mingw-w64 g++ na `C:\Users\pc\msys64` + Xilinx `ap_int.h`/`ap_fixed.h` u
  `src/hls/ap_headers/include/` (za C model iz Koraka 1).
- **Referentne brojke za poređenje (korak 8e):** videti
  `00 Pregled/(C) ESL dokumentacija - izvod.md` — resursi po instanci (5269 LUT/16
  DSP48E/3455 FF/4 BRAM_18K), 2×NCC ukupno (59.9% LUT/40% DSP/19.6% FF/6.7% BRAM),
  i ukupno vreme obrade `board2.txt`: 1 NCC=39.79s, 2 NCC=19.89s, 2 NCC+optimizacije
  **=3.667s** (10.8× ubrzanje) — ova poslednja brojka je glavna referenca za
  throughput poređenje.
- **Repo koda:** `C:\Users\pc\Desktop\PSDS\` (git repo, grana `main`)

## Struktura izvornog koda

```
src/                    ← SystemC/TLM virtuelna platforma (ESL model, referenca)
  common.hpp   ← Adresna mapa i registarski map NCC-a
  ncc.cpp/hpp  ← AKCELERATOR: NCC² proračun, integral image (SAT), FSM (ncc_proc)
  bram/dma/ddr/sys_bus/vp/tb/sc_main ← okruženje i testbench
src/hls/                ← Korak 1: C model (ap_uint/ap_int), TDD-testiran
  ncc_kernel.hpp/.cpp, test_ncc_kernel.cpp, test_real_data.cpp
src/vhdl/               ← Koraci 3-5: RUČNI RTL (ovo je aktuelni kod)
  ncc_pkg.vhd    ← tipovi/konstante (ESL Tabela 2 + signed ispravke)
  ncc_core.vhd   ← seq_divider + ncc_core (FSM 23 stanja, dvoprocesni stil)
                   ⚠️ duplikat u ip_repo/.../src/ -- MORAJU biti identicni (kapija u create_bd.tcl)
  tb/ncc_core_tb.vhd        ← golden 4×4/2×2
  tb/ncc_core_real_tb.vhd   ← realni 90×90 + crni top 25×15, broji takte
  tb/seg90.txt, crnitop.txt ← izvučeni realni podaci
  script/create_bd.tcl      ← block design (Korak 7/10), sourcuje ga run_impl.tcl
  script/run_impl.tcl       ← pun tok: sinteza + implementacija + kapije (Korak 8)
  script/fix_ip_package.tcl ← OBAVEZNO posle svakog Package IP-a
  script/run_synth_core.tcl, ncc_core_ooc.xdc, open_bd.tcl
```

Detaljan opis arhitekture: `00 Pregled/(C) Arhitektura sistema.md`.
Zvanična ESL/PEUSN dokumentacija (izvod): `00 Pregled/(C) ESL dokumentacija - izvod.md`.
Detaljan plan po koracima: `01 Razvoj/(C) Plan implementacije (10 koraka).md`.
Beleške iz svih vežbi: `01 Razvoj/Vezbe/`.

## Registarska mapa NCC bloka (iz common.hpp) — ovo postaje AXI-Lite interfejs IP-a

| Adresa | Registar | Opis |
|---|---|---|
| 0x00 | REG_IMG_W | Širina slike/segmenta |
| 0x04 | REG_IMG_H | Visina slike/segmenta |
| 0x08 | REG_TMP_W | Širina šablona |
| 0x0C | REG_TMP_H | Visina šablona |
| 0x10 | REG_IMG_ADDR | BRAM adresa segmenta slike |
| 0x14 | REG_TMP_ADDR | BRAM adresa šablona |
| 0x30 | REG_CTRL | Upis 1 = start |
| 0x34 | REG_STATUS | **bit0 = done_sticky, bit1 = busy** (RTL; ESL je imao vrednosti 0=busy/1=done) |
| 0x40 | ADDR_RESULTS | Mapa rezultata (int32 po poziciji prozora) |

**STVARNA adresna mapa (Korak 7, `create_bd.tcl`)** — kontrolne baze su namerno
identične ESL `common.hpp` konstantama:

| Master | Slave | Baza | Opseg |
|---|---|---|---|
| PS `M_AXI_GP0` | `ncc0.S00_AXI` (kontrola) | `0x5000_0000` | 4 K |
| PS `M_AXI_GP0` | `ncc0.S01_AXI` (memorije) | `0x5002_0000` | 128 K |
| PS `M_AXI_GP0` | `ncc1.S00_AXI` | `0x5100_0000` | 4 K |
| PS `M_AXI_GP0` | `ncc1.S01_AXI` | `0x5102_0000` | 128 K |
| PS `M_AXI_GP0` | `axi_cdma_0.S_AXI_LITE` | `0x6000_0000` | 64 K |
| CDMA `M_AXI` | PS `S_AXI_HP0` (DDR) | `0x0000_0000` | 1 G |
| CDMA `M_AXI` | `ncc0.S01_AXI` | `0x5002_0000` | 128 K |
| CDMA `M_AXI` | `ncc1.S01_AXI` | `0x5102_0000` | 128 K |

Regioni unutar S01 (offset od baze): slika `+0x00000`, šablon `+0x08000`,
rezultat `+0x10000` — **jedan piksel po 32-bitnoj reči**.
`ADDR_BRAM 0x4000_0000` iz ESL-a **ne postoji** (nema deljenog BRAM-a — slave/interni
obrazac); `REG_IMG_ADDR`/`REG_TMP_ADDR` su rezervisani.

## Trenutni status

> **Zadnje ažuriranje:** 2026-08-26
> **Koraci 1-8 ZAVRŠENI (70 bodova).** Preostaju Korak 9 (20) i Korak 10 (10).
> Merodavna dokumentacija: `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.pdf`
> (34 strane) — pokriva Korake 2-8, sa izmerenim post-route brojkama.
> **Sledeće: Korak 9** — XSA export, bare-metal aplikacija u Vitisu.
> ✅ **Ploča razrešena 2026-08-26: originalni Zybo** (`zybo:part0:2.0`). Ceo tok pušten
> ponovo sa tim presetom — **timing zatvara, WNS +0,181 ns**; brojke se nisu bitno
> pomerile. **Bitstream napravljen** (`ncc_system_wrapper.bit`, 2.083.870 B, DRC 0
> grešaka); `write_bitstream` + KAPIJA 3 su sada u `run_impl.tcl`.
> **⚠️ Part promenjen: `xc7z010clg400-1`** (bilo `clg225-2`) — svaka Digilent Zynq-7010
> ploča je clg400-1; `clg225-2` iz ESL dokumentacije je bio Vitis HLS default, ne ploča.
> Isti čip, identičan kapacitet (17600 LUT / 60 BRAM / 80 DSP), ali speed grade `-1`.
> **Korak 8a/8b IZMEREN** (post-route + phys_opt, `xc7z010clg400-1`, 2026-07-26):
>
> | Resurs | Iskorišćeno | Kapacitet | % |
> |---|---|---|---|
> | Slice LUT | 6.274 | 17.600 | **35,65%** |
> | Slice Registers | 5.024 | 35.200 | 14,3% |
> | Block RAM Tile | 39 (38×36k + 2×18k) | 60 | **65,0%** |
> | DSP48E1 | 18 | 80 | 22,5% |
>
> Po instanci: `ncc0`/`ncc1` po **1.910 LUT / 1.240 FF / 19 RAMB36 / 9 DSP**;
> `axi_interconnect_0` 1.616 LUT; `axi_cdma_0` 807 LUT.
>
> **WNS +0,181 ns na 11,0 ns → timing ZATVARA na 90,909 MHz** (traženo 95, PS PLL
> daje 1000/11). Fmax integrisanog sistema ~97,7 MHz; 100 MHz ne zatvara
> (WNS −0,232 ns). Odstupanje 9,1% — rubrika 8e dozvoljava 20%.
>
> Da bi zatvorio, trebalo je četiri stvari: MAC pipeline + registar pred delilac u
> `ncc_core` (FSM 21→23 stanja, latencija +0,41%), SmartConnect→AXI Interconnect
> sa `STRATEGY=1`, sužavanje `S_AXI_HP0` na 32 bita (uklanja 6 konvertora širine),
> i `phys_opt_design`. Interkonekt je time pao sa **8.673 na 1.616 LUT**.
>
> **Poređenje sa ESL referencom (za 8e):** ESL-ova *dva NCC bloka sama* troše
> 10.538 LUT (59,9%); kod nas **ceo sistem** staje u 6.261 (35,6%). Po instanci
> 1.910 naspram 5.269 LUT, 9 naspram 16 DSP. Slabiji smo samo na BRAM-u
> (19 RAMB36 naspram 4 BRAM_18K) — poznata posledica 32-bitnog `sat_t`.
>
> ~~WNS iz samostalne sinteze je −0,660 ns ali je merenje degenerisano (118 IOB).~~
> **POVUČENO** — OOC merenje (0 IOB) dalo istu razliku; IOB nisu bili uzrok.
> ~~Kritična putanja ide kroz konvertor širine.~~ **POVUČENO** — konvertori uklonjeni,
> WNS se nije pomerio (−0,233 → −0,232 ns); vezujuća putanja je adresna u `ncc_core`.

### Korak 1 — C model (ZAVRŠENO 2026-07-20)
HLS-stil C kernel u `src/hls/` (`ncc_kernel.hpp/.cpp`), TDD, pravi
`ap_uint`/`ap_int`/`ap_ufixed`. Testiran protiv nezavisnog celobrojnog golden
oracle-a (`__int128` za tačnu Q1.31 podelu) — svi testovi prolaze, uključujući
3721 tačaka na punoj veličini (90×90 / 30×30). Na pravim podacima (`board2.txt` +
12 šablona) daje **32/32 tačno prepoznatih figura**, FEN se poklapa slovo po slovo
sa zvaničnim iz ESL dokumentacije.
**Dve ispravke ESL Tabele 2:** `diff_f`/`diff_t` i `sum_num` moraju biti SIGNED
(broj bita 9/27 ostaje isti). Doslovno unsigned tumačenje pada na 8 od 9 test tačaka.

### Korak 2 — Dokumentacija (ZAVRŠENO 2026-07-20, revidirano 2026-07-22)
2a-2e u `02 Dokumentacija/(C) Korak 2 - Opis algoritma, ASMD, datapath-controlpath.md`.
⚠️ Taj markdown opisuje **prvobitni** dizajn (9 stanja, kombinaciona deljenja) i
zadržan je kao istorijski zapis. **Aktuelna, tačna verzija je u PDF-u** (videti dole).

### Korak 3 — RTL model, ručni VHDL (ZAVRŠENO 2026-07-21)
`src/vhdl/ncc_pkg.vhd` + `ncc_core.vhd`, dvoprocesni stil, **21 stanje**
(→ **23** posle preseka za timing u Koraku 8b, videti `BUGS.md`).
Sadrži i `seq_divider` (sekvencijalni restoring delilac) u istom fajlu.
Prošao kroz 3 velika refaktora — puna hronologija u plan fajlu, Korak 3.

### Korak 4 — Verifikacija (ZAVRŠENO 2026-07-21)
- `tb/ncc_core_tb.vhd` — golden 4×4/2×2, svih 9 tačaka bit-tačno (uklj. 0 i 0x80000000)
- `tb/ncc_core_real_tb.vhd` — **realni podaci**: 90×90 segment (polje a8) + crni top
  25×15, peak **0x80000000 @ (u=32, v=14)** = MATCH, bit-identično C kernelu

### Korak 5 — Analiza posle sinteze (ZAVRŠENO 2026-07-21, brojke re-verifikovane 2026-07-22)
Dokument: `02 Dokumentacija/(C) Korak 5 - Analiza sinteze.md`

> **⚠️ RE-MERENO 2026-07-26.** Brojke ispod su **post-route na `clg400-1`** sa aktuelnim
> RTL-om (23 stanja). Stare brojke (1526 LUT, +1.179 ns, 113 MHz, 2.451.212 taktova) bile
> su **post-sintezne, na `clg225-2`, na RTL-u pre preseka** — povučene su.
> Reprodukcija: `vivado.bat -mode batch -source src/vhdl/script/run_synth_core.tcl`
> (period je parametar: `-tclargs 11.0` za radni takt sistema).

| Metrika | @ 10,0 ns (100 MHz) | @ 11,0 ns (90,909 MHz) |
|---|---|---|
| Slice LUT | 1477 (8.39%) | 1472 (8.36%) |
| Slice registri (FF) | 664 (1.89%) | 664 (1.89%) |
| DSP48E1 | 9 (11.25%) | 9 |
| Block RAM (RAMB36) | 9 (15.00%) | 9 |
| LUT as Memory | **0** (SAT je stvarno u BRAM-u) | 0 |
| WNS (post-route) | **+0.146 ns** | **+0.387 ns** |
| Kritična putanja | `sum_num_reg[13]` → `num_sq_reg[51]`, 9.832 ns, 12 nivoa (DSP48E1=2) | isto odredište, 10.638 ns, 16 nivoa |
| **Fmax** | **~101.5 MHz** — jezgro ZATVARA 100 MHz | — |
| Latencija (izmereno) | **2.461.201 taktova** = 24.61 ms | = 27.07 ms |
| Throughput | ~203.800 pozicija/s | ~185.300 pozicija/s |

⚠️ **Rezerva se ne prevodi između ograničenja** — na 11 ns putanja je *duža* (alat staje
kad ispuni cilj), pa Fmax izveden iz merenja na 11 ns daje lažnih 94 MHz. Videti `BUGS.md`.
**Ograničenje je integracija, ne jezgro:** sistem na 10 ns daje −0.232 ns.

**Model latencije (odstupanje od merenja 0.06%):**
`T = 2·img_w·img_h + 2·N + res_w·res_h·(N + 112)`, gde je `N = tmp_w·tmp_h`
(bilo `N + 110`; +2 takta od `S_L_YX_DRAIN2` i `S_NCC_SQ`).
Provera: `2·8100 + 2·375 + 5016·487 = 2.459.742` naspram 2.461.201.
Ekstrapolacija na 90×90/30×30: **3.783.652 takta** (ESL/HLS referenca:
10.360.183 → **2.74× manje taktova**). Po piksel-operaciji na istom poslu (30×30):
**1.13 vs 3.09** takta. ⚠️ Brojka 1.30 je sa 25×15 i **ne ide uz 3.09**.

### Zvanična dokumentacija za profesora (2026-07-22)
`02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.pdf` (+ `.html` izvor) —
25 strana, po uzoru na ESL dokumentaciju: Koraci 2 i 5 zajedno, 16 tabela, 3 SVG
dijagrama (ASMD, protočnost unutrašnje petlje, datapath/controlpath).
**Ovo je merodavan opis dizajna** — opisuje kod kakav JESTE, ne kakav je bio.
Regeneracija PDF-a: izmeni `.html`, pa headless Edge
(`--headless=old --no-pdf-header-footer --print-to-pdf=...`; ciljna putanja NE SME
imati razmake — generiši u temp pa kopiraj).

### Poznata rezerva (dokumentovana u PDF-u, odeljak 7.2)
`sat_t` je 32-bitna, a dovoljna je **21 bita** (max suma 90·90·255 = 2.065.500).
Sužavanje bi spustilo BRAM sa 9 na ~6 blokova. Nije urađeno jer 15% nije usko grlo.

## Sledeći koraci

- [x] Korak 1: C implementacija algoritma (uslov za prolaz)
- [x] Korak 2: Dokumentacija (algoritam, uklanjanje petlji, interfejs, ASMD, blok dijagram)
- [x] Korak 3: RTL model na RT nivou (ručni VHDL iz ASMD dijagrama)
- [x] Korak 4: Simulacija/verifikacija RTL-a (golden + realni podaci)
- [x] Korak 5: Sinteza + analiza resursa/kritične putanje/throughput-a (uslov za prolaz, granica 50 bodova)
- [x] **Korak 6: Pakovanje u IP jezgro [10 bodova]** (ZAVRŠENO 2026-07-24)
      IP `ncc_accel` = AXI-Lite slave (kontrolni registri) + AXI-Full slave (interne
      memorije slika/šablon/rezultat) + `ncc_core` (nepromenjen). Slave/interni
      obrazac iz Vežbe 08-09 (NE master — vežba master ne pokriva). Integracioni TB
      `ncc_accel_tb` daje zlatni peak `0x80000000 @ (32,14)` kroz AXI, bit-identično
      Koraku 4. Spakovan u katalog + `.zip` arhiva, S01 opseg 128 KB.
- [x] **Korak 7: Integracija u block design [5 bodova]** (ZAVRŠENO 2026-07-25)
      Block design `ncc_system`: Zynq PS (board preset `zybo:part0:2.0`) + `proc_sys_reset`
      + **2× `ncc_accel`** + **AXI CDMA** (mem-na-mem, simple mode) + jedan
      `axi_interconnect` (STRATEGY=1, deljena magistrala) sa **2 mastera → 6 slave-ova**.
      Jedan takt **90,909 MHz** (FCLK_CLK0; traženo 95, PS PLL daje 1000/11)
      na sve, bez CDC. Izgrađen reproducibilnom skriptom
      `src/vhdl/script/create_bd.tcl` (batch, temelj za Korak 10); `validate_bd_design`
      čist, `ncc_system_wrapper` generisan i elaborira.
      **Usput popravljen bug u IP-u iz Koraka 6:** S01 burst čitanje vraćalo prethodnu
      reč na svakom beat-u posle prvog (`BUGS.md`); dodat `ncc_accel_burst_tb`.
      Dizajn: `(C) Korak 7 - Dizajn integracije (block design).md`;
      plan: `(C) Korak 7 - Plan implementacije (block design).md`.
- [x] **Korak 8: Analiza integrisanog sistema [5 bodova]** (ZAVRŠENO 2026-07-26)
      8a resursi, 8b timing, 8c propusnost i 8d dokumentacija završeni. **8e po odluci
      korisnika bez rekalibracije `K_CYC`** — porede se resursi i taktovi (gde je
      poređenje pošteno), ukupno vreme table se ne problematizuje.
      Dokumentacija: **`02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.pdf`**
      (34 strane, 24 tabele, 4 SVG dijagrama) — proširena sa Koraka 2-5 na 2-8, uz
      usklađivanje §4-§7 sa RTL-om kakav JESTE (23 stanja, post-route brojke).
      Plan i dizajn: `01 Razvoj/(C) Korak 8 - {Dizajn analize, Plan implementacije}*.md`.
      Izvršeno kroz 10 taskova; trag u `.superpowers/sdd/(C) Korak 8 .../progress.md`.
      Model propusnosti: `T = 2·img_w·img_h + 2·N + res_w·res_h·(N+112)`;
      izmereno **2.461.201 taktova = 27,07 ms** za 90×90/25×15 pri 90,909 MHz.
- [ ] Korak 9: Bitstream + bare-metal test u Vitis (port `tb.cpp` logike na realne
      registre/AXI DMA drajver) [20 bodova]
      - [x] **Task 1 (2026-08-26): bitstream.** `write_bitstream` + KAPIJA 3 (ne pravi
        bitstream ako timing ne zatvara) dodati u `run_impl.tcl`. Izmereno: DRC 0
        grešaka, `.bit` 2.083.870 B.
      - [ ] Task 2: export XSA sa bitstream-om
      - [ ] Task 3: bare-metal aplikacija u Vitisu
- [ ] Korak 10: TCL skripta za automatizaciju celog Vivado toka [10 bodova]
      (skeleton u `Vezbe/(C) Vezba 13 - Design Constraining i TCL Scripting.md`)
