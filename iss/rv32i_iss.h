// ============================================================================
// File:    rv32i_iss.h
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    RV32I Instruction Set Simulator — golden reference model.
//
//          This is a *functional* model of the RV32I ISA. It has no concept
//          of pipelines, hazards, forwarding, or clock cycles. It simply
//          executes one instruction at a time and updates architectural state
//          (registers, memory, PC). Its purpose is to define *correct*
//          behavior so the pipelined RTL can be verified against it.
//
//          In industry, this is called an ISS (Instruction Set Simulator) or
//          sometimes a "golden model." At Apple/ARM/NVIDIA, the DV team hooks
//          this into the UVM scoreboard via DPI-C: the scoreboard feeds each
//          committed instruction to the ISS and compares the ISS's predicted
//          register/memory writes against what the RTL actually produced.
//
// Ref:     RISC-V Unprivileged ISA Spec v20191213, Chapter 2 (RV32I)
// ============================================================================

#ifndef RV32I_ISS_H
#define RV32I_ISS_H

#include <cstdint>
#include <array>
#include <vector>
#include <string>
#include <fstream>

namespace rv32i {

// ----------------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------------
constexpr int      NUM_REGS  = 32;
constexpr uint32_t MEM_SIZE  = 4096;   // Words (16 KB byte-addressable)
constexpr uint32_t PC_START  = 0x0;    // Reset vector

// ----------------------------------------------------------------------------
// Instruction format types
// ----------------------------------------------------------------------------
// Every RV32I instruction maps to exactly one of these formats. The format
// determines how the immediate is extracted from the 32-bit encoding.
enum class Format {
    R, I, S, B, U, J, UNKNOWN
};

// ----------------------------------------------------------------------------
// Decoded instruction — all fields extracted and ready for execution
// ----------------------------------------------------------------------------
// After decoding, we never look at the raw 32-bit encoding again. Everything
// the executor needs is in this struct. This mirrors what the hardware decode
// stage produces: opcode, funct3, funct7, register addresses, and immediate.

struct DecodedInstr {
    uint32_t raw;         // Original 32-bit encoding (for trace/debug)
    Format   format;      // Instruction format type

    uint32_t opcode;      // [6:0]
    uint32_t rd;          // [11:7]   — destination register
    uint32_t funct3;      // [14:12]  — operation variant
    uint32_t rs1;         // [19:15]  — source register 1
    uint32_t rs2;         // [24:20]  — source register 2
    uint32_t funct7;      // [31:25]  — operation sub-variant

    int32_t  imm;         // Sign-extended immediate (format-dependent)
};

// ----------------------------------------------------------------------------
// Trace entry — one per retired instruction
// ----------------------------------------------------------------------------
// This is what gets compared against RTL output. The fields are:
//   pc        — PC of the instruction
//   instr     — raw 32-bit encoding
//   rd        — destination register (0 if no writeback)
//   rd_val    — value written to rd (undefined if rd == 0)
//   mem_write — true if instruction wrote to memory
//   mem_addr  — address written (only valid if mem_write)
//   mem_val   — value written to memory (only valid if mem_write)
//   disasm    — human-readable disassembly string

struct TraceEntry {
    uint32_t    pc;
    uint32_t    instr;
    uint32_t    rd;
    uint32_t    rd_val;
    bool        mem_write;
    uint32_t    mem_addr;
    uint32_t    mem_val;
    std::string disasm;
};

// ----------------------------------------------------------------------------
// ISS class — the complete RV32I machine
// ----------------------------------------------------------------------------
// Architectural state is just three things:
//   1. 32 x 32-bit general-purpose registers (x0 hardwired to 0)
//   2. A byte-addressable memory array
//   3. The program counter (PC)
//
// That's it. No pipeline registers, no forwarding muxes, no branch predictors.
// The simplicity is the point — if this model is correct, every discrepancy
// between ISS and RTL is a bug in the RTL (or the testbench).

class Simulator {
public:
    // -- Construction & initialization --------------------------------------
    Simulator();

    // Load a hex file into instruction memory. Format matches $readmemh:
    //   @XXXXXXXX          — set load address (word-aligned)
    //   DEADBEEF            — 32-bit hex word
    // Returns true on success.
    bool load_hex(const std::string& filename);

    // -- Execution ----------------------------------------------------------
    // Execute a single instruction at the current PC. Returns false if the
    // PC is out of bounds or the instruction is unrecognized (halt condition).
    bool step();

    // Execute up to `max_steps` instructions or until halt.
    void run(uint32_t max_steps);

    // -- State access (for testing / DPI-C) ---------------------------------
    uint32_t get_pc()                   const { return pc_; }
    uint32_t get_reg(uint32_t idx)      const;
    uint32_t read_mem_word(uint32_t addr) const;

    // -- Trace access -------------------------------------------------------
    const std::vector<TraceEntry>& get_trace() const { return trace_; }

    // Write trace log to file in a format suitable for diffing against RTL.
    // Format per line:  PC INSTR RD RD_VAL [MEM_WRITE ADDR VAL]
    void dump_trace(const std::string& filename) const;

    // Print register file state (for debug).
    void dump_regs() const;

private:
    // -- Architectural state ------------------------------------------------
    std::array<uint32_t, NUM_REGS> regs_;
    std::array<uint8_t, MEM_SIZE>  mem_;    // Byte-addressable
    uint32_t                       pc_;
    bool                           halted_;

    // -- Execution trace ----------------------------------------------------
    std::vector<TraceEntry> trace_;

    // -- Internal helpers ---------------------------------------------------
    // Decode: extract all fields from a 32-bit instruction.
    DecodedInstr decode(uint32_t instr) const;

    // Execute: update architectural state based on decoded instruction.
    // Returns a TraceEntry recording what happened.
    TraceEntry execute(const DecodedInstr& d);

    // Disassemble: produce human-readable string for trace log.
    std::string disassemble(const DecodedInstr& d) const;

    // Memory access helpers (handle byte/half/word and alignment).
    uint32_t mem_read_word(uint32_t addr)  const;
    uint16_t mem_read_half(uint32_t addr)  const;
    uint8_t  mem_read_byte(uint32_t addr)  const;
    void     mem_write_word(uint32_t addr, uint32_t val);
    void     mem_write_half(uint32_t addr, uint16_t val);
    void     mem_write_byte(uint32_t addr, uint8_t  val);

    // Sign-extension utility.
    static int32_t sign_extend(uint32_t val, unsigned bit_width);

    // Register write with x0 hardwire protection.
    void write_reg(uint32_t idx, uint32_t val);
};

} // namespace rv32i

#endif // RV32I_ISS_H
