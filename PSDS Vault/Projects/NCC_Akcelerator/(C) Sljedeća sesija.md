# Sljedeća sesija

## PRVO za sledeću sesiju

> **⚠️ NIŠTA OD KORAKA 3 NIJE FINALNO** — korisnik eksplicitno rekao da će se
> VHDL kod/testbench/interfejs verovatno još menjati. Proveriti stanje
> `src/vhdl/ncc_core.vhd` i `01 Razvoj/(C) Plan implementacije...` → Korak 3
> pre nego što se bilo šta pretpostavi kao gotovo.

1. Odlučiti sledeći korak: (a) proširiti VHDL testbench na pun opseg 90×90/30×30
   i/ili prave podatke (Korak 4), (b) početi AXI omotač oko `ncc_core` (Korak 6,
   AXI-Lite + AXI master, korisnik potvrdio da je to krajnji cilj), ili
   (c) Korak 5 (analiza posle sinteze — već imamo prve prave brojke, videti niže).
2. Ako se nastavi na trenutnom `ncc_core.vhd`: `sat_mem` je 32-bitna (puna
   `sat_t` širina) iako joj realno treba samo ~21-22 bita (max suma 90×90×255)
   — kandidat za suženje da BRAM iskorišćenje bude bliže referentnih 4×
   BRAM_18K iz ESL dokumentacije umesto trenutnih 16 RAMB36 (veći BRAM zbog
   preširokih reči).
3. Vivado projekat korisnika (`src/vhdl/result/ncc_core`) ima "Target language:
   Verilog" projektno podešavanje — nebitno za naše `.vhd` fajlove, ali vredi
   promeniti na VHDL radi doslednosti kad se doda block design wrapper
   (Korak 7) — ponuđeno korisniku, nije još urađeno.

## Istorija sesija (VHDL, Korak 3) — 2026-07-20 (nastavak 3)

- Korisnik odlučio (posle direktnog čitanja pravilnika) da Korak 3 ide kroz
  **ručni VHDL**, ne Vitis HLS kako je ranije "potvrđeno" — pravilnik je
  tool-agnostic, i Vezba 3-5 eksplicitno kaže da profesor to očekuje.
