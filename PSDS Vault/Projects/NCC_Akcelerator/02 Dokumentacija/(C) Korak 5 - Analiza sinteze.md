# Korak 5 — Analiza posle sinteze

Analiza sinteze **finalnog NCC jezgra** (`src/vhdl/ncc_core.vhd`): resursi,
kritična putanja/timing i latencija/throughput na ciljnoj ploči **Zybo Z7-10
(xc7z010-clg225-2)**, takt 100 MHz (period 10 ns).

## Analizirani kod

`ncc_core.vhd` je self-contained fajl sa dva design unita:
- `seq_divider` — sekvencijalni (restoring) celobrojni delilac, parametrizovan `W`,
  start/done handshake, egzaktna podela (bit-tačno kao `/`).
- `ncc_core` — NCC jezgro sa dve optimizacije:
  - **pipelined unutrašnja MAC petlja** (`S_L_YX_FILL/RUN/DRAIN`, ~1 takt/piksel):
    izdavanje adrese piksela N+1 se preklapa sa akumulacijom podatka piksela N.
  - **sekvencijalni delioci** umesto kombinacionih: `div_mean` (W=18, deljen za
    `template_mean` i `f_bar`) i `div_ncc` (W=83, `NCC² = (num_sq<<31)/den_prod`).
    Svako deljenje: pulse start → wait done → upis kvocijenta.

Potrebni fajlovi za projekat: `ncc_pkg.vhd` + `ncc_core.vhd` (bez zasebnog delioca).

## Metod

- **Sinteza/timing:** Vivado 2025.2 `synth_design` na `xc7z010clg225-2`, sa
  ograničenjem takta `create_clock -period 10.000 [get_ports clk]`, pa
  `report_utilization` + `report_timing_summary`.
  > Napomena: BEZ `create_clock` ograničenja `report_timing_summary` prijavljuje
  > `WNS = inf` (dizajn neograničen — nema šta da se analizira). Za realan broj
  > OBAVEZAN je clock constraint (XDC ili Tcl konzola).
- **Funkcija/latencija:** XSim behavioral na PRAVIM podacima — gornji-levi 90×90
  segment iz `board2.txt` (polje (0,0)) + crni top šablon 25×15
  (`Crnitoptemplate.txt`); testbench broji `busy='1'` taktove.

## Resursi (post-synth)

| Resurs | Iskorišćeno | Dostupno (xc7z010) | % |
|---|---|---|---|
| Slice LUT | 1526 | 17.600 | 8.7% |
| Slice Registers (FF) | 554 | 35.200 | 1.6% |
| DSP48E1 | 9 | 80 | 11.3% |
| Block RAM (RAMB36) | 9 | 60 | 15.0% |

Jezgro staje na ploču sa velikom rezervom — ostaje prostora i za drugi NCC blok
(cilj: 2 paralelne jedinice) i za AXI omotač/interkonekt (Korak 6/7).

## Timing / kritična putanja

| Metrika                  | Vrednost                                      |
| ------------------------ | --------------------------------------------- |
| Cilj takta               | 10.000 ns (100 MHz)                           |
| **WNS**                  | **+1.179 ns** (prolazi)                       |
| Kritična putanja (delay) | 8.670 ns (logika 6.86 ns + rutiranje 1.81 ns) |
| **Fmax**                 | ~113 MHz                                      |

Kritična putanja: `sum_num_reg → div_ncc/work_reg` — množenje `num_sq = sum_num²`
koje ulazi u NCC² delilac. **Dizajn zatvara 100 MHz sa rezervom** (može do ~113 MHz).

Ključna projektantska odluka koja ovo omogućava: sva tri deljenja (`template_mean`,
`f_bar`, `NCC²`) rade **sekvencijalno** (1 bit kvocijenta/takt), pa je putanja po
taktu jedno oduzimanje/komparacija umesto celog kombinacionog delioca. Delilac
po promenljivom deliocu je inače najskuplja operacija u datapath-u.

### Sekvencijalni delioci — standalone brojke

| Instanca | W | LUT | Taktova/deljenju | WNS@100MHz |
|---|---|---|---|---|
| `div_mean` (mean, f_bar) | 18 | ~56 | ~20 | +6.2 ns |
| `div_ncc` (NCC²) | 83 | ~220 | ~85 | +3.8 ns |

## Latencija i throughput

Izmereno na 90×90 segmentu / 25×15 šablon (rezultatska mapa 66×76 = 5016 pozicija):

| Metrika               | Vrednost              |
| --------------------- | --------------------- |
| **Latencija**         | 2.451.212 taktova     |
| Vreme/poziv @ 100 MHz | **24.5 ms**           |
| **Throughput**        | ~205k NCC² pozicija/s |

Latencija (raščlanjeno, dominira glavna petlja):
- SAT izgradnja: ~16.200 taktova (90×90 × 2)
- učitavanje šablona: ~750 (375 × 2)
- glavna petlja: 5016 prozora × ~487 taktova/prozor
  (L_U 5 + f_bar delilac ~20 + pipelined MAC ~376 + NCC² delilac ~85 + upis 1)

