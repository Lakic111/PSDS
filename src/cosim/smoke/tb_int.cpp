// Provera mapiranja VHDL `integer range 0 to 255` porta na SystemC tip.
// Pretpostavka koju testiramo: sc_uint<32>. Ako elaboracija pukne, poruka
// obicno kaze koji tip ocekuje -- to je odgovor koji nam treba za Task 2.
#define SC_MAIN
#include <systemc>
#include <iostream>

using namespace sc_core;
using namespace sc_dt;
using namespace std;

class intport : public sc_foreign_module
{
public:
    sc_in<bool>           clk;
    sc_out< sc_uint<32> > aout;

    intport(sc_module_name n) :
        sc_foreign_module(n), clk("clk"), aout("aout") {}

    const char* hdl_name() const { return "intport"; }
};

class tb : public sc_module
{
public:
    intport   dut;
    sc_clock  clk;
    sc_signal< sc_uint<32> > aout;

    SC_HAS_PROCESS(tb);

    tb(sc_module_name n) : sc_module(n), dut("dut"), clk("clk", 5, SC_NS)
    {
        SC_THREAD(run);
        dut.clk( clk.signal() );
        dut.aout( aout );
    }

    void run()
    {
        for (int i = 0; i < 5; i++) {
            wait(10, SC_NS);
            cout << "@" << sc_time_stamp() << "  aout = " << aout.read() << endl;
        }
        sc_stop();
    }
};

int sc_main(int argc, char* argv[])
{
    tb t("t");
    sc_start();
    return 0;
}
