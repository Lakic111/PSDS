#include "ncc.hpp"
#include <cstring>

using namespace sc_core;
using namespace tlm;
using namespace std;

// ============================================================================
//  PROCESNI MODEL (paralelnost):
//  - b_transport na CTRL=1 SAMO okine start_ev i odmah se vrati (ne računa
//    vreme obrade), pa CPU nije blokiran sekvencijalno.
//  - ncc_proc() je SC_THREAD: čeka start_ev, izračuna rezultat i kroz wait()
//    pusti da prođe modelovano vreme obrade, zatim javi done_ev.
//  - Učitavanje slike/šablona iz BRAM-a je na KRITIČNOJ putanji (IP mora da
//    pribavi podatke pre obrade), pa se njegovo vreme NAPLAĆUJE: read_from_bram
//    čeka kašnjenje koje je BRAM napunio takt po takt.
// ============================================================================

NCC_Target::NCC_Target(sc_module_name name) : sc_module(name), socket("socket"), i_bram("i_bram"),
    img_w(0), img_h(0), tmp_w(0), tmp_h(0), img_addr(0), tmp_addr(0), template_mean(0), hw_status(0),
    img_dirty(false) {
    socket.register_b_transport(this, &NCC_Target::b_transport);
    SC_THREAD(ncc_proc);
}

// NCC kao master čita iz BRAM-a. NCC je na kritičnoj putanji (mora da pribavi
// sliku i šablon pre obrade), pa se vreme ovog prenosa NAPLAĆUJE: pozivalac
// (ncc_proc, SC_THREAD) čeka 'scratch' koji je BRAM napunio takt po takt.
void NCC_Target::read_from_bram(uint64_t bram_addr, unsigned char* dst, unsigned int len) {
    sc_time scratch = SC_ZERO_TIME;
    tlm_generic_payload pl;
    pl.set_command(TLM_READ_COMMAND);
    pl.set_address(bram_addr - ADDR_BRAM);
    pl.set_data_ptr(dst);
    pl.set_data_length(len);
    i_bram->b_transport(pl, scratch);
    wait(scratch);   // čekanje na podatke iz BRAM-a (na kritičnoj putanji)
}

void NCC_Target::b_transport(tlm_generic_payload& trans, sc_time& delay) {
    tlm_command cmd = trans.get_command();
    uint64_t    addr = trans.get_address();
    unsigned char* ptr = trans.get_data_ptr();

    if (cmd == TLM_WRITE_COMMAND) {
        if (addr == REG_IMG_W) img_w = *(int*)ptr;
        else if (addr == REG_IMG_H) img_h = *(int*)ptr;
        else if (addr == REG_TMP_W) tmp_w = *(int*)ptr;
        else if (addr == REG_TMP_H) tmp_h = *(int*)ptr;
        else if (addr == REG_IMG_ADDR) {
            img_addr = *(uint32_t*)ptr;
            img_dirty = true;   // nov segment u BRAM-u -> NCC ga ponovo učita i izgradi SAT
        }
        else if (addr == REG_TMP_ADDR) {
            tmp_addr = *(uint32_t*)ptr;
        }
        else if (addr == REG_CTRL && *(uint32_t*)ptr == 1) {
            // Samo okidanje procesa - vreme obrade prolazi u ncc_proc(), ne ovde.
            hw_status = 0;          // BUSY
            start_ev.notify(SC_ZERO_TIME);
        }
        trans.set_response_status(TLM_OK_RESPONSE);
    }
    else if (cmd == TLM_READ_COMMAND) {
        unsigned int len = trans.get_data_length();
        if (addr == REG_STATUS) {
            memcpy(ptr, &hw_status, sizeof(uint32_t));
        }
        else if (addr == ADDR_RESULTS) {
            memcpy(ptr, result_map.data(), len);
        }
        trans.set_response_status(TLM_OK_RESPONSE);
    }
}

