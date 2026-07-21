# ESL dokumentacija (PEUSN) — izvod

Izvor: `06 Prilozi/ESL dokumentacija (PEUSN).pdf` — zvanična dokumentacija SystemC/TLM
virtuelne platforme, napisana za predmet **Projektovanje elektronskih uređaja na
sistemskom nivou (PEUSN)**. Ovo je isti sistem koji implementiramo na PSDS-u, samo
jedan nivo ranije (ESL/virtuelna platforma umesto RTL/HW). **Ovaj dokument je i
referenca za korak 8e** (poređenje sa PEUSN predviđanjima, ≤20% odstupanje).

## ⚠️ Potvrda strateške odluke (HLS)

Dokument **eksplicitno potvrđuje** ono što je pretpostavljeno iz Vezbe 10-12:

> "Funkcionalnost NCC jezgra opisana je u jeziku C++ i sintetizovana alatom **Vitis
> HLS 2023.1** za ciljni uređaj **xc7z010-clg225-2 (Zynq-7010)**."

Znači: NCC jezgro je **već** implementirano kroz HLS u prethodnoj fazi projekta. Ovo
više nije pretpostavka nego činjenica — nema potrebe za "rezervnim planom" ručnog
RTL-a osim ako HLS export stvarno zapne na integraciji.

## ⚠️ Korekcija ciljne ploče

**Ciljna ploča je Zybo Z7-10 (Zynq-7010, `xc7z010-clg225-2`), NE ZedBoard/Zynq-7020**
kako je ranije zapisano na osnovu primera iz Vezbe 1 (koja je koristila ZedBoard samo
kao generički tutorial primer za sam alat). XC7Z010 ima znatno manje resursa
(17.600 LUT naspram ~53.200 na XC7Z020) — ovo direktno objašnjava zašto su
korišćena samo 2 NCC bloka, ne 3 (videti ispod).

## Matematički aparat NCC-a

Izvršna specifikacija (baseline): MATLAB model (`FEN_notacija.m`, `fengenerator.m`),
učitava sliku 720×720, deli na 64 polja od 90×90, MATLAB-ova `normxcorr2` (FFT za
brojilac, running sums za imenilac). Profilisanje: `normxcorr2` + potfunkcije troše
**>70% procesorskog vremena** (Tabela 1) → glavni kandidat za HW akceleraciju.

Formula (korelacija u tački (u,v), segment f 90×90, šablon t 30×30):

```
γ(u,v) = Σ[f(x,y) - f̄ᵤᵥ][t(x-u,y-v) - t̄] / √( Σ[f(x,y) - f̄ᵤᵥ]² · Σ[t(x-u,y-v) - t̄]² )
```

**Ključna HW optimizacija:** umesto računanja `γ` (zahteva koren), poredi se
**γ² > threshold²** — eliminiše skup koren u hardveru. `γ ∈ [-1,1]`; eksperimentalno
utvrđen prag **γ = 0.75** za `board2.png` (ispod praga = prazno polje, oznaka 0 u FEN
matrici).

## Bitska analiza — TAČNE širine tipova za HLS/RTL (Tabela 2)

Ovo je kritično za korak 1 (HLS C++ sa `ap_uint`/`ap_int`) — koristiti TAČNO ove
širine, ne generičke `int`/`uint32_t`:

| Promenljiva | Tip (SystemC) | Bita |
|---|---|---|
| `f`/`image`, `t`/`template` (piksel) | `sc_uint<8>` | 8 |
| `sum_f` (suma piksela prozora) | `sc_uint<18>` | 18 |
| `f_bar`, `template_mean` (zaokr. sredina) | `sc_uint<8>` | 8 |
| `diff_f`, `diff_t` (piksel − sredina) | `sc_uint<9>` | 9 |
| `sum_num` (suma proizvoda) | `sc_uint<27>` | 27 |
| `sum_den_f`, `sum_den_t` (suma kvadrata) | `sc_uint<26>` | 26 |
| `num_sq` (kvadrat brojioca) | `sc_uint<52>` | 52 |
| `den_prod` (proizvod imenilaca) | `sc_uint<52>` | 52 |
| NCC² u Q1.31 | `sc_ufixed<32,1>` | 32 (1 celobrojni) |
| `result_t` (povratna vrednost) | `sc_uint<32>` | 32 |

**Ključna odluka projekta:** `f_bar` i `template_mean` se **zaokružuju na ceo broj**
→ `diff_f`/`diff_t` postaju egzaktni 9-bitni celi brojevi → **ceo datapath je
bit-egzaktan**, nema akumulacije greške zaokruživanja kroz sumiranje. Zato su skoro
sve međuvrednosti celobrojne (`sc_uint`), jedini pravi fixed-point je finalni NCC².

## Particionisanje sistema

HW/SW podela: NCC korelacija (>70% vremena) → hardver; kontrola toka, učitavanje
slike, FEN logika, upravljanje periferijama → softver (CPU). Omogućava paralelizam:
CPU priprema sledeći segment dok HW radi korelaciju na trenutnom.

**Bitno:** kontrolni put (CPU preko interkonekta) je odvojen od podatkovnog puta (DMA
čita DDR/piše BRAM direktno, NCC čita BRAM direktno) — podatkovni saobraćaj ne
prolazi kroz interkonekt, izbegava se usko grlo magistrale. Blok šema: PS (CPU
Cortex-A9 + DDR 8MB) ↔ PL (Interconnect/sys_bus + DMA + NCC0/NCC1 + BRAM 1MB).

