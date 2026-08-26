# Korak 9 Task 3 — Plan implementacije (bare-metal Vitis)

> **Za agentske izvršioce:** OBAVEZNA POD-VEŠTINA: koristi
> `superpowers:subagent-driven-development` (preporučeno) ili
> `superpowers:executing-plans` za izvršavanje task po task. Koraci koriste
> `- [ ]` sintaksu za praćenje.

**Cilj:** Bare-metal aplikacija na Cortex-A9 koja sa slike šahovske table prepoznaje
figure pomoću dva hardverska NCC akceleratora i ispisuje poziciju u FEN notaciji preko
UART-a, sa FEN-om identičnim zvaničnom iz ESL dokumentacije.

**Arhitektura:** Tri sloja — `ncc_hw` (jedini koji zna za AXI; oba obavezna invarijanta
zatvorena u njemu), `ncc_logic` (čista logika bez hardvera, testira se **na host
mašini**), `main` (petlja 8×8, FEN, merenje). Ključna odluka: sve što ne dira hardver
izdvojeno je u `ncc_logic` da bi imalo pravi jedinični test; hardverski sloj se dokazuje
u pet faza na ploči, svaka sa merljivim kriterijumom.

**Tech stack:** Vitis 2025.2 (XSCT Tcl, klasične `platform`/`app`/`domain` komande
potvrđene da postoje), `arm-none-eabi-gcc` iz `Vitis/gnu/aarch32/nt/`, standalone BSP,
`XAxiCdma` drajver, `XTime` za merenje. Host testovi: MSYS2 `g++ 16.1.0`.

**Spec:** `PSDS Vault/Projects/NCC_Akcelerator/01 Razvoj/(C) Korak 9 - Dizajn bare-metal aplikacije (Vitis).md`

## Globalna ograničenja

- Ulaz: `src/vhdl/result/ncc_system/ncc_system_wrapper.xsa` (sadrži bitstream, provereno).
- Adrese: `ncc0` S00 `0x5000_0000` / S01 `0x5002_0000`; `ncc1` S00 `0x5100_0000` /
  S01 `0x5102_0000`; CDMA `0x6000_0000`; DDR `0x0000_0000`–`0x1FFF_FFFF` (512 MB).
- Registri: `IMG_W 0x00`, `IMG_H 0x04`, `TMP_W 0x08`, `TMP_H 0x0C`, `CTRL 0x30`,
  `STATUS 0x34`. `IMG_ADDR 0x10` i `TMP_ADDR 0x14` su **rezervisani, ne koristiti**.
- Dimenzije su **8-bitne** — nikad ne slati vrednost > 255.
- `CTRL` bit0 = start **i briše `done_sticky`**. `STATUS` bit0 = `done_sticky`,
  bit1 = `core_busy`. **Nema prekida** — samo prozivanje.
- S01 regioni po instanci: slika `+0x00000`, šablon `+0x08000`, rezultat `+0x10000`.
  **Jedan piksel po 32-bitnoj reči.**
- CDMA: `C_INCLUDE_SG=0` (simple mode), **`C_INCLUDE_DRE=0` → poravnanje na 4 bajta
  obavezno**, `C_M_AXI_DATA_WIDTH=32`.
- **Dimenzije šablona (izmereno iz podataka, Task 1):** najviše 30×30, i **nisu svi
  iste veličine** — `W = 30,30,24,30,30,30,30,30,22,24,28,25`,
  `H = 30,30,22,30,30,30,30,30,22,23,23,15`. Zato je rezultata **3721** po finom
  pozivu (61×61) i **961** po grubom (31×31). Kod nigde ne sme zakucati te brojeve —
  računa ih kao `(img_w − tmp_w + 1) × (img_h − tmp_h + 1)`.
- **Invarijant 1:** skorovi se porede kao `u32`, nikad `int32`.
- **Invarijant 2:** nikad CDMA i procesor nad istim S01 istovremeno.
- Svi generisani fajlovi u vaultu nose prefiks `(C)`; kod ide u `src/`, ne u vault.
- ⚠️ **Tcl fajlovi za XSCT moraju biti bez BOM-a.** PowerShell
  `Set-Content -Encoding utf8` upisuje BOM i XSCT pukne sa
  `invalid command name "﻿puts"`. Pisati kroz bash heredoc ili `-Encoding ascii`.

---

## Struktura fajlova

```
src/vitis/
  scripts/gen_data.py        generator C nizova iz .txt podataka  [host, Python]
  scripts/build_app.tcl      XSCT: platform + domain + app + build
  scripts/run_app.tcl        XSCT: program PL, download .elf, pokreni
  app/ncc_logic.h/.c         cista logika -- BEZ Xil_* poziva
  app/ncc_hw.h/.c            jedini sloj koji zna za AXI
  app/main.c                 init, petlja 8x8, FEN, merenje
  app/data_board.c           720x720 slika, const u8
  app/data_tmpl.c            12 punih + 12 grubih sablona, const u8
  app/data_golden.c          zlatni vektor iz Koraka 4 (seg90 + crnitop)
  test/test_logic.c          host jedinicni testovi za ncc_logic
  test/Makefile              host build (g++/gcc), ne dira Vitis
```

`ncc_logic` **ne sme** uključivati nijedan Xilinx header — to je uslov da se kompajlira
na hostu. Provera je u Tasku 2, korak 6.

---

### Task 1: Generator podataka i ugrađeni nizovi

**Files:**
- Create: `src/vitis/scripts/gen_data.py`
- Create: `src/vitis/app/data_board.c`, `src/vitis/app/data_tmpl.c`, `src/vitis/app/data_golden.c`
- Create: `src/vitis/app/data.h`

**Interfaces:**
- Produces: `extern const unsigned char BOARD_IMG[518400];` (720×720)
  `extern const unsigned char TMPL_FULL[12][2700]; extern const int TMPL_FULL_W[12], TMPL_FULL_H[12];`
  `extern const unsigned char TMPL_COARSE[12][675]; extern const int TMPL_COARSE_W[12], TMPL_COARSE_H[12];`
  `extern const unsigned char GOLD_SEG[8100]; extern const unsigned char GOLD_TMPL[375];`

- [ ] **Korak 1: Napiši generator**

`src/vitis/scripts/gen_data.py`:

