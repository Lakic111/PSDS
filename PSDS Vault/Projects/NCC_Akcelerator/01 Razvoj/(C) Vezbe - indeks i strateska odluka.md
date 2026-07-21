# Vežbe — indeks i strateška odluka o toku alata

> **⚠️ PONIŠTENO 2026-07-20:** Odluka ispod ("HLS umesto ručnog RTL-a, POTVRĐENO")
> je preokrenuta. Pravilnik (`06 Prilozi/Bodovanje projekta.pdf`, pročitan direktno
> tek u ovoj sesiji) je tool-agnostic — ne zahteva HLS. ESL dokumentacija "potvrđuje"
> samo da je RANIJA faza projekta (PEUSN predmet) koristila HLS, ne da PSDS to
> zahteva. Ironično, ovaj isti fajl u redu 34-36 već je ispravno primetio da je HLS
> "opšteprihvaćena ALTERNATIVA" ručnom RTL-u (ne zamena) — ta nijansa je izgubljena
> kad je odluka kasnije upisana kao "POTVRĐENO". Korak 3 sada ide kroz **ručni VHDL**
> (korisnik potvrdio), po metodologiji iz Vezbe 3-5. Detalji zaokreta:
> `CLAUDE.md` → Trenutni status, i `(C) Plan implementacije...` → vrh fajla.
> Ostatak ovog fajla (indeks vežbi, pouke o loop folding/DSP48/memorijskoj
> arhitekturi) i dalje važi — samo je "Odluka" sekcija ispod zastarela.

Svih 8 laboratorijskih materijala (`06 Prilozi/Vezbe/`) je pročitano i izdvojeno u
`01 Razvoj/Vezbe/`. Ovo je indeks + najvažniji zaključak koji iz njih proizilazi.

## Indeks beleški

| Vežba | Fajl | Pokriva korake |
|---|---|---|
| 1 | `Vezbe/(C) Vezba 01 - Vivado osnove.md` | 3, 4, 5, 9, 10 (osnove alata) |
| 2 | `Vezbe/(C) Vezba 02 - Hijerarhijski dizajn, Datapath i Controlpath.md` | 2b, 2d, 2e |
| 3-5 | `Vezbe/(C) Vezba 03-05 - RT Modeling.md` | 2d, 2e, 3, 4 |
| 6-7 | `Vezbe/(C) Vezba 06-07 - Design Optimization.md` | 3 (optimizacija), 5b, 5c |
| 8-9 | `Vezbe/(C) Vezba 08-09 - IP Packaging.md` | 6 (ne pokriva korak 7 — nadoknaditi kasnije) |
| 10-12 | `Vezbe/(C) Vezba 10-12 - High-Level Synthesis.md` | 1, 3, 4, 5, 6 (alternativni/preporučeni tok) |
| 13 | `Vezbe/(C) Vezba 13 - Design Constraining i TCL Scripting.md` | 5b, 8b, 10 |
| dodatak | `Vezbe/(C) Dodatak - Inferring VHDL to DSP.md` | 3, 5a (DSP resursi) |

## ✅ Strateška odluka: HLS umesto ručnog RTL-a za korak 3 (POTVRĐENO)

Kad je zadat prvobitni plan (`(C) Plan implementacije (10 koraka).md`), pretpostavljeno
je da korak 3 (RT modeling) ide kroz **ručno pisan VHDL/Verilog** iz ASM dijagrama
(klasična FSMD metodologija), jer koraci 2b/2d ("uklanjanje petlji", "ASM dijagram")
zvuče kao ta metodologija.

Nakon čitanja **Vezba 10-12 (HLS)**, ta pretpostavka je bila dovedena u pitanje na
osnovu posrednih dokaza. **Nakon toga je pročitana i `06 Prilozi/ESL dokumentacija
(PEUSN).pdf`, koja ovo POTVRĐUJE eksplicitno i direktno** (nije više nagoveštaj):

- Dokument doslovno kaže: *"Funkcionalnost NCC jezgra opisana je u jeziku C++ i
  sintetizovana alatom Vitis HLS 2023.1 za ciljni uređaj xc7z010-clg225-2
  (Zynq-7010)."* — sa tačnim brojem ciklusa (10.360.183) i resursima koji se
  poklapaju sa `K_CYC` konstantom u `ncc.cpp`.
