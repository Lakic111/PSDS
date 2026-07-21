# Vezba 10-12 — High-Level Synthesis (Vivado HLS)

Izvor: `06 Prilozi/Vezbe/Vezba-10-12-High-Level-Synthesis.pdf` (Glava 7 udžbenika, str. 317-418)

## Šta ova vežba pokriva

Vivado HLS alat: automatska sinteza RTL modela (VHDL/Verilog) iz algoritamskog opisa
napisanog u C/C++/SystemC/OpenCL. Tri faze rade se potpuno automatski unutar alata:
**scheduling** (u kom taktu se izvršava koja operacija), **resource allocation/binding**
(koji HW resurs izvodi koju operaciju → generiše **datapath**), **ekstrakcija upravljačke
logike** (generiše FSM → **controlpath**). Kompletan tok: C model + ograničenja (klok
perioda, uncertainty, ciljni FPGA) + opcione optimizacione direktive + C testbench →
C simulacija → C sinteza → analiza izveštaja → (iteracija sa novim "solution"-ima) →
C/RTL kosimulacija (isti C testbench, sad nad generisanim RTL-om!) → Export RTL
(IP Catalog zip / System Generator / Synthesized Checkpoint).

## Ključno pitanje: HLS ili ručni RTL za naš projekat?

**Nalaz koji menja raniju pretpostavku:** Ovo poglavlje (Glava 7) rešava **isti** primer —
"Naive" množač matrica — koji je u **Glavi 4** (RT metodologija, ručni VHDL iz
ASM/datapath-controlpath dijagrama) već urađen ručno (udžbenik eksplicitno referencira
"str. 160" iz Glave 4 kao golden rezultat za poređenje). Dakle **HLS je u ovom
udžbeniku predstavljen kao ALTERNATIVNI, automatizovani put do ISTOG cilja** (IP
jezgro), ne kao poseban predmet — isti primer se radi oba puta da se pokaže
ekvivalentnost tokova.

**Jak signal da naš projekat cilja baš na HLS tok:** komentar u `ncc.cpp` (`K_CYC`,
"≈10.360.183 ciklusa **kao u HLS izveštaju**" za 90×90/30×30) je direktna referenca na
**Performance Estimates izveštaj koji generiše baš Vivado HLS** posle C sinteze (isti
format kao slika 7.16/7.45 u ovom poglavlju: Latency min/max, Interval, Utilization
Estimates sa DSP/FF/LUT/BRAM). To znači da je neko (verovatno u ranijoj fazi ovog istog
projekta, na predmetu PEUSN) **već pustio NCC kernel kroz Vivado HLS** i dobio taj broj
ciklusa iz HLS izveštaja. Ovo je jak dokaz da je **predviđeni tok za korak 3 (RT
modeling) upravo Vivado HLS**, ne ručno pisanje VHDL-a iz ASM dijagrama.

**Preporuka:** Koristiti **hibridni pristup**:
- Koraci 2b/2d/2e (uklanjanje petlji, ASM dijagram, blok dijagram datapath/controlpath)
  rade se kao **dokumentacija** — crta se konceptualni FSMD dizajn (baš kao u ovom
  udžbeniku za Glavu 2-5), jer to PDF pravilnik eksplicitno traži kao deliverable.
- Korak 3 (RTL model) se **realno implementira kroz Vivado HLS** (C++ kernel + pragma
  direktive), jer HLS generisani VHDL/Verilog **jeste** validan "HDL model na RT nivou"
  (doslovno tako piše u ovom poglavlju) — ogromna ušteda vremena u odnosu na ručni VHDL
  za algoritam ove složenosti (integral image + ugnježdene petlje + fixed-point NCC²).
- Korak 6 (IP jezgro) je gotovo besplatan — HLS "Export RTL → IP Catalog" direktno
  produkuje zip IP jezgro spremno za Vivado IP Catalog.
