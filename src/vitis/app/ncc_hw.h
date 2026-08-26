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

#define NCC_IMG_MAX_WORDS  8192u
#define NCC_TMPL_MAX_WORDS 8192u

int  ncc_load_image  (const ncc_dev_t *d, const u8 *px, u32 count);
int  ncc_load_tmpl   (const ncc_dev_t *d, const u8 *px, u32 count);
void ncc_read_results(const ncc_dev_t *d, u32 *dst, u32 count);

void ncc_set_dims  (const ncc_dev_t *d, u8 iw, u8 ih, u8 tw, u8 th);
void ncc_start     (const ncc_dev_t *d);
int  ncc_wait_done (const ncc_dev_t *d, u32 timeout_us);
u32  ncc_best_score(const ncc_dev_t *d, u32 n_results, u32 *idx_out);
#endif
