#ifndef NCC_APP_H
#define NCC_APP_H
#include "xil_types.h"

typedef struct { int occupied; int is_white; int best_tmpl; u32 best_score; } square_t;

square_t app_scan_square(int m, int n);
#endif