- Treba samo paziti da se u dokumentaciji jasno napiše da je HLS korišćen kao alat za
  RT sintezu (transparentno), uz priloženi ASM/datapath dijagram kao objašnjenje ŠTA
  HLS interno radi za naš kernel.

## HLS koraci i pragma direktive

**Osnovna pravila C modela za HLS:**
- Sav algoritam mora biti u JEDNOJ "top" funkciji (može pozivati podfunkcije); `main()`
  (ili `sc_main()`) se NE sintetiše — služi samo kao testbench koji poziva top funkciju.
- Ne podržava: dinamičku alokaciju, OS pozive (fajlovi, vreme).
- Specijalne biblioteke: `ap_int.h`/`ap_cint.h` (proizvoljna širina bita — `ap_uint<N>`,
  bitno za naš Q1.31 fixed-point i uske brojače), `hls_math.h`, `hls_linear_algebra.h`,
  `hls_dsp.h`.

**Ključne optimizacione direktive (pune tabele 7.1/7.2/7.3/7.4/7.5 u PDF-u):**
- `PIPELINE` — protočna obrada (redukuje inicijalizacioni interval na 1 takt); primenjuje
  se rekurzivno (jedina direktiva koja se automatski širi u podfunkcije/petlje).
- `UNROLL` (factor=N ili potpuno) — razmotavanje petlje za paralelizam. **UPOZORENJE
  (potvrđeno eksperimentom u PDF-u):** razmotavanje bez podele nizova koji hrane petlju
  ne pomaže — memorijski interfejs (dvopristupni BRAM) postaje usko grlo.
- `ARRAY_PARTITION` (block/cyclic/complete) — deli niz na više BRAM-ova ili registara da
  poveća broj paralelnih pristupa. **Mora ići uz UNROLL** da bi UNROLL dao efekat.
- `ARRAY_RESHAPE`, `ARRAY_MAP` — restrukturiranje/spajanje nizova radi uštede BRAM-a.
- `LOOP_FLATTEN` (uklanja ugnježđene petlje), `LOOP_MERGE` (spaja susedne petlje) —
  smanjuju broj taktova potrošenih na ulazak/izlazak iz petlji.
- `INTERFACE` — kontroliše I/O protokol porta: `s_axilite` (AXI-Lite, za skalarne
  kontrolne registre — ovo bi bio naš REG_IMG_W/H/CTRL/STATUS), `m_axi`/`bram`/`ap_fifo`
  (za nizove — ovo bi bio naš `i_bram` port ka slici/šablonu), `ap_none`/`ap_vld` (proste
  ulazne/izlazne skalare).
- `RESOURCE` — bira konkretan HW resurs (npr. `AddSub_DSP`, `Mul_LUT`, `RAM_2P_BRAM`).
- `ALLOCATION` — ograničava broj instanci operatora (npr. max broj množača na FPGA-u).
- `LATENCY` — traži min/max kašnjenje za operaciju/petlju/region.

**Demonstrirani primer optimizacije (Naive množač matrica, direktno analogan MAC
petljama u NCC-u):** baseline 1142 ciklusa → `PIPELINE` na najdubljoj petlji → 540
ciklusa (2× DSP) → `UNROLL factor=8` BEZ podele nizova → **pogoršanje** na 589 ciklusa
(memorijsko usko grlo, dvopristupni BRAM ne može da nahrani 8 paralelnih MAC operacija)
→ `ARRAY_PARTITION` (block, factor=8) na oba ulazna niza → **344 ciklusa**, veliko
poboljšanje. Pouka: unroll bez partition je beskorisan/štetan.

## Primena na NCC algoritam — instrukcije za sebe

Kad dođe vreme za korak 3, HLS C++ kernel za `solve_single_point`/`compute_full_matrix`
bi trebalo da:
1. Top funkcija prima `image[]` (segment, do 90×90), `templ[]` (do 30×30), `img_w/h`,
   `tmp_w/h`, `f_bar` (ili integral image ako se i on prenosi/gradi u HW), vraća
   `result_map[]`.
