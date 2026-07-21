#include "bram.hpp"
#include <cstring>

using namespace sc_core;
using namespace tlm;

BRAM_Module::BRAM_Module(sc_module_name name) : sc_module(name), socket("socket"), mem(1024 * 1024, 0) {
    socket.register_b_transport(this, &BRAM_Module::b_transport);
}

void BRAM_Module::b_transport(int /*id*/, tlm_generic_payload& trans, sc_time& delay) {
    tlm_command cmd = trans.get_command();
    uint64_t    addr = trans.get_address();
    unsigned char* ptr = trans.get_data_ptr();
    unsigned int len = trans.get_data_length();

    // bounds
    if (addr + len > mem.size()) {
        trans.set_response_status(TLM_ADDRESS_ERROR_RESPONSE);
        return;
    }

    // command
    switch (cmd) {
        case TLM_READ_COMMAND:
            memcpy(ptr, &mem[addr], len);
            break;
        case TLM_WRITE_COMMAND:
            memcpy(&mem[addr], ptr, len);
            break;
        case TLM_IGNORE_COMMAND:
            break;
        default:
            trans.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
            return;
    }

    // BRAM pristup košta vreme i ide takt po takt (100 MHz -> 10 ns/ciklus).
    // Model: jedna 32-bitna reč po ciklusu + 1 ciklus pristupne latencije.
    // Vreme se DODAJE u 'delay'; svaki master sam odlučuje da li ga troši:
    //   - NCC (i_bram): ČEKA ovo vreme  -> na kritičnoj je putanji (vadi sliku
    //     i šablon iz BRAM-a pre obrade).
    //   - DMA (i_wr):   ODBACUJE ovo vreme -> upis u BRAM se preklapa u pozadini
    //     takt po takt dok IP radi, pa nije na kritičnoj putanji.
    unsigned int cycles = (len + 3) / 4 + 1;
    delay += sc_time(cycles * 10.0, SC_NS);

    trans.set_response_status(TLM_OK_RESPONSE);
}
