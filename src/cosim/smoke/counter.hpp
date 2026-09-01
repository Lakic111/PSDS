// Listing 2.2 iz Mesovita.pdf (str. 101) -- omotac klase brojaca.
// Nasledjuje sc_foreign_module: navedeni su svi portovi HDL modela, a
// hdl_name() vraca ime entiteta/modula kako ga simulator vidi.
#ifndef _COUNTER_HPP_
#define _COUNTER_HPP_

#include <systemc>

class counter : public sc_core::sc_foreign_module
{
public:
    counter(sc_core::sc_module_name name) :
        sc_core::sc_foreign_module(name),
        clk("clk"),
        rst("rst"),
        load("load"),
        din("din"),
        dout("dout")
    {
    }

    sc_core::sc_in< bool >              clk;
    sc_core::sc_in< sc_dt::sc_logic >   rst;
    sc_core::sc_in< sc_dt::sc_logic >   load;
    sc_core::sc_in< sc_dt::sc_lv<8> >   din;
    sc_core::sc_out< sc_dt::sc_lv<8> >  dout;

    const char* hdl_name() const { return "counter"; }
};

#endif