- Udžbenik (Vezba 10-12) dodatno pokazuje da je HLS opšteprihvaćen kao **automatizovana
  alternativa** za isti cilj (IP jezgro) u odnosu na ručni RTL (Glava 2-5) — dakle
  metodološki legitiman izbor, ne prečica.
- **Dodatna korekcija iz ESL dokumentacije:** ciljna ploča je **Zybo Z7-10
  (Zynq-7010)**, ne ZedBoard/Zynq-7020 kako je ranije zapisano na osnovu Vezbe 1
  primera. Videti `00 Pregled/(C) ESL dokumentacija - izvod.md` za sve detalje,
  tačne brojke resursa/timing-a, i bitske širine za HLS tipove.

### Odluka (za sledeću sesiju)

**Hibridni pristup:**
- Koraci 2b/2d/2e (uklanjanje petlji, ASM dijagram, blok dijagram datapath/controlpath)
  se i dalje rade kao **dokumentacija** — PDF pravilnik ih eksplicitno traži kao
  deliverable, nezavisno od toga čime se stvarno implementira RTL.
- Korak 3 (RTL) se **realno implementira kroz Vivado HLS** (C++ kernel + pragma
  direktive iz `Vezba 10-12`), jer je HLS-generisani VHDL/Verilog validan "HDL model
  na RT nivou" i ogromna ušteda vremena za algoritam ove složenosti (integral image +
  ugnježdene petlje + fixed-point NCC²).
- Korak 1 (C algoritam) se piše **direktno u HLS stilu** (`ap_uint`/`ap_int` tipovi od
  početka, jedna "top" funkcija) umesto generičkog C-a koji bi se posle prepravljao.
- Korak 6 (IP jezgro) je skoro besplatan nakon HLS-a: `Export RTL → IP Catalog`.
- `Vezba 8-9` (ručni Package IP wizard) ostaje kao **rezervni plan** ako HLS export
  ne odgovara potpuno našem interfejsu (npr. treba li nam poseban AXI Master port ka
  BRAM-u koji HLS ne generiše automatski na pravi način) — pogledati tu belešku ako
  HLS export zapne.

### Šta ovo menja u odnosu na prvobitni plan

`01 Razvoj/(C) Plan implementacije (10 koraka).md` i `Projects/NCC_Akcelerator/CLAUDE.md`
("Tok alata" sekcija) i dalje pominju čist ručni RTL tok — **treba ih ažurirati** pre
sledeće sesije da odražavaju ovu HLS odluku (uraditi to na početku sledeće sesije, ili
odmah ako ima vremena u ovoj).

## Ostale bitne poruke iz vežbi (kratko, detalji u pojedinačnim fajlovima)

- **Loop folding / resource sharing** (Vezba 6-7): naš `solve_single_point` ima 3
  paralelne MAC sume (`sum_num`, `sum_den_f`, `sum_den_t`) — strukturno identično
  primeru gde je ta tehnika dala 25% brži takt. Relevantno i ako HLS ne da dovoljno
  dobar rezultat pa se ipak pređe na ručni RTL.
- **DSP48 mapiranje** (Dodatak): sve tri MAC sume su prirodni kandidati za DSP48E1
  (operandi ~10-bit, staju u 25×18 množač). Deljenja (f_bar, template_mean, finalni
  NCC² razlomak) NISU MAC — trebaće Divider Generator IP, posebna tema za korak 3.
- **Memorijska arhitektura** (Vezba 3-5): NCC treba odvojene memorije za sliku,
  šablon, integral image i rezultat (kao "Design Space Exploration" primer u vežbi) —
  bitno i za HLS `ARRAY_PARTITION`/`m_axi` odluke i za ručni RTL ako se na njega pređe.
- **Vezba 8-9 ne pokriva integraciju u block design** (korak 7, Zynq PS/BRAM
  Controller/DMA) — kad dođe taj korak, tražiti dodatni izvor (verovatno je pokriven
  u nekoj od preskočenih strana ili u zvaničnoj Xilinx dokumentaciji).