```python
#!/usr/bin/env python3
"""Konvertuje .txt podatke u C nizove za ugradnju u .elf.
board2.txt i sabloni: vrednosti razdvojene zarezom, jedan red po liniji.
seg90.txt i crnitop.txt: jedna vrednost po liniji.
"""
import os, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT  = os.path.join(REPO, "src", "vitis", "app")

def read_csv_grid(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip().rstrip(",")
            if not line:
                continue
            rows.append([int(float(v)) for v in line.split(",")])
    w = len(rows[0])
    for r in rows:
        assert len(r) == w, "%s: neujednacena sirina reda" % path
    return [v for r in rows for v in r], w, len(rows)

def read_flat(path):
    with open(path) as f:
        vals = [int(float(l.strip())) for l in f if l.strip()]
    return vals

def downsample2x(px, w, h):
    ow, oh = w // 2, h // 2
    out = []
    for y in range(oh):
        for x in range(ow):
            s = (px[(2*y)*w + 2*x] + px[(2*y)*w + 2*x + 1]
                 + px[(2*y+1)*w + 2*x] + px[(2*y+1)*w + 2*x + 1])
            out.append(s // 4)
    return out, ow, oh

def emit(fh, name, vals, per_line=16):
    fh.write("const unsigned char %s = {\n" % name)
    for i in range(0, len(vals), per_line):
        fh.write("    " + ",".join("%3d" % v for v in vals[i:i+per_line]) + ",\n")
    fh.write("};\n\n")

TMPL_NAMES = ["Belakraljica","Belikonj","Belikralj","Belilovac","Belipesak","Belitop",
              "Crnakraljica","Crnikonj","Crnikralj","Crnilovac","Crnipesak","Crnitop"]

def main():
    data_dir = os.path.join(REPO, "src", "hls", "data", "data")
    tb_dir   = os.path.join(REPO, "src", "vhdl", "tb")

    img, iw, ih = read_csv_grid(os.path.join(data_dir, "board2.txt"))
    assert (iw, ih) == (720, 720), "slika nije 720x720 nego %dx%d" % (iw, ih)
    with open(os.path.join(OUT, "data_board.c"), "w") as f:
        f.write('#include "data.h"\n\n')
        emit(f, "BOARD_IMG[%d]" % len(img), img)

    fulls, coarses, fw, fh_, cw, ch = [], [], [], [], [], []
    for n in TMPL_NAMES:
        px, w, h = read_csv_grid(os.path.join(data_dir, n + "template.txt"))
        cpx, ccw, cch = downsample2x(px, w, h)
        fulls.append(px); fw.append(w); fh_.append(h)
        coarses.append(cpx); cw.append(ccw); ch.append(cch)

    with open(os.path.join(OUT, "data_tmpl.c"), "w") as f:
        f.write('#include "data.h"\n\n')
        for i, px in enumerate(fulls):
            emit(f, "TMPL_FULL_%d[%d]" % (i, len(px)), px)
        for i, px in enumerate(coarses):
            emit(f, "TMPL_COARSE_%d[%d]" % (i, len(px)), px)
        f.write("const unsigned char *const TMPL_FULL[12] = {%s};\n"
                % ",".join("TMPL_FULL_%d" % i for i in range(12)))
        f.write("const unsigned char *const TMPL_COARSE[12] = {%s};\n"
                % ",".join("TMPL_COARSE_%d" % i for i in range(12)))
        f.write("const int TMPL_FULL_W[12]   = {%s};\n" % ",".join(map(str, fw)))
        f.write("const int TMPL_FULL_H[12]   = {%s};\n" % ",".join(map(str, fh_)))
        f.write("const int TMPL_COARSE_W[12] = {%s};\n" % ",".join(map(str, cw)))
        f.write("const int TMPL_COARSE_H[12] = {%s};\n" % ",".join(map(str, ch)))

    seg  = read_flat(os.path.join(tb_dir, "seg90.txt"))
    tmpl = read_flat(os.path.join(tb_dir, "crnitop.txt"))
    assert len(seg) == 8100, "seg90 ima %d, ocekivano 8100" % len(seg)
    assert len(tmpl) == 375, "crnitop ima %d, ocekivano 375" % len(tmpl)
    with open(os.path.join(OUT, "data_golden.c"), "w") as f:
        f.write('#include "data.h"\n\n')
        emit(f, "GOLD_SEG[8100]", seg)
        emit(f, "GOLD_TMPL[375]", tmpl)

    print("OK: slika %dx%d, 12 sablona, zlatni vektor %d/%d" %
          (iw, ih, len(seg), len(tmpl)))

if __name__ == "__main__":
    main()
```

`src/vitis/app/data.h`:

```c
#ifndef DATA_H
#define DATA_H
extern const unsigned char BOARD_IMG[518400];
extern const unsigned char *const TMPL_FULL[12];
extern const unsigned char *const TMPL_COARSE[12];
extern const int TMPL_FULL_W[12],   TMPL_FULL_H[12];
extern const int TMPL_COARSE_W[12], TMPL_COARSE_H[12];
extern const unsigned char GOLD_SEG[8100];
extern const unsigned char GOLD_TMPL[375];
#define BOARD_W 720
#define BOARD_H 720
#endif
```

- [ ] **Korak 2: Pokreni generator i proveri da tvrdnje prolaze**

```bash
cd "C:/Users/pc/Desktop/PSDS" && python src/vitis/scripts/gen_data.py
```

Očekivano: `OK: slika 720x720, 12 sablona, zlatni vektor 8100/375`.
Ako neka `assert` pukne, podaci nisu onakvi kakvim ih plan pretpostavlja — **stani i
javi**, ne prilagođavaj tvrdnje.

- [ ] **Korak 3: Nezavisna provera da nizovi odgovaraju izvoru**

Generator je i sam mogao pogrešiti. Provera čita **C fajl** nazad i poredi sa `.txt`:

```bash
cd "C:/Users/pc/Desktop/PSDS" && python - <<'PY'
import re
src = open("src/vitis/app/data_board.c").read()
nums = [int(x) for x in re.findall(r"-?\d+", src.split("{",1)[1])]
nums = nums[:518400]
ref = []
for line in open("src/hls/data/data/board2.txt"):
    line = line.strip().rstrip(",")
    if line:
        ref += [int(float(v)) for v in line.split(",")]
assert len(nums) == len(ref) == 518400, (len(nums), len(ref))
assert nums == ref, "nizovi se NE poklapaju sa board2.txt"
print("OK: data_board.c je bit-identican board2.txt")
PY
```

Očekivano: `OK: data_board.c je bit-identican board2.txt`.

- [ ] **Korak 4: Commit**

```bash
git add src/vitis/scripts/gen_data.py src/vitis/app/data.h src/vitis/app/data_board.c \
        src/vitis/app/data_tmpl.c src/vitis/app/data_golden.c
git commit -m "Korak 9 Task 3.1: generator podataka i ugradjeni C nizovi"
```

---

### Task 2: Čista logika i jedinični testovi na hostu

**Files:**
- Create: `src/vitis/app/ncc_logic.h`, `src/vitis/app/ncc_logic.c`
- Test: `src/vitis/test/test_logic.c`, `src/vitis/test/Makefile`

**Interfaces:**
- Consumes: `data.h` iz Taska 1
- Produces:
  `void   logic_downsample2x(const unsigned char *src, int w, int h, unsigned char *dst);`
  `int    logic_center_mean(const unsigned char *img, int img_w, int sx, int sy);`
  `int    logic_is_empty(const unsigned char *img, int img_w, int sx, int sy);`
  `int    logic_is_white(int mean);`
  `unsigned int logic_max_u32(const unsigned int *v, unsigned int n);`
  `void   logic_fen(const char board[8][8], char *out, unsigned int out_sz);`

- [ ] **Korak 1: Napiši padajuće testove**

`src/vitis/test/test_logic.c`:

```c
#include <stdio.h>
#include <string.h>
#include "../app/ncc_logic.h"

static int fails = 0;
#define CHECK(c, msg) do { if (!(c)) { printf("FAIL: %s\n", msg); fails++; } } while (0)

/* Invarijant 1: 0x80000000 je NAJVECI skor, ne najmanji.
   Sa int32 poredjenjem ovaj test pada -- to je i poenta. */
static void test_max_u32(void) {
    unsigned int v[4] = { 0x10000000u, 0x80000000u, 0x7FFFFFFFu, 0u };
    CHECK(logic_max_u32(v, 4) == 0x80000000u, "max_u32 mora vratiti 0x80000000");
    unsigned int w[2] = { 0u, 1u };
    CHECK(logic_max_u32(w, 2) == 1u, "max_u32 na malim vrednostima");
}

static void test_downsample(void) {
    /* 4x4 -> 2x2, svaki izlaz je prosek 2x2 bloka */
    unsigned char src[16] = { 0,4,8,12,  4,8,12,16,  0,0,0,0,  8,8,8,8 };
    unsigned char dst[4];
    logic_downsample2x(src, 4, 4, dst);
    CHECK(dst[0] == 4,  "downsample [0] = (0+4+4+8)/4 = 4");
    CHECK(dst[1] == 12, "downsample [1] = (8+12+12+16)/4 = 12");
    CHECK(dst[2] == 4,  "downsample [2] = (0+0+8+8)/4 = 4");
    CHECK(dst[3] == 4,  "downsample [3] = (0+0+8+8)/4 = 4");
}

static void test_fen_empty_board(void) {
    char b[8][8]; memset(b, ' ', sizeof b);
    char out[128];
    logic_fen(b, out, sizeof out);
    CHECK(strcmp(out, "8/8/8/8/8/8/8/8") == 0, "prazna tabla -> 8/8/8/8/8/8/8/8");
}

static void test_fen_mixed(void) {
    char b[8][8]; memset(b, ' ', sizeof b);
    b[0][0] = 'r'; b[0][7] = 'r';        /* red: r6r */
    b[7][4] = 'K';                        /* red: 4K3 */
    char out[128];
    logic_fen(b, out, sizeof out);
    CHECK(strncmp(out, "r6r/", 4) == 0, "prvi red r6r");
    CHECK(strstr(out, "/4K3") != NULL,  "poslednji red 4K3");
}

static void test_is_white(void) {
    CHECK(logic_is_white(200) == 1, "200 > 140 -> bela");
    CHECK(logic_is_white(100) == 0, "100 <= 140 -> crna");
    CHECK(logic_is_white(140) == 0, "granica 140 nije bela (strogo vece)");
}

int main(void) {
    test_max_u32();
    test_downsample();
    test_fen_empty_board();
    test_fen_mixed();
    test_is_white();
    if (fails == 0) { printf("SVI TESTOVI PROSLI\n"); return 0; }
    printf("%d testova palo\n", fails);
    return 1;
}
```

