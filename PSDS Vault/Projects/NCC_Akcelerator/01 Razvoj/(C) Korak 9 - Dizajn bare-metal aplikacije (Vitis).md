# Korak 9 — Dizajn bare-metal aplikacije (Vitis)

> Datum: 2026-08-26. Ulaz: `ncc_system_wrapper.xsa` (Task 2), bitstream dokazan na
> ploči (`DONE=1`). Ovo je dizajn za **Task 3** — jedini preostali deo Koraka 9.

## 1. Cilj i kriterijum prihvatanja

Bare-metal aplikacija na Cortex-A9 koja prepoznaje figure sa slike šahovske table
koristeći dva hardverska NCC akceleratora, i ispisuje poziciju u FEN notaciji.

**Prihvata se kad:** FEN sa ploče je **znak po znak identičan** zvaničnom FEN-u iz ESL
dokumentacije — isti rezultat koji je C model iz Koraka 1 dao (32/32 figure).

Port referentne logike iz `src/tb.cpp` (`tb_vp::test()`), ali sa `Xil_Out32`/`Xil_In32`
umesto TLM `b_transport` i pravim `XAxiCdma_*` drajverom umesto modela iz `dma.cpp`.

## 2. Ugovor sa hardverom (provereno u RTL-u, ne pretpostavljeno)

### 2.1 Registri (S00, AXI-Lite)

| Offset | Registar | Širina | Napomena |
|---|---|---|---|
| `0x00` | `IMG_W` | **8 bita** | `slv_reg0(7 downto 0)` |
| `0x04` | `IMG_H` | **8 bita** | |
| `0x08` | `TMP_W` | **8 bita** | |
| `0x0C` | `TMP_H` | **8 bita** | |
| `0x10` | `IMG_ADDR` | — | **REZERVISAN, bez značenja** |
| `0x14` | `TMP_ADDR` | — | **REZERVISAN, bez značenja** |
| `0x30` | `CTRL` | bit0 | upis 1 → `start_pulse` **i briše `done_sticky`** |
| `0x34` | `STATUS` | bit0/bit1 | bit0 = `done_sticky`, bit1 = `core_busy` |

Dimenzije su **8-bitne** — softver ne sme poslati vrednost > 255. Naše najveće su
90 i 45, pa je u redu, ali granica postoji.

`done_sticky` se **ne briše čitanjem**, nego sledećim startom. Obrazac je:
upiši `CTRL=1`, pa prozivaj `STATUS` dok bit0 ne postane 1.

**Nema prekida** — IP nema IRQ port. Isključivo prozivanje.

### 2.2 Memorije (S01, AXI-Full), po instanci

| Region   | Offset od `mem_base` | Kapacitet         | Naše korišćenje               |
| -------- | -------------------- | ----------------- | ----------------------------- |
| slika    | `+0x00000`           | 32 KB = 8192 reči | 90×90 = **8100** reči (taman) |
| šablon   | `+0x08000`           | 32 KB = 8192 reči | najviše 30×30 = **900** reči  |
| rezultat | `+0x10000`           | 64 KB = 16384 reči| **3721** (fino) / **961** (grubo) |

⚠️ **Ispravka 2026-08-26.** Ranija verzija ovog odeljka tvrdila je šablon 90×30 = 2700
reči i 61 rezultat. **Netačno** — izmereno iz samih podataka (Task 1):

```
TMPL_FULL_W = 30,30,24,30,30,30,30,30,22,24,28,25
TMPL_FULL_H = 30,30,22,30,30,30,30,30,22,23,23,15
```

Šabloni su najviše 30×30 i **nisu svi iste veličine**. Otud 61×61 = 3721 rezultata po
finom pozivu, a ne 61. Sve izvedeno iz toga je preračunato.

**Jedan piksel po 32-bitnoj reči.** U DDR-u su bajtovi → softver mora širiti 8→32 bita
pre prenosa. CDMA kopira bez konverzije formata.