**Terminologija:** *latencija* = taktovi/vreme za jedan poziv; *throughput* = posao
po jedinici vremena (ovde NCC² pozicija/s). Unutrašnja MAC petlja je ~1 takt/piksel
(pipeline); deljenja (retka: 2× po prozoru + 1× po pozivu) su glavni fiksni dodatak.

## Funkcionalna verifikacija (bit-tačnost)

| Test                                       | Rezultat                                              |
| ------------------------------------------ | ----------------------------------------------------- |
| Golden 4×4 / 2×2 (`ncc_core_tb`)           | svih 9 vrednosti tačno ✓                              |
| Real 90×90 + crni top (`ncc_core_real_tb`) | peak **0x80000000 @ (u=32, v=14)** → MATCH crni top ✓ |

Rezultat je **bit-identičan** validiranom C kernelu (Korak 1). `0x80000000` = NCC² = 1.0
(savršena korelacija), na poziciji koja odgovara zvaničnom FEN-u ((0,0) = crni top).
Sekvencijalni delioci ne menjaju numerički rezultat (egzaktna celobrojna podela).

## Fajlovi

- `src/vhdl/ncc_core.vhd` — jezgro (seq_divider + pipelined ncc_core)
- `src/vhdl/ncc_pkg.vhd` — tipovi/konstante (bitske širine iz ESL Tabele 2)
- `src/vhdl/tb/ncc_core_tb.vhd` — golden 4×4
- `src/vhdl/tb/ncc_core_real_tb.vhd` — real 90×90 + brojač taktova
- `src/vhdl/tb/seg90.txt`, `crnitop.txt` — izvučeni podaci (polje (0,0) + crni top)

## Status

- [x] Sinteza (resursi): 1526 LUT / 554 FF / 9 DSP / 9 BRAM
- [x] Timing (kritična putanja): WNS +1.18 ns @ 100 MHz, Fmax ~113 MHz
- [x] Latencija/throughput: 2.451.212 taktova = 24.5 ms/poziv @ 100 MHz
- [x] Funkcionalna verifikacija: bit-tačno (golden 4×4 + real 90×90)

**Korak 5 završen 2026-07-21.** Sledeće: Korak 6 (AXI omotač / IP pakovanje).

## Re-verifikacija 2026-07-22

Sve brojke iz ovog dokumenta **nezavisno ponovljene** pre nego što su ušle u
zvaničnu PDF dokumentaciju za profesora. Poklapaju se u potpunosti:

| Provera | Rezultat |
|---|---|
| `ncc_core_tb` (golden 4×4) | 9/9 tačno |
| `ncc_core_real_tb` | `0x80000000 @ (u=32, v=14)`, latencija **2.451.212** |
| `synth_design` + `report_utilization` | 1526 LUT / 554 FF / 9 DSP / 9 RAMB36, **LUT-as-Memory 0** |
| `report_timing_summary` (sa `create_clock`) | WNS **+1.179**, WHS **+0.127**, 0 od 1445 tačaka krši |
| `report_timing` | `sum_num_reg[16]` → `div_ncc/work_reg[78]`, 8.670 ns, 12 nivoa logike |

**Dodato u PDF (nije bilo ovde):**

- **Model latencije:** `T = 2·img_w·img_h + 2·N + res_w·res_h·(N + 110)`,
  `N = tmp_w·tmp_h`. Predviđa 2.449.729 naspram izmerenih 2.451.212 →
  **odstupanje 0.06%**, pa je model upotrebljiv za ekstrapolaciju.
- **Normalizovano poređenje sa ESL/HLS referencom.** Sirovi brojevi NISU
  uporedivi (ESL meren na 30×30 / mapa 61×61, naš na 25×15 / mapa 66×76).
  Zajednička mera je takt po piksel-operaciji (`res_w·res_h·tmp_w·tmp_h`):

  | | ESL / Vitis HLS | Ovaj RT model |
  |---|---|---|
  | piksel-operacija | 3.348.900 | 1.881.000 |
  | taktova po piksel-operaciji | 3.09 | **1.30** (2.37× povoljnije) |
  | predviđeno za 90×90/30×30 | 10.360.183 (103.6 ms) | **3.776.229 (37.8 ms)** — 2.74× brže |
  | LUT / DSP / FF | 5269 / 16 / 3455 | 1526 / 9 / 554 |
  | blok-memorija | 4× BRAM_18K (72 kb) | 9× RAMB36 (324 kb) — **4.5× više** |

- **Poznata rezerva (jedina stavka gde smo lošiji):** `sat_t` je 32-bitna, a
  max suma je 90·90·255 = 2.065.500 → staje u **21 bit**. Suženje bi spustilo
  potreban kapacitet sa 265 na 174 kb, tj. na ~6 blokova. Namerno uključeno u
  dokumentaciju za profesora umesto da se prećuti.

**Zvanična dokumentacija:** `PSDS_dokumentacija_y25-g10_Korak2-5.pdf` (poglavlja
7-8 pokrivaju ovaj korak).
