# Plan implementacije po 10 koraka bodovanja

Izvor: `06 Prilozi/Bodovanje projekta.pdf`. Koraci se **moraju** raditi redom.
Za prolaz treba 50 bodova (koraci 1-5). Koraci 6-10 nose dodatnih 50.

> **STANJE 2026-08-27: KORACI 1-9 ZAVRŠENI** (90 bodova).
> Sledeće i poslednje je **Korak 10** (TCL automatizacija).
> Part je `xc7z010clg400-1`; ploča je **originalni Zybo**, `board_part
> digilentinc.com:zybo:part0:2.0` (potvrđeno VGA konektorom, 2026-08-26).
> Zvanična dokumentacija: `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.pdf`.

> **⚠️ ZAOKRET 2026-07-20 (poništava belešku od 2026-07-14 ispod):** Korak 3 ide kroz
> **ručni VHDL**, NE Vivado HLS. Pravilnik (`06 Prilozi/Bodovanje projekta.pdf`,
> pročitan direktno) je tool-agnostic ("modelovanje u nekom od HDL jezika na RT
> nivou"). Ranija "HLS potvrđeno" odluka (ispod, precrtana) se oslanjala na ESL
> dokumentaciju koja opisuje RANIJU fazu projekta (PEUSN predmet), ne PSDS zahtev —
> a beleška iz same Vezbe 3-5 (pročitana još ranije, previđena) kaže eksplicitno da
> profesor očekuje ručni RTL. Korisnik potvrdio ovaj pravac. Alati (Vivado 2025.2,
> `xvhdl`/`xelab`/`xsim`) su lokalno dostupni na `C:\AMDDesignTools\2025.2\` (ranija
> tvrdnja da nisu instalirani je bila pogrešna — provera je tražila samo `C:\Xilinx`).
>
> ~~Ažurirano 2026-07-14 (POTVRĐENO, ne pretpostavka): Korak 3 (i time koraci 1/6)
> idu kroz Vivado HLS 2023.1, ne kroz ručno pisan VHDL — potvrđeno u
> `06 Prilozi/ESL dokumentacija (PEUSN).pdf`~~ — **zastarelo, videti gore.** Ciljna
> ploča ostaje **Zybo Z7-10 / Zynq-7010** (to je nezavisno od HLS-vs-VHDL odluke).
> Koraci 2b/2d/2e ostaju kao dokumentacija, sada i doslovan nacrt za VHDL (ne samo
> objašnjenje HLS internala).

## Korak 1 — C implementacija algoritma (uslov za prolaz)

Izdvojiti čist C (bez SystemC/TLM) iz `ncc.cpp`, ali pisati **direktno u HLS stilu**
(`ap_uint`/`ap_int` iz `ap_int.h`, jedna "top" funkcija koju HLS sintetiše — videti
`Vezbe/(C) Vezba 10-12 - High-Level Synthesis.md`) umesto generičkog C-a koji bi se
posle prepravljao:
- `build_integral_image` (linije 128-138)
- `calculate_template_mean` (117-123)
- `compute_full_matrix` (140-152)
- `solve_single_point` (154-193)

Ulaz: `image[]`, `templ[]`, dimenzije. Izlaz: `result_map[]` (NCC² u Q1.31).
Bez pokazivača na `sc_event`, bez `wait()` — samo funkcija koja se poziva i vraća.

**Bitske širine (TAČNE, iz ESL dokumentacije Tabela 2 — koristiti direktno, ne
generičke tipove):** piksel `sc_uint<8>`, `sum_f` `sc_uint<18>`, `f_bar`/
`template_mean` `sc_uint<8>` (zaokruženo!), `diff_f`/`diff_t` `sc_uint<9>`,
`sum_num` `sc_uint<27>`, `sum_den_f`/`sum_den_t` `sc_uint<26>`, `num_sq`/`den_prod`
`sc_uint<52>`, NCC² `sc_ufixed<32,1>` (Q1.31). Videti
`00 Pregled/(C) ESL dokumentacija - izvod.md` za punu tabelu i objašnjenje (zašto
zaokruživanje f_bar/template_mean čini ceo datapath bit-egzaktnim).

**Status: ZAVRŠENO (2026-07-20).** Kod u `src/hls/`:
- `ncc_kernel.hpp` — tipovi (`ap_uint`/`ap_int`/`ap_ufixed` iz Xilinx `ap_int.h`/
  `ap_fixed.h`) + deklaracija top funkcije `ncc_kernel()`.
- `ncc_kernel.cpp` — implementacija: `build_integral_image`, `calculate_template_mean`,
  `solve_single_point`, sve pozvano iz jedne top funkcije (HLS zahtev).
- `test_ncc_kernel.cpp` — TDD testbench sa NEZAVISNIM golden oracle-om (čista
  celobrojna aritmetika, `__int128` za tačnu Q1.31 podelu, bez ap_int) — 3 test
  grupe, sve prolaze: mali ručno proveren slučaj (4×4/2×2, 9 tačaka uklj. tačan 0
  i tačan max=2³¹), granični slučaj nulte varijanse (sum_den=0 → rezultat mora biti
  0), i **pun opseg 90×90/30×30 (stvarna veličina segmenta) — svih 3721 tačaka
  bit-tačno poklapa oracle**.
- **Dve ispravke u odnosu na Tabelu 2:** `diff_f`/`diff_t` i `sum_num` moraju biti
  **signed** (`ap_int`, ne `ap_uint`/`sc_uint` kako piše u ESL dokumentaciji) —
  piksel-minus-sredina i suma proizvoda mogu biti negativni; broj bita (9, 27)
  ostaje isti kao u dokumentu, menja se samo signedness. Obrazloženje u komentaru
  na vrhu `ncc_kernel.cpp`.
- **Q1.31 podela je egzaktna celobrojna** (`(num_sq << 31) / den_prod`), ne double
  množenje kao u `ncc.cpp` — bit-egzaktan izlaz, i `ncc2 > 1.0` safety clamp iz
  `ncc.cpp` (postojao samo zbog float zaokruživanja) ovde matematički otpada
  (Cauchy-Schwarz garantuje `num_sq <= den_prod` egzaktno u celobrojnoj aritmetici).
- **Toolchain:** MSYS2/mingw-w64 g++ instaliran lokalno (`C:\Users\pc\msys64`,
  dodat u PATH korisnika) + Xilinx-ov open-source `ap_int.h`/`ap_fixed.h`
  (`src/hls/ap_headers/include/`, sa https://github.com/Xilinx/HLS_arbitrary_Precision_Types)
  — omogućava STVARNO kompajliranje/pokretanje testova sa pravim `ap_uint`/`ap_fixed`
  semantikom bez punog Vitis HLS instalacije. Build komanda:
  `g++ -std=c++14 -O2 -I src/hls/ap_headers/include -o test.exe src/hls/ncc_kernel.cpp src/hls/test_ncc_kernel.cpp && ./test.exe`
- Sledeće: Korak 2 (dokumentacija — opis algoritma, ASM dijagram, blok dijagram)
  može ići paralelno/odmah; Korak 3 (prava HLS sinteza kroz Vitis HLS) čeka
  pristup mašini sa instaliranim alatom (ova mašina nema Vitis/Vivado).

**Dodatna validacija na PRAVIM projektnim podacima (2026-07-20, `test_real_data.cpp`):**
Korisnik dostavio prave fajlove (`src/hls/data/data/`: `board2.txt` 720×720 +
12 `*template.txt`, isti CSV format koji `tb.cpp::loadFile()` očekuje — do ove
sesije ti fajlovi fizički nisu postojali u repo-u, samo referencirani).
Napisan harness koji za svih 64 polja table pusti kernel brute-force protiv svih
12 šablona (bez coarse-to-fine/color-precheck optimizacija — namerno, radi čiste
provere tačnosti) i uporedi sa **zvaničnom golden FEN** iz ESL dokumentacije.
**Rezultat: 32/32 polja tačno prepoznato, 0 lažnih pozitiva na praznim poljima,
0 propuštenih figura — FEN se poklapa slovo po slovo.** Ovo je jača potvrda od
sintetičkih testova (Task #2-4) jer koristi stvarne slike figura, ne generisane
uzorke. Napomena: brute-force svih 12 šablona bez optimizacija traje ~2 min
(1.15+ milijardi MAC operacija) — to je očekivano i baš razlog zašto postoje
coarse-to-fine/pretklasifikacija optimizacije u `tb.cpp`/`ncc.cpp`, ne problem
sa kernelom.

## Korak 2 — Dokumentacija (uslov za prolaz)

- **2a Opis algoritma:** NCC² formula, integral image optimizacija (O(1) po
  prozoru), Q1.31 fixed-point izlaz, coarse-to-fine strategija (videti
  `00 Pregled/(C) Arhitektura sistema.md`).
- **2b Uklanjanje petlji:** ugnježdene `for` petlje (v,u u compute_full_matrix;
  y,x u solve_single_point i build_integral_image) → iterativni oblik gde brojači
  postaju registri stanja (FSMD priprema, ne HLS unroll).
- **2c Interfejs i okruženje:** registarska mapa iz `common.hpp` (već gotova, vidi
  tabelu u projektnom CLAUDE.md) + BRAM master port. Okruženje = BRAM + DMA + CPU
  (vidi `vp.cpp`).
- **2d ASM dijagram:** izvesti iz `ncc_proc()` (ncc.cpp:77-115):
  `IDLE → [ako img_dirty: LOAD_IMG → BUILD_SAT] → LOAD_TMPL → CALC_MEAN → COMPUTE
  (ugnježdena petlja v,u,y,x) → DONE → IDLE`.
- **2e Blok dijagram datapath/controlpath:**
  - Datapath: registri (w/h/adrese), memorije (image/templ/integral/result_map kao
    BRAM/FIFO portovi), ALU (sabirač/oduzimač za diff, množač za diff², akumulatori,
    delilac/komparator za NCC²)
  - Controlpath: FSM koji generiše adrese i kontroliše brojače petlji, prima status
    signale (npr. `sum_den == 0`)

**Status: ZAVRŠENO (2026-07-20).** Puni dokument:
`02 Dokumentacija/(C) Korak 2 - Opis algoritma, ASMD, datapath-controlpath.md`
— 2a (algoritam + formula + optimizacije + signed ispravka), 2b (if-goto forma,
4 brojača: y/x za SAT, v/u/y/x za korelaciju), 2c (4 RT interfejsa mapirana na
`common.hpp`), 2d (ASMD dijagram, Mermaid stateDiagram, uključuje `img_dirty`
optimizaciju iz originalnog `ncc_proc()`), 2e (datapath/controlpath blok
dijagram, Mermaid flowchart, 4 odvojene memorije, otvoreno pitanje resource
sharing za množače — ostavljeno za odluku u Koraku 3 VHDL implementaciji).
Rađeno po metodologiji iz `01 Razvoj/Vezbe/(C) Vezba 3-5 - RT Modeling.md`.

**Revizija 2026-07-22:** taj markdown opisuje PRVOBITNI dizajn (9 stanja) i sad je
istorijski zapis. Merodavna verzija Koraka 2 je PDF:
`02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.pdf`, poglavlja 2-6, gde ASMD
i datapath odgovaraju stvarnom `ncc_core.vhd` (21 stanje), uz odeljak 5.7
"Evolucija dizajna" koji objašnjava razliku.

## Korak 3 — RTL model (RT nivo, ručni VHDL)

**Realizacija: ručni VHDL** (zaokret 2026-07-20, videti napomenu na vrhu fajla),
po metodologiji iz `Vezbe/(C) Vezba 3-5 - RT Modeling.md` (dvoprocesni stil:
1 proces registri, 1 proces kombinaciona logika sa default assignments).
Direktan izvor: ASMD dijagram + datapath/registri iz
`02 Dokumentacija/(C) Korak 2 - Opis algoritma, ASMD, datapath-controlpath.md`.

> **Opis ispod (v1) je istorijski.** Finalno stanje je na kraju ovog odeljka.

Fajlovi (`src/vhdl/`): `ncc_pkg.vhd` (tipovi/konstante), `ncc_core.vhd` — **pravi
dvoprocesni stil** (Vezba 3-5 preporuka, videti ispravku 2026-07-20 ispod): Proces 1
= samo registri (`_reg <= _next`), Proces 2 = sva kombinaciona logika (default
assignments prvo, `case state_reg`). Memorije (`sat_mem`, `result_r`) su izuzetak
od pune "_next" kopije niza — Proces 2 im računa samo `wr_en/wr_addr/wr_data`, upis
radi Proces 1 (standardni BRAM-inference obrazac, ne odstupanje od principa).
9 stanja iz 2d, jedan MAC/piksel po taktu.

**Namerna pojednostavljenja za v1 (dokumentovano u fajlu):** `image_in`/
`templ_in`/`result_out` su puni nizovi na portu (BRAM master protokol dolazi u
Koraku 7), nema `img_dirty` keširanja (kao ni Korak 1 kernel), `sat_mem` čitanje
je zero-latency (realan 1-takt BRAM port je Korak 5 refinement).

Alati lokalno dostupni: `C:\AMDDesignTools\2025.2\Vivado\bin\`
(`xvhdl`, `xelab`, `xsim`, `vivado.bat`) — ranija tvrdnja da nisu instalirani je
bila pogrešna (proverено samo `C:\Xilinx`, stvarna putanja je AMD brend).

**Status: ZAVRŠENO (2026-07-20).** TDD: testbench prvo (RED — `ncc_core` ne
postoji, `xvhdl` javlja tačno tu grešku), pa VHDL implementacija (GREEN — svih
9 golden vrednosti iz Koraka 1 se poklapa, uključujući tačan 0 i tačan
maksimum 0x80000000). Build komanda:
```
export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
cd src/vhdl && mkdir -p work_sim && cd work_sim
xvhdl -2008 ../ncc_pkg.vhd ../ncc_core.vhd ../tb/ncc_core_tb.vhd
xelab -debug typical ncc_core_tb -s ncc_core_tb_sim
xsim ncc_core_tb_sim -runall
```

**Ispravka 2026-07-20 (isti dan, kasnije):** prva verzija je koristila JEDAN sinhroni
proces (memorije nisu lepo pristajale u dvoprocesni "_next" sablon). Korisnik pitao
da li je to dobar pristup s obzirom da Vezba 3-5 eksplicitno preporučuje dvoprocesni
stil za NCC — prepravljeno u pravi dvoprocesni stil (memorije rešene preko
`wr_en/wr_addr/wr_data` signala koje računa Proces 2, upis radi Proces 1). Isti
test i dalje prolazi identično (865 ns, svih 9 tačaka) — refaktor nije promenio
ponašanje, samo strukturu koda.

**Ispravka #2 2026-07-20 (v2 interfejs — pravi BRAM-stil portovi):** prva verzija
je imala `image_in`/`templ_in`/`result_out` kao PUNE nizove na portu (8100+900+8100
elemenata). Probna sinteza (`synth_1`, xc7z010clg225-2) je pokazala da je ovo
skupo: >10 min samo za synth fazu, netlist od **42045 primitiva** (stotine
upozorenja "asynchronous reset at DSP/BRAM block boundary"), jer je svaki
element bio poseban ulazni/izlazni pin umesto da ide kroz adresirani port.
Korisnik odlučio da se ovo reši odmah (prekinuta probna sinteza, `Stop-Process`
na vivado/parallel_synth_helper). **Prepravljeno u prave adresirane BRAM-stil
portove** (`img_addr_o`/`img_data_i`, `templ_addr_o`/`templ_data_i`,
`result_addr_o`/`result_data_o`/`result_wr_o`) — sinhrono citanje sa 1-taktnim
kasnjenjem (adresa ovaj takt, podatak sledeci, pravilo iz Vezbe 3-5), FSM
prosiren sa 9 na 11 stanja (`_ADDR`/`_DATA` parovi za LOAD_IMG/LOAD_TMPL/L_YX).
Testbench sada simulira 3 spoljne sinhrone memorije (`image_mem`/`templ_mem`/
`result_mem`) kao "pravi BRAM" umesto direktnih nizova na portu. Isti golden
test i dalje prolazi (sad 1425 ns umesto 865 ns — očekivano, dodatni ADDR/DATA
ciklusi po pristupu). `sat_mem` OSTAJE interna memorija (nije spoljni port —
to je namerno, videti 2e: to je "jedina memorija kojoj treba sopstveni privatni
port"). Projekat (`src/vhdl/result/`) resetovan i ponovo kreiran za novi
interfejs — sledeca sinteza treba da bude mnogo brza/manja.

**Ispravka #3 2026-07-20 (BRAM inferencija — dva odvojena bug-a, uzastopno):**
korisnik pokrenuo pravu sintezu na svom otvorenom Vivado-u (GUI, `xc7z010clg225-2`):
prvi pokušaj (posle Ispravke #2) → **0 BRAM, 48610 LUT (276% preko budžeta)**.
Uzrok: `sat_mem` se u stanju `S_L_U` čitala **kombinaciono, 4 različite adrese
istovremeno** (SAT formula `+A-B-C+D`) — pravi BRAM ima max 1-2 porta, pa je
Vivado napravio distribuirani RAM od LUT-ova.
- **Popravka 3a:** `S_L_U` razbijeno u 5 stanja (`S_L_U_A..E`), citanje sinhrono
  (adresa ovaj takt → podatak sledeci, isti obrazac kao `image_data_i`), plus
  `sat_mem` citanje/upis izolovano u **sopstveni** proces (`sat_ram_proc`) jer
  mešanje sa desetinama drugih registara u istom procesu sprečava Vivado-ov
  BRAM inference pattern matcher. Rezultat posle ovoga: bolje (23131 LUT, 14040
  LUT-kao-RAM) ali **i dalje 0 BRAM** — korisnik ponovio sintezu, isti nalaz.
- **Popravka 3b (pravi uzrok):** u `S_LOAD_IMG_DATA` je ostalo JOŠ JEDNO
  kombinaciono čitanje, previđeno u 3a: `sat_wr_data <= sat_mem(y_reg*SAT_W+
  (x_reg+1)) + new_row_sum` (čitanje SAT reda iznad, tokom izgradnje SAT-a).
  Jedno jedino preostalo asinhrono čitanje je bilo dovoljno da natera Vivado da
  ceo niz (8281×32bit) tretira kao ne-BRAM-abilan i pretvori GA CELOG u LUT-ove.
  Popravljeno: ta adresa se sad postavlja preko `sat_rd_addr` u `S_LOAD_IMG_ADDR`
  (zajedno sa `img_addr_o`), pa je `sat_rd_data` već validan sledećeg takta u
  `S_LOAD_IMG_DATA` — nijedno preostalo direktno `sat_mem(...)` čitanje van
  `sat_ram_proc`.
- **Rezultat (potvrđeno samostalnom sintezom, `synth_design -top ncc_core
  -part xc7z010clg225-2`, van korisnikovog projekta da se ne remeti):
  Block RAM Tile 16 (26.7%), LUT-as-Memory 0, Slice LUTs 6383 (36.27%, dole sa
  131%), DSP48E1 9, Slice Registers 282.** Staje na pločicu sa velikom rezervom.
  Simulacija (isti golden test) i dalje prolazi nepromenjeno (1795 ns, svih 9
  tačaka) kroz sve tri popravke — nijedna nije menjala funkcionalno ponašanje,
  samo sintetibilnost.
- **Pouka (vredna za odbranu/dokumentaciju):** i JEDNO kombinaciono čitanje
  velike memorije van namenskog "RAM procesa" dovoljno je da onemogući BRAM
  inferenciju za CEO niz — ne postoji "delimično" BRAM mapiranje. Pravilo:
  sva čitanja/pisanja jedne logičke memorije treba da budu u jednom, izolovanom,
  potpuno sinhronom procesu.

**Napomena o interfejsu (razjašnjeno sa korisnikom):** trenutni `img_addr_o`/
`templ_addr_o`/`result_addr_o` prost adresa+podatak interfejs je NAMERNO
privremen za Korak 3/4 (RT model + simulacija). Krajnji cilj je **AXI**
(AXI-Lite slave za komandne/statusne registre, AXI master port ka BRAM-u) —
to dolazi u **Koraku 6** (pakovanje u IP) kad se `ncc_core` omota AXI
interfejsom pre povezivanja sa DMA/BRAM/RAM u block design-u (Korak 7).
Vivado-ovo Project Setting "Target language: Verilog" (video se na screenshot-u
Project Summary-ja) je NEVEZANO za ovo — utiče samo na fajlove koje Vivado sam
generiše (npr. block design wrapper), ne primorava naše ručno pisane `.vhd`
fajlove da budu Verilog.

**Ispravka #4 2026-07-21 (v_final — sekvencijalni delioci + protočna petlja):**
posle sinteze iz Ispravke #3 dizajn je stao na ploču ali NIJE zatvarao timing —
kombinaciona deljenja (`template_mean`, `f_bar`, `NCC²`) su davala WNS oko
**−46 ns** pri periodu 10 ns. Uvedena su dva sekvencijalna (restoring) delioca
(`seq_divider`, u istom fajlu): `div_mean` (W=18, deljen za `template_mean` i
`f_bar`) i `div_ncc` (W=83). Istovremeno je unutrašnja MAC petlja
**pipeline-ovana** (`S_L_YX_FILL/RUN/DRAIN`): adresa piksela N+1 se izdaje u
istom taktu u kome se akumulira podatak piksela N → **1 takt/piksel** umesto 2.
FSM narastao na **21 stanje**. Rezultat: WNS **+1.179 ns** (prolazi), LUT pao sa
6383 na **1526**, BRAM sa 16 na **9**. Golden test nepromenjen.

**FINALNO STANJE KORAKA 3 (2026-07-21):** `ncc_pkg.vhd` + `ncc_core.vhd`
(self-contained: `seq_divider` + `ncc_core`), 21 stanje, dvoprocesni stil +
izolovan `sat_ram_proc`. Merodavan opis dizajna je PDF dokumentacija
(`02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.pdf`, poglavlja 2-6) —
markdown `(C) Korak 2 ...md` opisuje PRVOBITNI dizajn i zadržan je kao istorija.

## Korak 4 — Simulacija/verifikacija RTL-a

VHDL testbench (`src/vhdl/tb/ncc_core_tb.vhd`) — isti golden slučaj kao Korak 1
(4×4/2×2 iz `test_ncc_kernel.cpp`, ručno proveren + nezavisno potvrđen), obrazac
clk_gen/stim_gen iz Vezbe 3-5. Šablon u ovom testu je **sintetički 2×2 uzorak
namerno ugrađen u 4×4 sliku** (na poziciji u=1,v=1 — daje tačan NCC²=1.0), NE
prava figura — bira se ovako baš zato da pokrije oba ekstrema (tačna 0 i tačan
maksimum 2³¹) i da se svaka vrednost može proveriti ručno. Prave šablone/tablu
(`board2.txt` + 12 `*template.txt`) smo koristili SAMO u C testu (Korak 1,
`test_real_data.cpp`, 32/32 tačno) — u VHDL-u to još nije urađeno.

**Proširenje na prave podatke (2026-07-21):** napisan
`src/vhdl/tb/ncc_core_real_tb.vhd` — čita realni **90×90 segment** (gornje-levo
polje a8 iz `board2.txt`) i **crni top 25×15** (`Crnitoptemplate.txt`) kroz VHDL
`textio` iz `tb/seg90.txt` i `tb/crnitop.txt` (jedan piksel po liniji, row-major,
izvučeno iz `src/hls/data/data/`). Testbench modeluje 3 sinhrone spoljne memorije
(1-takt kašnjenje), broji `busy` takte (latencija) i pretražuje mapu rezultata
66×76 tražeći maksimum.

**Rezultat:** peak **0x80000000 @ (u=32, v=14)** — bit-identično C kernelu iz
Koraka 1, iznad praga 0.5625 (`0x48000000`), i položaj odgovara zvaničnom FEN-u
(polje a8 = crni top `r`). Latencija: **2.451.212 taktova**.

**Status: ZAVRŠENO (2026-07-21).** Oba testbencha prolaze:

| Test | Podaci | Rezultat |
|---|---|---|
| `ncc_core_tb` | sintetički 4×4 / 2×2 | 9/9 tačaka bit-tačno (uklj. 0 i 0x80000000) |
| `ncc_core_real_tb` | realni 90×90 + crni top 25×15 | peak 0x80000000 @ (32,14) ✓ |

Komande (re-verifikovano 2026-07-22):
```
export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
xvhdl -2008 ncc_pkg.vhd ncc_core.vhd tb/ncc_core_tb.vhd tb/ncc_core_real_tb.vhd
xelab -debug typical ncc_core_tb      -s tb_small && xsim tb_small -runall
xelab -debug typical ncc_core_real_tb -s tb_real  && xsim tb_real  -runall
```

## Korak 5 — Analiza posle sinteze/implementacije (uslov za prolaz, granica 50 bodova)

- 5a Utrošeni resursi
- 5b Kritična putanja / max frekvencija
- 5c Throughput / latency
- 5d Proširiti dokumentaciju sa ovim rezultatima

**Referentne brojke (POTVRĐENE, iz ESL dokumentacije — ne procena):** period takta
7.3ns procenjen (cilj 10ns/100MHz), latencija 10.360.183 ciklusa = 0.1036s po pozivu,
resursi po instanci NCC-a: **4× BRAM_18K, 16× DSP48E, 3455 FF, 5269 LUT** (na
xc7z010-clg225-2). Videti `00 Pregled/(C) ESL dokumentacija - izvod.md` za pune
tabele. **Napomena:** te brojke su iz DRUGOG toka alata (Vitis HLS) i iz ranije faze
projekta — koriste se kao referenca za poređenje, ne kao cilj koji treba pogoditi.

**Status: ZAVRŠENO (2026-07-21, brojke nezavisno re-verifikovane 2026-07-22).**
Puna analiza: `02 Dokumentacija/(C) Korak 5 - Analiza sinteze.md` i poglavlja 7-8
PDF dokumentacije.

> **⚠️ SVE BROJKE ISPOD SU POVUČENE (re-merene 2026-07-26).** Bile su post-sintezne, na
> partu `clg225-2`, na RTL-u **pre** dva preseka iz Koraka 8b. Aktuelne post-route brojke
> na `clg400-1` su u `CLAUDE.md` (odeljak Korak 5) i u poglavlju 7 PDF-a. Ključne razlike:
> 1472 LUT / 664 FF, WNS **+0.146 ns @ 10 ns**, **Fmax ~101.5 MHz** (jezgro zatvara
> 100 MHz), latencija **2.461.201 taktova**, model `N + 112`, po piksel-operaciji
> **1.13** (ne 1.30 — ta je sa 25×15 i ne ide uz ESL-ovih 3.09).
> Zapis ispod se zadržava kao istorija.

- ~~**5a Resursi:** 1526 LUT (8.67%), 554 FF (1.57%)~~, 9 DSP48E1 (11.25%),
  9 RAMB36 (15.00%), **LUT-as-Memory = 0** (ovo dvoje nepromenjeno)
- ~~**5b Kritična putanja:** WNS +1.179 ns @ 10 ns (0 od 1445 tačaka krši),
  WHS +0.127 ns, putanja `sum_num_reg[16]` → `div_ncc/work_reg[78]`,
  8.670 ns (logika 6.860 / rutiranje 1.810), 12 nivoa logike → Fmax ~113 MHz~~
- ~~**5c Latencija/throughput:** 2.451.212 taktova = 24.51 ms @ 100 MHz na
  90×90/25×15 (5016 pozicija) → ~204.600 pozicija/s, 1.30 takta po
  piksel-operaciji~~ (ESL/HLS referenca: 3.09)
- **5d Dokumentacija:** PDF za profesora, poglavlje 7 (prošireno u Koraku 8)

~~**Model latencije:** `T = 2·img_w·img_h + 2·N + res_w·res_h·(N + 110)`.
Ekstrapolacija na 90×90/30×30 = 3.776.229 taktova (37.8 ms)~~ → aktuelno:
`N + 112`, ekstrapolacija **3.783.652 takta** naspram ESL/HLS 10.360.183 →
**2.74× manje taktova**. Ovo je ulaz za korak 8e.

**Metodološka zamka:** bez `create_clock -period 10.000` izveštaj
`report_timing_summary` javlja `WNS = inf` (dizajn neograničen). Clock constraint
je OBAVEZAN da bi brojke imale značenje.

**Poznata rezerva:** `sat_t` je 32-bitna, dovoljna je 21 bita (max 90·90·255 =
2.065.500) → BRAM bi pao sa 9 na ~6 blokova. Dokumentovano, nije urađeno.

---
--- Sve iznad je uslov za prolazak (50 bodova) ---

## Korak 6 — Pakovanje u IP jezgro [10 bodova]

**Realizacija: ručni Package IP wizard** (zaokret 2026-07-20 — Korak 3 ide kroz
VHDL, ne HLS, pa "Export RTL → IP Catalog" opcija ne važi) — po uputstvima iz
`Vezbe/(C) Vezba 08-09 - IP Packaging.md`, pakuje se `ncc_core.vhd` (+ `ncc_pkg.vhd`)
iz Koraka 3.

**Status: ZAVRŠENO (2026-07-24).** IP `ncc_accel` = AXI-Lite slave (S00, kontrola)
+ AXI-Full slave (S01, interne memorije slika/šablon/rezultat) + `ncc_core`
(nepromenjen). **Slave + interne memorije** (obrazac matrix-multiply iz Vežbe
08-09 — vežba master NE pokriva). Integracioni TB `src/vhdl/tb/ncc_accel_tb.vhd`:
zlatni peak `0x80000000 @ (32,14)` kroz AXI, bit-identično Koraku 4. Spakovano u
katalog + `.zip`, S01 opseg 128 KB. Detalji: `(C) Korak 6 - Dizajn AXI omotača
(IP pakovanje).md` i `(C) Korak 6 - Plan implementacije (AXI IP).md`.

Šta je urađeno (istorijski, prvobitni plan bio je):
1. **AXI-Lite slave** omotač za komandne/statusne registre po mapi iz Tabele 3
   dokumentacije (`REG_IMG_W/H`, `REG_TMP_W/H`, `REG_IMG_ADDR`, `REG_TMP_ADDR`,
   `REG_CTRL`, `REG_STATUS`) — trenutno su to obični ulazi `img_w/h`, `tmp_w/h`
   i `start`/`busy`/`done` na portu `ncc_core`.
2. **AXI master** (ili AXI-Stream/BRAM port, odlučiti) za `img_addr_o`/`img_data_i`,
   `templ_addr_o`/`templ_data_i` i `result_addr_o`/`result_data_o`/`result_wr_o`.
   Trenutni interfejs je namerno prost adresa+podatak sa 1-taktnim kašnjenjem —
   to je tačno ponašanje BRAM porta, pa mapiranje treba da bude direktno.
3. Package IP wizard → IP Catalog, pa provera da se IP uredno instancira.

**Ne dirati `ncc_core` iznutra** — verifikovan je i sintetizovan (Koraci 4-5);
omotač ide okolo. Ako se `ncc_core` ipak menja, oba testbencha moraju ponovo proći.

## Korak 7 — Integracija u block design [5 bodova]

**Status: ZAVRŠENO (2026-07-25).** Block design `ncc_system`, izgrađen skriptom
`src/vhdl/script/create_bd.tcl` (batch Vivado, temelj za Korak 10):

- **Zynq PS** (`processing_system7:5.5`, board preset `zybo-z7-10`), `FCLK_CLK0` = 100 MHz,
  `M_AXI_GP0` + `S_AXI_HP0` uključeni, `FIXED_IO`/`DDR` na pinove.
- **`proc_sys_reset:5.0`** → `peripheral_aresetn` na sve.
- **2× `ncc_accel:1.0`** (IP iz Koraka 6, iz `src/vhdl_NCC_IP/ip_repo`).
- **`axi_cdma:4.1`** — mem-na-mem, `C_INCLUDE_SG=0`, `C_INCLUDE_DRE=0`, 32-bit,
  `MAX_BURST_LEN=256`. Podatkovni put DDR ⇄ CDMA ⇄ `ncc.S01`; kontrolni CPU → `ncc.S00`.
- **1× `smartconnect:1.0`**, `NUM_SI=2` / `NUM_MI=6`. Jedan interkonekt a ne dva jer AXI
  slave interfejs može biti povezan na samo jedan, a `ncc.S01` treba i PS-u i CDMA-u.
- Fiksna adresna mapa po ESL `common.hpp` (tabela u projektnom `CLAUDE.md`),
  po-master vidljivost: CDMA ne vidi kontrolne registre, PS ne rutira ka DDR-u kroz PL.
- `validate_bd_design` čist; `ncc_system_wrapper` generisan i prošao RTL elaboraciju.

**Odstupanje od ESL modela:** nema Block Memory Generator-a ni BRAM Controller-a — IP je
čist slave sa internim memorijama (obrazac iz Vežbe 08-09), pa deljeni BRAM ne postoji.
Pravilnik te komponente nabraja kao primer („…"), ne kao obavezu.

**Usput popravljen bug u IP-u iz Koraka 6:** S01 burst čitanje je vraćalo prethodnu reč
na svakom beat-u posle prvog (7/8 pogrešno na `arlen=7`) — nije bilo pokriveno jer
`ncc_accel_tb` koristi samo single-beat. Videti `BUGS.md`; test
`src/vhdl/tb/ncc_accel_burst_tb.vhd`.

**Part promenjen na `xc7z010clg400-1`** (bilo `clg225-2`) — videti dizajn §7.1.

Detalji: `(C) Korak 7 - Dizajn integracije (block design).md` i
`(C) Korak 7 - Plan implementacije (block design).md`.

## Korak 8 — Analiza integrisanog sistema [5 bodova]

**Status: ZAVRŠENO (2026-07-26).** 8a-8e svi urađeni; PDF proširen na Korake 2-8.
Brojke ispod su re-merene posle popravki AXI upisnog puta iz Koraka 9 (2026-08-27):
**LUT 6.225 (35,37 %), FF 5.020, WNS +0,268 ns.**

Reproducibilno iz `src/vhdl/script/run_impl.tcl` (post-route + phys_opt,
`xc7z010clg400-1`).

### 8a — Resursi (izmereno)

| Resurs | Iskorišćeno | Kapacitet | % | ESL referenca (2×NCC sam) |
|---|---|---|---|---|
| Slice LUT | 6.261 | 17.600 | **35,6%** | 10.538 (59,9%) |
| Slice Registers | 5.024 | 35.200 | 14,3% | 6.910 (19,6%) |
| Block RAM Tile | 39 | 60 | **65,0%** | 8 BRAM_18K (6,7%) |
| DSP48E1 | 18 | 80 | 22,5% | 32 (40%) |

Po instanci: `ncc0`/`ncc1` po 1.910 LUT / 1.240 FF / 19 RAMB36 / 9 DSP;
`axi_interconnect_0` 1.616 LUT; `axi_cdma_0` 807 LUT.
**Ceo naš sistem staje u manje LUT-ova nego ESL-ova dva NCC bloka sama.** Slabiji smo
samo na BRAM-u — poznata posledica 32-bitnog `sat_t` (dovoljna 21).

### 8b — Kritična putanja i Fmax (izmereno)

**WNS +0,170 ns na 11,0 ns → timing ZATVARA na 90,909 MHz.** Fmax ~97,7 MHz.
Kritična putanja: `ncc1/core_inst/y_reg[0] → ncc1/ms_inst/img_mem/ADDRBWRADDR[13]`,
9,904 ns (logika 3,629 / rutiranje 6,275) — kombinaciono računanje adrese
`(v+y)·img_w + (u+x)` do adresnog ulaza BRAM-a.

100 MHz ne zatvara (−0,232 ns). Odstupanje 90,909 od 100 MHz je **9,1%** — u granici.
Da bi i ovoliko zatvorilo, trebalo je: MAC pipeline i registar pred delilac u
`ncc_core` (FSM 21→23, latencija +0,41%), SmartConnect→AXI Interconnect, `S_AXI_HP0`
na 32 bita, i `phys_opt_design`. Puna hronologija u `BUGS.md`.

### 8c — Propusnost i latencija (preostaje)

Model latencije re-izveden posle preseka:
`T = 2·img_w·img_h + 2·N + res_w·res_h·(N + 112)`, `N = tmp_w·tmp_h` (bilo `N + 110`).
Izmereno 90×90/25×15: **2.461.201 taktova = 27,07 ms** @ 90,909 MHz.
Ekstrapolacija 90×90/30×30: **3.783.652 takta = 41,6 ms** (ESL/HLS: 10.360.183 = 103,6 ms).

### 8d — Dokumentacija (preostaje)

Proširiti PDF poglavljem o integrisanom sistemu.

### 8e — Poređenje sa PEUSN (preostaje, traži metodološku odluku)

Referenca: `board2.txt` = **3.667 s** (2 NCC + optimizacije). Frekvencija je u granici
(9,1%), ali throughput neće biti: sa optimizacijama izlazimo na ~1,7 s → ~54% **u našu
korist**. **Ne zasporavati veštački** — rekalibrisati `K_CYC` (`src/ncc.cpp:83`) našim
izmerenim modelom i porediti sistemski model sa HW-om; razlika prema originalnoj ESL
brojci se objašnjava time što je naš RTL 2,74× efikasniji po piksel-operaciji.

## Korak 9 — Bitstream + Vitis bare-metal test [20 bodova]

Port `tb_vp::test()` (tb.cpp) logike u bare-metal C aplikaciju: isti tok (učitavanje
slike, 8×8 petlja, provera praznog polja, coarse/fine NCC, FEN generisanje), ali
`Xil_Out32`/`Xil_In32` (ili volatile pokazivači) umesto TLM `b_transport`, i pravi
AXI DMA drajver umesto `dma.cpp` modela.

**Status: ZAVRŠENO (2026-08-27).** Aplikacija u `src/vitis/app/`, skripte u
`src/vitis/scripts/`. Pet faza dovođenja u pogon, svaka potvrđena na ploči:
AXI-Lite → S01 memorije → jezgro računa (`0x80000000 @ 956`) → prenosi → pun tok.

**FEN sa ploče je znak po znak identičan zvaničnom**,
`rnbqkbnr/pp5p/4ppp1/2pp4/5P2/1P1BPN2/P1PPQ1PP/RNB1K2R`, 32/32 polja, **1.782 ms**.
Raspodela: računanje 1.555 ms (87,3 %), upis u S01 120 ms, čitanje rezultata 67 ms,
procesor 40 ms. Naspram ESL reference (3,667 s) **2,06× brže**.

⚠️ Prenosi idu **procesorom** (`NCC_USE_CDMA 0`) — burstovi duži od dva beata
zaglavljuju `axi_interconnect_0`. Košta ~9 %; DMA ostaje u block designu. `BUGS.md`.

Usput nađena i popravljena **dva bug-a u IP-u** koja su preživela Korake 6-8: S00 i S01
AXI upisni put visili su kad `W` stigne pre `AW`. Novi TB-ovi `ncc_accel_wfirst_tb` i
`ncc_accel_s01_burst_wfirst_tb` to pokrivaju i dokazano padaju na starom RTL-u.

## Korak 10 — TCL skripta za automatizaciju [10 bodova]

Batch Vivado tok: package IP → block design → synth → impl → export .xsa.

**Status:** nije započeto.
