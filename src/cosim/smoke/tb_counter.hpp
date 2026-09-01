// Listing 2.3 iz Mesovita.pdf (str. 102) -- zaglavlje jednostavnog testbenca.
// SC_MODULE_EXPORT oznacava tb_counter kao kandidata za top modul kada se
// simulacija pokrece BEZ sc_main (varijanta sa -top tb_counter).
#ifndef TB_COUNTER
#define TB_COUNTER

#include <systemc>
#include "counter.hpp"

class tb_counter : public sc_core::sc_module
{
public:
    tb_counter(sc_core::sc_module_name name);
protected:
    void gen_thread();
    void mon_thread();
    counter dut;
    sc_core::sc_clock clk;

    sc_core::sc_signal< sc_dt::sc_logic >  rst;
    sc_core::sc_signal< sc_dt::sc_logic >  load;
    sc_core::sc_signal< sc_dt::sc_lv<8> >  din;
    sc_core::sc_signal< sc_dt::sc_lv<8> >  dout;
private:
};

#ifndef SC_MAIN
SC_MODULE_EXPORT(tb_counter)
#endif

#endif
