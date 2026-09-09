#include "ncc_target_rtl.hpp"
#include <cstring>
#include <algorithm>

using namespace sc_core;
using namespace sc_dt;
using namespace tlm;
using namespace std;

NCC_Target_RTL::NCC_Target_RTL(sc_module_name name) :
    sc_module(name), socket("socket"), i_bram("i_bram"),
    img_w(0), img_h(0), tmp_w(0), tmp_h(0), img_addr(0), tmp_addr(0),
    hw_status(0), img_dirty(false), busy_cycles(0),
    dut("dut"),
    clk("clk", 10, SC_NS),
    sig_rst("sig_rst"), sig_start("sig_start"), sig_busy("sig_busy"),
    sig_done("sig_done"), sig_result_wr("sig_result_wr"),
    sig_img_w("sig_img_w"), sig_img_h("sig_img_h"),
    sig_tmp_w("sig_tmp_w"), sig_tmp_h("sig_tmp_h"),
    sig_img_data("sig_img_data"), sig_templ_data("sig_templ_data"),
    sig_img_addr("sig_img_addr"), sig_templ_addr("sig_templ_addr"),
    sig_result_addr("sig_result_addr"), sig_result_data("sig_result_data"),
    image_mem(MAX_IMG_PIX, 0), templ_mem(MAX_TMP_PIX, 0), result_mem(MAX_IMG_PIX, 0),
    counting(false)
{
    socket.register_b_transport(this, &NCC_Target_RTL::b_transport);

    dut.clk(clk);
    dut.rst(sig_rst);
    dut.start(sig_start);
    dut.busy(sig_busy);
    dut.done(sig_done);
    dut.img_w(sig_img_w);   dut.img_h(sig_img_h);
    dut.tmp_w(sig_tmp_w);   dut.tmp_h(sig_tmp_h);
    dut.img_addr_o(sig_img_addr);        dut.img_data_i(sig_img_data);
    dut.templ_addr_o(sig_templ_addr);    dut.templ_data_i(sig_templ_data);
    dut.result_addr_o(sig_result_addr);
    dut.result_data_o(sig_result_data);
    dut.result_wr_o(sig_result_wr);

    sig_rst.write(SC_LOGIC_1);
    sig_start.write(SC_LOGIC_0);

    SC_THREAD(ncc_proc);

    SC_METHOD(mem_proc);
    sensitive << clk.posedge_event();
    dont_initialize();
}

void NCC_Target_RTL::read_from_bram(uint64_t bram_addr, unsigned char* dst, unsigned int len) {
    sc_time scratch = SC_ZERO_TIME;
    tlm_generic_payload pl;
    pl.set_command(TLM_READ_COMMAND);
    pl.set_address(bram_addr - ADDR_BRAM);
    pl.set_data_ptr(dst);
    pl.set_data_length(len);
    i_bram->b_transport(pl, scratch);
    wait(scratch);
}

void NCC_Target_RTL::b_transport(tlm_generic_payload& trans, sc_time& delay) {
    tlm_command    cmd  = trans.get_command();
    uint64_t       addr = trans.get_address();
    unsigned char* ptr  = trans.get_data_ptr();

    if (cmd == TLM_WRITE_COMMAND) {
        if      (addr == REG_IMG_W)    img_w = *(int*)ptr;
        else if (addr == REG_IMG_H)    img_h = *(int*)ptr;
        else if (addr == REG_TMP_W)    tmp_w = *(int*)ptr;
        else if (addr == REG_TMP_H)    tmp_h = *(int*)ptr;
        else if (addr == REG_IMG_ADDR) { img_addr = *(uint32_t*)ptr; img_dirty = true; }
        else if (addr == REG_TMP_ADDR) { tmp_addr = *(uint32_t*)ptr; }
        else if (addr == REG_CTRL && *(uint32_t*)ptr == 1) {
            hw_status = 0;
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

void NCC_Target_RTL::mem_proc() {
    unsigned ia = sig_img_addr.read().to_uint();
    unsigned ta = sig_templ_addr.read().to_uint();

    sig_img_data.write(ia < image_mem.size() ? (sc_uint<8>)image_mem[ia] : (sc_uint<8>)0);
    sig_templ_data.write(ta < templ_mem.size() ? (sc_uint<8>)templ_mem[ta] : (sc_uint<8>)0);

    if (sig_result_wr.read() == SC_LOGIC_1) {
        unsigned ra = sig_result_addr.read().to_uint();
        if (ra < result_mem.size())
            result_mem[ra] = sig_result_data.read().to_uint();
    }

    if (counting && sig_busy.read() == SC_LOGIC_1)
        busy_cycles++;
}

void NCC_Target_RTL::ncc_proc() {
    while (true) {
        wait(start_ev);
        hw_status = 0;

        if (img_dirty) {
            image.resize((size_t)img_w * img_h);
            read_from_bram(img_addr, image.data(), (unsigned)(img_w * img_h));
            std::fill(image_mem.begin(), image_mem.end(), 0);
            std::copy(image.begin(), image.end(), image_mem.begin());
            img_dirty = false;
        }

        templ.resize((size_t)tmp_w * tmp_h);
        read_from_bram(tmp_addr, templ.data(), (unsigned)(tmp_w * tmp_h));
        std::fill(templ_mem.begin(), templ_mem.end(), 0);
        std::copy(templ.begin(), templ.end(), templ_mem.begin());

        std::fill(result_mem.begin(), result_mem.end(), 0);

        int res_w = img_w - tmp_w + 1;
        int res_h = img_h - tmp_h + 1;
        if (res_w <= 0 || res_h <= 0) { hw_status = 1; done_ev.notify(); continue; }

        busy_cycles = 0;
        counting    = true;

        sig_rst.write(SC_LOGIC_1);
        wait(clk.posedge_event());
        wait(clk.posedge_event());
        wait(clk.posedge_event());
        sig_rst.write(SC_LOGIC_0);

        sig_img_w.write((sc_uint<8>)img_w);
        sig_img_h.write((sc_uint<8>)img_h);
        sig_tmp_w.write((sc_uint<8>)tmp_w);
        sig_tmp_h.write((sc_uint<8>)tmp_h);

        wait(clk.posedge_event());
        wait(clk.posedge_event());

        sig_start.write(SC_LOGIC_1);
        wait(clk.posedge_event());
        sig_start.write(SC_LOGIC_0);

        while (sig_done.read() != SC_LOGIC_1)
            wait(sig_done.value_changed_event());

        wait(clk.posedge_event());
        counting = false;

        result_map.assign((size_t)res_w * res_h, 0);
        for (int i = 0; i < res_w * res_h; i++)
            result_map[i] = (int32_t)result_mem[i];

        hw_status = 1;
        done_ev.notify();
    }
}
