#include "tb.hpp"
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <algorithm>

using namespace sc_core;
using namespace tlm;
using namespace std;

tb_vp::tb_vp(sc_module_name name) : sc_module(name), isoc("isoc") {
    SC_THREAD(test);
}

// 2x2 box-average downsample. Usrednjavanje (ne decimacija) -> tanke linije
// (prorez lovca, krst kralja) se ne gube/aliasuju. Radi za parne i neparne dim.
void tb_vp::downsample2x(const vector<uint8_t>& src, int w, int h,
                         vector<uint8_t>& dst, int& dw, int& dh) {
    dw = w / 2;  dh = h / 2;
    dst.resize((size_t)dw * dh);
    for (int y = 0; y < dh; y++)
        for (int x = 0; x < dw; x++) {
            int s = src[(2*y)  * w + 2*x] + src[(2*y)  * w + 2*x + 1]
                  + src[(2*y+1)* w + 2*x] + src[(2*y+1)* w + 2*x + 1];
            dst[y*dw + x] = (uint8_t)((s + 2) >> 2);   // +2 = zaokruživanje
        }
}

void tb_vp::loadFile(string path, vector<uint8_t>& data, int& w, int& h) {
    ifstream f(path);
    if(!f.is_open()) { cout << "[WARNING] Missing: " << path << endl; return; }
    string line; h = 0; w = 0;
    while (getline(f, line)) {
        stringstream ss(line); string val; int row_w = 0;
        while (getline(ss, val, ',')) {
            data.push_back(static_cast<uint8_t>(stod(val)));
            row_w++;
        }
        if (w == 0) w = row_w; h++;
    }
}