## HLS latencija i resursi NCC IP-ja (Vitis HLS 2023.1, xc7z010-clg225-2)

- **Procena perioda takta: 7.3 ns** (cilj 10 ns / 100 MHz → pozitivna rezerva)
- **Latencija po pozivu: 10.360.183 ciklusa** = **0.1036 s** na 10 ns/ciklus
  (ovo je TAČAN izvor `K_CYC` konstante u `ncc.cpp` — potvrđeno, ne pretpostavka)
- **Resursi po instanci:** 4× BRAM_18K, 16× DSP48E, 3455 FF, 5269 LUT

**Kapaciteti XC7Z010 i broj instanci (Tabela 6):**

| Resurs | Po instanci | Kapacitet XC7Z010 | % po instanci | Max instanci |
|---|---|---|---|---|
| LUT | 5269 | 17.600 | 29.9% | 3 (⌊3.34⌋) ← vezujući |
| DSP48E | 16 | 80 | 20.0% | 5 |
| FF | 3455 | 35.200 | 9.8% | 10 |
| BRAM_18K | 4 | 120 | 3.3% | 30 |

3 instance = teorijski max, ali ~90% LUT → ne ostaje prostora za AXI interkonekt/DMA/
BRAM kontroler. **2 instance = realan izbor** (60% LUT, ostavlja 40% za ostatak
sistema). Nakon dodavanja NCC1 (0x51000000), stvarno zauzeće (Tabela 7):

| Resurs | 2×NCC | Kapacitet | Iskorišćenost |
|---|---|---|---|
| LUT | 10.538 | 17.600 | 59.9% |
| DSP48E | 32 | 80 | 40.0% |
| FF | 6.910 | 35.200 | 19.6% |
| BRAM_18K | 8 | 120 | 6.7% |

**Ovo su REFERENTNI brojevi za korak 5a/8a (analiza resursa) — naš integrisani
sistem treba da bude blizu ovih vrednosti (plus BRAM Controller/DMA IP/interkonekt
overhead).**

## Ostala kašnjenja (Vivado izveštaji)

- **BRAM kašnjenje:** 2.08 ns (iz Vivado timing izveštaja) — u SystemC modelu
  pojednostavljeno na 10 ns/ciklus (1 reč/ciklus + 1 ciklus latencije, konzervativnije)
- **DMA:** ~320 ns setup ukupno (20+250+50 ns u kodu), prenos bajtova se preklapa
- **DDR:** kašnjenje se ne modeluje (odvojen, brži PS clock domen)

## Performanse sistema — REFERENTNE brojke za korak 8e

Testni fajl `board2.txt` (32 popunjenih polja):

| Konfiguracija | Simulaciono vreme | Ubrzanje |
|---|---|---|
| 1 NCC (polazno) | 39.79 s | 1× |
| 2 NCC paralelno (fiksna latencija) | 19.89 s | 2.0× |
| 2 NCC + optimizacije | **3.667 s** | **10.8×** |

**Ovo je krajnja referentna brojka za korak 8e** — throughput/frekvencija našeg
integrisanog sistema na realnoj ploči ne sme odstupati >20% od ovih vrednosti (uz
konzistentan test fajl `board2.txt`/`board2.png`).

FEN izlaz je identičan u svim konfiguracijama (potvrđuje tačnost optimizacija):
`rnbqkbnr/pp5p/4ppp1/2pp4/5P2/1P1BPN2/P1PPQ1PP/RNB1K2R`

## Optimizacije (već implementirane, opisane u `00 Pregled/(C) Arhitektura sistema.md`)

1. **Provera praznog polja** — CPU direktno iz DDR-a (bez DMA/NCC) upoređuje
   centralnu srednju vrednost sa uglovnim pikselom.
2. **Keširanje segmenta** (`img_dirty` flag) — slika/SAT se grade samo na upis
   `REG_IMG_ADDR`, ne na svaki od 12 šablona.
3. **Pred-klasifikacija boje** — centralna srednja vrednost: crne figure 81-116,
   bele 178-227, prag 140 → testira se samo 6 šablona te boje umesto 12.
4. **Coarse-to-fine (2× downsampling)** — grubi 45×45/15×15 screen nad 6
   kandidata → top-2 → fina potvrda na punom 90×90/30×30. Rad ~k⁴ (k=2→~16×) po
   pozivu, pa je 6 grubih poziva jeftino kao ~1 pun.

Model latencije (nakon optimizacija) je **proporcionalan stvarnom poslu**
(`res_w·res_h × tmp_w·tmp_h`), ne fiksan — ovo je baš `K_CYC` formula u `ncc.cpp`.

## Šta ovo menja u odnosu na ranije beleške u vault-u

- `01 Razvoj/(C) Vezbe - indeks i strateska odluka.md` je pravilno "nagovestio" HLS
  odluku iz posrednih dokaza (K_CYC komentar) — ovaj dokument to **potvrđuje
  direktno i eksplicitno**, sa alatom (Vitis HLS 2023.1) i ciljnim čipom
  (xc7z010-clg225-2) navedenim crno na belo.
- Ciljna ploča ispravljena: **Zybo Z7-10 / XC7Z010**, ne generički Zynq-7000/ZedBoard.
- Sada imamo TAČNE brojke (ne procene) za korake 5a/5b/8a/8b/8e — videti tabele
  iznad.
- Bitske širine (Tabela 2) daju gotov `ap_uint`/`ap_int` plan za korak 1 (HLS C++
  kernel) — ranije je plan samo generički pominjao `ap_uint`.
