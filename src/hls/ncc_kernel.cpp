#include "ncc_kernel.hpp"

// ============================================================================
// HLS C++ kernel (Korak 1) — čist algoritam, bez SystemC/TLM, port iz
// src/ncc.cpp (build_integral_image, calculate_template_mean,
// compute_full_matrix, solve_single_point) na ap_uint/ap_int tipove tačno
// prema Tabeli 2 (ESL dokumentacija), sa dve ispravke signedness-a (vidi
// ncc_kernel.hpp: diffpix_t, numacc_t moraju biti signed, dokument ih pogrešno
// navodi kao sc_uint).
//
// Finalna Q1.31 podela (num_sq/den_prod) se radi kao TAČNA celobrojna podela
// (num_sq << 31) / den_prod, ne double množenje kao u ncc.cpp — time je
// izlaz bit-egzaktan (bez zaokruživanja u floating point-u), i granični slučaj
// ncc2 > 1.0 iz ncc.cpp (postojao samo zbog double zaokruživanja) ovde
// matematički ne može da se desi: num_sq <= den_prod je Cauchy-Schwarz
// nejednakost nad diff_f/diff_t vektorima, egzaktna u celobrojnoj aritmetici.
// ============================================================================

typedef ap_uint<96> wide_t;  // num_sq (52b) << 31 -> do 83b, marginalna sirina za deljenje

static void build_integral_image(const pixel_t image[MAX_IMG_PIX], int img_w, int img_h,
                                  sat_t integral[(MAX_IMG_W + 1) * (MAX_IMG_H + 1)]) {
    const int W = img_w + 1;
    for (int i = 0; i < (img_w + 1) * (img_h + 1); i++) integral[i] = 0;

    for (int y = 0; y < img_h; y++) {
        sat_t row_sum = 0;
        for (int x = 0; x < img_w; x++) {
            row_sum += image[y * img_w + x];
            integral[(y + 1) * W + (x + 1)] = integral[y * W + (x + 1)] + row_sum;
        }
    }
}

static mean_t calculate_template_mean(const pixel_t templ[MAX_TMP_PIX], int tmp_w, int tmp_h) {
    int count = tmp_w * tmp_h;
    if (count == 0) return 0;
    sat_t sum = 0;
    for (int y = 0; y < tmp_h; y++)
        for (int x = 0; x < tmp_w; x++)
            sum += templ[y * tmp_w + x];
    return (mean_t)((sum + (count >> 1)) / count);
}

static result_t solve_single_point(const pixel_t image[MAX_IMG_PIX], int img_w,
                                    const sat_t integral[(MAX_IMG_W + 1) * (MAX_IMG_H + 1)],
                                    const pixel_t templ[MAX_TMP_PIX], int tmp_w, int tmp_h,
                                    mean_t template_mean, int u, int v) {
    const int count = tmp_w * tmp_h;
    if (count == 0) return 0;

    const int W = img_w + 1;
    sat_t sum_f = integral[(v + tmp_h) * W + (u + tmp_w)]
                - integral[ v          * W + (u + tmp_w)]
                - integral[(v + tmp_h) * W +  u         ]
                + integral[ v          * W +  u         ];
    mean_t f_bar = (mean_t)((sum_f + (count >> 1)) / count);

    numacc_t sum_num   = 0;
    denacc_t sum_den_f = 0;
    denacc_t sum_den_t = 0;

    for (int y = 0; y < tmp_h; y++) {
        for (int x = 0; x < tmp_w; x++) {
            diffpix_t diff_f = (diffpix_t)image[(v + y) * img_w + (u + x)] - (diffpix_t)f_bar;
            diffpix_t diff_t = (diffpix_t)templ[y * tmp_w + x]             - (diffpix_t)template_mean;

            sum_num   += (numacc_t)(diff_f * diff_t);
            sum_den_f += (denacc_t)(diff_f * diff_f);
            sum_den_t += (denacc_t)(diff_t * diff_t);
        }
    }

    if (sum_den_f == 0 || sum_den_t == 0) return 0;

    sq52_t num_sq   = (sq52_t)(sum_num * sum_num);
    sq52_t den_prod = (sq52_t)sum_den_f * (sq52_t)sum_den_t;

    wide_t scaled = ((wide_t)num_sq << 31) / (wide_t)den_prod;
    return (result_t)scaled;
}

void ncc_kernel(
    const pixel_t image[MAX_IMG_PIX],
    const pixel_t templ[MAX_TMP_PIX],
    int img_w, int img_h, int tmp_w, int tmp_h,
    result_t result_map[MAX_IMG_PIX]
) {
    static sat_t integral[(MAX_IMG_W + 1) * (MAX_IMG_H + 1)];
    build_integral_image(image, img_w, img_h, integral);

    mean_t template_mean = calculate_template_mean(templ, tmp_w, tmp_h);

    int res_w = img_w - tmp_w + 1;
    int res_h = img_h - tmp_h + 1;
    if (res_w <= 0 || res_h <= 0) return;

    for (int v = 0; v < res_h; v++) {
        for (int u = 0; u < res_w; u++) {
            result_map[v * res_w + u] =
                solve_single_point(image, img_w, integral, templ, tmp_w, tmp_h, template_mean, u, v);
        }
    }
}
