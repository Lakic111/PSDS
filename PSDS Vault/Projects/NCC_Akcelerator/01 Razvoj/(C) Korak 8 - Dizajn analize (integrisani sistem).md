# Korak 8 — Dizajn analize integrisanog sistema

> **Status:** DIZAJN, čeka pregled korisnika (2026-07-26).
> **Bodovi:** 5 (pravilnik: analiza resursa, kritične putanje, propusnosti integrisanog
> sistema i poređenje sa modelom iz PEUSN-a).
> **Ulaz:** `impl_1` izveštaji iz `C:\Users\pc\ncc_impl`, merenja golog jezgra od
> 2026-07-26, i šest testbencheva pokrenutih 2026-07-26.
> **Izlaz:** proširen PDF `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.*`
> na Korake 2-8, sa usklađenim poglavljima 5-7.

---

## 0. Odluke korisnika (fiksirane u ovoj sesiji, ne re-litigirati)

| # | Odluka | Obrazloženje |
|---|---|---|
| 1 | **8e bez rekalibracije `K_CYC`** | Korisnik: „nema potrebe napominjati to, neka radi brže za sada". U tabelama stoje naše izmerene brojke; odstupanje se ne problematizuje. Ako se pojavi na odbrani, odgovor je jedna rečenica (§5.3). Vraćamo se na to samo ako zatreba. |
| 2 | **Proširiti postojeći PDF na Korake 2-8** | Jedan dokument koji profesor čita linearno, umesto dva fajla koja mora sam da spaja. |
| 3 | **Re-meriti golo jezgro post-route** | Korak 5 je uslov za prolaz; brojke u PDF-u su bile post-sintezne, na starom partu i starom RTL-u. Izmereno (§2). |
| 4 | **Puno usklađivanje §5/§6, uključujući ASMD dijagram** | Dokument mora opisivati kod koji profesor čita zajedno sa njim. |

**SystemC nije instaliran na ovoj mašini** — provereno; `/tmp/.../systemc` su folderi iz
raspakovanih arhiva bez zaglavlja i biblioteke. Odluka 1 to čini nebitnim za Korak 8.

---

## 1. Zašto obim nije „dodati poglavlje"

Postojeći PDF opisuje jezgro **pre dva preseka radi timing-a** (Korak 8b). Neslaganja
nađena poređenjem dokumenta sa `ncc_core.vhd`:

| Mesto u dokumentu | Tvrdi | Stvarno |
|---|---|---|
| §5 ASMD — 3 mesta u tekstu + SVG dijagram | 21 stanje | **23** (`S_L_YX_DRAIN2`, `S_NCC_SQ`) |
| §5.4 pipeline-ovana MAC petlja | bez `df_reg`/`dt_reg`/`mac_v_reg` | MAC pipeline u dva stepena |
| §5.5 normalizacija | bez registra pred delilac | `num_sq_reg`/`den_prod_reg` |
| §6.1 registri | stara lista | +5 registara |
| §7.2 resursi | 1.526 LUT / 554 FF | 1.472 / 664 |
| §7.3 timing | +1,179 ns post-synth, 113 MHz | post-route, §2 |
| §7.4 latencija — 4 mesta | 2.451.212 taktova | **2.461.201** |

Profesor pregleda kod i dokumentaciju zajedno; neslaganje je prvo što se primeti. Ovo je
ista odluka kao 22.07. (dokumentovati dizajn KAKAV JESTE).

---

## 2. Izmerene brojke (sve iz ove sesije, nijedna prepisana iz beleški)

### 2.1 Goli `ncc_core`, OOC, `xc7z010clg400-1`, post-route + phys_opt

Dva merenja, na dva ograničenja takta. **Oba su potrebna** — vidi §2.2.