2. `templ[]` je mali (max 900 elemenata) → kandidat za `ARRAY_PARTITION complete` ili
   `ARRAY_RESHAPE`, jer se čita u svakoj iteraciji unutrašnje petlje (y,x) za svaki
   prozor (u,v) — baš onaj memorijski bottleneck iz primera.
3. `PIPELINE` na unutrašnjoj petlji (y,x) koja računa `diff_f*diff_t`, `diff_f²`,
   `diff_t²` — ovo je MAC-teška petlja, direktno analogna primeru iz ove vežbe.
4. Koristiti `ap_uint`/`ap_int` sa tačno potrebnom širinom umesto `int`/`int64_t` iz
   trenutnog C++ koda (npr. pikseli su 8-bitni, ne treba im `uint8_t` promovisan u
   32-bitne registre unutar HLS-a — eksplicitno navesti širinu).
5. Interfejs: `REG_IMG_W/H/TMP_W/H/CTRL/STATUS` → `s_axilite` grupa; `image[]`/`templ[]`
   ulazni nizovi i `result_map[]` izlaz → `m_axi` ili `bram` (ovo se mapira na naš
   `i_bram` inicijator port iz `ncc.hpp`).
6. Integral image (`build_integral_image`) je takođe kandidat za HLS, ali pažljivo —
   ima zavisnost između iteracija (running sum), teže se pipeline-uje bez restrukture.

## Bitne stvari / zamke na koje paziti

- `main()`/`sc_main()` se ne sintetiše — testbench mora biti odvojen od top funkcije
  (za nas: postojeći SystemC `tb.cpp` NE prelazi direktno u HLS testbench, ali njegova
  logika poziva je dobar predložak za C testbench koji hrani HLS top funkciju istim
  test slikama/šablonima).
- C simulacija i C/RTL kosimulacija koriste **isti** C testbench — velika ušteda,
  iskoristiti golden vrednosti koje već postoje/mogu se generisati iz čistog C
  algoritma (korak 1) kao testbench za HLS.
- Klok "Uncertainty" margina (Solution Configuration) — bitno postaviti realno (npr.
  1.25 ns na 10 ns period kao u primeru) da estimacija ne bude preoptimistična.
- Svaka nova optimizacija → nova "solution" (solution1, solution2...) da se sačuvaju
  performanse prethodne za poređenje — ne menjati direktive unutar iste solution.
- `Export RTL → Evaluate` opcija pokreće pravu RTL sintezu (Vivado XST) za tačniju
  procenu min. periode klok signala pre pakovanja — korisno pred korak 5/6.

## Mapiranje na korake iz bodovanja

- **Korak 1** (C algoritam) — HLS C++ kernel JESTE ta C implementacija, samo napisana
  sa HLS-specifičnim tipovima (`ap_uint` itd.) od početka.
- **Korak 3** (RT modeling) — zadovoljen HLS-generisanim VHDL/Verilog izlazom.
- **Korak 4** (simulacija) — C simulacija (algoritamski nivo) + C/RTL kosimulacija
  (RTL nivo, isti testbench).
- **Korak 5** (analiza posle sinteze) — HLS Synthesis Report (Performance Estimates +
  Utilization Estimates) je prvi sloj; treba i pravu Vivado sintezu/implementaciju za
  finalne brojke (HLS estimacije nisu 100% konačne, videti "Uncertainty" napomenu).
- **Korak 6** (IP jezgro) — `Export RTL → IP Catalog` format, direktno.
- **Koraci 2b/2d/2e** (dokumentacija: uklanjanje petlji, ASM, datapath/controlpath) —
  i dalje se pišu kao konceptualni dizajn dokument, nezavisno od toga što se
  implementacija radi kroz HLS.
