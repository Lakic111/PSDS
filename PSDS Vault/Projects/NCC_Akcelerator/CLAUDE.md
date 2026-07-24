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
- **Cilj: Zybo Z7-10 (Zynq-7010, `xc7z010-clg225-2`)** — PS (Cortex-A9) + PL (FPGA
  logika). **Potvrđeno** u `06 Prilozi/ESL dokumentacija (PEUSN).pdf`, ne pretpostavka.
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
  ncc_core.vhd   ← seq_divider + ncc_core (FSM 21 stanje, dvoprocesni stil)
  tb/ncc_core_tb.vhd        ← golden 4×4/2×2
  tb/ncc_core_real_tb.vhd   ← realni 90×90 + crni top 25×15, broji takte
  tb/seg90.txt, crnitop.txt ← izvučeni realni podaci
  script/create_project.tcl, run_synth.tcl
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
| 0x34 | REG_STATUS | 0=busy, 1=done |
| 0x40 | ADDR_RESULTS | Mapa rezultata (int32 po poziciji prozora) |

PL adresni prostor: BRAM `0x4000_0000`, NCC0 `0x5000_0000`, NCC1 `0x5100_0000`,
DMA `0x6000_0000`. PS: DDR `0x0000_0000`. **Ove adrese su već projektovane da liče na
realnu Zynq GP mapu** — iskoristiti direktno u Vivado block design-u (korak 7).

## Trenutni status

> **Zadnje ažuriranje:** 2026-07-24
> **Koraci 1-6 ZAVRŠENI.** Sledeće: **Korak 7 (integracija u block design)**.

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
`src/vhdl/ncc_pkg.vhd` + `ncc_core.vhd`, dvoprocesni stil, **21 stanje**.
Sadrži i `seq_divider` (sekvencijalni restoring delilac) u istom fajlu.
Prošao kroz 3 velika refaktora — puna hronologija u plan fajlu, Korak 3.

### Korak 4 — Verifikacija (ZAVRŠENO 2026-07-21)
- `tb/ncc_core_tb.vhd` — golden 4×4/2×2, svih 9 tačaka bit-tačno (uklj. 0 i 0x80000000)
- `tb/ncc_core_real_tb.vhd` — **realni podaci**: 90×90 segment (polje a8) + crni top
  25×15, peak **0x80000000 @ (u=32, v=14)** = MATCH, bit-identično C kernelu

### Korak 5 — Analiza posle sinteze (ZAVRŠENO 2026-07-21, brojke re-verifikovane 2026-07-22)
Dokument: `02 Dokumentacija/(C) Korak 5 - Analiza sinteze.md`

| Metrika | Vrednost |
|---|---|
| Slice LUT | 1526 (8.67%) |
| Slice registri (FF) | 554 (1.57%) |
| DSP48E1 | 9 (11.25%) |
| Block RAM (RAMB36) | 9 (15.00%) |
| LUT as Memory | **0** (potvrda da je SAT stvarno u BRAM-u) |
| WNS @ 100 MHz | **+1.179 ns** (prolazi, 0 od 1445 tačaka krši) |
| WHS | +0.127 ns |
| Kritična putanja | `sum_num_reg[16]` → `div_ncc/work_reg[78]`, 8.670 ns, 12 nivoa |
| Fmax | ~113 MHz |
| Latencija (izmereno) | **2.451.212 taktova** = 24.51 ms @ 100 MHz |
| Throughput | ~204.600 pozicija/s |

**Model latencije (potvrđen merenjem, odstupanje 0.06%):**
`T = 2·img_w·img_h + 2·N + res_w·res_h·(N + 110)`, gde je `N = tmp_w·tmp_h`.
Ekstrapolacija na 90×90/30×30: **3.776.229 taktova = 37.8 ms** (ESL/HLS referenca:
10.360.183 = 103.6 ms → **2.74× brže**). Po piksel-operaciji: 1.30 vs 3.09 takta.

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
- [ ] **Korak 7: Integracija u block design [5 bodova]** ← SLEDEĆE
      Zynq PS + AXI DMA → `ncc_accel` (S01 slave) upiše segment/šablon i pročita
      rezultat; kontrola preko AXI-Lite (S00). Napomena: `Vezba 08-09` NE pokriva
      ovaj korak — tražiti dodatni izvor (Zynq PS blok, AXI DMA IP).
- [ ] Korak 8: Analiza integrisanog sistema + poređenje sa PEUSN predviđanjima
      (odstupanje ≤ 20%) [5 bodova]
- [ ] Korak 9: Bitstream + bare-metal test u Vitis (port `tb.cpp` logike na realne
      registre/AXI DMA drajver) [20 bodova]
- [ ] Korak 10: TCL skripta za automatizaciju celog Vivado toka [10 bodova]
      (skeleton u `Vezbe/(C) Vezba 13 - Design Constraining i TCL Scripting.md`)
