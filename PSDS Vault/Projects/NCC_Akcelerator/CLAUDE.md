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

- **Postojeći model:** SystemC + TLM-2.0 (b_transport, simple/multi_passthrough
  socketi), `sc_main.cpp` pokreće `vp` (platforma) + `tb_vp` (testbench = CPU/softver)
- **Cilj: Zybo Z7-10 (Zynq-7010, `xc7z010-clg225-2`)** — PS (Cortex-A9) + PL (FPGA
  logika). **Potvrđeno** u `06 Prilozi/ESL dokumentacija (PEUSN).pdf`, ne pretpostavka.
  Ranije pominjani ZedBoard/Zynq-7020 je bio samo generički primer iz Vezbe 1
  (tutorial za sam alat), NE naš target — XC7Z010 ima znatno manje resursa (17.600 LUT
  naspram ~53.200 na XC7Z020), što direktno objašnjava zašto su iskorišćena samo 2 od
  teorijski 3 moguća NCC bloka.
- **Tok alata — POTVRĐENO (ne pretpostavka):** NCC jezgro je već implementirano i
  sintetizovano kroz **Vitis HLS 2023.1** za `xc7z010-clg225-2` (izveštaj u ESL
  dokumentaciji: period takta 7.3ns/cilj 10ns, latencija 10.360.183 ciklusa — ovo je
  TAČAN izvor `K_CYC` konstante u `ncc.cpp`). Koraci 2b/2d/2e (uklanjanje petlji, ASM
  dijagram, blok dijagram) se pišu kao **dokumentacija** (FSMD koncept), ali korak 3
  (RTL) se realno radi/nastavlja kroz **Vivado HLS** (C++ kernel + pragme →
  automatska sinteza VHDL/Verilog + IP export) — ne ručni VHDL. Dalje: Vivado
  (sinteza, block design) → Vitis (bare-metal test). Ručni RTL
  (`Vezbe/(C) Vezba 02...`, `03-05...`) ostaje rezervni plan ako HLS export ne pokrije
  interfejs kako treba.
- **Referentne brojke za poređenje (korak 8e):** videti
  `00 Pregled/(C) ESL dokumentacija - izvod.md` — resursi po instanci (5269 LUT/16
  DSP48E/3455 FF/4 BRAM_18K), 2×NCC ukupno (59.9% LUT/40% DSP/19.6% FF/6.7% BRAM),
  i ukupno vreme obrade `board2.txt`: 1 NCC=39.79s, 2 NCC=19.89s, 2 NCC+optimizacije
  **=3.667s** (10.8× ubrzanje) — ova poslednja brojka je glavna referenca za
  throughput poređenje.