Pošto su `IMG_ADDR`/`TMP_ADDR` rezervisani, jezgro **uvek** čita sliku sa `+0x00000` i
šablon sa `+0x08000`. Posledica: **svaki novi šablon zahteva nov upis**; ne mogu svih 12
stajati u memoriji i birati se adresom kao u ESL modelu.

### 2.3 Adresna mapa

| Blok | kontrola (S00) | memorije (S01) |
|---|---|---|
| `ncc0` | `0x5000_0000` | `0x5002_0000` |
| `ncc1` | `0x5100_0000` | `0x5102_0000` |
| `axi_cdma_0` | `0x6000_0000` | — |
| DDR | — | `0x0000_0000`–`0x1FFF_FFFF` (**512 MB**) |

### 2.4 CDMA

`C_INCLUDE_SG = 0` (simple mode, jedan prenos, prozivanje `XAxiCdma_IsBusy`),
`C_INCLUDE_DRE = 0`, `C_M_AXI_DATA_WIDTH = 32`, `C_M_AXI_MAX_BURST_LEN = 256`.

⚠️ **DRE je isključen** → izvor i odredište moraju biti poravnati na **4 bajta**.
Staging bafer se deklariše sa `__attribute__((aligned(64)))`; offseti `0x00000` i
`0x08000` su poravnati po konstrukciji.

### 2.5 Dva invarijanta koja hardver NE proverava

1. **Skorovi se porede kao `u32`.** `0x80000000` je NCC²=1,0 — savršeno poklapanje — ali
   kao `int32` negativan. Referentni `collect()` u `tb.cpp` koristi `int32_t mx = -1` i
   time bi odbacio baš najbolji rezultat. **Port to mora ispraviti.**
2. **Nikad CDMA i procesor nad istim S01 istovremeno.** `mem_addr_o` daje prioritet
   čitanju, a upis nije zabranjen → upis bi otišao na adresu čitanja. Održava se time što
   se čeka `XAxiCdma_IsBusy` pre i posle svakog prenosa.

## 3. Arhitektura

```
ncc_hw.c/h      jedini sloj koji zna za AXI; oba invarijanta iz 2.5 žive OVDE
ncc_app.c/h     logika po jednom polju: prazno? boja? grubi screen -> top-2 -> fina potvrda
main.c          init, petlja 8x8, FEN, UART ispis, merenje vremena
data_board.c    720x720 slika kao const u8 niz
data_tmpl.c     12 punih + 12 grubih sablona kao const u8 nizovi
```

### 3.1 `ncc_hw` — javni interfejs

```c
typedef struct { u32 ctrl_base; u32 mem_base; } ncc_dev_t;
extern const ncc_dev_t NCC0, NCC1;

int  ncc_hw_init   (void);                                        /* CDMA lookup + init */
void ncc_set_dims  (const ncc_dev_t*, u8 img_w, u8 img_h, u8 tmp_w, u8 tmp_h);
int  ncc_load_image(const ncc_dev_t*, const u8* px, u32 count);   /* u8->u32, flush, CDMA */
int  ncc_load_tmpl (const ncc_dev_t*, const u8* px, u32 count);
void ncc_start     (const ncc_dev_t*);
int  ncc_wait_done (const ncc_dev_t*, u32 timeout_us);            /* prozivanje STATUS.bit0 */
u32  ncc_best_score(const ncc_dev_t*, u32 n_results, u32 *idx_out); /* poređenje kao u32 */
```

**Zašto ova granica:** faza 4 bring-upa (uvođenje CDMA) menja **samo** `ncc_load_*`.
`ncc_app` se ne dira, pa se kvar izoluje na jedan sloj. CDMA je najverovatniji izvor
problema i zato je iza jedne granice.

`ncc_best_score` vraća `u32` i poredi kao `u32` — invarijant 2.5.1 je zatvoren u funkciju
da ga pozivalac ne može zaobići.

