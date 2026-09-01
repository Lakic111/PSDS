// Listing 2.4 iz Mesovita.pdf (str. 103) -- implementacija testbenca.
// Napomena: u PDF-u su razmaci u string literalima odstampani kao donje crte
// (font za listinge); ovde su vraceni u obicne razmake.
#include "tb_counter.hpp"
#include <string>
#include <sstream>

using namespace sc_core;
using namespace sc_dt;
using namespace std;

SC_HAS_PROCESS(tb_counter);

tb_counter::tb_counter(sc_module_name name) :
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

void tb_counter::gen_thread()
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

void tb_counter::mon_thread()
{
    ostringstream ss;
    ss << "@" << sc_time_stamp();
    ss << " dout = " << dout.read();
    ss << " (" << static_cast< sc_uint<8> >( dout.read() ) << ")";
    SC_REPORT_INFO(name(), ss.str().c_str());
}
