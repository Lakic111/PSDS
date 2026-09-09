#define SC_MAIN
#include "common.hpp"
#include "bram.hpp"
#include "ncc.hpp"
#include "ncc_target_rtl.hpp"

#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <cstdlib>

using namespace sc_core;
using namespace tlm;
using namespace std;

static const int IW = 90, IH = 90;
static const int TW = 25, TH = 15;
static const int RES_W = IW - TW + 1;
static const int RES_H = IH - TH + 1;

static const uint32_t GOLDEN_BEST = 0x80000000u;
static const int      GOLDEN_U    = 32;
static const int      GOLDEN_V    = 14;

static const uint64_t BRAM_OFF_IMG = 0x00000;
static const uint64_t BRAM_OFF_TMP = 0x10000;

class tb_cosim : public sc_module {
public:
    tlm_utils::simple_initiator_socket<tb_cosim> i_bram;
    tlm_utils::simple_initiator_socket<tb_cosim> i_ncc0;
    tlm_utils::simple_initiator_socket<tb_cosim> i_ncc1;

    SC_HAS_PROCESS(tb_cosim);

    tb_cosim(sc_module_name n) : sc_module(n),
        i_bram("i_bram"), i_ncc0("i_ncc0"), i_ncc1("i_ncc1"),
        m_done0(0), m_done1(0), m_rtl(0)
    {
        SC_THREAD(run);
    }

    void connect_irq(sc_event* d0, sc_event* d1) { m_done0 = d0; m_done1 = d1; }
    void set_rtl(NCC_Target_RTL* r)              { m_rtl = r; }

    void run();

private:
    sc_event*       m_done0;
    sc_event*       m_done1;
    NCC_Target_RTL* m_rtl;

    bool load_hex(const string& path, vector<uint8_t>& out, int expect_w, int expect_h);
    void bram_write(uint64_t off, vector<uint8_t>& data);
    void reg_write(tlm_utils::simple_initiator_socket<tb_cosim>& s, uint64_t addr, uint32_t val);
    void map_read(tlm_utils::simple_initiator_socket<tb_cosim>& s, vector<int32_t>& out);
};

bool tb_cosim::load_hex(const string& path, vector<uint8_t>& out, int expect_w, int expect_h) {
    ifstream f(path.c_str());
    if (!f.is_open()) { cout << "[GRESKA] ne mogu da otvorim " << path << endl; return false; }
    out.clear();
    string line;
    int rows = 0;
    while (getline(f, line)) {

        while (!line.empty() && (line[line.size() - 1] == '\r' || line[line.size() - 1] == '\n'))
            line.erase(line.size() - 1);
        if (line.empty()) continue;
        if ((int)line.size() != expect_w * 2) {
            cout << "[GRESKA] " << path << " red " << rows << ": " << line.size()
                 << " znakova, ocekivano " << expect_w * 2 << endl;
            return false;
        }
        for (int x = 0; x < expect_w; x++)
            out.push_back((uint8_t)strtoul(line.substr(x * 2, 2).c_str(), 0, 16));
        rows++;
    }
    if (rows != expect_h) {
        cout << "[GRESKA] " << path << ": " << rows << " redova, ocekivano "
             << expect_h << endl;
        return false;
    }
    return true;
}

void tb_cosim::bram_write(uint64_t off, vector<uint8_t>& data) {
    sc_time d = SC_ZERO_TIME;
    tlm_generic_payload pl;
    pl.set_command(TLM_WRITE_COMMAND);
    pl.set_address(off);
    pl.set_data_ptr(data.data());
    pl.set_data_length((unsigned)data.size());
    i_bram->b_transport(pl, d);

}

void tb_cosim::reg_write(tlm_utils::simple_initiator_socket<tb_cosim>& s,
                         uint64_t addr, uint32_t val) {
    sc_time d = SC_ZERO_TIME;
    tlm_generic_payload pl;
    pl.set_command(TLM_WRITE_COMMAND);
    pl.set_address(addr);
    pl.set_data_ptr((unsigned char*)&val);
    pl.set_data_length(4);
    s->b_transport(pl, d);
}

void tb_cosim::map_read(tlm_utils::simple_initiator_socket<tb_cosim>& s, vector<int32_t>& out) {
    out.assign(RES_W * RES_H, 0);
    sc_time d = SC_ZERO_TIME;
    tlm_generic_payload pl;
    pl.set_command(TLM_READ_COMMAND);
    pl.set_address(ADDR_RESULTS);
    pl.set_data_ptr((unsigned char*)out.data());
    pl.set_data_length((unsigned)(out.size() * sizeof(int32_t)));
    s->b_transport(pl, d);
}

