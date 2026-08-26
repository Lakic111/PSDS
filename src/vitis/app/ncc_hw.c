/* ---------------------------------------------------------------------------
 * NCC_USE_CDMA -- da li prenose radi CDMA (1) ili procesor (0).
 *
 * TRENUTNO 0. Razlog: burstovi duzi od DVA beata zaglavljuju axi_interconnect_0
 * (STRATEGY=1, deljena magistrala). Izmereno na ploci preko JTAG-a, bez ovog koda:
 *     1 beat  RADI    2 beata RADI    3 beata ZAGLAVI    4 beata ZAGLAVI
 * i to podjednako za DDR->DDR (kroz HP0) i za S01->S01. CDMA, HP0, S01 i topologija
 * block designa su time iskljuceni -- kriv je burst kroz interkonekt. Detalji u
 * BUGS.md.
 *
 * Procesorski prenosi su DOKAZANO ispravni (faza 2: 8100 reci, 0 neslaganja; faza 3:
 * zlatni vektor 0x80000000 @ 956). Poglavlje 9.5 dokumentacije navodi da DMA donosi
 * ~6 % ukupnog vremena, pa je cena mala.
 *
 * Kad se interkonekt popravi (izmestanje AXI-Lite slave-ova na zaseban), dovoljno je
 * ovde staviti 1 -- ostatak koda je netaknut.
 * ------------------------------------------------------------------------- */
#define NCC_USE_CDMA 0

#include "ncc_hw.h"
#include "xil_io.h"
#include "sleep.h"
#if NCC_USE_CDMA
#include "xaxicdma.h"
#include "xparameters.h"
#include "xil_cache.h"
#endif

const ncc_dev_t NCC0 = { 0x50000000u, 0x50020000u };
const ncc_dev_t NCC1 = { 0x51000000u, 0x51020000u };

#if NCC_USE_CDMA
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
    XAxiCdma_IntrDisable(&cdma, XAXICDMA_XR_IRQ_ALL_MASK);
    cdma_ready = 1;
    return 0;
}
#else
/* Procesorski prenosi ne traze nikakvu inicijalizaciju. */
int ncc_hw_init(void) { return 0; }
#endif


void ncc_write_reg(const ncc_dev_t *d, u32 off, u32 v) { Xil_Out32(d->ctrl_base + off, v); }
u32  ncc_read_reg (const ncc_dev_t *d, u32 off)        { return Xil_In32(d->ctrl_base + off); }

/* Sirenje 8 -> 32 bita: u S01 je jedan piksel po 32-bitnoj reci.
   Prenos radi CDMA preko staging bafera; procesor samo priprema podatke u DDR-u. */
#if NCC_USE_CDMA
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
#else
/* Procesorski upis: sirenje 8 -> 32 bita (u S01 je jedan piksel po reci).
   Jednobeat transakcije -- dokazano ispravne u fazi 2 (8100 reci, 0 neslaganja).
   Burst se ne koristi jer ga interkonekt ne prezivljava (BUGS.md). */
static int load_region(const ncc_dev_t *d, u32 off, const u8 *px, u32 count, u32 max) {
    u32 i;
    if (count > max) return -1;
    for (i = 0; i < count; i++) Xil_Out32(d->mem_base + off + 4u*i, (u32)px[i]);
    return 0;
}
#endif


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
#if NCC_USE_CDMA
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
#else
/* INVARIJANT 1: poredjenje kao u32. 0x80000000 je NCC^2 = 1,0 (savrseno poklapanje);
   kao int32 je negativan, pa bi trazenje maksimuma od -1 odbacilo bas najbolji
   rezultat. Referentni collect() u src/tb.cpp ima bas tu gresku. */
u32 ncc_best_score(const ncc_dev_t *d, u32 n_results, u32 *idx_out) {
    u32 i, v, mx = 0u, mi = 0u;
    for (i = 0; i < n_results; i++) {
        v = Xil_In32(d->mem_base + MEM_RES_OFF + 4u*i);
        if (v > mx) { mx = v; mi = i; }
    }
    if (idx_out) *idx_out = mi;
    return mx;
}
#endif

