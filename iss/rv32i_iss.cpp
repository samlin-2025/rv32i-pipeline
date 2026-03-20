// ============================================================================
// File:    rv32i_iss.cpp
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    RV32I ISS implementation — decode, execute, trace for all base
//          integer instructions.
//
// Note:    ECALL, EBREAK, FENCE, and CSR instructions are not implemented
//          (they require privileged ISA support). Encountering them halts
//          the simulator.
// ============================================================================

#include "rv32i_iss.h"
#include <iostream>
#include <iomanip>
#include <sstream>
#include <cstring>

namespace rv32i {

// ============================================================================
// OPCODES — matches rv32i_pkg.sv exactly
// ============================================================================
// These constants mirror the SystemVerilog package so there's zero ambiguity
// between the ISS and RTL about what an opcode means.

constexpr uint32_t OP_R_TYPE = 0b0110011;
constexpr uint32_t OP_I_TYPE = 0b0010011;
constexpr uint32_t OP_LOAD   = 0b0000011;
constexpr uint32_t OP_STORE  = 0b0100011;
constexpr uint32_t OP_BRANCH = 0b1100011;
constexpr uint32_t OP_JAL    = 0b1101111;
constexpr uint32_t OP_JALR   = 0b1100111;
constexpr uint32_t OP_LUI    = 0b0110111;
constexpr uint32_t OP_AUIPC  = 0b0010111;

// ============================================================================
// Constructor
// ============================================================================
Simulator::Simulator()
    : pc_(PC_START)
    , halted_(false)
{
    regs_.fill(0);  // All registers start at 0 (x0 is hardwired)
    mem_.fill(0);   // Memory zeroed
}

// ============================================================================
// Hex file loader
// ============================================================================
// Format compatible with Verilog $readmemh:
//   @00000000        — set byte address (we convert to byte addr)
//   00500293          — 32-bit instruction word
//
// This is the same hex file the RTL's Instruction_Memory loads. Using the
// identical file guarantees the ISS and RTL execute the same program.

bool Simulator::load_hex(const std::string& filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        std::cerr << "ERROR: Cannot open hex file: " << filename << "\n";
        return false;
    }

    uint32_t addr = 0;
    std::string line;

    while (std::getline(file, line)) {
        // Strip leading/trailing whitespace
        size_t start = line.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) continue;
        line = line.substr(start);

        // Skip empty lines and comments
        if (line.empty() || line[0] == '/' || line[0] == '#') continue;

        // Address directive: @XXXXXXXX
        if (line[0] == '@') {
            addr = std::stoul(line.substr(1), nullptr, 16);
            // The address in $readmemh is a word index for our mem array
            // Convert to byte address: addr * 4
            addr *= 4;
            continue;
        }

        // Data word: parse as 32-bit hex
        uint32_t word = std::stoul(line, nullptr, 16);
        uint32_t byte_addr = addr;

        // Store as little-endian bytes (RISC-V is little-endian)
        if (byte_addr + 3 < MEM_SIZE) {
            mem_[byte_addr + 0] = (word >>  0) & 0xFF;
            mem_[byte_addr + 1] = (word >>  8) & 0xFF;
            mem_[byte_addr + 2] = (word >> 16) & 0xFF;
            mem_[byte_addr + 3] = (word >> 24) & 0xFF;
        }
        addr += 4;
    }

    std::cout << "ISS: Loaded hex file '" << filename
              << "', last addr = 0x" << std::hex << addr << std::dec << "\n";
    return true;
}

// ============================================================================
// Sign extension utility
// ============================================================================
// Takes an unsigned value and sign-extends from bit position `bit_width - 1`.
//
// Example: sign_extend(0xFFF, 12) → 0xFFFFFFFF (sign bit is bit 11 = 1)
//          sign_extend(0x7FF, 12) → 0x000007FF (sign bit is bit 11 = 0)
//
// This is the C++ equivalent of what the sign_extend.sv module does in RTL.
// Getting this wrong is the #1 source of ISS vs RTL mismatches.