`src/vitis/test/Makefile`:

```make
CC     ?= gcc
CFLAGS ?= -std=c99 -Wall -Wextra -Werror -O1

test_logic: test_logic.c ../app/ncc_logic.c ../app/ncc_logic.h
	$(CC) $(CFLAGS) -o $@ test_logic.c ../app/ncc_logic.c

.PHONY: run clean
run: test_logic
	./test_logic

clean:
	rm -f test_logic test_logic.exe
```

- [ ] **Korak 2: Pusti testove i potvrdi da NE prolaze**

```bash
cd "C:/Users/pc/Desktop/PSDS/src/vitis/test" && make run
```

Očekivano: greška kompilacije — `ncc_logic.h: No such file or directory`.
To je RED faza; ne nastavljaj dok ne vidiš pad.

- [ ] **Korak 3: Napiši implementaciju**

`src/vitis/app/ncc_logic.h`:

```c
#ifndef NCC_LOGIC_H
#define NCC_LOGIC_H
/* Cista logika: BEZ Xilinx headera, kompajlira se i na hostu. */

#define COLOR_THRESHOLD 140
#define SEG_W 90
#define SEG_H 90

void         logic_downsample2x(const unsigned char *src, int w, int h, unsigned char *dst);
int          logic_center_mean (const unsigned char *img, int img_w, int sx, int sy);
int          logic_is_empty    (const unsigned char *img, int img_w, int sx, int sy);
int          logic_is_white    (int mean);
unsigned int logic_max_u32     (const unsigned int *v, unsigned int n);
void         logic_fen         (const char board[8][8], char *out, unsigned int out_sz);
#endif
```

`src/vitis/app/ncc_logic.c`:

```c
#include "ncc_logic.h"

void logic_downsample2x(const unsigned char *src, int w, int h, unsigned char *dst) {
    int ow = w / 2, oh = h / 2, x, y;
    for (y = 0; y < oh; y++)
        for (x = 0; x < ow; x++) {
            int s = src[(2*y)*w + 2*x]     + src[(2*y)*w + 2*x + 1]
                  + src[(2*y+1)*w + 2*x]   + src[(2*y+1)*w + 2*x + 1];
            dst[y*ow + x] = (unsigned char)(s / 4);
        }
}

/* Srednja vrednost centralnih 31x31 (redovi 29..59, kolone 29..59) segmenta
   ciji je gornji levi ugao na (sx, sy) u slici sirine img_w. */
int logic_center_mean(const unsigned char *img, int img_w, int sx, int sy) {
    int sum = 0, cnt = 0, x, y;
    for (y = 29; y <= 59; y++)
        for (x = 29; x <= 59; x++) { sum += img[(sy + y)*img_w + (sx + x)]; cnt++; }
    return sum / cnt;
}

/* Prazno polje: srednja vrednost centra jednaka pikselu (10,10) -- ujednacena
   povrsina bez figure. Isti kriterijum kao referentni tb.cpp. */
int logic_is_empty(const unsigned char *img, int img_w, int sx, int sy) {
    int mean = logic_center_mean(img, img_w, sx, sy);
    return mean == (int)img[(sy + 10)*img_w + (sx + 10)];
}

int logic_is_white(int mean) { return mean > COLOR_THRESHOLD; }

/* INVARIJANT 1: poredjenje kao u32. 0x80000000 je NCC^2 = 1,0 (savrseno
   poklapanje); kao int32 je negativan, pa bi trazenje maksimuma od -1 odbacilo
   bas najbolji rezultat. */
unsigned int logic_max_u32(const unsigned int *v, unsigned int n) {
    unsigned int i, mx = 0u;
    for (i = 0; i < n; i++) if (v[i] > mx) mx = v[i];
    return mx;
}

void logic_fen(const char board[8][8], char *out, unsigned int out_sz) {
    unsigned int p = 0; int m, n;
    for (m = 0; m < 8; m++) {
        int empty = 0;
        for (n = 0; n < 8; n++) {
            if (board[m][n] == ' ') { empty++; continue; }
            if (empty > 0 && p + 1 < out_sz) { out[p++] = (char)('0' + empty); empty = 0; }
            if (p + 1 < out_sz) out[p++] = board[m][n];
        }
        if (empty > 0 && p + 1 < out_sz) out[p++] = (char)('0' + empty);
        if (m < 7 && p + 1 < out_sz)     out[p++] = '/';
    }
    out[p < out_sz ? p : out_sz - 1] = '\0';
}
```

- [ ] **Korak 4: Pusti testove i potvrdi da prolaze**

```bash
cd "C:/Users/pc/Desktop/PSDS/src/vitis/test" && make run
```

Očekivano: `SVI TESTOVI PROSLI`, izlazni kod 0.

- [ ] **Korak 5: Uporedi `logic_is_empty` sa referencom na pravim podacima**

Test iznad koristi izmišljene brojeve. Ovaj korak proverava da broj zauzetih polja
odgovara stvarnoj tabli — `board2.txt` ima **32 figure**:

```bash
cd "C:/Users/pc/Desktop/PSDS" && cat > /tmp/cnt.c <<'EOF'
#include <stdio.h>
#include "src/vitis/app/ncc_logic.h"
#include "src/vitis/app/data.h"
int main(void) {
    int m, n, occ = 0;
    for (m = 0; m < 8; m++) for (n = 0; n < 8; n++)
        if (!logic_is_empty(BOARD_IMG, BOARD_W, n*90, m*90)) occ++;
    printf("zauzetih polja: %d\n", occ);
    return occ == 32 ? 0 : 1;
}
EOF
gcc -std=c99 -O1 -o /tmp/cnt /tmp/cnt.c src/vitis/app/ncc_logic.c src/vitis/app/data_board.c && /tmp/cnt
```

Očekivano: `zauzetih polja: 32`, izlazni kod 0.
Ako ispadne drugačije, kriterijum praznog polja ne odgovara podacima — **stani i javi**.

- [ ] **Korak 6: Potvrdi da `ncc_logic` ne zavisi od Xilinx headera**

```bash
cd "C:/Users/pc/Desktop/PSDS" && grep -nE '#include *[<"](xil|xparameters|xstatus)' src/vitis/app/ncc_logic.c src/vitis/app/ncc_logic.h && echo "GRESKA: ncc_logic zavisi od Xilinx headera" && exit 1 || echo "OK: ncc_logic je cist"
```

Očekivano: `OK: ncc_logic je cist`.

- [ ] **Korak 7: Commit**

```bash
git add src/vitis/app/ncc_logic.h src/vitis/app/ncc_logic.c src/vitis/test/
git commit -m "Korak 9 Task 3.2: cista logika + host jedinicni testovi (32/32 polja)"
```

---

### Task 3: Vitis platforma, skelet aplikacije i FAZA 1 (UART + AXI-Lite)

**Files:**
- Create: `src/vitis/scripts/build_app.tcl`, `src/vitis/scripts/run_app.tcl`
- Create: `src/vitis/app/ncc_hw.h`, `src/vitis/app/ncc_hw.c`, `src/vitis/app/main.c`

**Interfaces:**
- Produces: `int ncc_hw_init(void);`, `void ncc_write_reg(const ncc_dev_t*, u32 off, u32 v);`,
  `u32 ncc_read_reg(const ncc_dev_t*, u32 off);`, `const ncc_dev_t NCC0, NCC1;`

- [ ] **Korak 1: Napiši XSCT skriptu za gradnju**

`src/vitis/scripts/build_app.tcl` (**bez BOM-a!**):

```tcl
# Gradi Vitis platformu iz XSA i bare-metal aplikaciju. Batch, bez GUI-a.
set REPO C:/Users/pc/Desktop/PSDS
set XSA  $REPO/src/vhdl/result/ncc_system/ncc_system_wrapper.xsa
set WS   $REPO/src/vitis/ws
set APP  ncc_app

if {![file exists $XSA]} { error "nema XSA: $XSA -- pusti run_impl.tcl" }
file mkdir $WS
setws $WS

# Platforma iz XSA, standalone domen na ps7_cortexa9_0.
if {[catch {platform create -name ncc_plat -hw $XSA -os standalone -proc ps7_cortexa9_0 -out $WS} e]} {
    puts "### platform create: $e (verovatno vec postoji, nastavljam)"
}
platform active ncc_plat
platform generate

app create -name $APP -platform ncc_plat -domain standalone_ps7_cortexa9_0 -template {Empty Application(C)}

# Izvori: dodajemo sve iz src/vitis/app
foreach f [glob $REPO/src/vitis/app/*.c $REPO/src/vitis/app/*.h] {
    file copy -force $f $WS/$APP/src/
}

app config -name $APP build-config release
app config -name $APP -add compiler-optimization {Optimize more (-O2)}
app build -name $APP

set ELF $WS/$APP/build/$APP.elf
if {![file exists $ELF]} { set ELF $WS/$APP/Release/$APP.elf }
if {![file exists $ELF]} { error "BUILD PAO: nema .elf" }
puts "@@@ BUILD OK: $ELF ([file size $ELF] B)"
```

