#ifndef NCC_TARGET_RTL_HPP
#define NCC_TARGET_RTL_HPP

// ============================================================================
//  NCC_Target_RTL -- isti spoljni TLM interfejs kao NCC_Target (src/ncc.hpp),
//  ali NCC^2 racuna STVARNI VHDL RTL (src/vhdl/ncc_core.vhd) unutar iste
//  Xcelium simulacije, umesto C++ koda.
//
//  Uloga: transaktor. Ka spolja govori TLM (registri + citanje BRAM-a), ka
//  unutra vozi pinove `ncc_core`-a ciklus-po-ciklus. Protokol je DOSLOVNO isti
//  kao `mem_model` proces u src/vhdl/tb/ncc_core_real_tb.vhd: adresa ovog
//  takta -> podatak sledeceg takta, `result_wr='1'` upisuje na `result_addr`.
//
//  Memorije su namerno dimenzionisane na MAX_IMG_PIX/MAX_TMP_PIX (a ne na
//  img_w*img_h), tacno kao image_array_t/templ_array_t u ncc_pkg.vhd -- jezgro
//  sme da adresira ceo opseg, a visak je nula, kao u VHDL testbenchu.
// ============================================================================

#include "common.hpp"
#include "ncc_core_wrap.hpp"
#include <vector>

class NCC_Target_RTL : public sc_core::sc_module {
public:
    SC_HAS_PROCESS(NCC_Target_RTL);

    // --- identicno javno lice kao NCC_Target ---
    tlm_utils::simple_target_socket<NCC_Target_RTL>    socket;
    tlm_utils::simple_initiator_socket<NCC_Target_RTL> i_bram;

    sc_core::sc_event start_ev;
    sc_core::sc_event done_ev;

    std::vector<uint8_t> image, templ;
    std::vector<int32_t> result_map;
    int img_w, img_h, tmp_w, tmp_h;
    uint64_t img_addr, tmp_addr;
    uint32_t hw_status;
    bool     img_dirty;

    // Metrika koja u C++ modelu ne postoji: stvaran broj taktova u kojima je
    // jezgro drzalo busy='1'. Isto sto meri `cyc_cnt` u ncc_core_real_tb.vhd.
    long long busy_cycles;

    NCC_Target_RTL(sc_core::sc_module_name name);
    void b_transport(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay);

private:
    void ncc_proc();          // SC_THREAD: TLM -> reset/start/wait-done -> done_ev
    void mem_proc();          // SC_METHOD @ clk.pos(): BRAM model + hvatanje rezultata
    void read_from_bram(uint64_t bram_addr, unsigned char* dst, unsigned int len);

    // Ogledalo ncc_pkg.vhd -- ne menjati nezavisno od paketa.
    static const int MAX_IMG_PIX = 90 * 90;   // 8100
    static const int MAX_TMP_PIX = 30 * 30;   // 900

    ncc_core_wrap dut;

    // Slobodan takt (10 ns = 100 MHz), isti kao CLK_PERIOD u ncc_core_real_tb.
    // NAMERNO nije "gasiv" takt iz plana: dva bloka u istoj simulaciji dele
    // vremensku osu, pa je stalan takt jedina stvar o kojoj se lako rezonuje.
    sc_core::sc_clock clk;

    sc_core::sc_signal<sc_dt::sc_logic>     sig_rst, sig_start, sig_busy, sig_done, sig_result_wr;
    sc_core::sc_signal< sc_dt::sc_uint<8> > sig_img_w, sig_img_h, sig_tmp_w, sig_tmp_h;
    sc_core::sc_signal< sc_dt::sc_uint<8> > sig_img_data, sig_templ_data;
    sc_core::sc_signal< sc_dt::sc_uint<32> > sig_img_addr, sig_templ_addr;
    sc_core::sc_signal< sc_dt::sc_uint<32> > sig_result_addr, sig_result_data;

    // Interne memorije transaktora (pandan image_mem/templ_mem/result_mem).
    std::vector<uint8_t>  image_mem;
    std::vector<uint8_t>  templ_mem;
    std::vector<uint32_t> result_mem;

    bool counting;   // broj busy taktove samo dok traje prolaz
};

#endif // NCC_TARGET_RTL_HPP
