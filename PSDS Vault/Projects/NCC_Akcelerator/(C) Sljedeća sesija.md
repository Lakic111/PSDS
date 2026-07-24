# Sljedeća sesija

## PRVO za sledeću sesiju

> **KORACI 1-6 SU ZAVRŠENI I VERIFIKOVANI** (stanje 2026-07-24). 60 bodova
> pokriveno. Ne vraćati se na njih bez konkretnog razloga.
>
> **Sledeće je Korak 7: integracija `ncc_accel` IP-a u block design** (Zynq PS +
> AXI DMA + kontrola preko AXI-Lite). Napomena: Vežba 08-09 NE pokriva Korak 7 —
> tražiti dodatni izvor (Zynq PS blok, AXI DMA IP, adresna mapa iz `common.hpp`).
>
> **Korak 6 (gotovo):** IP `ncc_accel` spakovan (slave + interne memorije, obrazac
> matrix-multiply iz vežbe). Dizajn: `01 Razvoj/(C) Korak 6 - Dizajn AXI omotača
> (IP pakovanje).md`; plan/koraci: `(C) Korak 6 - Plan implementacije (AXI IP).md`.
> Izvori: `src/vhdl/ip/{dp_bram,mem_subsystem}.vhd`, modifikovani generisani
> kontroleri u `src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/`, TB
> `src/vhdl/tb/ncc_accel_tb.vhd` (zlatni peak PASS). `.zip` arhiva IP-a u istom
> ip_repo folderu.

**Merodavan opis dizajna** je od sada PDF dokumentacija:
`02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.pdf` (izvor: `.html` pored
njega). Markdown `(C) Korak 2 - Opis algoritma, ASMD...md` opisuje PRVOBITNI
dizajn (9 stanja, kombinaciona deljenja) i zadržan je samo kao istorija — ne
koristiti ga kao referencu za trenutni kod.

Otvorene sitnice (nijedna nije blokirajuća):

1. `sat_t` je 32-bitna, a dovoljna je **21 bita** (max suma 90·90·255 =
   2.065.500) — suženje bi spustilo BRAM sa 9 na ~6 blokova. Dokumentovano u
   PDF-u (odeljak 7.2) kao poznata rezerva.
2. Vivado projekat korisnika (`src/vhdl/result/ncc_core`) ima "Target language:
   Verilog" projektno podešavanje — nebitno za naše `.vhd` fajlove, ali vredi
   promeniti na VHDL radi doslednosti kad se doda block design wrapper
   (Korak 7) — ponuđeno korisniku, nije još urađeno.
3. Korak 7 (block design) nije dobro pokriven pročitanim vežbama (Vezba 8-9
   staje na pakovanju IP-a) — tražiti dodatni izvor kad dođe na red.

### Kako regenerisati PDF dokumentaciju

Izmeni `.html`, pa headless Edge (pandoc/LaTeX/Word NISU instalirani na ovoj
mašini; Edge jeste):

```
--headless=old --disable-gpu --no-first-run --user-data-dir=<svež temp profil>
--virtual-time-budget=12000 --no-pdf-header-footer --print-to-pdf=<temp>\out.pdf <file:// URL>
```

Dve zamke, obe potvrđene: **(a)** ciljna putanja PDF-a NE SME imati razmake —
Edge je protumači kao više URL-ova ("Multiple targets are not supported"), pa
generiši u temp folder bez razmaka i onda kopiraj; **(b)** `--print-to-pdf-no-header`
NE radi u ovoj verziji, ispravan naziv je `--no-pdf-header-footer` (inače Edge
utisne datum i lokalnu putanju do fajla u zaglavlje/podnožje).

## Istorija sesija

### 2026-07-24 — Korak 6 ZAVRŠEN (AXI IP pakovanje)
- **Odluka arhitekture (potvrđena čitanjem celog PDF-a Vežbe 08-09, str. 229–302):**
  vežba razrađuje ISKLJUČIVO obrazac *slave + interne memorije* (matrix-multiply:
  AXI-Lite slave za registre + AXI-Full slave za interne memorije A/B/C). **Nema
  master interfejsa nigde**, ni integracije u block design. Zato NCC spakovan istim
  obrascem — kao čist slave sa internim memorijama, `ncc_core` NEPROMENJEN.
  Divergencija od ESL `i_bram` master modela dokumentovana (REG_IMG_ADDR/TMP_ADDR
  postali rezervisani).
- **Napisano/verifikovano (lokalni xsim, isti tok kao Korak 3–5):**
  `src/vhdl/ip/dp_bram.vhd` (true-dual-port RAM) i `mem_subsystem.vhd` (3× dp_bram
  + adresni dekoder: region=addr(16:15), word=addr(14:2)) — oba sa unit testovima,
  PASS.