- **Repo koda:** `C:\Users\pc\Desktop\PSDS\src\` (nije git repo trenutno)

## Struktura izvornog koda (src/) — referenca, ne duplirati

```
common.hpp   ← Adresna mapa (VEĆ liči na realnu Zynq PL mapu!) i registarski map NCC-a
ncc.cpp/hpp  ← AKCELERATOR: NCC² proračun, integral image (SAT), FSM procesa (ncc_proc)
bram.cpp/hpp ← Deljeni PL bafer (BRAM_Module), multi-master (CPU/DMA/NCC)
dma.cpp/hpp  ← DMA (DDR → BRAM segment), setup vreme se naplaćuje, prenos se ne
ddr.cpp/hpp  ← PS memorija (DDR), latencija se zanemaruje (nije usko grlo)
sys_bus.cpp/hpp ← Adresni dekoder/interkonekt ka PL periferijama
vp.cpp/hpp   ← Sastavlja platformu (CPU dekoder: DDR opseg vs PL opseg)
tb.cpp/hpp   ← "CPU/softver": test scenario, coarse-to-fine algoritam, FEN generisanje
sc_main.cpp  ← Top: vezuje vp + tb
```

Detaljan opis arhitekture: `00 Pregled/(C) Arhitektura sistema.md`.
Zvanična ESL/PEUSN dokumentacija (algoritam, bitska analiza, HLS izveštaj, performanse):
`00 Pregled/(C) ESL dokumentacija - izvod.md`.
Detaljan plan po koracima PDF-a: `01 Razvoj/(C) Plan implementacije (10 koraka).md`.
Beleške iz svih vežbi (Vivado, RT modeling, HLS, IP packaging, optimizacija, TCL):
`01 Razvoj/Vezbe/` — pregled i ključna odluka: `01 Razvoj/(C) Vezbe - indeks i strateska odluka.md`.

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

> **Zadnje ažuriranje:** 2026-07-20
> **Status:** Korak 1 ZAVRŠENO — HLS C++ kernel napisan i testiran (TDD, pravi
> `ap_uint`/`ap_int`/`ap_ufixed` tipovi, ne mock). Kod u `src/hls/` (`ncc_kernel.hpp`,
> `ncc_kernel.cpp`, `test_ncc_kernel.cpp`). Testbench upoređuje kernel protiv
> nezavisnog celobrojnog golden oracle-a (bez ap_int, `__int128` za tačnu Q1.31
> podelu) — svi testovi prolaze, uključujući punih 3721 tačaka na realnoj veličini
> segmenta (90×90 slika / 30×30 šablon). Detalji, dve ispravke signedness-a u odnosu
> na ESL Tabelu 2, i build komanda: `01 Razvoj/(C) Plan implementacije (10 koraka).md`
> → Korak 1.
>
> **Dodatna validacija na pravim podacima:** korisnik dostavio prave `board2.txt` +
> 12 šablona figura (`src/hls/data/data/`) — kernel na svih 64 polja table (brute-force,
> svih 12 šablona) daje **32/32 tačno prepoznatih figura**, poklapa se slovo po slovo
> sa zvaničnom golden FEN vrednošću iz ESL dokumentacije. Detalji u istom fajlu.
>
> **Korak 2 ZAVRŠEN** — puna dokumentacija (2a-2e: algoritam, uklanjanje petlji,
> interfejs, ASMD dijagram, datapath/controlpath) u
> `02 Dokumentacija/(C) Korak 2 - Opis algoritma, ASMD, datapath-controlpath.md`,
> rađena po metodologiji iz Vezbe 3-5.
>
> **Toolchain instaliran na ovoj mašini:** MSYS2/mingw-w64 g++ (`C:\Users\pc\msys64`,
> dodat u PATH korisnika) + Xilinx open-source `ap_int.h`/`ap_fixed.h` header
> biblioteka (`src/hls/ap_headers/include/`) — korišćeno za Korak 1.
> **ISPRAVKA (2026-07-20, kasnije u sesiji):** ranija tvrdnja "Vitis/Vivado NISU
> instalirani ovde" je bila POGREŠNA — provera je tražila samo `C:\Xilinx`, a
> stvarna instalacija je na `C:\AMDDesignTools\2025.2\` (AMD brend posle
> preuzimanja Xilinx-a). Tu su i **Vivado 2025.2** (`Vivado\bin\vivado.bat`,
> `xvhdl`/`xelab`/`xsim` — potvrđeno radi) i **Vitis HLS** (`Vitis\include\hls_*.h`,
> `Vitis\bin\vitis-run`). Svi dalji koraci (RTL simulacija, sinteza) mogu se raditi
> lokalno.
>
> **STRATEŠKI ZAOKRET (2026-07-20):** Korak 3 ide kroz **ručni VHDL**, NE Vitis HLS
> kako je ranije "potvrđeno". Pravilnik (`06 Prilozi/Bodovanje projekta.pdf`,
> pročitan direktno) kaže samo "modelovanje u nekom od HDL jezika na RT nivou" —
> tool-agnostic, ne zahteva HLS. Ranija "HLS potvrđeno" odluka se oslanjala na ESL
> dokumentaciju koja opisuje RANIJU FAZU PROJEKTA (PEUSN predmet), ne PSDS zahtev.
> Beleška iz same Vezbe 3-5 (pročitana još ranije, previđena pri toj odluci) kaže
> eksplicitno: "ovo je metod koji profesor očekuje da se koristi — ručni RTL iz
> ASMD dijagrama, ne HLS." Korak 2 (ASMD/datapath dijagrami) je direktan nacrt za
> ovo, ne samo dokumentacija HLS internala. Korisnik potvrdio ovaj pravac. Sledeće:
> Korak 3, ručni VHDL (`src/vhdl/`), TDD pristup (testbench sa golden vrednostima
> prvo, `xvhdl`/`xelab`/`xsim` lokalno).
>
> **Korak 3 — VHDL napisan i simulacijski proveren, sinteza potvrđena, ali NIJE
> FINALNO** (korisnik eksplicitno rekao da će se menjati sledeću sesiju).
> `ncc_core.vhd` prošao isti golden test kao Korak 1 (4×4/2×2, svih 9 tačaka
> uklj. 0x80000000). Kroz sesiju je interfejs prošao 2 velika refaktora (puni
> nizovi na portu → adresirani BRAM-stil portovi) i **3 uzastopne popravke BRAM
> inferencije** — poslednja i prava: JEDNO preostalo kombinaciono čitanje
> `sat_mem` (previđeno u prve dve popravke) je terelo ceo niz u LUT-ove (0 BRAM,
> 276% preko budžeta). Posle popravke: **16 BRAM, 6383 LUT (36%), 9 DSP** —
> potvrđeno samostalnom sintezom (`synth_design`), staje na `xc7z010clg225-2`
> sa velikom rezervom. Puna hronologija (sve 3 popravke, tačan uzrok svake):
> `01 Razvoj/(C) Plan implementacije (10 koraka).md` → Korak 3.
>
> **Pojašnjeno sa korisnikom:** krajnji interfejs biće **AXI** (AXI-Lite +
> AXI master), dolazi u Koraku 6 (pakovanje u IP) pre povezivanja sa DMA/BRAM/RAM
> u block design-u (Korak 7) — trenutni prost adresa/podatak interfejs je
> namerno privremen za RT model/simulaciju. Vivado projekt setting "Target
> language: Verilog" ne primorava naše `.vhd` fajlove — utiče samo na fajlove
> koje Vivado sam generiše.
>
> **Testbench koristi sintetički 2×2 šablon** (ne pravu figuru) — prava
> `board2.txt`/šabloni su korišćeni samo u C testu (Korak 1), ne još u VHDL-u.
>
> **⚠️ Sledeća sesija: proveriti šta je promenjeno pre nastavka** — korisnik je
> rekao da ništa od VHDL koda/testbench-a/interfejsa nije finalno.
>
> **Sledeća sesija počinje od:** Korak 2 — dokumentacija (opis algoritma, uklanjanje
> petlji, ASM dijagram, blok dijagram datapath/controlpath), nezavisno od HLS alata,
> može se raditi na bilo kojoj mašini. Korak 3 (prava HLS sinteza kroz Vitis HLS)
> ide kad korisnik bude na mašini sa instaliranim alatom.
>
> **Već urađeno/potvrđeno (treba samo "prevesti"/nastaviti):**
> - Algoritam definisan i vremenski kalibrisan (`K_CYC` u `ncc.cpp` = tačan HLS
>   izveštaj: 10.360.183 ciklusa za 90×90 sliku / 30×30 šablon, xc7z010-clg225-2)
> - Bitske širine svih signala već definisane (Tabela 2, ESL dok.) — direktan
>   `ap_uint`/`ap_int` plan za korak 1
> - Interfejs (registri + BRAM master port) već definisan i liči na AXI
> - Adresna mapa već liči na realnu Zynq PL mapu
> - Okruženje (BRAM, DMA, DDR, interkonekt) već modelovano — direktan predložak za
>   Vivado block design (korak 7)
> - Referentne brojke za korak 8e (throughput/resursi) već postoje — videti
>   `00 Pregled/(C) ESL dokumentacija - izvod.md`

## Sledeći koraci

- [x] Korak 1: Napisati HLS C++ kernel NCC-a (`ap_uint`/`ap_int`, jedna top funkcija)
- [x] Korak 2: Dokumentacija (opis algoritma, uklanjanje petlji, interfejs, ASM
      dijagram, blok dijagram datapath/controlpath) — konceptualna, nezavisna od HLS-a
- [ ] Korak 3: HLS C sinteza + pragma optimizacija (PIPELINE, ARRAY_PARTITION...)
- [ ] Korak 4: C simulacija + C/RTL kosimulacija naspram golden C rezultata
- [ ] Korak 5: Sinteza + implementacija, analiza resursa/kritične putanje/throughput-a
- [ ] Korak 6: Export RTL → IP Catalog (HLS)
- [ ] Korak 7: Integracija u block design (Zynq PS, BRAM controller, Block Memory
      Generator, DMA) — nedostaje dobar izvor u pročitanim vežbama, tražiti dodatni
- [ ] Korak 8: Analiza integrisanog sistema + poređenje sa PEUSN predviđanjima
      (odstupanje ≤ 20%)
- [ ] Korak 9: Bitstream + bare-metal test u Vitis (port `tb.cpp` logike na realne
      registre/AXI DMA drajver)
- [ ] Korak 10: TCL skripta za automatizaciju celog Vivado toka (skeleton već u
      `Vezbe/(C) Vezba 13 - Design Constraining i TCL Scripting.md`)