// SC_THREAD: hardverski blok koji radi paralelno sa CPU-om i DMA-om.
void NCC_Target::ncc_proc() {
    // (#6) Latencija NCC-a zavisi od STVARNOG posla: broj pozicija pretrage
    // (res_w·res_h) puta veličina šablona (tmp_w·tmp_h). Kalibrisano tako da
    // pun poziv (slika 90×90, šablon 30×30) ≈ 10.360.183 ciklusa kao u HLS
    // izveštaju. Time grubi screen (45×45) i manji šabloni realno koštaju manje,
    // pa coarse-to-fine i piramida donose stvarnu uštedu sim-vremena.
    const double K_CYC = 10360183.0 / (61.0 * 61.0 * 30.0 * 30.0);  // ≈ 3.094
    while (true) {
        wait(start_ev);
        hw_status = 0;

        // (#7) Sliku čitamo iz BRAM-a i SAT gradimo SAMO kad je CPU najavio nov
        // segment (upis REG_IMG_ADDR), a ne na svakom šablonu. Tako se isti
        // segment ne re-čita 6x po polju (jednom 6 šablona na ovaj blok).
        if (img_dirty) {
            image.resize((size_t)img_w * img_h);
            read_from_bram(img_addr, image.data(), (unsigned int)(img_w * img_h));
            build_integral_image();
            img_dirty = false;
        }

        // Šablon se menja svaki put -> uvek ga čitamo.
        templ.resize((size_t)tmp_w * tmp_h);
        read_from_bram(tmp_addr, templ.data(), (unsigned int)(tmp_w * tmp_h));
        calculate_template_mean();

        compute_full_matrix();

        long long res_w = (long long)img_w - tmp_w + 1;
        long long res_h = (long long)img_h - tmp_h + 1;
        if (res_w < 0) res_w = 0;
        if (res_h < 0) res_h = 0;
        long long work    = res_w * res_h * (long long)tmp_w * tmp_h;
        long long ciklusi = 1000 + (long long)(K_CYC * work);   // +1000 = fiksni overhead
        wait(ciklusi * 10, SC_NS);
        hw_status = 1;
        done_ev.notify();
    }
}

void NCC_Target::calculate_template_mean() {
    if (templ.empty()) { template_mean = 0; return; }
    uint32_t sum = 0;
    for (uint8_t val : templ) sum += val;
    unsigned n = (unsigned)templ.size();
    template_mean = (int)((sum + (n >> 1)) / n);
}

// (#8) Summed-area table (integral image): integral[(y+1)*W + (x+1)] = suma svih
// piksela u pravougaoniku (0,0)..(y,x). Gradi se jednom po segmentu, pa se suma
// proizvoljnog prozora dobija u O(1) sa 4 pristupa (umesto O(tmp_w*tmp_h)).
void NCC_Target::build_integral_image() {
    const int W = img_w + 1;
    integral.assign((size_t)W * (img_h + 1), 0);
    for (int y = 0; y < img_h; y++) {
        int64_t row_sum = 0;
        for (int x = 0; x < img_w; x++) {
            row_sum += image[y * img_w + x];
            integral[(y + 1) * W + (x + 1)] = integral[y * W + (x + 1)] + row_sum;
        }
    }
}

void NCC_Target::compute_full_matrix() {
    int res_w = img_w - tmp_w + 1;
    int res_h = img_h - tmp_h + 1;
    if (res_w <= 0 || res_h <= 0) return;

    result_map.assign(res_w * res_h, 0);
    for (int v = 0; v < res_h; v++) {
        for (int u = 0; u < res_w; u++) {
            result_t val = solve_single_point(u, v);
            result_map[v * res_w + u] = static_cast<int32_t>(val);
        }
    }
}

result_t NCC_Target::solve_single_point(int u, int v) {
    const int count = tmp_w * tmp_h;
    if (count == 0) return 0;

    // (#8) Suma piksela prozora u O(1) iz SAT-a (umesto dvostruke petlje).
    const int W = img_w + 1;
    int64_t sum_f = integral[(v + tmp_h) * W + (u + tmp_w)]
                  - integral[ v          * W + (u + tmp_w)]
                  - integral[(v + tmp_h) * W +  u         ]
                  + integral[ v          * W +  u         ];

    int f_bar = (int)((sum_f + (count >> 1)) / count);

    int64_t  sum_num   = 0;
    int64_t  sum_den_f = 0;
    int64_t  sum_den_t = 0;

    for (int y = 0; y < tmp_h; y++) {
        for (int x = 0; x < tmp_w; x++) {
            int diff_f = (int)image[(v + y) * img_w + (u + x)] - f_bar;
            int diff_t = (int)templ [y * tmp_w + x]            - template_mean;

            sum_num   += diff_f * diff_t;
            sum_den_f += diff_f * diff_f;
            sum_den_t += diff_t * diff_t;
        }
    }

    if (sum_den_f == 0 || sum_den_t == 0) return 0;

    uint64_t num_sq   = (uint64_t)(sum_num   * sum_num);
    uint64_t den_prod = (uint64_t)(sum_den_f * sum_den_t);
    if (den_prod == 0) return 0;

    // NCC^2 u Q1.31 fixed-point formatu (u HW-u bi bilo sc_ufixed<32,1>)
    double ncc2 = (double)num_sq / (double)den_prod;
    if (ncc2 > 1.0) ncc2 = 1.0;

    return (result_t)(ncc2 * 2147483648.0);
}
