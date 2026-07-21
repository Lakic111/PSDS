# Vezba 6-7 — Design Optimization

Izvor: `06 Prilozi/Vezbe/Vezba-6-7-Design-Optimization.pdf`

Pokriveno u ovom pregledu: str. 171-228 (Poglavlje 5 udžbenika — Deljenje resursa,
Protočna obrada, Razmotavanje petlje, Preklapanje petlje/Loop Folding, sa punim
ASMD+VHDL primerima na "Naive" množaču matrica). Dokument se verovatno nastavlja
dalje (Loop Tiling, Strip-Mining, Data-Oriented Transformations) — nije pokriveno u
ovom prolazu, proveriti kasnije ako zatreba.

## Šta ova vežba pokriva

Optimizacione tehnike koje se primenjuju NA VEĆ PROJEKTOVAN sistem (iz koraka 3
naše plana) da bi se poboljšale performanse (brzina) ili smanjila potrošnja resursa:

- **Transformacije koda** (na pseudo-kodu, pre ASMD-a): bit-level, instrukcijske,
  transformacije petlji (unrolling, folding, tiling, strip-mining, merging,
  distribution), transformacije podataka (distribucija, replikacija, reuse)
- **Optimizacije mapiranja/izvršavanja** (na nivou hardvera): Resource Sharing,
  Pipelining

## Tehnike optimizacije iz vežbe

### Deljenje resursa (Resource Sharing)
- Isti hardverski resurs (npr. sabirač) koristi više MEĐUSOBNO ISKLJUČIVIH operacija
  (tipično grane if/else) → ušteda resursa, cena: dodatni multiplekseri na
  ulazu/izlazu resursa + duža kritična putanja (sporiji max takt).
- Dva tipa: **Operator Sharing** (iste operacije, npr. sve su sabiranja) i
  **Functionality Sharing** (srodne operacije, npr. +/- preko jednog sabirača sa
  negacijom operanda).
- Ima smisla SAMO za velike/skupe resurse (deljenje jednog XOR gejta se ne isplati).

### Protočna obrada (Pipelining)
- Deli kombinacionu mrežu na N faza sa registrima (baferima) između faza.
- Teorijski N× throughput, u praksi manje (`T_clk_pipe > T_comb/N` zbog setup/hold
  vremena registara) — throughput uvek < N×.
- **Kašnjenje pojedinačnog paketa (latency) se NE menja** — pipelining povećava
  throughput, ne latency jednog izračunavanja.
- Postupak: 1) blok dijagram kao lanac koraka, 2) proceni kašnjenje svake komponente,
  3) grupiši u faze sa sličnim kašnjenjem, 4) nađi signale koji prelaze granice faza,
  5) ubaci registre na te signale.
- Primer iz vežbe: Add-and-Shift množač → drvo sabirača (umesto kaskade) smanjuje
  kritičnu putanju sa O(n) na O(log n) sabirača — ISTI princip primenjiv na bilo koje
  sabiranje niza parcijalnih proizvoda.

### Razmotavanje petlje (Loop Unrolling)
- Telo petlje se replicira k puta (potpuno ili delimično), otvara paralelizam na
  nivou instrukcija (ILP), ALI zahteva k× više funkcionalnih jedinica (množača,
  sabirača) I k× veći propusni opseg ka memoriji (višepristupne/dual-port memorije).
- Kod delimičnog razmotavanja sa faktorom k gde n/k nije ceo broj → potrebne dodatne
  if-provere u telu (trošak koji umanjuje dobitak) — birati k tako da n/k bude celo
  kad god je moguće.
- Primer iz vežbe (množač matrica, faktor 2 na spoljašnjoj i petlji): 2× brže, ALI
  2× množača/sabirača i dual-port memorije za A i C.