`ncc_wait_done` ima **timeout** i vraća grešku umesto da visi zauvek. Bez toga bi svaka
greška u konfiguraciji izgledala kao zamrznuta ploča, bez ijedne poruke.

Staging bafer pripada `ncc_hw`: **8192 reči × 4 = 32.768 B**, što pokriva i najveći
pojedinačni prenos (pun segment 8100 reči = 32.400 B). Pozivalac vidi samo `const u8*`.

### 3.2 `ncc_app` — jedno polje

```c
typedef struct { int occupied; int is_white; int best_tmpl; u32 best_score; } square_t;
square_t app_scan_square(int m, int n);
```

## 4. Tok po jednom polju

```
1. srednja vrednost centralnih 31x31 direktno iz const niza; poredi sa pikselom (10,10)
   jednako -> prazno, preskoci                                   [bez PL-a, bez prenosa]
2. boja: is_white = (mean > 140) -> 6 kandidata te boje

3. GRUBI SCREEN                                                   [45x45 / 45x15]
   - 2x smanji segment na procesoru
   - upisi ga u ncc0 I ncc1 (slika)                               2 x 8,1 KB
   - po parovima (3 para): sablon A -> ncc0, B -> ncc1
     set_dims, start oba, prozivaj oba, procitaj po 31 rezultat
     (neparan broj kandidata: poslednji krug koristi samo ncc0 -- kao run_pairs u tb.cpp)
4. top-2 po grubom skoru

5. FINA POTVRDA                                                   [90x90 / 90x30]
   - pun segment u oba bloka                                      2 x 32,4 KB
   - jedan par sablona, start, prozivaj, 61 rezultat po bloku
6. najveci skor kao u32 -> board_state[m][n]
```

**Segment se upisuje jednom po stepenu, ne po paru** — unutar grubog screena menjaju se
samo šabloni. Štedi 4 od 6 prenosa segmenta po polju.

Prenos po jednom zauzetom polju, izvedeno iz gornjeg toka:

| Stavka | Računica | Bajtova |
|---|---|---|
| grubi segment ×2 bloka | 2 × 2025 reči × 4 | 16.200 |
| grubi šabloni ×6 | 6 × 225 × 4 | 5.400 |
| pun segment ×2 bloka | 2 × 8100 × 4 | 64.800 |
| fini šabloni ×2 | 2 × 900 × 4 | 7.200 |
| **ukupno** | | **93.600 B = 91 KiB** |

⚠️ **Poglavlje 9.5 tvrdi „oko 146 KB" i ne pokazuje izvođenje.** Ni sa ispravljenim
dimenzijama se ne poklapa (91 KiB). Ne usklađujem svoju računicu sa njom. Task 3
**meri** stvarni prenos, pa se posle merenja 9.5 ili ispravlja ili dobija izvođenje.


Paralelizam je **po šablonu**, ne po polju — dva bloka obrađuju dva različita šablona nad
istim segmentom. To je odluka preuzeta iz ESL modela (`run_pairs`).

PL vreme po polju, sa stvarnim dimenzijama i našim modelom latencije:

| Stepen | Poziv | Taktova | Vreme |
|---|---|---|---|
| grubi | 45×45 / 15×15, ×3 para | 3 × 328.357 | 10,8 ms |
| fini | 90×90 / 30×30, ×1 par | 3.783.652 | 41,6 ms |
| **po polju** | | | **52,5 ms** |
| **32 polja** | | | **≈ 1,68 s** |

Fina brojka 3.783.652 takta = 41,6 ms **poklapa se sa Tabelom 22 u PDF-u**, a 1,68 s sa
ranijom procenom „~1,7 s". **Računanje dominira, ne prenosi** — suprotno od onoga što je
ranija verzija ovog odeljka tvrdila.



## 5. Podaci

`board2.txt` (2,5 MB teksta = 518.400 piksela) i 12 šablona konvertuju se **jednom**, van
ploče, u `const u8` nizove i linkuju u `.elf`. Grubi (2× smanjeni) šabloni se generišu
istim postupkom i takođe ugrađuju — ne računaju se na ploči, jer se ne menjaju.

