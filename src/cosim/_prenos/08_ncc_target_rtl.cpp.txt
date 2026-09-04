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

// Identicno NCC_Target::read_from_bram (src/ncc.cpp:29) -- transaktor cita
// sliku i sablon iz ISTOG deljenog BRAM-a kao C++ model, pa je ulaz u oba
// bloka dokazano isti niz bajtova, a ne dve nezavisno ucitane kopije.
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

// Registarska mapa je ista kao kod NCC_Target (src/ncc.cpp:39) -- ukljucujuci
// citanje cele mape rezultata jednim memcpy-em na ADDR_RESULTS.
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
            hw_status = 0;                    // BUSY
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

// Pandan `mem_model` procesu iz ncc_core_real_tb.vhd:
//
//   if rising_edge(clk) then
//       img_data   <= image_mem(img_addr);
//       templ_data <= templ_mem(templ_addr);
//       if result_wr = '1' then result_mem(result_addr) <= result_data; end if;
//   end if;
//
// Upis u sc_signal stupa na snagu u sledecoj delta fazi, sto je ista semantika
// kao VHDL dodela signala -- jezgro podatak uzorkuje tek na sledecoj ivici.
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

// Glavni proces. Redosled je isti kao `stim_gen` u ncc_core_real_tb.vhd:
// napuni memorije -> rst -> dimenzije -> start puls -> cekaj done.
void NCC_Target_RTL::ncc_proc() {
    while (true) {
        wait(start_ev);
        hw_status = 0;

        // Slika se ponovo cita samo kad je CPU najavio nov segment -- ista
        // politika kao NCC_Target (src/ncc.cpp:87), da se ponasanje registara
        // ne razlikuje izmedju dva bloka.
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

        // --- vozi RTL ---
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
        wait(clk.posedge_event());   // da dimenzije sigurno stignu preko granice

        sig_start.write(SC_LOGIC_1);
        wait(clk.posedge_event());
        sig_start.write(SC_LOGIC_0);

        // `wait until done = '1'` iz VHDL testbencha. Cekamo promenu signala,
        // ne ivicu takta: done ume da bude puls od jednog takta, a uzorkovanje
        // bas na ivici moze da uhvati staru vrednost preko SystemC/HDL granice.
        while (sig_done.read() != SC_LOGIC_1)
            wait(sig_done.value_changed_event());

        wait(clk.posedge_event());   // da poslednji result_wr sigurno upadne
        counting = false;

        result_map.assign((size_t)res_w * res_h, 0);
        for (int i = 0; i < res_w * res_h; i++)
            result_map[i] = (int32_t)result_mem[i];

        hw_status = 1;               // DONE
        done_ev.notify();
    }
}