- [ ] **Korak 2: Napiši XSCT skriptu za pokretanje na ploči**

`src/vitis/scripts/run_app.tcl`:

```tcl
# Programira PL, inicijalizuje PS, spusta .elf i pusta ga.
set REPO C:/Users/pc/Desktop/PSDS
set WS   $REPO/src/vitis/ws
set APP  ncc_app
set BIT  $REPO/src/vhdl/result/ncc_system/ncc_system.runs/impl_1/ncc_system_wrapper.bit

set ELF $WS/$APP/build/$APP.elf
if {![file exists $ELF]} { set ELF $WS/$APP/Release/$APP.elf }
if {![file exists $ELF]} { error "nema .elf -- pusti build_app.tcl" }

connect
targets -set -filter {name =~ "xc7z010"}
fpga -file $BIT
targets -set -filter {name =~ "*Cortex-A9 MPCore #0*"}
rst -processor
# ps7_init.tcl dolazi iz platforme; inicijalizuje DDR i takt.
source $WS/ncc_plat/hw/ps7_init.tcl
ps7_init
ps7_post_config
dow $ELF
con
puts "@@@ POKRENUT -- prati UART na 115200 8N1"
```

- [ ] **Korak 3: Napiši minimalni `ncc_hw` (samo registri) i `main` za fazu 1**

`src/vitis/app/ncc_hw.h`:

```c
#ifndef NCC_HW_H
#define NCC_HW_H
#include "xil_types.h"

typedef struct { u32 ctrl_base; u32 mem_base; } ncc_dev_t;
extern const ncc_dev_t NCC0, NCC1;

#define REG_IMG_W  0x00u
#define REG_IMG_H  0x04u
#define REG_TMP_W  0x08u
#define REG_TMP_H  0x0Cu
#define REG_CTRL   0x30u
#define REG_STATUS 0x34u
/* 0x10 IMG_ADDR i 0x14 TMP_ADDR su REZERVISANI -- ne koristiti. */

#define MEM_IMG_OFF  0x00000u
#define MEM_TMPL_OFF 0x08000u
#define MEM_RES_OFF  0x10000u

#define STATUS_DONE_BIT 0x1u
#define STATUS_BUSY_BIT 0x2u

int  ncc_hw_init  (void);
void ncc_write_reg(const ncc_dev_t *d, u32 off, u32 v);
u32  ncc_read_reg (const ncc_dev_t *d, u32 off);
#endif
```

`src/vitis/app/ncc_hw.c`:

```c
#include "ncc_hw.h"
#include "xil_io.h"

const ncc_dev_t NCC0 = { 0x50000000u, 0x50020000u };
const ncc_dev_t NCC1 = { 0x51000000u, 0x51020000u };

int  ncc_hw_init(void) { return 0; }   /* CDMA se dodaje u Tasku 6 */
void ncc_write_reg(const ncc_dev_t *d, u32 off, u32 v) { Xil_Out32(d->ctrl_base + off, v); }
u32  ncc_read_reg (const ncc_dev_t *d, u32 off)        { return Xil_In32(d->ctrl_base + off); }
```

`src/vitis/app/main.c`:

```c
#include <stdio.h>
#include "xil_printf.h"
#include "ncc_hw.h"

static int phase1(const ncc_dev_t *d, const char *name) {
    u32 st, rb;
    int ok = 1;

    st = ncc_read_reg(d, REG_STATUS);
    xil_printf("%s STATUS = 0x%08x (done=%d busy=%d)\r\n",
               name, st, (st & STATUS_DONE_BIT) ? 1 : 0, (st & STATUS_BUSY_BIT) ? 1 : 0);
    if (st & STATUS_BUSY_BIT) { xil_printf("  GRESKA: busy=1 na pocetku\r\n"); ok = 0; }

    ncc_write_reg(d, REG_IMG_W, 90);
    rb = ncc_read_reg(d, REG_IMG_W);
    xil_printf("%s IMG_W upisano 90, procitano %d\r\n", name, (int)rb);
    if (rb != 90u) { xil_printf("  GRESKA: ocekivano 90\r\n"); ok = 0; }

    ncc_write_reg(d, REG_TMP_H, 30);
    rb = ncc_read_reg(d, REG_TMP_H);
    if (rb != 30u) { xil_printf("  GRESKA: TMP_H procitano %d\r\n", (int)rb); ok = 0; }

    return ok;
}

int main(void) {
    int ok;
    xil_printf("\r\n=== NCC akcelerator, FAZA 1 ===\r\n");
    ncc_hw_init();
    ok  = phase1(&NCC0, "ncc0");
    ok &= phase1(&NCC1, "ncc1");
    xil_printf(ok ? "FAZA 1: PROSLA\r\n" : "FAZA 1: PALA\r\n");
    while (1) { }
}
```

- [ ] **Korak 4: Izgradi**

```bash
cd "C:/Users/pc/Desktop/PSDS" && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/build_app.tcl
```

Očekivano: `@@@ BUILD OK: ...ncc_app.elf (<veličina> B)`.

- [ ] **Korak 5: Pusti na ploči**

Ploča mora biti povezana (JTAG meta `Digilent/210279A430A6A`). Otvori serijski terminal
na **115200 8N1** pre pokretanja.

```bash
cd "C:/Users/pc/Desktop/PSDS" && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/run_app.tcl
```

**Kriterijum FAZE 1:** UART ispisuje `FAZA 1: PROSLA`, oba bloka javljaju `busy=0`,
`IMG_W` pročitano 90 i `TMP_H` pročitano 30.

Ako UART ćuti: proveri baud iz `xparameters.h` (`XPAR_PS7_UART_1_BAUDRATE`) umesto da
pretpostavljaš 115200. Ako čitanje vraća `0xFFFFFFFF`: PL nije konfigurisan ili adresa
nije ta — vrati se na `fpga -file` korak.

- [ ] **Korak 6: Commit**

```bash
git add src/vitis/scripts/ src/vitis/app/ncc_hw.h src/vitis/app/ncc_hw.c src/vitis/app/main.c
git commit -m "Korak 9 Task 3.3: Vitis platforma, XSCT skripte, FAZA 1 (UART + AXI-Lite)"
```

---

### Task 4: Pristup S01 memorijama procesorom i FAZA 2

**Files:**
- Modify: `src/vitis/app/ncc_hw.h`, `src/vitis/app/ncc_hw.c`, `src/vitis/app/main.c`

**Interfaces:**
- Produces: `int ncc_load_image(const ncc_dev_t*, const u8 *px, u32 count);`
  `int ncc_load_tmpl(const ncc_dev_t*, const u8 *px, u32 count);`
  `void ncc_read_results(const ncc_dev_t*, u32 *dst, u32 count);`
  Vraćaju 0 na uspeh, != 0 na grešku.

- [ ] **Korak 1: Dodaj deklaracije u `ncc_hw.h`**

```c
#define NCC_IMG_MAX_WORDS  8192u
#define NCC_TMPL_MAX_WORDS 8192u

int  ncc_load_image  (const ncc_dev_t *d, const u8 *px, u32 count);
int  ncc_load_tmpl   (const ncc_dev_t *d, const u8 *px, u32 count);
void ncc_read_results(const ncc_dev_t *d, u32 *dst, u32 count);
```

- [ ] **Korak 2: Implementiraj upis procesorom u `ncc_hw.c`**

Dodaj na kraj fajla. **Ovo je privremena implementacija** — Task 6 je menja CDMA-om, a
interfejs ostaje isti:

