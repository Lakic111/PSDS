// Testbench za ncc_kernel (Korak 1, TDD).
// "reference_ncc2" je NEZAVISNI golden oracle: čist int/__int128, BEZ ap_int,
// namerno odvojen od ncc_kernel.cpp da poređenje nešto stvarno dokazuje
// (isti kod kopiran na dva mesta bi samo potvrdio da se sam sebi slaže).
#include "ncc_kernel.hpp"
#include <cstdio>
#include <cstdint>
#include <vector>

static int g_failures = 0;

// Egzaktna celobrojna referenca: rezultat = floor((sum_num^2 << 31) / (sum_den_f*sum_den_t)),
// tj. isti NCC^2 u Q1.31 kao original, ali bez ikakvog float/double zaokruživanja usput.
static uint32_t reference_ncc2(const std::vector<int>& image, int img_w, int img_h,
                                const std::vector<int>& templ, int tmp_w, int tmp_h,
                                int u, int v) {
    long tsum = 0;
    for (int y = 0; y < tmp_h; y++)
        for (int x = 0; x < tmp_w; x++)
            tsum += templ[y * tmp_w + x];
    int count = tmp_w * tmp_h;
    int template_mean = (int)((tsum + (count >> 1)) / count);

    long sum_f = 0;
    for (int y = 0; y < tmp_h; y++)
        for (int x = 0; x < tmp_w; x++)
            sum_f += image[(v + y) * img_w + (u + x)];
    int f_bar = (int)((sum_f + (count >> 1)) / count);

    long long sum_num = 0, sum_den_f = 0, sum_den_t = 0;
    for (int y = 0; y < tmp_h; y++) {
        for (int x = 0; x < tmp_w; x++) {
            int diff_f = image[(v + y) * img_w + (u + x)] - f_bar;
            int diff_t = templ[y * tmp_w + x] - template_mean;
            sum_num   += (long long)diff_f * diff_t;
            sum_den_f += (long long)diff_f * diff_f;
            sum_den_t += (long long)diff_t * diff_t;
        }
    }
    if (sum_den_f == 0 || sum_den_t == 0) return 0;

    __int128 num_sq   = (__int128)sum_num * (__int128)sum_num;
    __int128 den_prod = (__int128)sum_den_f * (__int128)sum_den_t;
    __int128 scaled    = (num_sq << 31) / den_prod;  // floor -> truncacija, kao Q1.31
    if (scaled > 2147483648LL) scaled = 2147483648LL; // teorijski nedostižno (Cauchy-Schwarz), samo za svaki slučaj
    return (uint32_t)scaled;
}

static void check_point(const char* label, const result_t* result_map, int res_w,
                         const std::vector<int>& image, int img_w, int img_h,
                         const std::vector<int>& templ, int tmp_w, int tmp_h,
                         int u, int v) {
    uint32_t expected = reference_ncc2(image, img_w, img_h, templ, tmp_w, tmp_h, u, v);
    uint32_t actual = (uint32_t)result_map[v * res_w + u];
    if (actual != expected) {
        printf("[FAIL] %s (u=%d,v=%d): expected=%u actual=%u\n", label, u, v, expected, actual);
        g_failures++;
    } else {
        printf("[ OK ] %s (u=%d,v=%d): %u\n", label, u, v, actual);
    }
}

// Test A: 4x4 slika / 2x2 sablon, rucno proveren slucaj (razlicite NCC^2 vrednosti
// po tacki, uklj. tacan 0 i tacan max=2^31, da se uhvate i granicni slucajevi).
static void test_small_4x4() {
    printf("-- test_small_4x4 --\n");
    std::vector<int> image_i = {
        10,50,20,80,
        60,90,30,10,
        40,20,100,70,
        90,10,60,40
    };
    std::vector<int> templ_i = { 90,30,20,100 };
    const int img_w = 4, img_h = 4, tmp_w = 2, tmp_h = 2;

    pixel_t image[MAX_IMG_PIX];
    pixel_t templ[MAX_TMP_PIX];
    for (size_t i = 0; i < image_i.size(); i++) image[i] = (pixel_t)image_i[i];
    for (size_t i = 0; i < templ_i.size(); i++) templ[i] = (pixel_t)templ_i[i];

    result_t result_map[MAX_IMG_PIX];
    ncc_kernel(image, templ, img_w, img_h, tmp_w, tmp_h, result_map);

    int res_w = img_w - tmp_w + 1;
    int res_h = img_h - tmp_h + 1;
    for (int v = 0; v < res_h; v++)
        for (int u = 0; u < res_w; u++)
            check_point("4x4/2x2", result_map, res_w, image_i, img_w, img_h, templ_i, tmp_w, tmp_h, u, v);
}