Konverziju radi mala skripta u repou, da je postupak reproducibilan a ne ručni.

`.elf` je time ~600 KB; JTAG download 10–30 s. Bez SD kartice i bez UART protokola —
jedan izvor grešaka manje, i podaci su identični svaki put.

## 6. Faze bring-upa

Svaka faza se pušta na ploči pre sledeće. Kriterijum je merljiv, ne „izgleda dobro".

| Faza | Šta dokazuje | Kriterijum |
|---|---|---|
| 1 | UART + AXI-Lite žive | `STATUS` čitljiv, `busy=0`; upis `IMG_W=90` pa čitanje vrati 90 |
| 2 | S01 memorije rade | procesor upiše obrazac u sliku i šablon, pročita ga nazad identično |
| 3 | Jezgro računa | zlatni slučaj iz Koraka 4 (90×90 + crni top 25×15) → **`0x80000000` @ (32,14)** |
| 4 | CDMA i keš rade | isti zlatni slučaj, prenos preko CDMA → **bit-identičan rezultat fazi 3** |
| 5 | Pun tok | 8×8, FEN identičan zvaničnom; `XTime` meri ukupno vreme |

**Faza 3 je ključna.** Koristi već verifikovan vektor iz Koraka 4, pa ako prođe, znamo da
su AXI, jezgro i naše razumevanje registara ispravni. Faza 4 menja samo `ncc_load_*` i
mora dati bit-identičan rezultat — time je CDMA izolovan na jednu promenu.

## 7. Merenje

`XTime_GetTime` oko celog skeniranja i oko svakog stepena. Daje Koraku 9 merenu brojku
umesto modela, i poglavlju 10.6 pošteno poređenje sa ESL referencom (`board2.txt`,
2 NCC + optimizacije = 3,667 s).

## 8. Odstupanje od zatečene dokumentacije — POVUČENO

Ranija verzija ovog odeljka predlagala je da **procesor** čita mapu rezultata, uz
obrazloženje „rezultata je 61, čitanje traje ~12 µs". **Taj broj je bio pogrešan** —
rezultata je 3.721 po finom pozivu. Procesorsko čitanje bi bilo 13.208 reči po polju,
oko 9,9 ms, odnosno **~317 ms na 32 polja = ~19 % ukupnog vremena.** Argument pada.

**Rezultate čita DMA**, tačno kako poglavlje 9.3 stavka 7 već kaže. Time
**dokumentacija ostaje nepromenjena** — nijedno poglavlje i nijedna slika se ne diraju.

Cena je jedan `Xil_DCacheInvalidateRange` nad opsegom rezultata posle svakog prenosa.


## 9. Rizici

| Rizik | Zašto | Ublažavanje |
|---|---|---|
| Keš | staging bafer mora biti ispran pre nego CDMA čita | `Xil_DCacheFlushRange` u `ncc_load_*`; faza 4 ga izoluje |
| Poravnanje | DRE isključen (2.4) | bafer `aligned(64)`; offseti poravnati po konstrukciji |
| Zamrzavanje | nema prekida, samo prozivanje | `ncc_wait_done` sa timeout-om i porukom |
| `int32` skorovi | referentni kod ima tu grešku | zatvoreno u `ncc_best_score` |
| UART baud | PS preset originalnog Zybo | pročitati iz `xparameters.h`, ne pretpostaviti |

## 10. Šta NIJE u opsegu

- SD kartica i učitavanje slike u vreme izvršavanja
- Prekidi umesto prozivanja
- Preklapanje prenosa sa računanjem (memorije su jednostruko baferovane — poglavlje 9.5)
- Treća instanca akceleratora
- Zlatni skorovi po svakom polju — dodaju se **samo ako** faza 5 zabrlja; dotad je
  dovoljno poređenje celog FEN-a