```c
/* Sirenje 8 -> 32 bita: u S01 je jedan piksel po 32-bitnoj reci.
   U Tasku 6 ovo ide preko staging bafera i CDMA; sada pise procesor direktno. */
static int load_region(const ncc_dev_t *d, u32 off, const u8 *px, u32 count, u32 max) {
    u32 i;
    if (count > max) return -1;
    for (i = 0; i < count; i++) Xil_Out32(d->mem_base + off + 4u*i, (u32)px[i]);
    return 0;
}

int ncc_load_image(const ncc_dev_t *d, const u8 *px, u32 count) {
    return load_region(d, MEM_IMG_OFF, px, count, NCC_IMG_MAX_WORDS);
}

int ncc_load_tmpl(const ncc_dev_t *d, const u8 *px, u32 count) {
    return load_region(d, MEM_TMPL_OFF, px, count, NCC_TMPL_MAX_WORDS);
}

void ncc_read_results(const ncc_dev_t *d, u32 *dst, u32 count) {
    u32 i;
    for (i = 0; i < count; i++) dst[i] = Xil_In32(d->mem_base + MEM_RES_OFF + 4u*i);
}
```

- [ ] **Korak 3: Zameni `main.c` fazom 2**

```c
#include <stdio.h>
#include "xil_printf.h"
#include "ncc_hw.h"

static u8  pat[8100];
static u32 rb [8100];

static int phase2(const ncc_dev_t *d, const char *name) {
    u32 i; int bad = 0;

    for (i = 0; i < 8100u; i++) pat[i] = (u8)(i * 7u + 13u);   /* neponovljiv obrazac */

    if (ncc_load_image(d, pat, 8100u)) { xil_printf("%s: load_image odbio\r\n", name); return 0; }
    for (i = 0; i < 8100u; i++) rb[i] = Xil_In32(d->mem_base + MEM_IMG_OFF + 4u*i);
    for (i = 0; i < 8100u; i++)
        if (rb[i] != (u32)pat[i]) {
            if (bad < 3) xil_printf("%s slika[%d]: upisano %d procitano %d\r\n",
                                    name, (int)i, (int)pat[i], (int)rb[i]);
            bad++;
        }

    if (ncc_load_tmpl(d, pat, 2700u)) { xil_printf("%s: load_tmpl odbio\r\n", name); return 0; }
    for (i = 0; i < 2700u; i++) {
        u32 v = Xil_In32(d->mem_base + MEM_TMPL_OFF + 4u*i);
        if (v != (u32)pat[i]) {
            if (bad < 6) xil_printf("%s sablon[%d]: upisano %d procitano %d\r\n",
                                    name, (int)i, (int)pat[i], (int)v);
            bad++;
        }
    }

    xil_printf("%s: %d neslaganja\r\n", name, bad);
    return bad == 0;
}

int main(void) {
    int ok;
    xil_printf("\r\n=== NCC akcelerator, FAZA 2 ===\r\n");
    ncc_hw_init();
    ok  = phase2(&NCC0, "ncc0");
    ok &= phase2(&NCC1, "ncc1");
    xil_printf(ok ? "FAZA 2: PROSLA\r\n" : "FAZA 2: PALA\r\n");
    while (1) { }
}
```

Potreban je `#include "xil_io.h"` u `main.c` zbog `Xil_In32` — dodaj ga.

- [ ] **Korak 4: Izgradi i pusti**

```bash
cd "C:/Users/pc/Desktop/PSDS" && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/build_app.tcl && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/run_app.tcl
```

**Kriterijum FAZE 2:** `FAZA 2: PROSLA`, oba bloka `0 neslaganja`.

Ako neslaganja postoje samo na visokim indeksima, S01 opseg je manji nego što mislimo —
proveri `C_S01_AXI_ADDR_WIDTH = 17` (`BUGS.md`).

- [ ] **Korak 5: Commit**

```bash
git add src/vitis/app/ncc_hw.h src/vitis/app/ncc_hw.c src/vitis/app/main.c
git commit -m "Korak 9 Task 3.4: pristup S01 memorijama procesorom, FAZA 2"
```

---

### Task 5: Pokretanje jezgra i FAZA 3 (zlatni vektor iz Koraka 4)

**Files:**
- Modify: `src/vitis/app/ncc_hw.h`, `src/vitis/app/ncc_hw.c`, `src/vitis/app/main.c`

**Interfaces:**
- Produces: `void ncc_set_dims(const ncc_dev_t*, u8 iw, u8 ih, u8 tw, u8 th);`
  `void ncc_start(const ncc_dev_t*);`
  `int  ncc_wait_done(const ncc_dev_t*, u32 timeout_us);`  (0 = OK, -1 = timeout)
  `u32  ncc_best_score(const ncc_dev_t*, u32 n_results, u32 *idx_out);`

- [ ] **Korak 1: Dodaj deklaracije u `ncc_hw.h`**

```c
void ncc_set_dims  (const ncc_dev_t *d, u8 iw, u8 ih, u8 tw, u8 th);
void ncc_start     (const ncc_dev_t *d);
int  ncc_wait_done (const ncc_dev_t *d, u32 timeout_us);
u32  ncc_best_score(const ncc_dev_t *d, u32 n_results, u32 *idx_out);
```

- [ ] **Korak 2: Implementiraj u `ncc_hw.c`**

```c
#include "sleep.h"

void ncc_set_dims(const ncc_dev_t *d, u8 iw, u8 ih, u8 tw, u8 th) {
    /* Registri su 8-bitni; vrednosti > 255 su nemoguce po tipu, ali sirina je stvarna. */
    ncc_write_reg(d, REG_IMG_W, iw);
    ncc_write_reg(d, REG_IMG_H, ih);
    ncc_write_reg(d, REG_TMP_W, tw);
    ncc_write_reg(d, REG_TMP_H, th);
}

/* Upis bita 0 u CTRL daje start_pulse I brise done_sticky. */
void ncc_start(const ncc_dev_t *d) { ncc_write_reg(d, REG_CTRL, 1u); }

/* Nema prekida -- samo prozivanje. Timeout postoji da greska u konfiguraciji
   ne izgleda kao zamrznuta ploca. */
int ncc_wait_done(const ncc_dev_t *d, u32 timeout_us) {
    u32 waited = 0u;
    while ((ncc_read_reg(d, REG_STATUS) & STATUS_DONE_BIT) == 0u) {
        usleep(100);
        waited += 100u;
        if (waited >= timeout_us) return -1;
    }
    return 0;
}

/* INVARIJANT 1: poredjenje kao u32 (videti ncc_logic.c). */
/* INVARIJANT 1: poredjenje kao u32 (videti ncc_logic.c).
   Rezultata je do 3721 po pozivu, pa se u Tasku 6 citanje prebacuje na DMA;
   potpis se NE menja. Ovde je jos direktno citanje -- dovoljno za fazu 3. */
u32 ncc_best_score(const ncc_dev_t *d, u32 n_results, u32 *idx_out) {
    u32 i, v, mx = 0u, mi = 0u;
    for (i = 0; i < n_results; i++) {
        v = Xil_In32(d->mem_base + MEM_RES_OFF + 4u*i);
        if (v > mx) { mx = v; mi = i; }
    }
    if (idx_out) *idx_out = mi;
    return mx;
}
    if (idx_out) *idx_out = mi;
    return mx;
}
```

- [ ] **Korak 3: Zameni `main.c` fazom 3**

Zlatni slučaj iz Koraka 4: segment 90×90, šablon 25×15 (crni top), očekivan pik
`0x80000000` na poziciji `(u=32, v=14)`. Rezultata je
`(90-25+1) × (90-15+1) = 66 × 76 = 5016`; linearni indeks pika je `14*66 + 32 = 956`.

