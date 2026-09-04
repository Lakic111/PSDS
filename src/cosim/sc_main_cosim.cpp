// ============================================================================
//  MESOVITA SIMULACIJA (SystemC ESL + VHDL RTL) -- gornji nivo
//
//  Jedna Xcelium simulacija u kojoj rade OBA modela istovremeno:
//
//      bram (deljeni)
//        |-- ncc0 : NCC_Target      -> NCC^2 racuna C++ ESL model (src/ncc.cpp)
//        |-- ncc1 : NCC_Target_RTL  -> NCC^2 racuna ncc_core.vhd (Korak 5)
//
//  CPU (ovaj testbench) upise ISTU sliku i ISTI sablon u BRAM jednom, pa oba
//  bloka procitaju iste bajtove sa istih adresa i krenu u istom trenutku.
//  Time se dokaz ne oslanja na poredjenje dva odvojeno snimljena golden fajla
//  (primedba na dosadasnji pristup), nego na jedan zajednicki run.
//
//  STA SE TVRDI, A STA NE:
//    * TVRDO se proverava vrh: 0x80000000 @ (u=32, v=14) kod OBA bloka.
//      To je golden iz Koraka 1 (C kernel), potvrdjen u Koraku 4 (VHDL tb) i
//      na ploci (Korak 9).
//    * Cela mapa se NE tvrdi kao bit-identicna. C++ model deli u pokretnom
//      zarezu (src/ncc.cpp: double ncc2 = num_sq/den_prod), RTL celobrojnim
//      seq_divider-om. Van vrha se najnizi bitovi razilaze po konstrukciji.
//      Zato se razlike MERE i ispisu (broj identicnih pozicija, najvece
//      odstupanje), umesto da test na njima puca -- tvrdnja koja bi pukla nije
//      dokaz nego sum.
//
//  Ulazni podaci: seg90.hex / crnitop.hex -- isti pikseli kao seg90.txt i
//  crnitop.txt iz src/vhdl/tb/, samo u heks formatu (jedan red slike po liniji,
//  2 heks cifre po pikselu), jer se na ws2 fajlovi prenose klipbordom, a
//  8100 linija teksta se tako ne prenosi.
// ============================================================================

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
static const int RES_W = IW - TW + 1;   // 66
static const int RES_H = IH - TH + 1;   // 76

static const uint32_t GOLDEN_BEST = 0x80000000u;
static const int      GOLDEN_U    = 32;
static const int      GOLDEN_V    = 14;

static const uint64_t BRAM_OFF_IMG = 0x00000;
static const uint64_t BRAM_OFF_TMP = 0x10000;

// ---------------------------------------------------------------------------

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
    NCC_Target_RTL* m_rtl;      // samo radi citanja busy_cycles metrike

    bool load_hex(const string& path, vector<uint8_t>& out, int expect_w, int expect_h);
    void bram_write(uint64_t off, vector<uint8_t>& data);
    void reg_write(tlm_utils::simple_initiator_socket<tb_cosim>& s, uint64_t addr, uint32_t val);
    void map_read(tlm_utils::simple_initiator_socket<tb_cosim>& s, vector<int32_t>& out);
};

// Heks format: jedan red slike po liniji, 2 heks cifre po pikselu, bez razmaka.
// Namerno bez zavisnosti van standardne biblioteke -- ws2 nema internet, pa ni
// mogucnost da se bilo sta instalira.
bool tb_cosim::load_hex(const string& path, vector<uint8_t>& out, int expect_w, int expect_h) {
    ifstream f(path.c_str());
    if (!f.is_open()) { cout << "[GRESKA] ne mogu da otvorim " << path << endl; return false; }
    out.clear();
    string line;
    int rows = 0;
    while (getline(f, line)) {
        // CRLF ako je fajl prosao kroz Windows editor
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
    // Vreme upisa se ne naplacuje: CPU puni BRAM pre starta, van kriticne putanje.
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

    // Jedan upis u deljeni BRAM -> oba bloka citaju iste bajtove.
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

    // --- vrh po mapi, za svaki blok posebno ---
    uint32_t best0 = 0, best1 = 0;
    int u0 = -1, v0 = -1, u1 = -1, v1 = -1;
    for (int v = 0; v < RES_H; v++) {
        for (int u = 0; u < RES_W; u++) {
            // Skorovi se porede kao u32: 0x80000000 je NCC^2 = 1.0, a kao int32
            // bi bio negativan -- bas najbolji rezultat bi ispao iz maksimuma.
            uint32_t a = (uint32_t)m0[v * RES_W + u];
            uint32_t b = (uint32_t)m1[v * RES_W + u];
            if (a > best0) { best0 = a; u0 = u; v0 = v; }
            if (b > best1) { best1 = b; u1 = u; v1 = v; }
        }
    }

    // --- razlike po celoj mapi (mere se, ne tvrde) ---
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

    // --- tvrde provere ---
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

// ---------------------------------------------------------------------------

int sc_main(int argc, char* argv[]) {
    BRAM_Module    bram("bram");
    NCC_Target     ncc0("ncc0");     // C++ ESL model (src/ncc.cpp)
    NCC_Target_RTL ncc1("ncc1");     // VHDL RTL preko sc_foreign_module
    tb_cosim       tb("tb");

    // Oba bloka su masteri nad ISTIM BRAM-om (multi_passthrough target).
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