void tb_vp::test() {
    vector<uint8_t> img_raw;
    int iw = 720, ih = 720;
    sc_time delay = SC_ZERO_TIME;

    // FEN Mapping and Board State Array
    char fen_map[12] = {'Q', 'N', 'K', 'B', 'P', 'R', 'q', 'n', 'k', 'b', 'p', 'r'};
    char board_state[8][8];
    for(int i=0; i<8; i++) for(int j=0; j<8; j++) board_state[i][j] = ' ';

    // Slika cele table -> DDR (PS memorija)
    loadFile("data/board2.txt", img_raw, iw, ih);
    send_data(ADDR_DDR, img_raw, delay);

    const string template_names[12] = {
        "data/Belakraljicatemplate.txt", "data/Belikonjtemplate.txt", "data/Belikraljtemplate.txt",
        "data/Belilovactemplate.txt", "data/Belipesaktemplate.txt", "data/Belitoptemplate.txt",
        "data/Crnakraljicatemplate.txt", "data/Crnikonjtemplate.txt", "data/Crnikraljtemplate.txt",
        "data/Crnilovactemplate.txt", "data/Crnipesaktemplate.txt", "data/Crnitoptemplate.txt"
    };

    // Šabloni -> BRAM (CPU ih upisuje preko sys_bus)
    vector<vector<uint8_t>> templates(12);
    int t_w[12], t_h[12];
    uint64_t current_bram_offset = 0;
    uint64_t template_bram_addrs[12];

    // (#4) Grubi (2x smanjeni) šabloni za coarse screen, jednom pri učitavanju.
    int ct_w[12] = {0}, ct_h[12] = {0};
    uint64_t coarse_tmpl_addrs[12] = {0};
    uint64_t coarse_offset = 0;

    for (int i = 0; i < 12; i++) {
        loadFile(template_names[i], templates[i], t_w[i], t_h[i]);
        template_bram_addrs[i] = ADDR_BRAM + current_bram_offset;
        if (!templates[i].empty()) {
            send_data(template_bram_addrs[i], templates[i], delay);
            current_bram_offset += templates[i].size();

            vector<uint8_t> tc;
            downsample2x(templates[i], t_w[i], t_h[i], tc, ct_w[i], ct_h[i]);
            coarse_tmpl_addrs[i] = ADDR_BRAM + BRAM_TMP_COARSE + coarse_offset;
            send_data(coarse_tmpl_addrs[i], tc, delay);
            coarse_offset += tc.size();
        }
    }

    int seg_w = 90, seg_h = 90;
    const int COLOR_THRESHOLD = 140;   // centralna srednja vred. > prag -> bela figura
    const int COARSE_TOPK     = 2;     // koliko kandidata sa grubog screena ide u finu potvrdu

    // --- pomoćne lambde za upravljanje NCC blokovima ---
    auto set_img = [&](uint64_t base, int w, int h, uint64_t addr) {
        write_reg32(base + REG_IMG_W, w, delay);
        write_reg32(base + REG_IMG_H, h, delay);
        write_reg32(base + REG_IMG_ADDR, (uint32_t)addr, delay);
    };
    auto launch = [&](uint64_t base, int tw, int th, uint64_t taddr) {
        write_reg32(base + REG_TMP_W, tw, delay);
        write_reg32(base + REG_TMP_H, th, delay);
        write_reg32(base + REG_TMP_ADDR, (uint32_t)taddr, delay);
        write_reg32(base + REG_CTRL, 1, delay);
    };
    auto collect = [&](uint64_t base, int imgw, int imgh, int tw, int th) -> int32_t {
        int rw = imgw - tw + 1, rh = imgh - th + 1;
        if (rw <= 0 || rh <= 0) return -1;
        int rp = rw * rh;
        vector<int32_t> rr(rp);
        read_data(base + ADDR_RESULTS, (uint8_t*)rr.data(), rp * sizeof(int32_t), delay);
        int32_t mx = -1;
        for (int i = 0; i < rp; i++) if (rr[i] > mx) mx = rr[i];
        return mx;
    };
    // Obradi listu šablona u PAROVIMA (NCC0/NCC1 paralelno); scores[] paralelno idxs[].
    auto run_pairs = [&](const vector<int>& idxs, const int* TW, const int* TH,
                         const uint64_t* TADDR, int imgw, int imgh, vector<int32_t>& scores) {
        scores.assign(idxs.size(), -1);
        for (size_t k = 0; k < idxs.size(); k += 2) {
            int ta = idxs[k];
            bool hb = (k + 1 < idxs.size());
            int tb_ = hb ? idxs[k + 1] : -1;
            launch(ADDR_NCC, TW[ta], TH[ta], TADDR[ta]);
            if (hb) launch(ADDR_NCC1, TW[tb_], TH[tb_], TADDR[tb_]);
            if (hb) wait(*m_ncc0_done & *m_ncc1_done);
            else    wait(*m_ncc0_done);
            scores[k] = collect(ADDR_NCC, imgw, imgh, TW[ta], TH[ta]);
            if (hb) scores[k + 1] = collect(ADDR_NCC1, imgw, imgh, TW[tb_], TH[tb_]);
        }
    };

    int executed_count = 0;

    for (int m = 0; m < 8; m++) {
        for (int n = 0; n < 8; n++) {

            uint64_t ddr_seg_addr  = ADDR_DDR + (m * seg_h * iw) + (n * seg_w);

            // Provjera praznog polja direktno iz DDR-a (bez DMA-a).
            // Čitamo centralnu zonu segmenta red po red (stride-aware).
            int sum = 0, count = 0;
            for (int y = 29; y <= 59; y++) {
                vector<uint8_t> row_buf(31);
                read_data(ADDR_DDR + ((m * seg_h + y) * iw) + (n * seg_w + 29), row_buf, delay);
                for (uint8_t v : row_buf) { sum += v; count++; }
            }
            int mean = sum / count;

            uint8_t p10_val;
            read_data(ADDR_DDR + ((m * seg_h + 10) * iw) + (n * seg_w + 10), &p10_val, 1, delay);

            if (mean != (int)p10_val) {
                uint64_t full_seg_addr   = ADDR_BRAM + BRAM_SEG_FULL;
                uint64_t coarse_seg_addr = ADDR_BRAM + BRAM_SEG_COARSE;

                // DMA puni pun 90x90 segment u BRAM (za finu potvrdu, stage 2).
                configure_dma(ddr_seg_addr, full_seg_addr, seg_w, seg_h, iw, seg_w, delay);
                wait(*m_dma_done);

                // (#1) Klasifikacija boje iz iste centralne srednje vrednosti:
                // bele figure -> visok intenzitet, crne -> nizak (jaz ~116..178).
                // Testiramo SAMO 6 šablona te boje (0..5 bele, 6..11 crne).
                bool is_white = (mean > COLOR_THRESHOLD);
                vector<int> cands;
                for (int i = 0; i < 6; i++) {
                    int t = is_white ? i : 6 + i;
                    if (!templates[t].empty()) cands.push_back(t);
                }

                cout << "\n[TB] Segment (" << m << "," << n << ") "
                     << (is_white ? "WHITE" : "black") << " -> " << cands.size()
                     << " kandidata, coarse 45x45 screen -> top-" << COARSE_TOPK << endl;

                // (#4) Grubi segment 45x45: izrežemo 90x90 iz table i 2x2 usrednjimo.
                vector<uint8_t> seg((size_t)seg_w * seg_h);
                for (int y = 0; y < seg_h; y++)
                    for (int x = 0; x < seg_w; x++)
                        seg[y*seg_w + x] = img_raw[(m*seg_h + y)*iw + (n*seg_w + x)];
                vector<uint8_t> seg_c; int cseg_w, cseg_h;
                downsample2x(seg, seg_w, seg_h, seg_c, cseg_w, cseg_h);
                send_data(coarse_seg_addr, seg_c, delay);

                int32_t absolute_max = -1;
                int best_template_idx = -1;

                if (!cands.empty()) {
                    // --- STAGE 1: grubi screen (45x15) nad svim kandidatima ---
                    set_img(ADDR_NCC,  cseg_w, cseg_h, coarse_seg_addr);
                    set_img(ADDR_NCC1, cseg_w, cseg_h, coarse_seg_addr);
                    vector<int32_t> cscore;
                    run_pairs(cands, ct_w, ct_h, coarse_tmpl_addrs, cseg_w, cseg_h, cscore);

                    // top-K kandidata po grubom skoru
                    vector<int> order(cands.size());
                    for (size_t i = 0; i < order.size(); i++) order[i] = (int)i;
                    sort(order.begin(), order.end(),
                         [&](int a, int b) { return cscore[a] > cscore[b]; });
                    int K = min(COARSE_TOPK, (int)cands.size());
                    vector<int> topk;
                    for (int i = 0; i < K; i++) topk.push_back(cands[order[i]]);

                    // --- STAGE 2: fina potvrda (90x30) nad top-K ---
                    set_img(ADDR_NCC,  seg_w, seg_h, full_seg_addr);
                    set_img(ADDR_NCC1, seg_w, seg_h, full_seg_addr);
                    vector<int32_t> fscore;
                    run_pairs(topk, t_w, t_h, template_bram_addrs, seg_w, seg_h, fscore);
                    for (size_t i = 0; i < topk.size(); i++)
                        if (fscore[i] > absolute_max) { absolute_max = fscore[i]; best_template_idx = topk[i]; }
                }

                // Ispis + upis u tablu samo ako je nađen validan šablon.
                if (best_template_idx != -1) {
                    double best_coef2 = (double)absolute_max / 2147483648.0;  // /2^31 -> NCC^2 u [0,1]
                    cout << ">>> BEST PIECE DETECTED: " << template_names[best_template_idx]
                         << " | NCC^2 = " << best_coef2
                         << " (raw " << absolute_max << ") <<<" << endl;
                    board_state[m][n] = fen_map[best_template_idx];
                }
                executed_count++;
            }
        }
    }

    // --- FEN Generation Logic ---
    stringstream fen;
    for (int m = 0; m < 8; m++) {
        int empty_count = 0;
        for (int n = 0; n < 8; n++) {
            if (board_state[m][n] == ' ') {
                empty_count++;
            } else {
                if (empty_count > 0) {
                    fen << empty_count;
                    empty_count = 0;
                }
                fen << board_state[m][n];
            }
        }
        if (empty_count > 0) fen << empty_count;
        if (m < 7) fen << "/";
    }

    wait(delay);
    cout << "\n[TB] Completed. Evaluated " << executed_count << " populated squares." << endl;

    cout << "\n" << string(50, '=') << endl;
    cout << "FINAL FEN NOTATION:" << endl;
    cout << fen.str() << endl;
    cout << string(50, '=') << "\n" << endl;

    cout << "Total Sim Time: " << sc_time_stamp() << endl;
    sc_stop();
}

