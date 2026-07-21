# Arhitektura sistema (SystemC/TLM model)

Referenca na `C:\Users\pc\Desktop\PSDS\src\`. Ovo je zapis stanja modela u trenutku
kad je prelazak na PSDS bodovni tok počeo (2026-07-14), da se ne izgubi kontekst
između sesija.

## Problem koji se rešava

Slika šahovske table (720×720) + 12 šablona figura (6 belih, 6 crnih) → za svako od
64 polja odrediti da li je prazno, i ako nije, koja je figura → FEN notacija pozicije.

## Softverski tok (tb.cpp — model CPU/PS strane)

1. Učitaj sliku table u DDR, šablone (i njihove 2× smanjene "coarse" verzije) u BRAM.
2. Za svako od 64 polja:
   - Proveri da li je prazno **bez DMA-a** — čitanje centralne zone (31×31) direktno
     iz DDR-a, poređenje srednje vrednosti sa pikselom u centru.
   - Ako nije prazno: DMA prebaci pun 90×90 segment DDR → BRAM.
   - Klasifikuj boju figure iz iste srednje vrednosti (prag 140) → testiraj samo 6
     šablona te boje.
   - **Stage 1 (grubi screen):** 45×45 (2× smanjeno) protiv svih 6 kandidata,
     paralelno na NCC0/NCC1 (`run_pairs`) → uzmi top-2 (`COARSE_TOPK`).
   - **Stage 2 (fina potvrda):** pun 90×90 segment protiv top-2 kandidata iz stage 1.
   - Najbolji NCC² skor → upiši figuru u `board_state[m][n]`.
3. Generiši FEN string iz `board_state`.

**Zašto coarse-to-fine:** puna NCC nad 90×90/30×30 je skupa (~10.36M ciklusa po
pozivu, videti `K_CYC` u `ncc.cpp`). Grubi 45×45 screen je 4× jeftiniji i brzo
eliminiše 4 od 6 kandidata pre nego što se pozove skupa fina potvrda.

## Akcelerator (ncc.cpp/hpp) — jezgro koje se prenosi na FPGA

**Ulazi:** slika (segment), šablon, dimenzije obe.
**Izlaz:** mapa NCC² skorova (int32, Q1.31 fixed-point) za svaku poziciju prozora.

Algoritam po pozivu:
1. Ako je CPU najavio nov segment slike (upis `REG_IMG_ADDR`) → učitaj sliku iz BRAM-a
   i izgradi **integral image / summed-area table** (jednom po segmentu, ne po
   šablonu — 6 šablona dele isti segment).
2. Učitaj šablon (uvek, menja se svaki poziv), izračunaj njegovu srednju vrednost.
3. Za svaku poziciju prozora (u,v):
   - Srednja vrednost prozora slike iz SAT-a u O(1) (4 pristupa umesto
     tmp_w×tmp_h sabiranja).
   - Prođi tmp_w×tmp_h piksela: `diff_f = pixel - f_bar`, `diff_t = tmpl - t_mean`,
     akumuliraj `sum_num`, `sum_den_f`, `sum_den_t`.
   - `NCC² = (sum_num²) / (sum_den_f × sum_den_t)`, skaliraj u Q1.31 (`× 2^31`).
4. Javi `done_ev`, CPU pročita `result_map` preko `ADDR_RESULTS`.

**Procesni model (bitno za tajming):** upis `REG_CTRL=1` samo okine `start_ev` i
odmah vrati kontrolu CPU-u (ne blokira). Sam proračun se dešava u `ncc_proc()`
(SC_THREAD) paralelno, i troši modelovano vreme kroz `wait(ciklusi*10, SC_NS)` —
ovo je model *latencije hardvera*, ne funkcija koja se izvršava na CPU-u.

**Dva bloka (ncc0, ncc1):** identična HW jedinica instancirana dvaput na različitim
adresama (`ADDR_NCC`, `ADDR_NCC1`) radi paralelizma u stage 1/2 — u RTL-u ovo je
isti IP jezgro instanciran dvaput u block design-u.

## Okruženje / infrastruktura

- **BRAM (bram.cpp):** deljeni bafer, 3 mastera (CPU, DMA, oba NCC bloka) preko
  `multi_passthrough_target_socket`. Model tajminga: 1 reč/ciklus + 1 ciklus
  latencije, 100 MHz (10 ns/ciklus). NCC **čeka** ovo vreme (kritična putanja); DMA
  ga odbacuje (preklapa se u pozadini).
- **DDR (ddr.cpp):** PS memorija, latencija se **ne** naplaćuje (nije usko grlo, brži
  clock domen).
- **DMA (dma.cpp):** kopira DDR→BRAM. Naplaćuje se samo setup (20+250+50 ns = FSM
  pokretanje + AXI komanda), sam prenos bajtova se ne naplaćuje (preklapa se sa
  korisnim poslom).
- **sys_bus.cpp / vp.cpp:** adresni dekoder — PS (CPU) bira DDR ili PL opseg; PL
  interkonekt rutira dalje ka BRAM/NCC0/NCC1/DMA po adresi.

## Zašto je ovo bitno za PSDS korake

- Adresna mapa i registarski interfejs (`common.hpp`) su **već** dizajnirani da liče
  na realnu AXI-Lite/Zynq PL mapu → korak 2c i korak 7 imaju gotov predložak.
  - REG_CTRL/REG_STATUS = start/done AXI-Lite registri
  - `i_bram` inicijator port NCC-a = AXI Master port ka BRAM Controller-u
- Timing model (K_CYC kalibracija, 100 MHz) je **već** postavljen prema
  očekivanom HLS/HW izveštaju → koraci 5b/5c/8c imaju referentnu tačku za poređenje
  (i korak 8e zahteva upravo ovo poređenje, ≤20% odstupanje).
- FSM u `ncc_proc()` (IDLE → load img → build SAT → load tmpl → compute → done) je
  skoro doslovno ASM dijagram za korak 2d.