| | @ 11,0 ns (radni takt) | @ 10,0 ns (100 MHz) |
|---|---|---|
| WNS | **+0,387 ns**, 0/1804 krši | **+0,146 ns**, 0 krši |
| Kritična putanja | `sum_num_reg[17]` → `num_sq_reg[51]` | `sum_num_reg[13]` → `num_sq_reg[51]` |
| Data path delay | 10,638 ns | 9,832 ns |
| logika / rutiranje | 5,719 / 4,919 (46% ruta) | 7,901 / 1,931 (20% ruta) |
| Nivoa logike | 16 (CARRY4=9) | 12 (CARRY4=10, **DSP48E1=2**) |
| Slice LUT | 1.472 (8,36%) | 1.477 (8,39%) |
| Slice Registers | 664 (1,89%) | 664 (1,89%) |
| DSP48E1 | 9 (11,25%) | 9 |
| Block RAM (RAMB36) | 9 (15,00%) | 9 |
| LUT as Memory | **0** | 0 |

**Fmax golog jezgra ≈ 101,5 MHz.** Jezgro **zatvara 100 MHz** sa aktuelnim RTL-om.

### 2.2 Metodološko pravilo (posledica pogrešnog koraka u ovoj sesiji)

Prvo merenje je pušteno samo na 11 ns, a Fmax i „rezerva prema 100 MHz" izvedeni
aritmetički iz tog slack-a → dobijeno 94,22 MHz i −0,613 ns. **Oboje netačno.** Alat
optimizuje *do* ograničenja i staje kad ga ispuni, pa je putanja na labavijem
ograničenju duža. Na 10 ns je alat kvadriranje mapirao u DSP48E1 i rutiranje spustio sa
4,919 na 1,931 ns — druga implementacija istog RTL-a.

**Pravilo: slack se ne prevodi između ograničenja; Fmax se meri na ograničenju koje se
tvrdi.** Ovo je isti obrazac kao tri pogrešne hipoteze iz `BUGS.md` (uzrok pripisan iz
jednog merenja) — ide u `BUGS.md` kao četvrti zapis.

### 2.3 Integrisani sistem (`ncc_system_wrapper`, post-route + phys_opt)

Verifikovano danas iz `impl_1` izveštaja:

| Resurs | Iskorišćeno | Kapacitet | % |
|---|---|---|---|
| Slice LUT | 6.261 | 17.600 | **35,57%** |
| Slice Registers | 5.024 | 35.200 | 14,27% |
| Block RAM Tile | 39 (38×RAMB36 + 2×RAMB18) | 60 | **65,00%** |
| DSP48E1 | 18 | 80 | 22,50% |

WNS **+0,170 ns**, WHS +0,025 ns, **0 od 15.459** endpoint-ova krši; 0 DRC CRITICAL.
Po instanci: `ncc0`/`ncc1` po 1.910 LUT / 1.240 FF / 19 RAMB36 / 9 DSP;
`axi_interconnect_0` 1.616 LUT; `axi_cdma_0` 807 LUT.

### 2.4 Novi zaključak o taktu

Goli core zatvara 100 MHz (+0,146 ns); **sistem ne zatvara** (−0,232 ns, mereno
2026-07-26 u prethodnoj sesiji). Vezujuća putanja u sistemu je
`ncc1/core_inst/y_reg[0]` → `ncc1/ms_inst/img_mem/ADDRBWRADDR[13]` — adresna, unutar
jezgra, ali kritična **samo pod pritiskom razmeštaja i zagušenja u sistemu**.

