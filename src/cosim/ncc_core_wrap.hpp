#ifndef NCC_CORE_WRAP_HPP
#define NCC_CORE_WRAP_HPP

#include <systemc>

class ncc_core_wrap : public sc_core::sc_foreign_module
{
public:

    sc_core::sc_in<bool>            clk;
    sc_core::sc_in<sc_dt::sc_logic> rst;
    sc_core::sc_in<sc_dt::sc_logic> start;
    sc_core::sc_out<sc_dt::sc_logic> busy;
    sc_core::sc_out<sc_dt::sc_logic> done;

    sc_core::sc_in< sc_dt::sc_uint<8> > img_w;
    sc_core::sc_in< sc_dt::sc_uint<8> > img_h;
    sc_core::sc_in< sc_dt::sc_uint<8> > tmp_w;
    sc_core::sc_in< sc_dt::sc_uint<8> > tmp_h;

    sc_core::sc_out< sc_dt::sc_uint<32> > img_addr_o;
    sc_core::sc_in < sc_dt::sc_uint<8>  > img_data_i;
    sc_core::sc_out< sc_dt::sc_uint<32> > templ_addr_o;
    sc_core::sc_in < sc_dt::sc_uint<8>  > templ_data_i;
    sc_core::sc_out< sc_dt::sc_uint<32> > result_addr_o;
    sc_core::sc_out< sc_dt::sc_uint<32> > result_data_o;
    sc_core::sc_out< sc_dt::sc_logic    > result_wr_o;

    ncc_core_wrap(sc_core::sc_module_name name) :
        sc_core::sc_foreign_module(name),
        clk("clk"), rst("rst"), start("start"), busy("busy"), done("done"),
        img_w("img_w"), img_h("img_h"), tmp_w("tmp_w"), tmp_h("tmp_h"),
        img_addr_o("img_addr_o"),   img_data_i("img_data_i"),
        templ_addr_o("templ_addr_o"), templ_data_i("templ_data_i"),
        result_addr_o("result_addr_o"),
        result_data_o("result_data_o"),
        result_wr_o("result_wr_o")
    {}

    const char* hdl_name() const { return "ncc_core"; }
};

#endif