// Test B: ivican slucaj nulte varijanse — prozor slike je konstantan (sve iste
// vrednosti) => sum_den_f=0 => rezultat MORA biti tacno 0 (deljenje nulom se
// izbegava), bez obzira sto je sablon promenljiv.
static void test_uniform_window_edge_case() {
    printf("-- test_uniform_window_edge_case --\n");
    const int img_w = 4, img_h = 4, tmp_w = 2, tmp_h = 2;
    std::vector<int> image_i = {
        50,50,50,50,
        50,50,50,50,
        50,50,50,50,
        50,50,50,50
    };
    std::vector<int> templ_i = { 10, 200, 30, 90 }; // sablon IMA varijansu

    pixel_t image[MAX_IMG_PIX];
    pixel_t templ[MAX_TMP_PIX];
    for (size_t i = 0; i < image_i.size(); i++) image[i] = (pixel_t)image_i[i];
    for (size_t i = 0; i < templ_i.size(); i++) templ[i] = (pixel_t)templ_i[i];

    result_t result_map[MAX_IMG_PIX];
    ncc_kernel(image, templ, img_w, img_h, tmp_w, tmp_h, result_map);

    int res_w = img_w - tmp_w + 1;
    bool ok = true;
    for (int i = 0; i < res_w * (img_h - tmp_h + 1); i++) {
        if (result_map[i] != 0) { ok = false; break; }
    }
    if (ok) { printf("[ OK ] uniform-window svi rezultati == 0\n"); }
    else    { printf("[FAIL] uniform-window ocekivano 0 svuda\n"); g_failures++; }
}

// Deterministicki pseudo-slucajni piksel (bez rand() zavisnosti od platforme) —
// isti seed uvek daje isti test, ponovljivo.
static int pseudo_pixel(int idx) {
    return (idx * 2654435761u >> 24) & 0xFF;
}

// Test C: pun opseg realnog segmenta (90x90 slika / 30x30 sablon, kao u
// projektnoj specifikaciji) — proverava sve pozicije (61x61 = 3721 tacaka)
// protiv nezavisnog oracle-a, hvata probleme koji se ne vide na malim testovima
// (bit-sirine akumulatora, indeksiranje SAT-a na granicama).
static void test_full_size_90x30() {
    printf("-- test_full_size_90x30 --\n");
    const int img_w = 90, img_h = 90, tmp_w = 30, tmp_h = 30;
    std::vector<int> image_i(img_w * img_h);
    std::vector<int> templ_i(tmp_w * tmp_h);
    for (int i = 0; i < img_w * img_h; i++) image_i[i] = pseudo_pixel(i);
    for (int i = 0; i < tmp_w * tmp_h; i++) templ_i[i] = pseudo_pixel(i * 7 + 3);

    pixel_t image[MAX_IMG_PIX];
    pixel_t templ[MAX_TMP_PIX];
    for (size_t i = 0; i < image_i.size(); i++) image[i] = (pixel_t)image_i[i];
    for (size_t i = 0; i < templ_i.size(); i++) templ[i] = (pixel_t)templ_i[i];

    result_t result_map[MAX_IMG_PIX];
    ncc_kernel(image, templ, img_w, img_h, tmp_w, tmp_h, result_map);

    int res_w = img_w - tmp_w + 1;
    int res_h = img_h - tmp_h + 1;
    int local_failures = 0;
    for (int v = 0; v < res_h; v++) {
        for (int u = 0; u < res_w; u++) {
            uint32_t expected = reference_ncc2(image_i, img_w, img_h, templ_i, tmp_w, tmp_h, u, v);
            uint32_t actual = (uint32_t)result_map[v * res_w + u];
            if (actual != expected) {
                if (local_failures < 5)
                    printf("[FAIL] full90x30 (u=%d,v=%d): expected=%u actual=%u\n", u, v, expected, actual);
                local_failures++;
            }
        }
    }
    if (local_failures == 0) {
        printf("[ OK ] full90x30 svih %d tacaka poklapa oracle\n", res_w * res_h);
    } else {
        printf("[FAIL] full90x30: %d/%d tacaka pogresno\n", local_failures, res_w * res_h);
        g_failures += local_failures;
    }
}

int main() {
    test_small_4x4();
    test_uniform_window_edge_case();
    test_full_size_90x30();

    if (g_failures == 0) {
        printf("\nSVI TESTOVI PROSLI\n");
        return 0;
    } else {
        printf("\n%d TEST(OVA) PALO\n", g_failures);
        return 1;
    }
}
