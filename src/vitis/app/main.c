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
    xil_printf("\r\n=== NCC akcelerator, FAZA 4 (CDMA) (zlatni vektor) ===\r\n");
    ncc_hw_init();
    ok  = phase3(&NCC0, "ncc0");
    ok &= phase3(&NCC1, "ncc1");
    xil_printf(ok ? "FAZA 4 (CDMA): PROSLA\r\n" : "FAZA 4 (CDMA): PALA\r\n");
    while (1) { }
}