int32_t Simulator::sign_extend(uint32_t val, unsigned bit_width) {
    uint32_t sign_bit = 1u << (bit_width - 1);
    // If sign bit is set, OR in all the upper bits
    if (val & sign_bit) {
        val |= ~((1u << bit_width) - 1);
    }
    return static_cast<int32_t>(val);
}

// ============================================================================
// Decode
// ============================================================================
// Extracts all fields from a 32-bit instruction. The key insight is that
// RISC-V fixed the position of rs1, rs2, rd, funct3, and funct7 across all
// formats — they're always in the same bit positions when they exist. This
// is a deliberate ISA design choice to simplify the hardware decoder.
//
// What changes between formats is which fields are *valid* and how the
// immediate is assembled. The immediate extraction is the tricky part:
//
//   I-type:  imm[11:0]                    = instr[31:20]
//   S-type:  imm[11:5|4:0]               = instr[31:25|11:7]
//   B-type:  imm[12|10:5|4:1|11]         = instr[31|30:25|11:8|7]
//   J-type:  imm[20|10:1|11|19:12]       = instr[31|30:21|20|19:12]
//   U-type:  imm[31:12]                  = instr[31:12] << 12
//
// B-type and J-type immediates are always even (bit 0 = 0) because RISC-V
// instructions are 4-byte aligned. The ISA exploits this by not encoding
// bit 0 — it's implicitly 0. This gives you one extra bit of range.

