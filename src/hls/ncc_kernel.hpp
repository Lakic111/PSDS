#ifndef NCC_KERNEL_HPP
#define NCC_KERNEL_HPP

#include <ap_int.h>
#include <ap_fixed.h>

// Maksimalne dimenzije koje kernel realno vidi u ovom projektu:
// pun segment/šablon (90x90 / 30x30) ili grubi coarse-to-fine prolaz (45x45 / 15x15).
// HLS ne podržava dinamičku alokaciju -> nizovi su statički, sa stvarnim img_w/h/tmp_w/h
// kao runtime granicama unutar tog fiksnog budžeta (isti obrazac kao registri u common.hpp).
static const int MAX_IMG_W = 90;
static const int MAX_IMG_H = 90;
static const int MAX_TMP_W = 30;
static const int MAX_TMP_H = 30;
static const int MAX_IMG_PIX = MAX_IMG_W * MAX_IMG_H;
static const int MAX_TMP_PIX = MAX_TMP_W * MAX_TMP_H;

// Bitske širine — TAČNO prema Tabeli 2 (ESL dokumentacija), sa DVE ISPRAVKE u odnosu
// na dokument (obrazloženje u ncc_kernel.cpp uz solve_single_point):
//   - diff_f/diff_t moraju biti POTPISANI (piksel - sredina može biti negativan),
//     dokument ih navodi kao sc_uint<9> što je numerički netačno za razliku.
//   - sum_num (suma diff_f*diff_t) mora biti POTPISAN iz istog razloga.
// Sve ostale širine (uključujući 9 i 27 bita) ostaju TAČNO kako piše u dokumentu —
// menja se samo signedness, ne broj bita.
typedef ap_uint<8>  pixel_t;      // f/t (piksel)
typedef ap_uint<18> winsum_t;     // sum_f (suma piksela prozora, iz SAT-a)
typedef ap_uint<8>  mean_t;       // f_bar / template_mean (zaokruženo)
typedef ap_int<9>   diffpix_t;    // diff_f / diff_t (ISPRAVKA: signed, ne sc_uint<9>)
typedef ap_int<27>  numacc_t;     // sum_num (ISPRAVKA: signed, ne sc_uint<27>)
typedef ap_uint<26> denacc_t;     // sum_den_f / sum_den_t
typedef ap_uint<52> sq52_t;       // num_sq / den_prod
typedef ap_ufixed<32, 1> ncc2_t;  // NCC^2 u Q1.31
typedef ap_uint<32> result_t;     // rezultat po poziciji prozora (isto kao common.hpp::result_t)

// Integral image (SAT) akumulator — NIJE u Tabeli 2 (interna struktura, ne deo
// solve_single_point datapath-a), dovoljno širok za sumu čitavog 90x90 segmenta
// (max 90*90*255 = 2.066.050, staje u 22 bita) — ap_uint<32> ostavlja marginu.
typedef ap_uint<32> sat_t;

// Top HLS funkcija — jedina koju HLS sintetiše, poziva podfunkcije ispod.
// image/templ ulazni segmenti (do MAX_IMG_PIX / MAX_TMP_PIX, popunjeni od (0,0)),
// img_w/h, tmp_w/h su stvarne runtime dimenzije (<= MAX_*), rezultat u result_map
// (Q1.31 NCC^2 po poziciji prozora, red-major, veličina (img_w-tmp_w+1)*(img_h-tmp_h+1)).
void ncc_kernel(
    const pixel_t image[MAX_IMG_PIX],
    const pixel_t templ[MAX_TMP_PIX],
    int img_w, int img_h, int tmp_w, int tmp_h,
    result_t result_map[MAX_IMG_PIX]
);

#endif // NCC_KERNEL_HPP