```c
#include "xil_printf.h"
#include "xil_io.h"
#include "ncc_hw.h"
#include "data.h"

#define GOLD_IW 90
#define GOLD_IH 90
#define GOLD_TW 25
#define GOLD_TH 15
#define GOLD_RW (GOLD_IW - GOLD_TW + 1)          /* 66 */
#define GOLD_RH (GOLD_IH - GOLD_TH + 1)          /* 76 */
#define GOLD_N  (GOLD_RW * GOLD_RH)              /* 5016 */
#define GOLD_EXPECT_SCORE 0x80000000u
#define GOLD_EXPECT_IDX   956u                   /* v=14, u=32 -> 14*66 + 32 */

static int phase3(const ncc_dev_t *d, const char *name) {
    u32 score, idx;

    if (ncc_load_image(d, GOLD_SEG,  8100u)) { xil_printf("%s: load_image odbio\r\n", name); return 0; }
    if (ncc_load_tmpl (d, GOLD_TMPL,  375u)) { xil_printf("%s: load_tmpl odbio\r\n",  name); return 0; }
    ncc_set_dims(d, GOLD_IW, GOLD_IH, GOLD_TW, GOLD_TH);
    ncc_start(d);
    if (ncc_wait_done(d, 2000000u)) { xil_printf("%s: TIMEOUT\r\n", name); return 0; }

    score = ncc_best_score(d, (u32)GOLD_N, &idx);
    xil_printf("%s: skor 0x%08x @ idx %d (u=%d v=%d)\r\n",
               name, score, (int)idx, (int)(idx % GOLD_RW), (int)(idx / GOLD_RW));

    if (score != GOLD_EXPECT_SCORE) { xil_printf("  GRESKA: ocekivano 0x80000000\r\n"); return 0; }
    if (idx   != GOLD_EXPECT_IDX)   { xil_printf("  GRESKA: ocekivan idx 956\r\n");     return 0; }
    return 1;
}

int main(void) {
    int ok;
    xil_printf("\r\n=== NCC akcelerator, FAZA 3 (zlatni vektor) ===\r\n");
    ncc_hw_init();
    ok  = phase3(&NCC0, "ncc0");
    ok &= phase3(&NCC1, "ncc1");
    xil_printf(ok ? "FAZA 3: PROSLA\r\n" : "FAZA 3: PALA\r\n");
    while (1) { }
}
```

- [ ] **Korak 4: Izgradi i pusti**

```bash
cd "C:/Users/pc/Desktop/PSDS" && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/build_app.tcl && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/run_app.tcl
```

**Kriterijum FAZE 3:** oba bloka javljaju `skor 0x80000000 @ idx 956 (u=32 v=14)`,
`FAZA 3: PROSLA`. To je **bit-identično** rezultatu iz Koraka 4 i Koraka 6.

Ako je skor 0: proveri redosled — `set_dims` mora doći **pre** `start`, a memorije pre
`set_dims`. Ako je TIMEOUT: `done_sticky` se briše startom, pa proveri da se `STATUS`
čita **posle** upisa u `CTRL`.

- [ ] **Korak 5: Commit**

```bash
git add src/vitis/app/ncc_hw.h src/vitis/app/ncc_hw.c src/vitis/app/main.c
git commit -m "Korak 9 Task 3.5: pokretanje jezgra, FAZA 3 -- zlatni vektor 0x80000000 @ 956"
```

---

### Task 6: CDMA umesto procesorskog upisa i FAZA 4

**Files:**
- Modify: `src/vitis/app/ncc_hw.c` (samo `load_region`), `src/vitis/app/main.c`

**Interfaces:**
- Interfejs se **ne menja** — `ncc_load_image`/`ncc_load_tmpl` zadržavaju potpis.
  To je smisao granice: faza 4 dokazuje CDMA bez diranja pozivaoca.

- [ ] **Korak 1: Zameni `load_region` verzijom sa staging baferom i CDMA**

U `ncc_hw.c`, dodaj uvoze i staging bafer na vrh:

```c
#include "xaxicdma.h"
#include "xparameters.h"
#include "xil_cache.h"

/* DRE je iskljucen (C_INCLUDE_DRE=0) -> izvor i odrediste moraju biti poravnati
   na 4 bajta. aligned(64) je sa rezervom i poklapa se sa linijom kesa. */
static u32 staging[NCC_IMG_MAX_WORDS] __attribute__((aligned(64)));
static XAxiCdma cdma;
static int cdma_ready = 0;
```

Zameni `ncc_hw_init`:

⚠️ **Ime `XPAR_*` simbola se NE pretpostavlja.** Vitis 2025.2 može koristiti stariji
device-ID tok (`XPAR_AXICDMA_0_DEVICE_ID`) ili noviji SDT tok sa baznim adresama
(`XPAR_XAXICDMA_0_BASEADDR`), zavisno od toga kako je platforma generisana. Prvo pogledaj
šta stvarno postoji:

```bash
cd "C:/Users/pc/Desktop/PSDS" && grep -rin "cdma" src/vitis/ws/ncc_plat/*/standalone*/bsp/*/include/xparameters.h | head
```

Upotrebi simbol koji ta komanda vrati. Ako je SDT tok, poziv postaje
`XAxiCdma_LookupConfig(XPAR_XAXICDMA_0_BASEADDR)`; ostatak funkcije je isti.

```c
int ncc_hw_init(void) {
    XAxiCdma_Config *cfg = XAxiCdma_LookupConfig(XPAR_AXICDMA_0_DEVICE_ID);
    if (!cfg) { xil_printf("CDMA: nema konfiguracije\r\n"); return -1; }
    if (XAxiCdma_CfgInitialize(&cdma, cfg, cfg->BaseAddress) != XST_SUCCESS) {
        xil_printf("CDMA: init pao\r\n"); return -1;
    }
    XAxiCdma_IntrDisable(&cdma, XAXICDMA_XR_IRQ_ALL_MASK);   /* prozivanje, ne prekidi */
    cdma_ready = 1;
    return 0;
}
```

Zameni `load_region`:

```c
static int load_region(const ncc_dev_t *d, u32 off, const u8 *px, u32 count, u32 max) {
    u32 i;
    int tries;
    if (count > max) return -1;
    if (!cdma_ready) return -2;

    /* 8 -> 32 bita: CDMA kopira bez konverzije formata. */
    for (i = 0; i < count; i++) staging[i] = (u32)px[i];

    /* Bafer je u kesiranom DDR-u; CDMA ga cita iz memorije, ne iz kesa. */
    Xil_DCacheFlushRange((UINTPTR)staging, count * 4u);

    /* INVARIJANT 2: nikad CDMA i procesor nad istim S01 istovremeno. */
    tries = 100000;
    while (XAxiCdma_IsBusy(&cdma)) { if (--tries <= 0) return -3; }

    if (XAxiCdma_SimpleTransfer(&cdma, (UINTPTR)staging,
                                (UINTPTR)(d->mem_base + off),
                                count * 4u, NULL, NULL) != XST_SUCCESS) return -4;

    tries = 100000;
    while (XAxiCdma_IsBusy(&cdma)) { if (--tries <= 0) return -5; }

    return (XAxiCdma_GetError(&cdma) != 0x0) ? -6 : 0;
}
```

- [ ] **Korak 1b: Prebaci i čitanje rezultata na DMA**

Rezultata je do **3721** po finom pozivu. Procesorsko čitanje bi bilo ~13.208 reči po
polju (~9,9 ms), odnosno **~317 ms na 32 polja = ~19 % ukupnog vremena**. Zato i rezultati
idu preko CDMA — kako poglavlje 9.3 stavka 7 već nalaže.

Dodaj u `ncc_hw.c` (staging bafer se ponovo koristi, smer je obrnut):

```c
/* CDMA: S01 -> DDR. Posle prenosa kes MORA biti ponisten nad baferom,
   inace procesor cita staru sadrzinu. */
static int fetch_results(const ncc_dev_t *d, u32 count) {
    int tries;
    if (count > NCC_IMG_MAX_WORDS) return -1;
    if (!cdma_ready) return -2;

    tries = 100000;
    while (XAxiCdma_IsBusy(&cdma)) { if (--tries <= 0) return -3; }

    if (XAxiCdma_SimpleTransfer(&cdma, (UINTPTR)(d->mem_base + MEM_RES_OFF),
                                (UINTPTR)staging, count * 4u, NULL, NULL) != XST_SUCCESS)
        return -4;

    tries = 100000;
    while (XAxiCdma_IsBusy(&cdma)) { if (--tries <= 0) return -5; }
    if (XAxiCdma_GetError(&cdma) != 0x0) return -6;

    Xil_DCacheInvalidateRange((UINTPTR)staging, count * 4u);
    return 0;
}
```

Zameni telo `ncc_best_score` tako da koristi taj bafer i **već testiranu**
`logic_max_u32` umesto sopstvene petlje:

```c
u32 ncc_best_score(const ncc_dev_t *d, u32 n_results, u32 *idx_out) {
    u32 i, mx = 0u, mi = 0u;
    if (fetch_results(d, n_results)) return 0u;      /* greska -> skor 0, ne lazni pik */
    for (i = 0; i < n_results; i++)
        if (staging[i] > mx) { mx = staging[i]; mi = i; }
    if (idx_out) *idx_out = mi;
    return mx;
}
```

Dodaj `#include "ncc_logic.h"` ako koristiš `logic_max_u32` za samu vrednost; indeks
ionako traži sopstvenu petlju, pa je gornja varijanta dovoljna.

