# Skripta za odbranu

> Pročitati pre odbrane. Cilj: znati **tok rada napamet** i **brojke koje se
> pitaju prve** — ne prepričavati dokumentaciju, nju profesor već ima.

## Šta smo napravili, u jednoj rečenici

Hardverski akcelerator za NCC (normalizovanu unakrsnu korelaciju) koji
prepoznaje šahovske figure sa slike table — algoritam prvo u C-u, pa ručno u
VHDL-u (bez HLS), spakovan u AXI IP, integrisan sa Zynq procesorom na Zybo
ploči, i stvarno testiran na hardveru.

## Tok rada — 10 koraka, tim redosledom

1. **C model** algoritma (`src/hls/ncc_kernel.cpp`) — TDD, testiran protiv
   nezavisnog golden oracle-a (ceo brojevi, `__int128` za tačnu podelu).
2. **Dokumentacija algoritma** — matematika, uklanjanje petlji, ASMD dijagram,
   blok dijagram datapath/controlpath.
3. **RTL ručno u VHDL-u** (`ncc_core.vhd`) — dvoprocesni stil, iz ASMD
   dijagrama. *Zašto ručno, ne HLS:* pravilnik traži "modelovanje na RT nivou",
   tool-agnostic; Vežba 3-5 eksplicitno kaže da se očekuje ručni RTL.
4. **Verifikacija simulacijom** — golden 4×4/2×2 (ekstremi: 0 i puno
   poklapanje), pa realni 90×90 segment + 25×15 šablon, bit-tačno sa C
   kernelom.
5. **Sinteza + analiza** golog jezgra — resursi, kritična putanja, Fmax,
   propusnost. Jezgro samo **zatvara 100 MHz**.
6. **Pakovanje u AXI IP** (`ncc_accel`) — slave sa internim memorijama
   (obrazac iz Vežbe 08-09), NE master (vežba to ne pokriva).
7. **Integracija u block design** — Zynq PS + 2× `ncc_accel` + AXI CDMA + AXI
   Interconnect, sve na jednom taktu.
8. **Analiza integrisanog sistema** — resursi/timing/propusnost sistema,
   poređenje sa referentnim (HLS) rešenjem iz prethodnog predmeta.
9. **Bitstream + bare-metal na Vitisu, na stvarnoj ploči** — FEN tačan,
   32/32 polja.
10. **TCL automatizacija** celog toka (paket IP → block design → sinteza →
    implementacija → XSA), jednom komandom.

**Merodavan opis dizajna je PDF u `02 Dokumentacija/`, ne stari markdown u
`01 Razvoj/`** — markdown fajlovi po koracima su istorijski zapis procesa,
ne konačno stanje. Ako profesor pita "kako radi X", odgovor je iz PDF-a i
koda, ne iz starih beleški.

## Brojke koje treba znati napamet

| Šta | Vrednost |
|---|---|
| Ploča | Zybo (originalni), `xc7z010clg400-1` |
| Radni takt sistema | **90,909 MHz** (period 11 ns) — PLL od 50 MHz ne može tačno 95 MHz, najbliže je 1000/11 |
| Zašto ne 100 MHz | Sistem **i to zatvara** (WNS +0,032 ns) — radna tačka je ostala na 90,909 jer su sva merenja tu urađena, ne zato što 100 MHz ne radi |
| Odstupanje od 100 MHz | 9,1 % (dozvoljeno do 20 %) |
| Resursi sistema | 6.225 LUT (35,4 %), 39 BRAM (65 %), 18 DSP (22,5 %) |
| Referentno (HLS) rešenje | 10.538 LUT za dva jezgra SAMA — naš ceo sistem staje u manje od toga |
| Takt-poređenje | **2,74× manje taktova** od referentnog rešenja na istom poslu |
| Na ploči, cela tabla | 32/32 polja tačno, FEN slovo po slovo tačan, **1,782 s** |
| Naspram reference | **2,06× brže** (referenca 3,667 s) |
| Raspodela vremena na ploči | računanje 87,3 %, prenosi ~10,5 %, obrada na CPU 2,2 % |
| Slabost koju sami priznajemo | Block RAM 65 % — jedini resurs bez rezerve (32-bitna reč integralne slike, dovoljno je 21 bit) |

## Zašto smo tako odlučili — ako pitaju "zašto"

- **Signed umesto unsigned za `diff_f`/`diff_t`/`sum_num`** — piksel minus
  srednja vrednost može biti negativan. ESL dokumentacija je tu imala grešku
  (unsigned), mi smo je ispravili i to je vredno pomena.
