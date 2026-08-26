# PSDS OS — Claude Context File

Lični sistem (Obsidian vault) posvećen isključivo predmetu **Projektovanje Složenih
Digitalnih Sistema** — konkretno projektu akceleracije NCC (Normalized Cross-Correlation)
prepoznavanja šahovskih figura na FPGA.

Ovo je poseban vault od glavnog "StefanOS" sistema (koji pokriva fakultet uopšte i
ZN_APP) — ovde Claude vodi svoje beleške SAMO o ovom projektu: arhitekturu, odluke,
napredak kroz 10 koraka bodovanja, i šta je sledeće.


## Ko sam ja i moja svrha

Student sam, apsolvent, peta godina elektrotehnike. Kodiram u C, C++ i SystemC.
Projekat: akcelerator za prepoznavanje šahovskih figura sa table (NCC template
matching), koji treba da prođe kroz ceo tok — od C algoritma, preko RTL/HDL modela,
do bitstream-a na realnoj Zynq ploči.

Izvorni SystemC/TLM model (virtuelna platforma) postoji i živi u
`C:\Users\pc\Desktop\PSDS\src\` — TO JE KOD, ne diraj ga odavde bez pitanja. Ovaj vault
je samo dokumentacija/beleške/plan, ne kopija koda.


## Claude-ova svrha na ovom nivou

- **Praćenje napretka** kroz 10 koraka bodovanja (vidi PDF u `Projects/NCC_Akcelerator/06 Prilozi/`)
- **Dokumentacija** koju projekat inače zahteva (opis algoritma, ASM dijagram, blok
  dijagram, analize posle sinteze...) — pišem je ovde pre nego što ide u finalni
  izveštaj
- **Odluke i rezonovanje** — zašto smo nešto uradili na određeni način, da se ne
  zaboravi između sesija
- **Sledeći koraci** — uvek jasno šta je sledeća konkretna stvar za uraditi

Glavna direktiva: koraci u PDF-u MORAJU ići redom (1→10). Ako sesija luta van
trenutnog koraka, vrati na pravi put: "Koji korak trenutno radimo — je li prethodni
zaista završen?"


## Claude-ova pravila i granice

- **Direktno i bez uvijanja** — reci kad nešto neće proći na odbrani, ne ulepšavaj
- **Označavaj svoje fajlove** — sve što generišem ide sa prefiksom `(C)`
- **Ne diraj postojeće beleške bez pitanja** — pitaj pre nego što menjaš nešto što je
  student napisao ručno
- **Kod ostaje u `src/`** — ovaj vault ne duplira kod, samo referenciše putanje


## Folder Struktura

```
PSDS Vault/
├── CLAUDE.md                      ← Ovde si
├── Projects/
│   └── NCC_Akcelerator/           ← Jedini projekat u ovom vault-u
│       ├── CLAUDE.md
│       ├── BUGS.md
│       ├── IDEJE.md
│       ├── (C) Sljedeća sesija.md
│       ├── 00 Pregled/            ← Arhitektura, sistem, algoritam (opis stanja)
│       ├── 01 Razvoj/             ← Plan implementacije po koracima iz PDF-a
│       ├── 02 Dokumentacija/      ← Nacrti zvanične dokumentacije (ASM, blok dijagram...)
│       └── 06 Prilozi/            ← PDF pravilnika, slike, izveštaji sa sinteze
└── Skills/
```


## Moji trenutni projekti i pregledi

### NCC_Akcelerator — `Projects/NCC_Akcelerator/`
**Status (2026-08-27): KORACI 1-9 ZAVRŠENI — 90 bodova.** Preostaje samo Korak 10.
Šahovski NCC template-matching akcelerator (coarse-to-fine, dva paralelna NCC bloka);
SystemC/TLM ESL model je referenca, a RTL se piše **ručno u VHDL-u** (`src/vhdl/`),
ne kroz HLS.

- C model (Korak 1): `src/hls/`, TDD, 32/32 figure tačno
- RTL (Korak 3): `ncc_core.vhd`, **23 stanja** (dva preseka za tajming u Koraku 8)
- Verifikacija (Korak 4): golden 4×4 + realni 90×90, bit-tačno
- Analiza (Korak 5): golo jezgro post-route 1.472 LUT, WNS **+0,146 ns na 10 ns**
- IP jezgro (Korak 6) i block design (Korak 7): `ncc_accel`, `ncc_system`
- Sistem (Korak 8): **6.225 LUT (35,4 %)**, WNS **+0,268 ns**, 90,909 MHz
- **Ploča (Korak 9): FEN tačan, 32/32 polja, 1.782 ms — 2,06× brže od ESL reference**
- Dokumentacija za profesora: `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.pdf`

⚠️ Prenosi u aplikaciji idu **procesorom, ne DMA-om** — burstovi zaglavljuju
`axi_interconnect_0`. Detalji u `Projects/NCC_Akcelerator/BUGS.md`.

Sledeće: **Korak 10** (`package_ip.tcl` + ulančavanje celog toka do XSA).
