// Listing 2.5 iz Mesovita.pdf (str. 103-104) -- glavni program.
// SC_MAIN se definise PRE ukljucivanja tb_counter.hpp da SC_MODULE_EXPORT
// ne bi bio aktiviran (top modul je ovde sc_main, ne tb_counter).
#define SC_MAIN
#include <systemc>
#include "tb_counter.hpp"

using namespace sc_core;

int sc_main(int argc, char* argv[])
{
    tb_counter uut("uut");
    sc_start();
    return 0;
}