### Preklapanje petlje (Loop Folding)
- Razdvaja MEĐUSOBNO ZAVISNE operacije (npr. `sum += a[i]*b[i]`) u DVE iteracije:
  trenutna iteracija koristi proizvod izračunat u PRETHODNOJ (registar `mul`/`temp`),
  dok se paralelno računa proizvod za SLEDEĆU iteraciju.
- Efekat: umesto kaskade množač→sabirač (dugačka kritična putanja), množač i sabirač
  rade NEZAVISNO i KONKURENTNO → kritična putanja pada na kašnjenje SAMO jedne
  komponente (najsporije od te dve) → viši max takt.
- Cena: potrebne su **prolog** (inicijalno računanje pre petlje) i **epilog**
  (dovršavanje poslednje akumulacije posle petlje) operacije → +1-2 takta ukupno, ali
  ZANEMARLJIVO za veliki broj iteracija.
- Konkretan brojčani rezultat iz vežbe (16-bitni operandi): kritična putanja pada sa
  `2n + 4log₄n` (množač+sabirač u kaskadi) na `2n` (samo množač) → **1.25× viši takt
  (25% brže)**, uz ~n_in·p_in dodatnih taktova (zanemarljivo).

## Kako se čitaju Vivado izveštaji (resursi, kritična putanja, throughput/latency)

(Napomena: ovo je moje znanje o Vivado toku, PDF u ovom delu ne pokriva direktno
Vivado UI — proveriti Vezba 1 i Vezba 13 za konkretne Vivado komande/izveštaje.)

- **Resursi:** Report Utilization (LUT, FF, DSP48, BRAM count) posle synthesis i
  posle implementation (implementation brojevi su konačni/tačni).
- **Kritična putanja / Fmax:** Report Timing Summary → WNS (Worst Negative Slack).
  Ako WNS ≥ 0 → timing zadovoljen na zadatom taktu. Max Fmax ≈ 1/(perioda_zadata −
  WNS_negativan) — grubo, `Fmax = 1 / (T_clk - WNS)` kad je WNS negativan.
- **Throughput/latency:** latency = broj ciklusa jednog izračunavanja × T_clk;
  throughput (pipeline) = 1/T_clk_pipe (paketa po sekundi), ili ako nije pipeline,
  throughput = 1/latency.

## Primena na NCC datapath — instrukcije za sebe

Naš najdublji deo posla je u `solve_single_point` (ncc.cpp:154-193): za svaki od
`tmp_w*tmp_h` piksela prozora računamo `diff_f`, `diff_t`, pa akumuliramo TRI
nezavisna proizvoda: `sum_num += diff_f*diff_t`, `sum_den_f += diff_f*diff_f`,
`sum_den_t += diff_t*diff_t`. Ovo je STRUKTURNO identično `sum += a(i)*b(i)` primeru
iz vežbe (5.3.2), samo utrostručeno.

1. **Loop Folding je prvi kandidat za primenu**, direktno po uzoru na Primer 5.1/5.3
   iz vežbe: za SVAKI od tri akumulatora (num, den_f, den_t) razdvojiti množenje
   tekućeg piksela od sabiranja prethodnog proizvoda → 3 nezavisna
   registra `mul_num`, `mul_den_f`, `mul_den_t` + `sum_num`, `sum_den_f`,
   `sum_den_t`. Bez ovoga bi kritična putanja u l3-ekvivalentnom stanju bila
   množač→sabirač u kaskadi za SVA TRI proizvoda odjednom — najduža moguća putanja u
   celom datapath-u.
   - Prolog: pri ulasku u petlju (prvi piksel), izračunaj sve tri `mul_*` vrednosti
     bez sabiranja.
   - Epilog: posle poslednjeg piksela, dodaj poslednje `mul_*` vrednosti na sume pre
     prelaska u sledeće stanje (računanje NCC² razlomka).
