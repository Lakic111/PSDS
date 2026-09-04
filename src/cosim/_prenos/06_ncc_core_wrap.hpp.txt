#ifndef NCC_CORE_WRAP_HPP
#define NCC_CORE_WRAP_HPP

// ============================================================================
//  SystemC omotac oko VHDL entiteta `ncc_core` (src/vhdl/ncc_core.vhd, Korak 5).
//
//  NE MENJATI ncc_core.vhd -- ovo je samo "ogledalo" njegovih pinova prema
//  xmsc_run konvenciji za mesovitu simulaciju (Mesovita.pdf, 2.1.1). Jezgro je
//  verifikovano cetiri puta (C kernel, VHDL tb, sinteza, ploca); ako
//  kosimulacija ne prolazi, greska je ovde ili u transaktoru, ne u jezgru.
//
//  TIPOVI PORTOVA -- nisu pretpostavljeni, nego IZMERENI u Tasku 1 na ws2
//  (Xcelium 19.03-s013) sa src/cosim/smoke/typeprobe.vhd + tb_probe.cpp:
//
//    std_logic (takt)        -> sc_in<bool>
//    std_logic (ostalo)      -> sc_in<sc_logic> / sc_out<sc_logic>
//    unsigned(7 downto 0)    -> sc_uint<8>     (dim_t, pixel_t)
//    integer range 0 to N-1  -> sc_uint<32>    (sve tri adrese)
//    unsigned(31 downto 0)   -> sc_uint<32>    (result_t)
//
//  Nijedan VHDL adapter nije potreban.
//
//  SMER PORTOVA: VHDL `out` -> `sc_out` u omotacu, bez izuzetka. Plan
//  implementacije je ovde imao gresku (busy/done kao sc_out, ali result_wr_o
//  kao sc_in, iako su svi cetiri VHDL `out`). Smoke test to resava merenjem:
//  `typeprobe.vhd` ima addr/res/wr kao `out`, u tb_probe.cpp su svi `sc_out`
//  i citaju se ispravno. Transaktor CITA vrednost sa signala vezanog na
//  sc_out port -- to je legalno i tako je i testirano.
//
//  `elaborate_foreign_module()` se NE zove u konstruktoru: smoke test (koji je
//  prosao) koristi golu formu sa samo `hdl_name()`. Ne "popravljati" po PDF-u.
// ============================================================================

#include <systemc>

class ncc_core_wrap : public sc_core::sc_foreign_module
{
public:
    // Kontrola i status
    sc_core::sc_in<bool>            clk;
    sc_core::sc_in<sc_dt::sc_logic> rst;
    sc_core::sc_in<sc_dt::sc_logic> start;
    sc_core::sc_out<sc_dt::sc_logic> busy;
    sc_core::sc_out<sc_dt::sc_logic> done;

    // Dimenzije -- dim_t = unsigned(7 downto 0)
    sc_core::sc_in< sc_dt::sc_uint<8> > img_w;
    sc_core::sc_in< sc_dt::sc_uint<8> > img_h;
    sc_core::sc_in< sc_dt::sc_uint<8> > tmp_w;
    sc_core::sc_in< sc_dt::sc_uint<8> > tmp_h;

    // BRAM-stil interfejs ka slici / sablonu / mapi rezultata.
    // Adrese su u VHDL-u `integer range`, ali se vezuju na sc_uint<32>
    // (izmereno: src/cosim/smoke/intport.vhd).
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

#endif // NCC_CORE_WRAP_HPP
