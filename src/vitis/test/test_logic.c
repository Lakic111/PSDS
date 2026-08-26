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
    test_downsample_zaokruzivanje();
    test_fen_empty_board();
    test_fen_mixed();
    test_is_white();
    if (fails == 0) { printf("SVI TESTOVI PROSLI\n"); return 0; }
    printf("%d testova palo\n", fails);
    return 1;
}
