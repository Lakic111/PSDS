#ifndef NCC_TARGET_RTL_HPP
#define NCC_TARGET_RTL_HPP

#include "common.hpp"
#include "ncc_core_wrap.hpp"
#include <vector>

class NCC_Target_RTL : public sc_core::sc_module {
public:
    SC_HAS_PROCESS(NCC_Target_RTL);

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

    long long busy_cycles;

    NCC_Target_RTL(sc_core::sc_module_name name);
    void b_transport(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay);

private:
    void ncc_proc();
    void mem_proc();
    void read_from_bram(uint64_t bram_addr, unsigned char* dst, unsigned int len);

    static const int MAX_IMG_PIX = 90 * 90;
    static const int MAX_TMP_PIX = 30 * 30;

    ncc_core_wrap dut;

    sc_core::sc_clock clk;

    sc_core::sc_signal<sc_dt::sc_logic>     sig_rst, sig_start, sig_busy, sig_done, sig_result_wr;
    sc_core::sc_signal< sc_dt::sc_uint<8> > sig_img_w, sig_img_h, sig_tmp_w, sig_tmp_h;
    sc_core::sc_signal< sc_dt::sc_uint<8> > sig_img_data, sig_templ_data;
    sc_core::sc_signal< sc_dt::sc_uint<32> > sig_img_addr, sig_templ_addr;
    sc_core::sc_signal< sc_dt::sc_uint<32> > sig_result_addr, sig_result_data;

    std::vector<uint8_t>  image_mem;
    std::vector<uint8_t>  templ_mem;
    std::vector<uint32_t> result_mem;

    bool counting;
};

#endif
