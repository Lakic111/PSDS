#include "ncc_hw.h"
#include "xil_io.h"

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