- **Wizard (korisnik, GUI):** „Create a new AXI4 peripheral" → S00 Lite (16 reg) +
  S01 Full. **Zamka:** prvo generisao Verilog (projekat bio „Target language:
  Verilog") → prebačeno na VHDL, regenerisano. **Druga zamka:** wizard „Memory Size"
  staje na 1024 B → `C_S01_AXI_ADDR_WIDTH` ručno postavljen na 17 (128 KB); u
  paketu opseg S01 = 131072.
- **Modifikacije generisanih kontrolera** (`src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/`):
  S00 — `img_w/h`, `tmp_w/h` iz slv_reg0..3, 1-taktni `start` puls na CTRL(0x30)
  bit0, sticky `done` (jer je `ncc_core.done` puls), STATUS(0x34)=busy&done. S01 —
  ADDR 17-bit, `low` literal → (others=>'0'), RDATA iz `mem_rdata_i`, adresa na
  ciklusu prihvata (poravnanje sa 1-taktnim dp_bram čitanjem). Top — prepisana
  arhitektura na direktnu instancijaciju + `mem_subsystem` + `ncc_core` + konverzije
  integer↔slv.
- **Integracioni TB `ncc_accel_tb.vhd`** (glumi CPU/DMA preko AXI): upiše dimenzije
  (Lite), sliku 90×90 + šablon 25×15 (Full, jedan piksel/reč, realni `seg90.txt`/
  `crnitop.txt` iz Koraka 4), start, poll STATUS, čita 66×76 rezultata. **PASS:
  peak `0x80000000` @ idx 956 = (u=32, v=14)** — bit-identično golom `ncc_core`
  (Korak 4). Omotač potpuno transparentan.
- **Spakovano:** File Groups merge, Compatibility=Zynq, Addressing S01=128 KB
  (zamka: „128K" ne sme u „Range Dependency" nego Range=131072), Create archive →
  Package IP. Arhiva `ip_repo/ncc_accel_1_0/xilinx.com_user_ncc_accel_1.0.zip`.

### 2026-07-22 — Zvanična dokumentacija (Koraci 2 i 5) za profesora
- Zatečeno: kod je 21.07. otišao daleko ispred beleški — `ncc_core.vhd` prerađen
  (sekvencijalni delioci + protočna petlja), dodat `ncc_core_real_tb.vhd`, i
  napisan `(C) Korak 5 - Analiza sinteze.md`, ali `CLAUDE.md`, plan fajl i ova
  beleška su i dalje tvrdili da Korak 3 "nije finalan". Sinhronizovano na kraju
  ove sesije.
- **Sve brojke nezavisno re-verifikovane u ovoj sesiji**, nisu prepisane iz
  beleški: oba testbencha ponovo pokrenuta (prolaze), `synth_design` +
  `report_timing_summary` ponovo pokrenuti sa `create_clock`. Poklapaju se sa
  onim što je 21.07. zapisano.
- Napisana **PDF dokumentacija za profesora** (25 strana) po uzoru na ESL
  dokumentaciju: `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.pdf`
  (+ `.html` izvor). Koraci 2 i 5 u jednom dokumentu, 16 tabela, 3 ručno crtana
  SVG dijagrama (ASMD sa 21 stanjem, protočnost unutrašnje petlje,
  datapath/controlpath). Mermaid nije upotrebljiv (nema interneta u headless
  renderu), pa su dijagrami pisani direktno u SVG-u.
- **Odluka korisnika:** dokumentovati dizajn KAKAV JESTE (finalnih 21 stanje), uz
  pododeljak "Evolucija dizajna" koji objašnjava odstupanja od prvobitnog dizajna
  — umesto da se čuva zastareli ASMD sa 9 stanja. Razlog: profesor pregleda kod I
  dokumentaciju zajedno, neslaganje bi bilo prvo što primeti.
- U dokument je namerno uključena i **jedna slabost**: 9 RAMB36 naspram
  referentnih 4×BRAM_18K, zbog preširoke `sat_t` reči (32 bita umesto 21).
  Bolje da profesor to pročita nego da pita.
- **Poređenje sa ESL/HLS referencom normalizovano** — sirovi brojevi nisu
  uporedivi (ESL meren na 30×30, naš na 25×15). Po taktu na piksel-operaciju:
  3.09 naspram 1.30. Izveden i potvrđen model latencije
  `T = 2·img_w·img_h + 2·N + res_w·res_h·(N+110)` (odstupanje od merenja 0.06%),
  pa ekstrapolacija na 90×90/30×30 daje 3.78 M taktova naspram 10.36 M → 2.74×.
  Ovo je gotov ulaz za Korak 8e.
- Naslovna strana: **bez ličnih imena**, samo oznaka grupe `y25-g10` — provereno
  da ni ESL PDF nema imena (počinje Sadržajem, metapodaci prazni), jedina oznaka
  je u imenu fajla.

### 2026-07-21 — Korak 3 finalizovan + Korak 4 + Korak 5 (sesija bez zapisa u ovoj beleški)
Rekonstruisano 2026-07-22 iz koda, git istorije i `(C) Korak 5 - Analiza sinteze.md`:
- `ncc_core.vhd` prerađen u finalnu verziju: dodat `seq_divider` (restoring delilac,
  W=18 i W=83) jer kombinaciona deljenja nisu zatvarala timing (WNS ≈ −46 ns), i
  unutrašnja MAC petlja pipeline-ovana (`S_L_YX_FILL/RUN/DRAIN`, 1 takt/piksel).
  FSM 11 → **21 stanje**. LUT 6383 → 1526, BRAM 16 → 9, WNS → +1.179 ns.
- Napisan `tb/ncc_core_real_tb.vhd` + izvučeni podaci `tb/seg90.txt`,
  `tb/crnitop.txt` → Korak 4 završen (peak 0x80000000 @ (32,14)).
- Napisan `02 Dokumentacija/(C) Korak 5 - Analiza sinteze.md` → Korak 5 završen.
- Napravljen git repo i prvi commit (`5759e33`, 21.07. 21:16).

### 2026-07-20 (nastavak 3) — Korak 3, prva verzija VHDL-a

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
  sesija treba da proveri stanje pre nastavka. (Bio je u pravu: sutradan je
  usledila prerada u finalnu verziju, videti zapis za 2026-07-21 iznad.)

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
