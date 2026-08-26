#ifndef NCC_HW_H
#define NCC_HW_H
#include "xil_types.h"

typedef struct { u32 ctrl_base; u32 mem_base; } ncc_dev_t;
extern const ncc_dev_t NCC0, NCC1;

#define REG_IMG_W  0x00u
#define REG_IMG_H  0x04u
#define REG_TMP_W  0x08u
#define REG_TMP_H  0x0Cu
#define REG_CTRL   0x30u
#define REG_STATUS 0x34u
/* 0x10 IMG_ADDR i 0x14 TMP_ADDR su REZERVISANI -- ne koristiti. */

#define MEM_IMG_OFF  0x00000u
#define MEM_TMPL_OFF 0x08000u
#define MEM_RES_OFF  0x10000u

#define STATUS_DONE_BIT 0x1u
#define STATUS_BUSY_BIT 0x2u

int  ncc_hw_init  (void);
void ncc_write_reg(const ncc_dev_t *d, u32 off, u32 v);
u32  ncc_read_reg (const ncc_dev_t *d, u32 off);
#endif