void tb_cosim::run() {
    cout << endl
         << "=== MESOVITA SIMULACIJA: SystemC ESL (ncc0) vs VHDL RTL (ncc1) ==="
         << endl;

    vector<uint8_t> img, tmpl;
    if (!load_hex("seg90.hex", img, IW, IH))    { sc_stop(); return; }
    if (!load_hex("crnitop.hex", tmpl, TW, TH)) { sc_stop(); return; }
    cout << "Ucitano: segment " << IW << "x" << IH
         << ", sablon " << TW << "x" << TH << endl;

    bram_write(BRAM_OFF_IMG, img);
    bram_write(BRAM_OFF_TMP, tmpl);

    for (int k = 0; k < 2; k++) {
        tlm_utils::simple_initiator_socket<tb_cosim>& s = k ? i_ncc1 : i_ncc0;
        reg_write(s, REG_IMG_W,    IW);
        reg_write(s, REG_IMG_H,    IH);
        reg_write(s, REG_IMG_ADDR, (uint32_t)(ADDR_BRAM + BRAM_OFF_IMG));
        reg_write(s, REG_TMP_W,    TW);
        reg_write(s, REG_TMP_H,    TH);
        reg_write(s, REG_TMP_ADDR, (uint32_t)(ADDR_BRAM + BRAM_OFF_TMP));
    }

    cout << "Start oba bloka @ " << sc_time_stamp() << " ..." << endl;
    reg_write(i_ncc0, REG_CTRL, 1);
    reg_write(i_ncc1, REG_CTRL, 1);

    wait(*m_done0 & *m_done1);
    cout << "Oba bloka javila done @ " << sc_time_stamp() << endl;

    vector<int32_t> m0, m1;
    map_read(i_ncc0, m0);
    map_read(i_ncc1, m1);

    uint32_t best0 = 0, best1 = 0;
    int u0 = -1, v0 = -1, u1 = -1, v1 = -1;
    for (int v = 0; v < RES_H; v++) {
        for (int u = 0; u < RES_W; u++) {

            uint32_t a = (uint32_t)m0[v * RES_W + u];
            uint32_t b = (uint32_t)m1[v * RES_W + u];
            if (a > best0) { best0 = a; u0 = u; v0 = v; }
            if (b > best1) { best1 = b; u1 = u; v1 = v; }
        }
    }

    long long same = 0, maxdiff = 0;
    int mu = -1, mv = -1;
    for (int v = 0; v < RES_H; v++) {
        for (int u = 0; u < RES_W; u++) {
            long long a = (uint32_t)m0[v * RES_W + u];
            long long b = (uint32_t)m1[v * RES_W + u];
            long long d = (a > b) ? (a - b) : (b - a);
            if (d == 0) same++;
            else if (d > maxdiff) { maxdiff = d; mu = u; mv = v; }
        }
    }
    long long total = (long long)RES_W * RES_H;

    cout << endl << "--- REZULTAT ---" << endl;
    cout << "ESL (ncc0): best = 0x" << hex << best0 << dec
         << "  @ (u=" << u0 << ", v=" << v0 << ")" << endl;
    cout << "RTL (ncc1): best = 0x" << hex << best1 << dec
         << "  @ (u=" << u1 << ", v=" << v1 << ")";
    if (m_rtl) cout << "   busy taktova = " << m_rtl->busy_cycles;
    cout << endl;
    cout << "Mapa " << RES_W << "x" << RES_H << " = " << total << " pozicija: "
         << same << " bit-identicnih (" << (100.0 * same / total) << " %)" << endl;
    if (maxdiff > 0)
        cout << "Najvece odstupanje: " << maxdiff << " LSB @ (u=" << mu
             << ", v=" << mv << ")  -- ocekivano: ESL deli u double, RTL celobrojno"
             << endl;

    int fails = 0;
    if (best0 != GOLDEN_BEST || u0 != GOLDEN_U || v0 != GOLDEN_V) {
        cout << "[FAIL] ESL vrh nije golden 0x80000000 @ (32,14)" << endl; fails++;
    }
    if (best1 != GOLDEN_BEST || u1 != GOLDEN_U || v1 != GOLDEN_V) {
        cout << "[FAIL] RTL vrh nije golden 0x80000000 @ (32,14)" << endl; fails++;
    }
    if (best0 != best1 || u0 != u1 || v0 != v1) {
        cout << "[FAIL] ESL i RTL se ne slazu oko vrha" << endl; fails++;
    }

    if (fails == 0)
        cout << endl
             << "GOLDEN OK: ESL i RTL daju isti vrh 0x80000000 @ (32,14) "
                "u JEDNOJ zajednickoj simulaciji." << endl;
    else
        cout << endl
             << "PALO: " << fails << " provera. Prvo sumnjati na transaktor "
                "(ncc_target_rtl.cpp), ne na ncc_core.vhd -- jezgro je nezavisno "
                "verifikovano cetiri puta." << endl;

    sc_stop();
}

int sc_main(int argc, char* argv[]) {
    BRAM_Module    bram("bram");
    NCC_Target     ncc0("ncc0");
    NCC_Target_RTL ncc1("ncc1");
    tb_cosim       tb("tb");

    tb.i_bram.bind(bram.socket);
    ncc0.i_bram.bind(bram.socket);
    ncc1.i_bram.bind(bram.socket);

    tb.i_ncc0.bind(ncc0.socket);
    tb.i_ncc1.bind(ncc1.socket);

    tb.connect_irq(&ncc0.done_ev, &ncc1.done_ev);
    tb.set_rtl(&ncc1);

    sc_start();
    return 0;
}
