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