void tb_vp::write_reg32(uint64_t addr, uint32_t val, sc_time& d) {
    tlm_generic_payload pl;
    pl.set_command(TLM_WRITE_COMMAND);
    pl.set_address(addr);
    pl.set_data_ptr((unsigned char*)&val);
    pl.set_data_length(sizeof(uint32_t));
    isoc->b_transport(pl, d);
}
void tb_vp::write_reg64(uint64_t addr, uint64_t val, sc_time& d) {
    tlm_generic_payload pl;
    pl.set_command(TLM_WRITE_COMMAND);
    pl.set_address(addr);
    pl.set_data_ptr((unsigned char*)&val);
    pl.set_data_length(sizeof(uint64_t));
    isoc->b_transport(pl, d);
}
void tb_vp::send_data(uint64_t addr, vector<uint8_t>& data, sc_time& d) {
    tlm_generic_payload pl;
    pl.set_command(TLM_WRITE_COMMAND);
    pl.set_address(addr);
    pl.set_data_ptr(data.data());
    pl.set_data_length(data.size());
    isoc->b_transport(pl, d);
}
void tb_vp::read_data(uint64_t addr, vector<uint8_t>& data, sc_time& d) {
    read_data(addr, data.data(), data.size(), d);
}
void tb_vp::read_data(uint64_t addr, uint8_t* ptr, int len, sc_time& d) {
    tlm_generic_payload pl;
    pl.set_command(TLM_READ_COMMAND);
    pl.set_address(addr);
    pl.set_data_ptr(ptr);
    pl.set_data_length(len);
    isoc->b_transport(pl, d);
}
void tb_vp::configure_dma(uint64_t src, uint64_t dst, uint32_t w, uint32_t h, uint32_t s_stride, uint32_t d_stride, sc_time& d) {
    write_reg64(ADDR_DMA + 0x00, src, d);
    write_reg64(ADDR_DMA + 0x08, dst, d);
    write_reg32(ADDR_DMA + 0x10, w, d);
    write_reg32(ADDR_DMA + 0x14, h, d);
    write_reg32(ADDR_DMA + 0x18, s_stride, d);
    write_reg32(ADDR_DMA + 0x1C, d_stride, d);
    write_reg32(ADDR_DMA + 0x20, 1, d);
}