- **Sekvencijalni delilac, ne kombinacioni** — kombinaciono deljenje je davalo
  WNS ≈ −46 ns, potpuno neupotrebljivo. Restoring delilac, hendšejk sa FSM-om.
- **Integralna slika (SAT)** — svaka suma piksela u prozoru postaje O(1)
  umesto O(N²) po poziciji.
- **Slave + interne memorije za AXI IP, ne master** — vežba pokriva samo taj
  obrazac; master bi tražio neverifikovanu logiku u bloku koji je već bio
  bit-tačan.
- **DMA postoji u dizajnu, ali se ne koristi u aplikaciji** — `axi_cdma`
  zaglavljuje na burstovima dužim od 2 beata kroz deljeni AXI interkonekt
  (izmereno preko JTAG-a, van naše logike). Prenosi idu procesorom, reč po
  reč — košta ~9-10 % vremena. Ovo je **priznata, izmerena slabost**, ne
  bag koji krijemo.
- **32-bitna reč za integralnu sliku** — dovoljno je 21 bit (max suma
  90·90·255). Nije suženo jer BRAM nije usko grlo, ali smo to naveli otvoreno.

## Dva bug-a koja smo NAŠLI i POPRAVILI (dobra priča za odbranu)

- AXI kontroleri (S00 i S01) su prihvatali podatke (`W`) i pre nego što je
  adresa (`AW`) prihvaćena — AXI protokol to dozvoljava, generisani Xilinx
  šablon to nije poštovao. Dokazano testom da 7 od 8 beat-ova upisnog bursta
  propada na starom RTL-u, popravljeno, pa ponovo dokazano da prolazi.
- Burst čitanje je vraćalo prethodnu reč na svakom beat-u posle prvog — nije
  uhvaćeno ranije jer prvi integracioni testbench koristi samo pojedinačne
  transfere (procesor to nikad ne pogodi, DMA bi pogodio svaki put).

Ako pitaju "kako ste verifikovali IP, ne samo jezgro" — ovo je odgovor:
nezavisni testbenchevi za burst slučajeve, koji prvo dokazano padaju na
starom RTL-u pa prolaze na popravljenom.

## Verovatna pitanja i kratki odgovori

**"Zašto 90,909 MHz a ne 100 MHz?"**
PLL procesorskog sistema deli ulaznih 50 MHz celim brojem; za traženih 95 MHz
najbliže ostvarivo je 1000/11 = 90,909. Sistem zatvara i 100 MHz zasebno
izmereno, ali sva merenja propusnosti su urađena na 90,909 pa je to ostala
radna tačka.

**"Šta je kritična putanja?"**
Adresna putanja unutar `ncc_core`-a (`v_reg` → adresa BRAM upisa), ne
integracija — integracija je čak malo popravila rezervu (+0,146 ns golo jezgro
→ +0,032 ns u sistemu na 10 ns).

**"Zašto RTL ručno, a ne HLS?"** — vidi tačku 3 gore.

**"Da li ste testirali na pravom hardveru ili samo simulacijom?"**
Oboje — simulacija (XSim, golden + realni podaci) je prvi nivo, pa je isti
bit-tačan rezultat dokazan i kroz AXI omotač, i na kraju na stvarnoj ploči
(JTAG program, UART čitanje FEN-a).

**"Šta biste popravili da imate više vremena?"**
Sužavanje `sat_t` sa 32 na 21 bit (BRAM 65% → ~55%), i razdvajanje AXI-Lite
kontrolnih slave-ova na zaseban interkonekt da se proveri da li burstovi
onda rade kroz CDMA.

## Ako zatraže da otvorite/pokrenete nešto uživo

- **Vivado projekat:** `src/vhdl/script/create_bd.tcl` pravi block design od
  nule; `run_impl.tcl` radi sintezu→implementaciju→bitstream→XSA sa četiri
  automatske provere (kapije) koje zaustave tok ako nešto tiho krene po zlu.
- **Simulacija jezgra:** `src/vhdl/tb/ncc_core_real_tb.vhd` — realni podaci,
  ispisuje broj taktova i peak vrednost.
- **Rezultat na ploči:** UART na COM6 (baud 115200), `uart_log.ps1` snima FEN
  ispis bez ijednog dodatnog Windows programa.

Ne ulaziti u objašnjavanje TCL skripti detaljno osim ako pitaju — dovoljno je
znati da postoje i šta svaka radi u jednoj rečenici (tabela u
`(C) PSDS_Projekat - uputstvo za build.md`).
