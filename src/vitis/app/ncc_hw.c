#include "ncc_hw.h"
#include "xil_io.h"

const ncc_dev_t NCC0 = { 0x50000000u, 0x50020000u };
const ncc_dev_t NCC1 = { 0x51000000u, 0x51020000u };

int  ncc_hw_init(void) { return 0; }   /* CDMA se dodaje u Tasku 6 */
void ncc_write_reg(const ncc_dev_t *d, u32 off, u32 v) { Xil_Out32(d->ctrl_base + off, v); }
u32  ncc_read_reg (const ncc_dev_t *d, u32 off)        { return Xil_In32(d->ctrl_base + off); }
