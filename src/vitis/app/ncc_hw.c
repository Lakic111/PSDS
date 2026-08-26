#include "ncc_hw.h"
#include "xil_io.h"
#include "sleep.h"

const ncc_dev_t NCC0 = { 0x50000000u, 0x50020000u };
const ncc_dev_t NCC1 = { 0x51000000u, 0x51020000u };

int  ncc_hw_init(void) { return 0; }   /* CDMA se dodaje u Tasku 6 */
void ncc_write_reg(const ncc_dev_t *d, u32 off, u32 v) { Xil_Out32(d->ctrl_base + off, v); }
u32  ncc_read_reg (const ncc_dev_t *d, u32 off)        { return Xil_In32(d->ctrl_base + off); }

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
   ne izgleda kao zamrznuta ploca bez ijedne poruke. */
int ncc_wait_done(const ncc_dev_t *d, u32 timeout_us) {
    u32 waited = 0u;
    while ((ncc_read_reg(d, REG_STATUS) & STATUS_DONE_BIT) == 0u) {
        usleep(100);
        waited += 100u;
        if (waited >= timeout_us) return -1;
    }
    return 0;
}

/* INVARIJANT 1: poredjenje kao u32 (videti ncc_logic.c: logic_max_u32).
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
