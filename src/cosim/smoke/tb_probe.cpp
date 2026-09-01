// SystemC strana provere tipova. Tipovi su TACNO oni koje plan predvidja za
// omotac oko ncc_core -- ako ovo elaborira, Task 2 moze da se pise bez straha.
#define SC_MAIN
#include <systemc>
#include <iostream>

using namespace sc_core;
using namespace sc_dt;
using namespace std;

class typeprobe : public sc_foreign_module
{
public:
    sc_in<bool>            clk;    // std_logic
    sc_in<sc_logic>        rst;    // std_logic
    sc_in< sc_uint<8> >    dim;    // unsigned(7 downto 0)  <-- neprovereno do sad
    sc_out< sc_uint<32> >  addr;   // integer range 0 to 8099
    sc_out< sc_uint<32> >  res;    // unsigned(31 downto 0)
    sc_out<sc_logic>       wr;     // std_logic

    typeprobe(sc_module_name n) :
        sc_foreign_module(n),
        clk("clk"), rst("rst"), dim("dim"),
        addr("addr"), res("res"), wr("wr") {}

    const char* hdl_name() const { return "typeprobe"; }
};

class tb : public sc_module
{
public:
    typeprobe dut;
    sc_clock  clk;

    sc_signal<sc_logic>       rst;
    sc_signal< sc_uint<8> >   dim;
    sc_signal< sc_uint<32> >  addr;
    sc_signal< sc_uint<32> >  res;
    sc_signal<sc_logic>       wr;

    SC_HAS_PROCESS(tb);

    tb(sc_module_name n) : sc_module(n), dut("dut"), clk("clk", 5, SC_NS)
    {
        SC_THREAD(run);
        dut.clk( clk.signal() );
        dut.rst( rst );
        dut.dim( dim );
        dut.addr( addr );
        dut.res( res );
        dut.wr( wr );
    }

    void run()
    {
        rst.write(SC_LOGIC_1);
        dim.write(100);              // ocekujemo res = 100 + addr
        wait(20, SC_NS);
        rst.write(SC_LOGIC_0);

        for (int i = 0; i < 6; i++) {
            wait(10, SC_NS);
            cout << "@" << sc_time_stamp()
                 << "  addr = " << addr.read()
                 << "  res = "  << res.read()
                 << "  wr = "   << wr.read()
                 << "   (ocekivano res = 100 + addr)" << endl;
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
