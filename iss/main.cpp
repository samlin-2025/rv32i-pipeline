// ============================================================================
// File:    main.cpp
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    ISS driver — loads a hex file, runs the program, dumps trace
//          and final register state.
//
// Usage:   ./rv32i_iss <hex_file> [max_steps]
// ============================================================================

#include "rv32i_iss.h"
#include <iostream>
#include <cstdlib>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <hex_file> [max_steps]\n";
        return 1;
    }

    std::string hex_file  = argv[1];
    uint32_t    max_steps = (argc >= 3) ? std::atoi(argv[2]) : 1000;

    // Create simulator
    rv32i::Simulator sim;

    // Load program
    if (!sim.load_hex(hex_file)) {
        return 1;
    }

    // Run
    std::cout << "ISS: Running up to " << max_steps << " steps...\n\n";
    sim.run(max_steps);

    // Dump results
    sim.dump_regs();
    sim.dump_trace("iss_trace.log");

    return 0;
}
