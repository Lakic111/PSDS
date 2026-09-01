// Smoke test za mesovitu simulaciju (SystemC + HDL) u Xcelium-u.
// Listinzi 2.2-2.5 iz Mesovita.pdf spojeni u JEDAN fajl -- sadrzaj je isti,
// samo bez podele na zaglavlja, da prenos preko klipborda bude jedno kratko
// nalepljivanje. Za Task 2 se vracamo na podelu po fajlovima.
#define SC_MAIN
#include <systemc>
#include <string>
#include <sstream>

using namespace sc_core;
using namespace sc_dt;
using namespace std;

// ---- Listing 2.2: omotac oko HDL modula --------------------------------
// hdl_name() vraca ime entiteta/modula kako ga simulator vidi ("counter"),
// a imena portova u konstruktoru moraju da se poklope sa HDL portovima.
class counter : public sc_foreign_module
{
public:
    counter(sc_module_name name) :
        sc_foreign_module(name),
        clk("clk"),
        rst("rst"),
        load("load"),
        din("din"),
        dout("dout")
    {
    }

    sc_in< bool >        clk;
    sc_in< sc_logic >    rst;
    sc_in< sc_logic >    load;
    sc_in< sc_lv<8> >    din;
    sc_out< sc_lv<8> >   dout;

    const char* hdl_name() const { return "counter"; }
};

// ---- Listinzi 2.3 i 2.4: testbench -------------------------------------
class tb_counter : public sc_module
{
public:
    // clanovi se deklarisu PRE konstruktora: redosled inicijalizacije prati
    // redosled deklaracije, pa je ovako odmah vidljivo da se poklapaju
    counter   dut;
    sc_clock  clk;

    sc_signal< sc_logic >  rst;
    sc_signal< sc_logic >  load;
    sc_signal< sc_lv<8> >  din;
    sc_signal< sc_lv<8> >  dout;

    SC_HAS_PROCESS(tb_counter);

    tb_counter(sc_module_name name) :
        sc_module(name),
        dut("dut"),
        clk("clk", 5, SC_NS)
    {
        SC_THREAD(gen_thread);
        SC_METHOD(mon_thread);
        dont_initialize();
        sensitive << dout;
        dut.clk( clk.signal() );
        dut.rst( rst );
        dut.load( load );
        dut.din( din );
        dut.dout( dout );
    }

protected:
    void gen_thread()
    {
        rst.write( SC_LOGIC_1 );
        load.write( SC_LOGIC_0 );
        din.write( 7 );
        wait(100, SC_NS);
        rst.write( SC_LOGIC_0 );
        wait(500, SC_NS);
        load.write( SC_LOGIC_1 );
        wait(100, SC_NS);
        load.write( SC_LOGIC_0 );
        wait(1000, SC_NS);
        sc_stop();
    }

    void mon_thread()
    {
        ostringstream ss;
        ss << "@" << sc_time_stamp();
        ss << " dout = " << dout.read();
        ss << " (" << static_cast< sc_uint<8> >( dout.read() ) << ")";
        SC_REPORT_INFO(name(), ss.str().c_str());
    }
};

// ---- Listing 2.5: glavni program ---------------------------------------
int sc_main(int argc, char* argv[])
{
    tb_counter uut("uut");
    sc_start();
    return 0;
}