Dakle: **ograničenje je integracija, ne jezgro.** Naslov u `BUGS.md`
(„`ncc_core` ne zatvara 100 MHz") opisuje RTL pre preseka i treba ga ispraviti.

### 2.5 Funkcionalna verifikacija (2026-07-26, svih 6 PASS)

| Testbench | Rezultat |
|---|---|
| `dp_bram_tb` | PASS |
| `mem_subsystem_tb` | PASS |
| `ncc_core_tb` (zlatni 4×4/2×2) | PASS, 9/9 bit-tačno |
| `ncc_accel_burst_tb` | PASS, read 8/8, write 8/8, RLAST, WSTRB, rani AW |
| `ncc_core_real_tb` | PASS, peak `0x80000000` @ (32,14), **2.461.201 taktova** |
| `ncc_accel_tb` | PASS, peak `0x80000000` @ idx 956 (= `14·66+32`) |

Presek jezgra i popravka `wr_beat` **nisu promenili izlaz** — bit-identičan Koraku 4.

---

## 3. Struktura proširenog dokumenta

```
1-4   NEPROMENJENI   uvod, algoritam, uklanjanje petlji, interfejs
                     (presek nije dirao ni algoritam ni bitske širine)
5     USKLADITI      ASMD: 21 → 23 stanja, tekst §5.1/5.4/5.5, SVG dijagram
6     USKLADITI      §6.1 registri (+5), §6.2 funkcionalne jedinice
7     PREPISATI      naslov → „Analiza posle sinteze i implementacije";
                     brojke iz §2.1; §7.4 latencija 2.461.201; §7.5 + 2 TB-a
8     NOVO           Pakovanje u IP jezgro                (Korak 6)
9     NOVO           Integracija u sistem                 (Korak 7)
10    NOVO           Analiza integrisanog sistema         (Korak 8)
11    Zaključak      (bilo 8), dopunjen
```

### 3.1 §8 Pakovanje u IP jezgro

Obrazac **slave + interne memorije** i zašto (Vežba 08-09 razrađuje isključivo taj
obrazac; master interfejs nije pokriven). AXI-Lite registarska mapa; S01 regioni sa
dekodiranjem `addr(16:15)`, jedan piksel po 32-bitnoj reči; tabela AXI parametara
(`C_S01_AXI_ADDR_WIDTH = 17` → 128 KB). Divergencija od ESL `i_bram` master modela:
`REG_IMG_ADDR`/`REG_TMP_ADDR` postaju rezervisani, `ADDR_BRAM 0x4000_0000` ne postoji.

### 3.2 §9 Integracija u sistem

Topologija: Zynq PS + `proc_sys_reset` + 2× `ncc_accel` + `axi_cdma` + jedan
`axi_interconnect` (2 mastera → 6 slave-ova), jedan takt bez CDC. **Nov SVG blok
dijagram.** Adresna mapa po masteru i poklapanje sa ESL `common.hpp`. Tok podataka po
polju table (7 koraka). Dva obavezna softverska pravila za Korak 9: `u32` poređenje
(jer je `0x80000000` kao `int32` negativan) i nikad CDMA+CPU nad istim S01.

**Obrazloženja koja moraju biti u tekstu, ne prećutana:**
- `axi_interconnect` sa `STRATEGY=1` umesto SmartConnect-a: 8.673 → 1.616 LUT.
- `S_AXI_HP0` sužen na 32 bita: −3.334 LUT / −3.659 FF, 6 → 0 konvertora širine.
- CDMA je izabran zbog pravilnika i zato što popravka burst čitanja ionako mora,
  **ne zbog performansi** — dobitak je ~6% ukupnog vremena (§4.2 dizajna Koraka 7).

### 3.3 §10 Analiza integrisanog sistema

- **10.1 Metod** — `run_impl.tcl`, post-route + phys_opt, kapije u toku.
- **10.2 Resursi (8a)** — tabela §2.3 + poređenje sa ESL referencom.
- **10.3 Kritična putanja i takt (8b)** — tabela §2.1/§2.4, zašto 90,909 a ne 100 (§5.2).
- **10.4 Propusnost (8c)** — model latencije, merenje, ekstrapolacija (§4).
- **10.5 Put do zatvaranja timing-a** — četiri mere, −3,299 → +0,170 ns, sa dobitkom
  svake. Uključiti i da `phys_opt_design` sam donosi 0,481 ns, više od drugog RTL preseka.
- **10.6 Poređenje sa ESL/PEUSN referencom (8e)** — §5.3.

---

## 4. Propusnost (8c) — sadržaj

Model latencije, re-izveden posle preseka:

```
T = 2·img_w·img_h + 2·N + res_w·res_h·(N + 112),    N = tmp_w·tmp_h
```

(bilo `N + 110`; +2 takta po prozoru od dva nova stepena pipeline-a).

**Provera na merenju** (90×90 slika, 25×15 šablon, `res` = 66×76 = 5.016):

```
2·8100 + 2·375 + 5016·487 = 16.200 + 750 + 2.442.792 = 2.459.742
```

naspram izmerenih **2.461.201** → odstupanje **0,06%** (1.459 taktova).

⚠️ **Dve ispravke u odnosu na ranije beleške, nađene pri pisanju ovog dizajna:**

1. Vault je navodio zbir **2.459.712**; tačan je **2.459.742** (aritmetička greška od 30).
   Odstupanje od merenja ostaje 0,06% u oba slučaja.
2. Vault je razliku pripisivao tome da „prozori sa nultom varijansom preskaču jedan takt
   (43 od 5.016)". **To ne može biti uzrok:** izmereno je *veće* od modela, a preskakanje
   bi ga učinilo *manjim*; uz to 43 takta ne objašnjavaju 1.459.

**Kako se piše u dokumentu:** model se navodi kao aproksimacija sa odstupanjem 0,06%, a
ostatak od 1.459 taktova se opisuje kao **fiksna režija koju model ne obuhvata**
(inicijalizacija FSM-a, sekvencijalno deljenje pri računanju srednje vrednosti šablona,
prelazi kroz `S_DONE`) — **bez tvrdnje o tačnom mehanizmu**, jer nije izmeren. Ako se
želi tačan razlaz, meri se brojanjem taktova po fazi u `ncc_core_real_tb`; to nije
potrebno za 5 bodova ovog koraka.

| Veličina | Taktova | @ 90,909 MHz |
|---|---|---|
| 90×90 / 25×15 (izmereno) | 2.461.201 | **27,07 ms** |
| 90×90 / 30×30 (ekstrapolacija) | 3.783.652 | **41,6 ms** |

Propusnost: ~36,9 poziva/s po bloku na 90×90/25×15; dva bloka rade paralelno.

## 5. Tri mesta gde tekst mora biti pažljiv

### 5.1 BRAM je naša slabost — reći to

39/60 = 65% je najveće zauzeće u dizajnu, i **gore je od ESL reference** (8 BRAM_18K).
Uzrok je 32-bitni `sat_t` kod koga je dovoljno 21 bit (max suma 90·90·255 = 2.065.500).
Već je u §7.2 postojećeg PDF-a kao poznata rezerva; u §10.2 se ponavlja na nivou sistema
sa procenom koliko bi suženje vratilo (~3 RAMB36 po instanci). Bolje da profesor to
pročita nego da pita.

### 5.2 Takt 90,909 MHz kao odluka, ne propust

Redosled izlaganja: PS PLL daje `1000/11` za traženih 95 MHz → 90,909; odstupanje od
nominalnih 100 MHz je **9,1%** (rubrika dozvoljava 20%); **goli core zatvara 100 MHz**
(+0,146 ns), ograničenje je integracija; i navesti **koja poluga ostaje neiskorišćena**
(inkrementalno računanje adrese u unutrašnjoj petlji — izbacuje množač iz petlje, ne
menja latenciju) sa procenom i rizikom (greška daje pogrešan rezultat, ne pad, ali
`ncc_core_real_tb` to hvata).

### 5.3 Poređenje sa ESL referencom (8e) — po odluci 1

Tabela poredi **resurse i takte po piksel-operaciji**, gde smo jasno bolji i gde je
poređenje pošteno:

| | ESL/HLS referenca | Naš RTL |
|---|---|---|
| LUT po instanci | 5.269 | **1.910** |
| DSP po instanci | 16 | **9** |
| BRAM po instanci | 4 × BRAM_18K | 19 × RAMB36 ← slabije |
| 2× NCC LUT | 10.538 (59,9%) | **ceo sistem** 6.261 (35,6%) |
| Taktova, 90×90/30×30 | 10.360.183 | **3.783.652** |
| Taktova po piksel-operaciji (30×30) | 3,09 | **1,13** |

⚠️ **Ispravka nasleđena iz beleški:** vault navodi „1,30 naspram 3,09 → 2,74×". Te
brojke ne idu zajedno — 1,30 je iz merenja na **25×15**, a 3,09 sa **30×30**. Na istom
opterećenju: `3.783.652 / (61·61·30·30) = 1,13`, i tek `3,094 / 1,130 = 2,74×` slaže se
sa odnosom taktova (`10.360.183 / 3.783.652`). Sa 1,30 bi ispalo 2,37× i tabela bi sama
sebi protivrečila. **U dokument ide 1,13.**

Napomena za tekst: efikasnost po piksel-operaciji **raste sa veličinom šablona** (1,31 na
25×15, 1,13 na 30×30), jer se režija od 112 taktova po prozoru amortizuje na više MAC
ciklusa. To treba reći uz tabelu da se ne čini da je brojka proizvoljna.

Ukupno vreme obrade `board2.txt` (ESL: 3,667 s) **se ne poredi tabelarno** — po odluci 1
ne problematizujemo odstupanje. Jedna rečenica u tekstu: naš RTL je 2,74× efikasniji po
piksel-operaciji od HLS reference na koju je ESL `K_CYC` kalibrisan, pa sistemsko vreme
nije direktno uporedivo bez rekalibracije modela.

---

## 6. Fajlovi

| Akcija | Fajl |
|---|---|
| Menja se | `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.html` (glavni posao) |
| Regeneriše se | isti `.pdf` (headless Edge, dve zamke u `(C) Sljedeća sesija.md`) |
| Preimenuje se | oba u `...y25-g10_Korak2-8.*` |
| Dopunjuje se | `BUGS.md` (§2.2 pravilo o slack-u; ispravka naslova iz §2.4) |
| Ažurira se | `CLAUDE.md`, `(C) Plan implementacije (10 koraka).md`, `(C) Sljedeća sesija.md` |
| U repo | `src/vhdl/script/run_synth_core.tcl` — parametrizovati period (sad fiksno 10 ns) |

**Preimenovanje PDF-a** je potrebno jer ime fajla nosi opseg koraka, a to je jedina
oznaka grupe u dokumentu (naslovna strana je bez ličnih imena, po ESL uzoru).

## 7. Kriterij završenosti

| # | Provera | Očekivano |
|---|---|---|
| 1 | Nijedno „21 stanje" u dokumentu | 0 pojava; ASMD dijagram prikazuje 23 |
| 2 | Nijedna stara brojka | 0 pojava `1526`, `1.179`, `113 MHz`, `2.451.212` |
| 3 | Sve brojke imaju izvor | svaka tabela vezana za izveštaj iz §2 |
| 4 | PDF se generiše | bez zaglavlja/podnožja, putanja bez razmaka |
| 5 | Poglavlja 8/9/10/11 postoje i numeracija je dosledna | Sadržaj se poklapa |

## 8. Šta ovaj korak NE pokriva

- Bitstream, XSA, Vitis aplikacija — **Korak 9**.
- `package_ip.tcl` i regeneracija `.zip` arhive IP-a — **Korak 10**.
- Suženje `sat_t` na 21 bit — poluga, ostaje dokumentovana rezerva.
- Inkrementalno računanje adrese — poluga za 100 MHz, nije primenjena.
- Rekalibracija `K_CYC` i pokretanje SystemC modela — po odluci 1.