2. **Resource Sharing za 3 množača** — pošto se `diff_f*diff_t`, `diff_f*diff_f`,
   `diff_t*diff_t` računaju ISTOVREMENO (ne isključivo kao if/else grane), OVDE
   operator sharing NE važi direktno (sve tri operacije su konkurentne, ne
   međusobno isključive). Deljenje bi značilo vremensko multipleksiranje kroz 3
   ciklusa po pikselu → trade-off: 1 množač umesto 3, ali 3× duže po pikselu (manje
   resursa, manji throughput). Razmotriti ovo ako DSP48 slotovi postanu usko grlo
   (videti belešku o Inferring VHDL to DSP).
3. **Loop Unrolling na (y,x) petlji unutar prozora** — razmatrati SAMO ako
   throughput posle Loop Folding-a i dalje nije dovoljan. Zahteva k× više
   množača/sabirača I k× propusniji pristup BRAM-u sa slikom/šablonom (multi-port
   memorija) — veliki trošak resursa za korist koja treba da se opravda kroz
   throughput zahtev (korak 8e: ≤20% odstupanje od PEUSN predviđanja).
4. **Integral image (SAT) computation** (build_integral_image, ncc.cpp:128-138) je
   TAKOĐE kandidat za Loop Folding — akumulacija `row_sum += image[...]` je isti
   obrazac kao Primer 5.2 vežbe (skalarni proizvod/suma niza).
5. **ASMD stanja iz mog ranijeg plana** (`01 Razvoj/(C) Plan implementacije (10
   koraka).md`, korak 2d) treba PROŠIRITI sa prolog/epilog stanjima ako se primeni
   Loop Folding — analogno `l3_prologue`/`l3`/`l3_epilogue` stanjima iz primera u
   vežbi.

## Bitne stvari / zamke na koje paziti

- Loop Folding UVEK dodaje prolog/epilog stanja — ne zaboraviti ih u ASMD dijagramu
  (korak 2d) i u brojanju ciklusa za korak 5c (throughput/latency proračun).
- Delimično razmotavanje petlje sa faktorom k gde ukupan broj iteracija nije
  deljiv sa k zahteva dodatne granske provere — pošto su `tmp_w`/`tmp_h` promenljivi
  (menjaju se po šablonu: 30×30, ili coarse 15×15 posle 2× smanjenja), NE mogu se
  osloniti na "uvek deljivo sa k" pretpostavku ako se ide na unrolling.
- Resource sharing povećava kritičnu putanju (multiplekseri) — ne uvoditi ga
  olako ako je cilj brzina; koristan samo kad su resursi (DSP48/LUT) usko grlo.
- Pipelining ne smanjuje latenciju pojedinačnog piksela/prozora — samo povećava
  throughput ako se OBRAĐUJE VIŠE paketa u letu istovremeno. Za NCC to bi značilo
  pipeline-ovati OBRADU VIŠE POZICIJA PROZORA istovremeno (ne samo jednog piksela) —
  razmisliti da li je to isplativo s obzirom da imamo već 2 paralelna NCC bloka
  (ncc0/ncc1) na nivou cele obrade.

## Mapiranje na korake iz bodovanja

- **Korak 2b** (uklanjanje petlji) i **2d** (ASM dijagram): ASMD stanja moraju već
  odražavati odluku o Loop Folding-u (prolog/epilog stanja) pre crtanja dijagrama.
- **Korak 3** (RTL model): implementacija folding/pipelining direktno utiče na
  strukturu VHDL/Verilog koda (dodatni registri mul_num/mul_den_f/mul_den_t).
- **Korak 5** (analiza posle sinteze): rezultati resursa i Fmax direktno zavise od
  toga da li su ove optimizacije primenjene — ovo je materijal za 5a/5b/5c.
- **Korak 8** (analiza integrisanog sistema + poređenje sa PEUSN, ≤20% odstupanje):
  ako throughput ne zadovoljava, Loop Folding (jeftino, ~25% brže po ovoj vežbi) je
  prva optimizacija za probanje pre skupljeg Loop Unrolling-a.
