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
    /* 4x4 -> 2x2, svaki izlaz je zaokruzen prosek 2x2 bloka: (s + 2) >> 2 */
    unsigned char src[16] = { 0,4,8,12,  4,8,12,16,  0,0,0,0,  8,8,8,8 };
    unsigned char dst[4];
    logic_downsample2x(src, 4, 4, dst);
    CHECK(dst[0] == 4,  "downsample [0]: s=16 -> 4");
    CHECK(dst[1] == 12, "downsample [1]: s=48 -> 12");
    CHECK(dst[2] == 4,  "downsample [2]: s=16 -> 4");
    CHECK(dst[3] == 4,  "downsample [3]: s=16 -> 4");
}

/* Gornji test je SLEP na razliku izmedju s/4 i (s+2)>>2 jer su sve sume
   tacni umnosci 4. Ovaj bira sume kod kojih zaokruzivanje odlucuje. */
static void test_downsample_zaokruzivanje(void) {
    unsigned char dst[1];
    /* s = 2 -> odsecanje daje 0, zaokruzivanje 1 */
    unsigned char a[4] = { 1,1,0,0 };
    logic_downsample2x(a, 2, 2, dst);
    CHECK(dst[0] == 1, "s=2 mora dati 1 (zaokruzivanje), ne 0 (odsecanje)");
    /* s = 6 -> odsecanje 1, zaokruzivanje 2 */
    unsigned char b[4] = { 3,3,0,0 };
    logic_downsample2x(b, 2, 2, dst);
    CHECK(dst[0] == 2, "s=6 mora dati 2, ne 1");
    /* s = 1 -> oba daju 0, granicni slucaj */
    unsigned char c[4] = { 1,0,0,0 };
    logic_downsample2x(c, 2, 2, dst);
    CHECK(dst[0] == 0, "s=1 mora dati 0");
}

/* Sinteticki testovi za logic_center_mean / logic_is_empty -- ne zavise od data.h,
   brzi su i samostalni. Segment mora biti dovoljno veliki da centar (redovi/kolone
   29..59 od (sx, sy)) i pixel (sy+10, sx+10) stanu unutar slike -- 100x100 je dovoljno
   za sx = sy = 0. */
static void test_center_mean_uniform(void) {
    unsigned char img[100 * 100];
    int i;
    for (i = 0; i < 100 * 100; i++) img[i] = 50;
    CHECK(logic_center_mean(img, 100, 0, 0) == 50, "center_mean na ujednacenoj povrsini vraca konstantu");
    CHECK(logic_is_empty(img, 100, 0, 0) == 1, "ujednacena povrsina -> prazno polje");
}

static void test_is_empty_center_pixel_differs(void) {
    unsigned char img[100 * 100];
    int i;
    for (i = 0; i < 100 * 100; i++) img[i] = 50;
    img[10 * 100 + 10] = 200; /* sx = sy = 0 -> pixel (10,10) */
    CHECK(logic_is_empty(img, 100, 0, 0) == 0, "razlicit pixel (10,10) -> nije prazno polje");
    CHECK(logic_center_mean(img, 100, 0, 0) == 50, "center_mean i dalje 50 -- (10,10) je van centra 29..59");
}

static void test_center_mean_known_sample(void) {
    unsigned char img[100 * 100];
    int i, x, y;
    for (i = 0; i < 100 * 100; i++) img[i] = 7;
    for (y = 29; y <= 44; y++)          /* 16 redova centra */
        for (x = 29; x <= 59; x++)      /* svih 31 kolona */
            img[y * 100 + x] = 20;
    /* Rucno izracunato: 16 redova * 31 kolonu = 496 celija sa vrednoscu 20,
       ostatak centra (15 redova * 31 kolonu = 465 celija) je 7.
       Suma = 496*20 + 465*7 = 9920 + 3255 = 13175.
       cnt = 31*31 = 961. mean = 13175 / 961 = 13 (celobrojno deljenje). */
    CHECK(logic_center_mean(img, 100, 0, 0) == 13, "center_mean na poznatom uzorku daje 13");
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
    CHECK(strcmp(out, "r6r/8/8/8/8/8/8/4K3") == 0, "puna fen linija za mesovitu tablu");
}

static void test_fen_figure_in_middle(void) {
    char b[8][8]; memset(b, ' ', sizeof b);
    b[3][3] = 'p';                        /* red: 3p4 (3 + 1 + 4 = 8) */
    char out[128];
    logic_fen(b, out, sizeof out);
    CHECK(strcmp(out, "8/8/8/3p4/8/8/8/8") == 0, "figura u sredini reda -> 3p4");
}

static void test_fen_small_buffer(void) {
    char b[8][8]; memset(b, ' ', sizeof b);

    char out1[1];
    out1[0] = 'X';
    logic_fen(b, out1, 1);
    CHECK(out1[0] == '\0', "out_sz=1: samo null terminator, bez upisa van granica");

    char out2[2];
    out2[0] = 'X'; out2[1] = 'X';
    logic_fen(b, out2, 2);
    CHECK(strlen(out2) <= 1, "out_sz=2: sadrzaj ne prelazi granicu bafera");
    CHECK(out2[strlen(out2)] == '\0', "out_sz=2: rezultat je null-terminisan");
}

static void test_is_white(void) {
    CHECK(logic_is_white(200) == 1, "200 > 140 -> bela");
    CHECK(logic_is_white(100) == 0, "100 <= 140 -> crna");
    CHECK(logic_is_white(140) == 0, "granica 140 nije bela (strogo vece)");
}

int main(void) {
    test_max_u32();
    test_downsample();
    test_downsample_zaokruzivanje();
    test_center_mean_uniform();
    test_is_empty_center_pixel_differs();
    test_center_mean_known_sample();
    test_fen_empty_board();
    test_fen_mixed();
    test_fen_figure_in_middle();
    test_fen_small_buffer();
    test_is_white();
    if (fails == 0) { printf("SVI TESTOVI PROSLI\n"); return 0; }
    printf("%d testova palo\n", fails);
    return 1;
}
