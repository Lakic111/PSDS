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