⚠️ **Bez `Xil_DCacheInvalidateRange` ovo tiho vraća prethodni sadržaj bafera** — faza 4
bi prošla (isti podaci kao faza 3), a faza 5 davala besmislice. Ne izostavljaj ga.


- [ ] **Korak 2: Vrati `main.c` na fazu 3, samo promeni natpis**

Faza 4 je **isti test** kao faza 3 — jedina razlika je što prenos sada radi CDMA.
Promeni oba ispisa `FAZA 3` u `FAZA 4 (CDMA)`; sav ostali kod ostaje netaknut.

- [ ] **Korak 3: Izgradi i pusti**

```bash
cd "C:/Users/pc/Desktop/PSDS" && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/build_app.tcl && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/run_app.tcl
```

**Kriterijum FAZE 4:** `skor 0x80000000 @ idx 956` — **bit-identično fazi 3**.
Bilo kakvo odstupanje znači da je kriv CDMA ili keš, jer se ništa drugo nije promenilo.

Ako je skor 0 ili smeće: najverovatniji uzrok je izostao `Xil_DCacheFlushRange`.
Ako `load_region` vrati −3 ili −5: CDMA visi — proveri da je `XPAR_AXICDMA_0_DEVICE_ID`
stvarno naš blok (`xparameters.h`), i da je adresa `0x6000_0000`.

- [ ] **Korak 4: Commit**

```bash
git add src/vitis/app/ncc_hw.c src/vitis/app/main.c
git commit -m "Korak 9 Task 3.6: CDMA + staging bafer + kes, FAZA 4 bit-identicna fazi 3"
```

---

### Task 7: Logika po polju, petlja 8×8, FEN i FAZA 5

**Files:**
- Create: `src/vitis/app/ncc_app.h`, `src/vitis/app/ncc_app.c`
- Modify: `src/vitis/app/main.c`

**Interfaces:**
- Consumes: sve iz `ncc_hw.h`, `ncc_logic.h`, `data.h`
- Produces: `typedef struct { int occupied; int is_white; int best_tmpl; u32 best_score; } square_t;`
  `square_t app_scan_square(int m, int n);`

- [ ] **Korak 1: Napiši `ncc_app.h`**

```c
#ifndef NCC_APP_H
#define NCC_APP_H
#include "xil_types.h"

typedef struct { int occupied; int is_white; int best_tmpl; u32 best_score; } square_t;

square_t app_scan_square(int m, int n);
#endif
```

- [ ] **Korak 2: Napiši `ncc_app.c`**

```c
#include "ncc_app.h"
#include "ncc_hw.h"
#include "ncc_logic.h"
#include "data.h"
#include "xil_printf.h"

#define COARSE_TOPK 2
#define TIMEOUT_US  2000000u

static u8 seg_full  [SEG_W * SEG_H];        /* 8100 */
static u8 seg_coarse[(SEG_W/2) * (SEG_H/2)];/* 2025 */

/* Pokrece par sablona (drugi je opcion) i vraca njihove najbolje skorove. */
static void run_pair(int ta, int tb,
                     const unsigned char *const *TP, const int *TW, const int *TH,
                     int iw, int ih, u32 *sa, u32 *sb) {
    int rwa = iw - TW[ta] + 1, rha = ih - TH[ta] + 1;
    *sa = 0u; if (sb) *sb = 0u;

    ncc_load_tmpl(&NCC0, TP[ta], (u32)(TW[ta] * TH[ta]));
    ncc_set_dims (&NCC0, (u8)iw, (u8)ih, (u8)TW[ta], (u8)TH[ta]);
    if (tb >= 0) {
        ncc_load_tmpl(&NCC1, TP[tb], (u32)(TW[tb] * TH[tb]));
        ncc_set_dims (&NCC1, (u8)iw, (u8)ih, (u8)TW[tb], (u8)TH[tb]);
    }

    ncc_start(&NCC0);
    if (tb >= 0) ncc_start(&NCC1);

    if (ncc_wait_done(&NCC0, TIMEOUT_US)) { xil_printf("ncc0 TIMEOUT\r\n"); return; }
    *sa = ncc_best_score(&NCC0, (u32)(rwa * rha), NULL);

    if (tb >= 0) {
        int rwb = iw - TW[tb] + 1, rhb = ih - TH[tb] + 1;
        if (ncc_wait_done(&NCC1, TIMEOUT_US)) { xil_printf("ncc1 TIMEOUT\r\n"); return; }
        *sb = ncc_best_score(&NCC1, (u32)(rwb * rhb), NULL);
    }
}

square_t app_scan_square(int m, int n) {
    square_t r; int x, y, i, k, nc = 0, ncand;
    int cands[6], topk[COARSE_TOPK];
    u32 cscore[6];
    int cw = SEG_W / 2, ch = SEG_H / 2;
    int mean, sx = n * SEG_W, sy = m * SEG_H;

    r.occupied = 0; r.is_white = 0; r.best_tmpl = -1; r.best_score = 0u;

    if (logic_is_empty(BOARD_IMG, BOARD_W, sx, sy)) return r;
    r.occupied = 1;

    mean = logic_center_mean(BOARD_IMG, BOARD_W, sx, sy);
    r.is_white = logic_is_white(mean);
    for (i = 0; i < 6; i++) cands[nc++] = r.is_white ? i : 6 + i;
    ncand = nc;

    /* Izrezi segment iz table (stride 720) i napravi grubu verziju. */
    for (y = 0; y < SEG_H; y++)
        for (x = 0; x < SEG_W; x++)
            seg_full[y*SEG_W + x] = BOARD_IMG[(sy + y)*BOARD_W + (sx + x)];
    logic_downsample2x(seg_full, SEG_W, SEG_H, seg_coarse);

    /* --- GRUBI SCREEN: segment se upisuje JEDNOM, sabloni se menjaju --- */
    ncc_load_image(&NCC0, seg_coarse, (u32)(cw * ch));
    ncc_load_image(&NCC1, seg_coarse, (u32)(cw * ch));
    for (k = 0; k < ncand; k += 2) {
        int ta = cands[k];
        int tb = (k + 1 < ncand) ? cands[k + 1] : -1;
        u32 sa, sb;
        run_pair(ta, tb, TMPL_COARSE, TMPL_COARSE_W, TMPL_COARSE_H, cw, ch, &sa, &sb);
        cscore[k] = sa;
        if (tb >= 0) cscore[k + 1] = sb;
    }

    /* top-2 po grubom skoru (selekcija, ne sortiranje -- lista ima 6 elemenata) */
    for (i = 0; i < COARSE_TOPK; i++) {
        int best = -1; u32 bs = 0u; int j;
        for (j = 0; j < ncand; j++) {
            int already = 0, q;
            for (q = 0; q < i; q++) if (topk[q] == cands[j]) already = 1;
            if (!already && (best < 0 || cscore[j] > bs)) { best = cands[j]; bs = cscore[j]; }
        }
        topk[i] = best;
    }

    /* --- FINA POTVRDA nad top-2 --- */
    ncc_load_image(&NCC0, seg_full, (u32)(SEG_W * SEG_H));
    ncc_load_image(&NCC1, seg_full, (u32)(SEG_W * SEG_H));
    {
        u32 sa, sb;
        run_pair(topk[0], topk[1], TMPL_FULL, TMPL_FULL_W, TMPL_FULL_H,
                 SEG_W, SEG_H, &sa, &sb);
        /* INVARIJANT 1: poredjenje kao u32. */
        if (sa >= sb) { r.best_score = sa; r.best_tmpl = topk[0]; }
        else          { r.best_score = sb; r.best_tmpl = topk[1]; }
    }
    return r;
}
```

- [ ] **Korak 3: Napiši `main.c` za fazu 5**

