#include <stdio.h>
#include "xil_printf.h"
#include "xil_io.h"
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