DecodedInstr Simulator::decode(uint32_t instr) const {
    DecodedInstr d;
    d.raw    = instr;
    d.opcode = instr & 0x7F;
    d.rd     = (instr >>  7) & 0x1F;
    d.funct3 = (instr >> 12) & 0x07;
    d.rs1    = (instr >> 15) & 0x1F;
    d.rs2    = (instr >> 20) & 0x1F;
    d.funct7 = (instr >> 25) & 0x7F;
    d.imm    = 0;

    switch (d.opcode) {
        case OP_R_TYPE:
            d.format = Format::R;
            d.imm    = 0;  // R-type has no immediate
            break;

        case OP_I_TYPE:
        case OP_LOAD:
        case OP_JALR:
            d.format = Format::I;
            d.imm    = sign_extend(instr >> 20, 12);
            break;

        case OP_STORE:
            d.format = Format::S;
            d.imm    = sign_extend(
                ((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12
            );
            break;

        case OP_BRANCH:
            d.format = Format::B;
            // B-type immediate: {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
            d.imm    = sign_extend(
                ((instr >> 31) << 12) |      // imm[12]
                (((instr >> 7) & 1) << 11) | // imm[11]
                (((instr >> 25) & 0x3F) << 5) | // imm[10:5]
                (((instr >> 8) & 0xF) << 1), // imm[4:1]
                13  // 13 bits total (12 down to 0, but bit 0 is always 0)
            );
            break;

        case OP_JAL:
            d.format = Format::J;
            // J-type immediate: {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
            d.imm    = sign_extend(
                ((instr >> 31) << 20) |           // imm[20]
                (((instr >> 12) & 0xFF) << 12) |  // imm[19:12]
                (((instr >> 20) & 1) << 11) |     // imm[11]
                (((instr >> 21) & 0x3FF) << 1),   // imm[10:1]
                21  // 21 bits total
            );
            break;

        case OP_LUI:
        case OP_AUIPC:
            d.format = Format::U;
            d.imm    = static_cast<int32_t>(instr & 0xFFFFF000);  // Upper 20 bits, lower 12 zeroed
            break;

        default:
            d.format = Format::UNKNOWN;
            d.imm    = 0;
            break;
    }

    return d;
}

// ============================================================================
// Execute
// ============================================================================
// This is the heart of the ISS. Each instruction reads source registers,
// computes a result, and writes to a destination register and/or memory.
//
// Key invariant: x0 is ALWAYS 0. Every write to x0 is silently discarded.
// This is enforced by write_reg(), not by the caller. This matches the
// hardware, where x0's flip-flops are tied to ground.

TraceEntry Simulator::execute(const DecodedInstr& d) {
    TraceEntry t;
    t.pc        = pc_;
    t.instr     = d.raw;
    t.rd        = 0;
    t.rd_val    = 0;
    t.mem_write = false;
    t.mem_addr  = 0;
    t.mem_val   = 0;
    t.disasm    = disassemble(d);

    uint32_t rs1_val = regs_[d.rs1];
    uint32_t rs2_val = regs_[d.rs2];
    uint32_t next_pc = pc_ + 4;  // Default: sequential execution

    switch (d.opcode) {

    // ---- R-TYPE: register-register ALU operations -------------------------
    // All R-type instructions read rs1 and rs2, compute a result, write to rd.
    // funct3 + funct7 together determine the exact operation.
    case OP_R_TYPE: {
        uint32_t result = 0;
        switch (d.funct3) {
            case 0x0: result = (d.funct7 == 0x20) ? rs1_val - rs2_val           // SUB
                                                   : rs1_val + rs2_val;          // ADD
                      break;
            case 0x1: result = rs1_val << (rs2_val & 0x1F);                      // SLL
                      break;
            case 0x2: result = (static_cast<int32_t>(rs1_val) <                  // SLT
                                static_cast<int32_t>(rs2_val)) ? 1 : 0;
                      break;
            case 0x3: result = (rs1_val < rs2_val) ? 1 : 0;                      // SLTU
                      break;
            case 0x4: result = rs1_val ^ rs2_val;                                 // XOR
                      break;
            case 0x5: result = (d.funct7 == 0x20)
                             ? static_cast<uint32_t>(static_cast<int32_t>(rs1_val) >> (rs2_val & 0x1F))  // SRA
                             : rs1_val >> (rs2_val & 0x1F);                       // SRL
                      break;
            case 0x6: result = rs1_val | rs2_val;                                 // OR
                      break;
            case 0x7: result = rs1_val & rs2_val;                                 // AND
                      break;
        }
        write_reg(d.rd, result);
        t.rd     = d.rd;
        t.rd_val = result;
        break;
    }

    // ---- I-TYPE: register-immediate ALU operations ------------------------
    // Same as R-type, but rs2 is replaced by the sign-extended 12-bit immediate.
    // Note: SLLI/SRLI/SRAI use only the lower 5 bits of the immediate as the
    // shift amount, and funct7 (bits [31:25]) distinguishes SRLI from SRAI.
    case OP_I_TYPE: {
        uint32_t imm = static_cast<uint32_t>(d.imm);
        uint32_t shamt = imm & 0x1F;  // Shift amount is lower 5 bits
        uint32_t result = 0;

        switch (d.funct3) {
            case 0x0: result = rs1_val + imm;                                     // ADDI
                      break;
            case 0x1: result = rs1_val << shamt;                                  // SLLI
                      break;
            case 0x2: result = (static_cast<int32_t>(rs1_val) <                   // SLTI
                                static_cast<int32_t>(imm)) ? 1 : 0;
                      break;
            case 0x3: result = (rs1_val < imm) ? 1 : 0;                           // SLTIU
                      break;
            case 0x4: result = rs1_val ^ imm;                                      // XORI
                      break;
            case 0x5: result = (d.funct7 == 0x20)
                             ? static_cast<uint32_t>(static_cast<int32_t>(rs1_val) >> shamt)  // SRAI
                             : rs1_val >> shamt;                                   // SRLI
                      break;
            case 0x6: result = rs1_val | imm;                                      // ORI
                      break;
            case 0x7: result = rs1_val & imm;                                      // ANDI
                      break;
        }
        write_reg(d.rd, result);
        t.rd     = d.rd;
        t.rd_val = result;
        break;
    }

    // ---- LOAD: read from memory into register -----------------------------
    // Effective address = rs1 + sign-extended immediate.
    // funct3 determines the width and sign-extension of the loaded value:
    //   LB  (000): load byte, sign-extend to 32 bits
    //   LH  (001): load halfword, sign-extend to 32 bits
    //   LW  (010): load word (no extension needed)
    //   LBU (100): load byte, zero-extend
    //   LHU (101): load halfword, zero-extend
    case OP_LOAD: {
        uint32_t addr = rs1_val + static_cast<uint32_t>(d.imm);
        uint32_t result = 0;

        switch (d.funct3) {
            case 0x0: result = sign_extend(mem_read_byte(addr), 8);       // LB
                      break;
            case 0x1: result = sign_extend(mem_read_half(addr), 16);      // LH
                      break;
            case 0x2: result = mem_read_word(addr);                        // LW
                      break;
            case 0x4: result = mem_read_byte(addr);                        // LBU
                      break;
            case 0x5: result = mem_read_half(addr);                        // LHU
                      break;
            default:
                std::cerr << "ISS: Unknown load funct3=0x"
                          << std::hex << d.funct3 << " at PC=0x" << pc_ << "\n";
                halted_ = true;
                break;
        }
        write_reg(d.rd, result);
        t.rd     = d.rd;
        t.rd_val = result;
        break;
    }

    // ---- STORE: write register to memory ----------------------------------
    // Effective address = rs1 + sign-extended S-type immediate.
    // funct3 determines width: SB (000), SH (001), SW (010).
    // No register writeback (rd field is part of the immediate in S-type).
    case OP_STORE: {
        uint32_t addr = rs1_val + static_cast<uint32_t>(d.imm);
        t.mem_write = true;
        t.mem_addr  = addr;

        switch (d.funct3) {
            case 0x0: mem_write_byte(addr, rs2_val & 0xFF);        // SB
                      t.mem_val = rs2_val & 0xFF;
                      break;
            case 0x1: mem_write_half(addr, rs2_val & 0xFFFF);      // SH
                      t.mem_val = rs2_val & 0xFFFF;
                      break;
            case 0x2: mem_write_word(addr, rs2_val);                // SW
                      t.mem_val = rs2_val;
                      break;
            default:
                std::cerr << "ISS: Unknown store funct3=0x"
                          << std::hex << d.funct3 << " at PC=0x" << pc_ << "\n";
                halted_ = true;
                break;
        }
        break;
    }

    // ---- BRANCH: conditional PC-relative jump -----------------------------
    // Compares rs1 and rs2 according to funct3. If condition is true,
    // PC += sign-extended B-type immediate. Otherwise, PC += 4.
    //
    // Interview tip: The original repo only implemented BEQ (Zero flag).
    // A real RV32I needs all six: BEQ, BNE, BLT, BGE, BLTU, BGEU.
    // The signed vs unsigned distinction (BLT vs BLTU) is critical — it
    // determines whether the ALU uses signed or unsigned comparison.
    case OP_BRANCH: {
        bool taken = false;
        int32_t s_rs1 = static_cast<int32_t>(rs1_val);
        int32_t s_rs2 = static_cast<int32_t>(rs2_val);

        switch (d.funct3) {
            case 0x0: taken = (rs1_val == rs2_val);       break;  // BEQ
            case 0x1: taken = (rs1_val != rs2_val);       break;  // BNE
            case 0x4: taken = (s_rs1 < s_rs2);            break;  // BLT
            case 0x5: taken = (s_rs1 >= s_rs2);           break;  // BGE
            case 0x6: taken = (rs1_val < rs2_val);        break;  // BLTU
            case 0x7: taken = (rs1_val >= rs2_val);       break;  // BGEU
            default:
                std::cerr << "ISS: Unknown branch funct3=0x"
                          << std::hex << d.funct3 << " at PC=0x" << pc_ << "\n";
                halted_ = true;
                break;
        }

        if (taken) {
            next_pc = pc_ + static_cast<uint32_t>(d.imm);
        }
        break;
    }

    // ---- JAL: jump and link -----------------------------------------------
    // PC-relative unconditional jump. Stores return address (PC + 4) in rd.
    // The 21-bit J-type immediate gives ±1 MiB range.
    //
    // This is how function calls work: JAL x1, offset
    // x1 (ra) gets the return address, PC jumps to the function.
    case OP_JAL: {
        uint32_t link_addr = pc_ + 4;
        next_pc = pc_ + static_cast<uint32_t>(d.imm);
        write_reg(d.rd, link_addr);
        t.rd     = d.rd;
        t.rd_val = link_addr;
        break;
    }

    // ---- JALR: jump and link register -------------------------------------
    // Indirect jump: target = (rs1 + imm) & ~1. Stores PC + 4 in rd.
    // The &~1 clears the LSB to ensure 2-byte alignment.
    //
    // This is how function returns work: JALR x0, x1, 0
    // (jump to address in x1, discard return address by writing to x0)
    case OP_JALR: {
        uint32_t link_addr = pc_ + 4;
        next_pc = (rs1_val + static_cast<uint32_t>(d.imm)) & ~1u;
        write_reg(d.rd, link_addr);
        t.rd     = d.rd;
        t.rd_val = link_addr;
        break;
    }

    // ---- LUI: load upper immediate ----------------------------------------
    // Writes the 20-bit U-type immediate (shifted left by 12) directly to rd.
    // Used to build 32-bit constants: LUI rd, upper20 ; ADDI rd, rd, lower12
    case OP_LUI: {
        uint32_t result = static_cast<uint32_t>(d.imm);
        write_reg(d.rd, result);
        t.rd     = d.rd;
        t.rd_val = result;
        break;
    }

    // ---- AUIPC: add upper immediate to PC ---------------------------------
    // rd = PC + (imm << 12). Used for PC-relative addressing of data that's
    // far from the current instruction. AUIPC + ADDI can address any 32-bit
    // offset from the current PC.
    case OP_AUIPC: {
        uint32_t result = pc_ + static_cast<uint32_t>(d.imm);
        write_reg(d.rd, result);
        t.rd     = d.rd;
        t.rd_val = result;
        break;
    }

    default:
        std::cerr << "ISS: Unimplemented opcode 0x" << std::hex << d.opcode
                  << " at PC=0x" << pc_ << "\n";
        halted_ = true;
        break;
    }

    // Advance PC
    pc_ = next_pc;
    return t;
}

// ============================================================================
// Disassembler
// ============================================================================
// Produces human-readable strings like "ADD x5, x10, x6" for the trace log.
// This is invaluable for debugging: when the RTL and ISS disagree, you look
// at the trace and immediately see which instruction caused the divergence.

std::string Simulator::disassemble(const DecodedInstr& d) const {
    std::ostringstream ss;
    auto reg_name = [](uint32_t r) -> std::string {
        return "x" + std::to_string(r);
    };

    switch (d.opcode) {
    case OP_R_TYPE: {
        const char* op = "???";
        switch (d.funct3) {
            case 0x0: op = (d.funct7 == 0x20) ? "SUB" : "ADD"; break;
            case 0x1: op = "SLL";  break;
            case 0x2: op = "SLT";  break;
            case 0x3: op = "SLTU"; break;
            case 0x4: op = "XOR";  break;
            case 0x5: op = (d.funct7 == 0x20) ? "SRA" : "SRL"; break;
            case 0x6: op = "OR";   break;
            case 0x7: op = "AND";  break;
        }
        ss << op << " " << reg_name(d.rd) << ", "
           << reg_name(d.rs1) << ", " << reg_name(d.rs2);
        break;
    }
    case OP_I_TYPE: {
        const char* op = "???";
        switch (d.funct3) {
            case 0x0: op = "ADDI";  break;
            case 0x1: op = "SLLI";  break;
            case 0x2: op = "SLTI";  break;
            case 0x3: op = "SLTIU"; break;
            case 0x4: op = "XORI";  break;
            case 0x5: op = (d.funct7 == 0x20) ? "SRAI" : "SRLI"; break;
            case 0x6: op = "ORI";   break;
            case 0x7: op = "ANDI";  break;
        }
        ss << op << " " << reg_name(d.rd) << ", "
           << reg_name(d.rs1) << ", " << d.imm;
        break;
    }
    case OP_LOAD: {
        const char* op = "???";
        switch (d.funct3) {
            case 0x0: op = "LB";  break;
            case 0x1: op = "LH";  break;
            case 0x2: op = "LW";  break;
            case 0x4: op = "LBU"; break;
            case 0x5: op = "LHU"; break;
        }
        ss << op << " " << reg_name(d.rd) << ", "
           << d.imm << "(" << reg_name(d.rs1) << ")";
        break;
    }
    case OP_STORE: {
        const char* op = "???";
        switch (d.funct3) {
            case 0x0: op = "SB"; break;
            case 0x1: op = "SH"; break;
            case 0x2: op = "SW"; break;
        }
        ss << op << " " << reg_name(d.rs2) << ", "
           << d.imm << "(" << reg_name(d.rs1) << ")";
        break;
    }
    case OP_BRANCH: {
        const char* op = "???";
        switch (d.funct3) {
            case 0x0: op = "BEQ";  break;
            case 0x1: op = "BNE";  break;
            case 0x4: op = "BLT";  break;
            case 0x5: op = "BGE";  break;
            case 0x6: op = "BLTU"; break;
            case 0x7: op = "BGEU"; break;
        }
        ss << op << " " << reg_name(d.rs1) << ", "
           << reg_name(d.rs2) << ", " << d.imm;
        break;
    }
    case OP_JAL:
        ss << "JAL " << reg_name(d.rd) << ", " << d.imm;
        break;
    case OP_JALR:
        ss << "JALR " << reg_name(d.rd) << ", "
           << reg_name(d.rs1) << ", " << d.imm;
        break;
    case OP_LUI:
        ss << "LUI " << reg_name(d.rd) << ", 0x"
           << std::hex << (static_cast<uint32_t>(d.imm) >> 12);
        break;
    case OP_AUIPC:
        ss << "AUIPC " << reg_name(d.rd) << ", 0x"
           << std::hex << (static_cast<uint32_t>(d.imm) >> 12);
        break;
    default:
        ss << "UNKNOWN (0x" << std::hex << d.raw << ")";
        break;
    }

    return ss.str();
}

// ============================================================================
// Step & Run
// ============================================================================

bool Simulator::step() {
    if (halted_) return false;

    // Bounds check
    if (pc_ + 3 >= MEM_SIZE) {
        std::cerr << "ISS: PC out of bounds: 0x" << std::hex << pc_ << "\n";
        halted_ = true;
        return false;
    }

    // Fetch
    uint32_t instr = mem_read_word(pc_);

    // Halt on NOP/zero instruction (end of program marker)
    if (instr == 0x00000000) {
        std::cout << "ISS: Encountered zero instruction at PC=0x"
                  << std::hex << pc_ << ", halting.\n" << std::dec;
        halted_ = true;
        return false;
    }

    // Decode
    DecodedInstr d = decode(instr);

    if (d.format == Format::UNKNOWN) {
        std::cerr << "ISS: Unknown instruction 0x" << std::hex << instr
                  << " at PC=0x" << pc_ << "\n";
        halted_ = true;
        return false;
    }

    // Execute (updates architectural state and returns trace entry)
    TraceEntry t = execute(d);
    trace_.push_back(t);

    return !halted_;
}

void Simulator::run(uint32_t max_steps) {
    for (uint32_t i = 0; i < max_steps; ++i) {
        if (!step()) break;
    }
}

// ============================================================================
// State access
// ============================================================================

uint32_t Simulator::get_reg(uint32_t idx) const {
    if (idx >= NUM_REGS) return 0;
    return regs_[idx];
}

uint32_t Simulator::read_mem_word(uint32_t addr) const {
    return mem_read_word(addr);
}

// ============================================================================
// Memory access helpers
// ============================================================================
// RISC-V is little-endian. A 32-bit word at address A is stored as:
//   mem[A+0] = byte 0 (LSB)
//   mem[A+1] = byte 1
//   mem[A+2] = byte 2
//   mem[A+3] = byte 3 (MSB)
//
// The original Verilog used mem[A] with 32-bit-wide memory words, which hides
// the byte ordering. Our ISS uses byte-addressable memory to match real
// hardware behavior and to correctly handle LB/LH/SB/SH.

uint32_t Simulator::mem_read_word(uint32_t addr) const {
    addr &= ~3u;  // Word-align
    if (addr + 3 >= MEM_SIZE) return 0;
    return static_cast<uint32_t>(mem_[addr + 0])        |
           (static_cast<uint32_t>(mem_[addr + 1]) << 8)  |
           (static_cast<uint32_t>(mem_[addr + 2]) << 16) |
           (static_cast<uint32_t>(mem_[addr + 3]) << 24);
}

uint16_t Simulator::mem_read_half(uint32_t addr) const {
    addr &= ~1u;  // Half-word align
    if (addr + 1 >= MEM_SIZE) return 0;
    return static_cast<uint16_t>(mem_[addr + 0]) |
           (static_cast<uint16_t>(mem_[addr + 1]) << 8);
}

uint8_t Simulator::mem_read_byte(uint32_t addr) const {
    if (addr >= MEM_SIZE) return 0;
    return mem_[addr];
}

void Simulator::mem_write_word(uint32_t addr, uint32_t val) {
    addr &= ~3u;
    if (addr + 3 >= MEM_SIZE) return;
    mem_[addr + 0] = (val >>  0) & 0xFF;
    mem_[addr + 1] = (val >>  8) & 0xFF;
    mem_[addr + 2] = (val >> 16) & 0xFF;
    mem_[addr + 3] = (val >> 24) & 0xFF;
}

void Simulator::mem_write_half(uint32_t addr, uint16_t val) {
    addr &= ~1u;
    if (addr + 1 >= MEM_SIZE) return;
    mem_[addr + 0] = (val >> 0) & 0xFF;
    mem_[addr + 1] = (val >> 8) & 0xFF;
}

void Simulator::mem_write_byte(uint32_t addr, uint8_t val) {
    if (addr >= MEM_SIZE) return;
    mem_[addr] = val;
}

// ============================================================================
// Register write — x0 hardwire protection
// ============================================================================
void Simulator::write_reg(uint32_t idx, uint32_t val) {
    if (idx == 0) return;  // x0 is hardwired to 0, writes are discarded
    if (idx >= NUM_REGS) return;
    regs_[idx] = val;
}

// ============================================================================
// Trace dump
// ============================================================================
// Output format (one line per retired instruction):
//   PC        INSTR     RD  RD_VAL    [W ADDR VAL]  DISASM
//
// Example:
//   00000000  00500293  05  00000005                 ADDI x5, x0, 5
//   00000004  00300313  06  00000003                 ADDI x6, x0, 3
//   00000008  006283B3  07  00000008                 ADD x7, x5, x6

void Simulator::dump_trace(const std::string& filename) const {
    std::ofstream file(filename);
    if (!file.is_open()) {
        std::cerr << "ERROR: Cannot open trace file: " << filename << "\n";
        return;
    }

    file << "# PC        INSTR     RD  RD_VAL    MEM               DISASM\n";
    file << "# --------  --------  --  --------  ----------------  ------\n";

    for (const auto& t : trace_) {
        file << std::hex << std::setw(8) << std::setfill('0') << t.pc << "  "
             << std::setw(8) << std::setfill('0') << t.instr << "  "
             << std::dec << std::setw(2) << std::setfill(' ') << t.rd << "  "
             << std::hex << std::setw(8) << std::setfill('0') << t.rd_val << "  ";

        if (t.mem_write) {
            file << "W " << std::hex << std::setw(8) << std::setfill('0') << t.mem_addr
                 << " " << std::setw(8) << std::setfill('0') << t.mem_val;
        } else {
            file << "                ";
        }

        file << "  " << t.disasm << "\n";
    }

    std::cout << "ISS: Trace written to '" << filename
              << "' (" << trace_.size() << " instructions)\n";
}

// ============================================================================
// Register dump
// ============================================================================
void Simulator::dump_regs() const {
    std::cout << "\n===== Register File =====\n";
    for (int i = 0; i < 32; i += 4) {
        for (int j = 0; j < 4; ++j) {
            std::cout << "  x" << std::setw(2) << std::setfill(' ') << (i + j)
                      << " = 0x" << std::hex << std::setw(8) << std::setfill('0')
                      << regs_[i + j] << std::dec;
        }
        std::cout << "\n";
    }
    std::cout << "  PC  = 0x" << std::hex << std::setw(8) << std::setfill('0')
              << pc_ << std::dec << "\n";
    std::cout << "=========================\n\n";
}

} // namespace rv32i