- Otkriveno (usput) da su Vivado 2025.2 I Vitis HLS zapravo INSTALIRANI na ovoj
  mašini, na `C:\AMDDesignTools\2025.2\` — ranija tvrdnja da nisu bila je
  greška (provera je tražila samo `C:\Xilinx`).
- Napisan `src/vhdl/ncc_pkg.vhd` + `ncc_core.vhd` (FSM+datapath, dvoprocesni
  stil) + `tb/ncc_core_tb.vhd`, TDD (testbench prvo, RED, pa GREEN) — isti
  golden test kao Korak 1 (4×4/2×2, 9 tačaka).
- Korisnik pitao da li je jednoprocesni stil OK — prepravljeno u pravi
  dvoprocesni stil (Vezba 3-5 preporuka), isti test i dalje prolazi.
- Korisnik pitao "koliko traje sinteza" — pokrenuta probna sinteza,
  **>10 min, netlist od 42045 primitiva** (puni nizovi `image_in`/`templ_in`/
  `result_out` na portu, svaki element poseban pin). Korisnik prekinuo
  (`Stop-Process` na vivado.exe), prepravljeno u adresirane BRAM-stil portove
  (adresa+podatak, sinhrono, kao pravi BRAM) — FSM 9→11 stanja.
- Korisnik otkrio (screenshot) da Vivado projekat ima "Target language:
  Verilog" — razjašnjeno da je to samo podešavanje za auto-generisane fajlove,
  ne primorava naše VHDL izvore.
- Korisnik pokrenuo pravu sintezu (svoj Vivado GUI): **0 BRAM, 48610 LUT
  (276% preko budžeta)** — uzrok: `sat_mem` čitana kombinaciono, 4 adrese
  istovremeno u `S_L_U`. Popravljeno (5 stanja `S_L_U_A..E`, sinhrono čitanje,
  izolovan `sat_ram_proc`) — korisnik ponovio sintezu, **i dalje 0 BRAM**.
  Pravi uzrok pronađen (`grep sat_mem`): JOŠ JEDNO kombinaciono čitanje u
  `S_LOAD_IMG_DATA` (SAT red iznad, tokom izgradnje SAT-a), previđeno u prvoj
  popravci. Popravljeno — potvrđeno SAMOSTALNOM sintezom (van korisnikovog
  projekta): **16 BRAM, 6383 LUT (36%), 9 DSP**, staje na pločicu sa velikom
  rezervom. Simulacija (isti golden test) nepromenjena kroz sve popravke.
- Korisnik razjasnio krajnji cilj: `ncc_core` treba da postane **funkcionalni
  IP blok povezan preko AXI protokola** sa DMA/BRAM/RAM u block integratoru —
  potvrđuje plan da AXI omotač ide u Korak 6, ne u Korak 3.
- Objašnjeno korisniku da je testbench šablon (2×2) sintetički, namerno ugrađen
  u 4×4 sliku da pokrije oba ekstrema (0 i 2³¹) — prava data (board2.txt) su
  korišćena samo u C testu (Korak 1), ne još u VHDL-u.
- **Korisnik eksplicitno rekao da ništa od ovoga nije finalno** — sledeća
  sesija treba da proveri stanje pre nastavka.

## Istorija sesija

### 2026-07-20 — Korak 1 ZAVRŠEN (TDD, prva sesija koja piše kod)
- Korisnik zatražio nastavak rada; prethodne beleške u vault-u pokazale tačno gde
  se stalo (Korak 1, sledeća sesija).
- **Toolchain instaliran na ovoj mašini** (nije postojao): MSYS2/mingw-w64 g++
  (`C:\Users\pc\msys64`, dodat u PATH korisnika) preko self-extracting arhive sa
  GitHub-a (msys2-installer nightly release). Korisnik izabrao ovu opciju eksplicitno
  (pitan preko AskUserQuestion) umesto pisanja koda bez lokalne verifikacije.
- **Xilinx open-source `ap_int.h`/`ap_fixed.h`** povučen sa
  https://github.com/Xilinx/HLS_arbitrary_Precision_Types u `src/hls/ap_headers/include/`
  — omogućava STVARNO kompajliranje sa pravim `ap_uint`/`ap_int`/`ap_ufixed`
  semantikom lokalno, bez punog Vitis HLS-a (koji ovde nije instaliran).
- Primenjen TDD (superpowers:test-driven-development skill): napisan
  `test_ncc_kernel.cpp` sa NEZAVISNIM golden oracle-om (čist int/`__int128`, bez
  ap_int) PRE kernela → potvrđen RED (link greška, funkcija ne postoji) → napisan
  `ncc_kernel.cpp`/`.hpp` → GREEN (svi testovi prošli) → prošireno sa graničnim
  slučajem (nulta varijansa) i punim opsegom 90×90/30×30 (3721 tačaka, sve tačne).
- **Otkrivena i ispravljena greška u ESL dokumentaciji (Tabela 2):** `diff_f`/
  `diff_t` i `sum_num` moraju biti SIGNED (`ap_int`, ne `ap_uint`/`sc_uint` kako
  dokument navodi) — piksel-minus-sredina i suma proizvoda mogu biti negativni.
  Broj bita (9, 27) ostaje isti, menja se samo signedness. Vredno pomena na
  odbrani/u dokumentaciji koraka 2.
- **Q1.31 podela urađena kao egzaktna celobrojna** (`(num_sq << 31) / den_prod`
  u širem `ap_uint<96>`), ne double množenje kao u originalnom `ncc.cpp` — bit-
  egzaktan izlaz. Napomena: `ncc2 > 1.0` safety clamp iz `ncc.cpp` matematički
  otpada u ovoj verziji (Cauchy-Schwarz garantuje `num_sq <= den_prod` egzaktno
  u celobrojnoj aritmetici, bez float zaokruživanja koje je taj clamp
  originalno pravdalo).
- Detalji, build komanda i puna lista fajlova:
  `01 Razvoj/(C) Plan implementacije (10 koraka).md` → Korak 1.
- Nije rađeno: unakrsna provera protiv stvarnog SystemC `ncc.cpp` izvršavanja
  (zahtevalo bi SystemC biblioteku instaliranu ovde, van obima ove sesije) —
  golden oracle u testu je nezavisna reimplementacija istog algoritma, ne
  pokretanje SystemC modela.

### 2026-07-14 (nastavak 2) — ESL/PEUSN dokumentacija pročitana, HLS odluka potvrđena
- Korisnik dostavio `ESL dokumentaccija pdf/ESL_dokumentacija_y25-g10_1-2.pdf` — zvanična
  dokumentacija SystemC/TLM virtuelne platforme sa PEUSN predmeta (prethodna faza ovog
  istog projekta). Pročitana u celosti i izdvojena u
  `00 Pregled/(C) ESL dokumentacija - izvod.md`.
- **HLS odluka POTVRĐENA eksplicitno** (ranije samo posredno nagoveštena iz Vezbe
  10-12): dokument doslovno navodi da je NCC jezgro već sintetizovano u **Vitis HLS
  2023.1** za **xc7z010-clg225-2 (Zynq-7010)**, sa latencijom 10.360.183 ciklusa
  (tačan izvor `K_CYC` konstante) i tačnim resursima (4 BRAM_18K/16 DSP48E/3455 FF/
  5269 LUT po instanci).
- **Korekcija ciljne ploče:** Zybo Z7-10, ne ZedBoard/Zynq-7020 (ispravljeno u
  CLAUDE.md i plan fajlu — ranija pretpostavka je bila zasnovana samo na Vezbi 1
  koja koristi ZedBoard kao generički tutorial primer).
- Dobijene tačne bitske širine (Tabela 2 u ESL dok.) za sve signale u NCC datapath-u —
  direktan `ap_uint`/`ap_int` plan za korak 1, upisano u plan fajl.
- Dobijene tačne referentne brojke za korak 8e: ukupno vreme obrade `board2.txt` =
  3.667s (2 NCC + optimizacije, 10.8× ubrzanje) — glavni throughput cilj za poređenje
  na realnoj ploči.
- Ova sesija i dalje NIJE pisala kod niti pokretala alate — čista priprema.

### 2026-07-14 (nastavak) — Sve vežbe pročitane i izdvojene

### 2026-07-14 (nastavak) — Sve vežbe pročitane i izdvojene
- Pročitano svih 8 laboratorijskih materijala iz `Vezbe pdf/` (paralelno, 8 fork
  agenata) i izdvojeno u `01 Razvoj/Vezbe/` — po jedan fajl po vežbi, sa konkretnim
  instrukcijama primenjenim na naš NCC projekat (ne generički sažeci).
- PDF-ovi kopirani u `06 Prilozi/Vezbe/` radi reference unutar vault-a.
- **Ključan zaokret:** čitanje Vezbe 10-12 (HLS) je pokazalo da korak 3 (RTL) verovatno
  treba da ide kroz **Vivado HLS**, ne ručni VHDL kako je prvobitno pretpostavljeno —
  `K_CYC` komentar u `ncc.cpp` je otisak HLS Performance Estimates izveštaja, znači je
  neko već pustio ovaj kernel kroz HLS u ranijoj fazi projekta. Detalji i puno
  obrazloženje: `01 Razvoj/(C) Vezbe - indeks i strateska odluka.md`. Plan i CLAUDE.md
  ažurirani da odražavaju ovo.
- Ova sesija NIJE pisala kod niti pokretala Vivado/Vitis — čisto priprema/dokumentacija
  za sledeću sesiju (po dogovoru sa korisnikom).
- Otvoreno: korak 7 (integracija u block design) nije dobro pokriven pročitanim
  vežbama (Vezba 8-9 staje na pakovanju IP-a) — treba dodatni izvor kad dođe na red.

### 2026-07-14 — Vault kreiran
- Napravljen ovaj Obsidian vault (`PSDS Vault/`), po uzoru na StefanOS/KJ OS Template
  strukturu, ali kao potpuno odvojen vault posvećen samo ovom projektu.
- Pregledan ceo `src/` (common, bram, ddr, dma, ncc, sys_bus, tb, vp, sc_main) i
  PDF pravilnika (`06 Prilozi/Bodovanje projekta.pdf`).
- Napisan pregled arhitekture (`00 Pregled/`) i plan po 10 koraka (`01 Razvoj/`).
- Zaključak: sistem je šahovski NCC template-matching akcelerator; SystemC/TLM model
  je gotov i već ima adresnu mapu/interfejs/timing kalibraciju koji liče na realan
  HW.
