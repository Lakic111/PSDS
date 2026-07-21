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
**Status:** SystemC/TLM model sistema gotov i proveren (šahovski NCC template-matching
akcelerator, coarse-to-fine, dva paralelna NCC bloka). Predmet implementacije na PSDS
predmetu — **Korak 1 završen** (HLS C++ kernel u `src/hls/`, TDD-testiran, bit-tačan),
sledeće **Korak 2** (dokumentacija).
