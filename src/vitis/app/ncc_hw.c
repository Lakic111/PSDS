#include "ncc_hw.h"
#include "xil_io.h"
#include "sleep.h"
#include "xaxicdma.h"
#include "xparameters.h"
#include "xil_cache.h"

const ncc_dev_t NCC0 = { 0x50000000u, 0x50020000u };
const ncc_dev_t NCC1 = { 0x51000000u, 0x51020000u };

/* DRE je iskljucen (C_INCLUDE_DRE=0) -> izvor i odrediste moraju biti poravnati
   na 4 bajta. aligned(64) je sa rezervom i poklapa se sa linijom kesa. */
static u32 staging[NCC_IMG_MAX_WORDS] __attribute__((aligned(64)));
static XAxiCdma cdma;
static int cdma_ready = 0;

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

void ncc_write_reg(const ncc_dev_t *d, u32 off, u32 v) { Xil_Out32(d->ctrl_base + off, v); }
u32  ncc_read_reg (const ncc_dev_t *d, u32 off)        { return Xil_In32(d->ctrl_base + off); }

/* Sirenje 8 -> 32 bita: u S01 je jedan piksel po 32-bitnoj reci.
   Prenos radi CDMA preko staging bafera; procesor samo priprema podatke u DDR-u. */
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

/* INVARIJANT 1: poredjenje kao u32 (videti ncc_logic.c: logic_max_u32).
   Rezultata je do 3721 po pozivu; citanje ide preko CDMA u staging bafer. */
u32 ncc_best_score(const ncc_dev_t *d, u32 n_results, u32 *idx_out) {
    u32 i, mx = 0u, mi = 0u;
    if (fetch_results(d, n_results)) return 0u;      /* greska -> skor 0, ne lazni pik */
    for (i = 0; i < n_results; i++)
        if (staging[i] > mx) { mx = staging[i]; mi = i; }
    if (idx_out) *idx_out = mi;
    return mx;
}
