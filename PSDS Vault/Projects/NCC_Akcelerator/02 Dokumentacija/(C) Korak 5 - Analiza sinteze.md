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