```c
#include "xil_printf.h"
#include "xtime_l.h"
#include "ncc_hw.h"
#include "ncc_app.h"
#include "ncc_logic.h"

static const char FEN_MAP[12] = {'Q','N','K','B','P','R','q','n','k','b','p','r'};
/* Zvanicni FEN za board2.txt. Izvor: src/hls/test_real_data.cpp:51 (GOLDEN_FEN),
   isti koji je C model iz Koraka 1 reprodukovao 32/32. Provereno: 32 figure. */
static const char FEN_EXPECT[] = "rnbqkbnr/pp5p/4ppp1/2pp4/5P2/1P1BPN2/P1PPQ1PP/RNB1K2R";

static char board[8][8];
static char fen[128];

int main(void) {
    int m, n, occ = 0;
    XTime t0, t1;

    xil_printf("\r\n=== NCC akcelerator, FAZA 5 (pun tok) ===\r\n");
    if (ncc_hw_init()) { xil_printf("init pao\r\n"); while (1) {} }

    for (m = 0; m < 8; m++) for (n = 0; n < 8; n++) board[m][n] = ' ';

    XTime_GetTime(&t0);
    for (m = 0; m < 8; m++) {
        for (n = 0; n < 8; n++) {
            square_t s = app_scan_square(m, n);
            if (!s.occupied) continue;
            occ++;
            if (s.best_tmpl >= 0) board[m][n] = FEN_MAP[s.best_tmpl];
            xil_printf("(%d,%d) %s tmpl %d skor 0x%08x\r\n",
                       m, n, s.is_white ? "bela" : "crna", s.best_tmpl, s.best_score);
        }
    }
    XTime_GetTime(&t1);

    logic_fen((const char (*)[8])board, fen, sizeof fen);
    xil_printf("\r\nzauzetih polja: %d\r\n", occ);
    xil_printf("FEN:       %s\r\n", fen);
    xil_printf("ocekivano: %s\r\n", FEN_EXPECT);

    {
        u64 ticks = (u64)(t1 - t0);
        u32 ms = (u32)((ticks * 1000u) / COUNTS_PER_SECOND);
        xil_printf("vreme: %d ms (%d tikova)\r\n", (int)ms, (int)ticks);
    }

    {
        int i, same = 1;
        for (i = 0; fen[i] || FEN_EXPECT[i]; i++)
            if (fen[i] != FEN_EXPECT[i]) { same = 0; break; }
        xil_printf(same ? "FAZA 5: PROSLA\r\n" : "FAZA 5: PALA -- FEN se ne poklapa\r\n");
    }
    while (1) { }
}
```

- [ ] **Korak 4: Potvrdi da je očekivani FEN i dalje isti u izvoru**

`FEN_EXPECT` nije pogođen — prepisan je iz `src/hls/test_real_data.cpp:51`. Potvrdi da se
izvor nije promenio:

```bash
cd "C:/Users/pc/Desktop/PSDS" && grep -n "GOLDEN_FEN" src/hls/test_real_data.cpp
```

Očekivano: `rnbqkbnr/pp5p/4ppp1/2pp4/5P2/1P1BPN2/P1PPQ1PP/RNB1K2R` (32 figure).
Ako se razlikuje od onog u `main.c`, **izvor je merodavan**.

- [ ] **Korak 5: Izgradi i pusti**

```bash
cd "C:/Users/pc/Desktop/PSDS" && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/build_app.tcl && "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" src/vitis/scripts/run_app.tcl
```

**Kriterijum FAZE 5:** `zauzetih polja: 32`, FEN znak po znak jednak očekivanom,
`FAZA 5: PROSLA`. Zabeleži ispisano vreme u ms — treba za Task 8.

Ako je FEN blizu ali greši na par polja: ispis po polju pokazuje koje. Tada dodaj zlatne
skorove po polju iz C modela (odeljak 10 specifikacije) — dotad su nepotrebni.

- [ ] **Korak 6: Commit**

```bash
git add src/vitis/app/ncc_app.h src/vitis/app/ncc_app.c src/vitis/app/main.c
git commit -m "Korak 9 Task 3.7: logika po polju, petlja 8x8, FEN -- FAZA 5"
```

---

### Task 8: Merenje, dokumentacija i zatvaranje Koraka 9

**Files:**
- Modify: `PSDS Vault/Projects/NCC_Akcelerator/02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.html`
- Modify: `PSDS Vault/Projects/NCC_Akcelerator/CLAUDE.md`, `(C) Sljedeća sesija.md`

- [ ] **Korak 1: Potvrdi da poglavlje 9.3 NE treba menjati**

Ranija verzija plana je ovde tražila ispravku stavke 7 (rezultate čita procesor).
**Povučeno** — rezultata je 3721, ne 61, pa je DMA ispravan izbor i stavka 7 je već
tačna. Samo potvrdi da implementacija zaista koristi DMA za rezultate
(`fetch_results` u `ncc_hw.c`) i pređi dalje. Nijedno poglavlje i nijedna slika se ne
menjaju zbog ove odluke.


- [ ] **Korak 2: Reši nesklad oko 146 KB u poglavlju 9.5**

Specifikacija je izračunala **118.800 B = 116 KiB** po polju, a poglavlje 9.5 tvrdi
„oko 146 KB" bez izvođenja. Sada postoji **izmereno** vreme prenosa iz faze 5 — upiši
merenu brojku i pokaži izvođenje, ili ukloni tvrdnju. Ne ostavljaj nepotkrepljenu brojku.

- [ ] **Korak 3: Dodaj izmereno vreme u poglavlje 10.4**

Do sada su sve brojke propusnosti bile iz modela. Faza 5 daje **mereno vreme na ploči** —
dodaj ga uz postojeće, i uporedi sa ESL referencom (`board2.txt`, 2 NCC + optimizacije
= 3,667 s).

- [ ] **Korak 4: Regeneriši PDF i proveri renderom**

```bash
cd "C:/Users/pc/Desktop/PSDS/PSDS Vault/Projects/NCC_Akcelerator/02 Dokumentacija" && python -c "
import io,re,html
s=io.open('PSDS_dokumentacija_y25-g10_Korak2-8.html',encoding='utf-8').read()
print('komentari sa --:', len([c for c in re.findall(r'<!--.*?-->',s,re.S) if '--' in c[4:-3]]))
for t in ('table','tr','td','p','li','figcaption'):
    o=len(re.findall(r'<%s[ >]'%t,s)); c=len(re.findall(r'</%s>'%t,s))
    if o!=c: print('NEBALANS',t,o,c)
print('entiteti:', [e for e in set(re.findall(r'&[a-zA-Z]+;',s)) if html.unescape(e)==e] or 'ok')
"
```

Zatim headless Edge (**`--headless`, ne `--headless=old`** — uklonjen je u Edge 151):

```
--headless --disable-gpu --no-first-run --user-data-dir=<svez profil>
--virtual-time-budget=15000 --no-pdf-header-footer --print-to-pdf=<putanja bez razmaka>
```

⚠️ Edge vraća kontrolu **pre** nego što ispiše fajl — ne zaključuj da je pao ako
`Test-Path` odmah vrati `false`; sačekaj pa proveri veličinu i `%%EOF`.

⚠️ Ekstrakcija teksta iz ovog PDF-a **ne radi** (podskupljeni fontovi, tekst je
heksadecimalni glif). Provera je **gledanje renderovanih strana**, ne `grep`.

- [ ] **Korak 5: Ažuriraj stanje projekta**

U `CLAUDE.md` označi Task 3 i ceo Korak 9 kao završen, sa merenim vremenom.
U `(C) Sljedeća sesija.md` upiši da sledi **Korak 10** (`package_ip.tcl` + ulančavanje
celog toka do XSA; `package_ip.tcl` MORA na kraju zvati `fix_ip_package.tcl`).

- [ ] **Korak 6: Commit**

```bash
git add "PSDS Vault/"
git commit -m "Korak 9 Task 3.8: mereno vreme na ploci, ispravke poglavlja 9.3/9.5/10.4, PDF"
```

---

## Provera plana prema specifikaciji

| Zahtev iz specifikacije | Task |
|---|---|
| §1 kriterijum: FEN identičan zvaničnom | 7 (korak 5) |
| §2.1 registri, 8-bitne dimenzije, `done_sticky` | 3, 5 |
| §2.2 S01 regioni, 1 piksel/reč | 4 |
| §2.3 adresna mapa | 3 |
| §2.4 CDMA, poravnanje, simple mode | 6 |
| §2.5.1 poređenje kao `u32` | 2 (test), 5 (`ncc_best_score`) |
| §2.5.2 CDMA/CPU serijalizacija | 6 (`XAxiCdma_IsBusy`) |
| §3.1 interfejs `ncc_hw` | 3, 4, 5, 6 |
| §3.2 `app_scan_square` | 7 |
| §4 tok po polju, segment jednom po stepenu | 7 |
| §5 ugrađeni podaci i generator | 1 |
| §6 pet faza sa kriterijumima | 3, 4, 5, 6, 7 |
| §7 merenje `XTime` | 7, 8 |
| §8 ispravka poglavlja 9.3 | 8 |
| §9 rizici (keš, poravnanje, timeout, `int32`, baud) | 3, 5, 6 |
