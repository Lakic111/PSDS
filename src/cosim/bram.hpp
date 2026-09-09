#ifndef BRAM_HPP
#define BRAM_HPP

#include "common.hpp"
#include <vector>

class BRAM_Module : public sc_core::sc_module {
public:

    tlm_utils::multi_passthrough_target_socket<BRAM_Module> socket;
    std::vector<uint8_t> mem;

    BRAM_Module(sc_core::sc_module_name name);
    void b_transport(int id, tlm::tlm_generic_payload& trans, sc_core::sc_time& delay);
};

#endif
