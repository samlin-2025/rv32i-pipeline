// ============================================================================
// File:    rv32i_pkg.sv
// Author:  Sam Lin
// Date:    2026-03-19
// Desc:    Shared package for RV32I 5-stage pipelined processor.
//          Contains all opcodes, ALU enums, control signal typedefs,
//          and datapath width parameters. Every magic number in the
//          design traces back to a named constant here.
//
// Ref:     RISC-V Unprivileged ISA Spec v20191213, Chapter 2 (RV32I)
//          Harris & Harris, Digital Design & Computer Architecture: RISC-V Ed.
// ============================================================================

package rv32i_pkg;

  // --------------------------------------------------------------------------
  // 1. Datapath width parameters
  // --------------------------------------------------------------------------
  // Centralizing widths here makes it trivial to extend to RV64I later — you
  // change XLEN once and every module that imports the package adapts.

  parameter int unsigned XLEN       = 32;       // Register / data width
  parameter int unsigned ALEN       = 32;       // Address width
  parameter int unsigned RF_ADDR_W  =  5;       // log2(32 registers)
  parameter int unsigned INSTR_W    = 32;       // Fixed-length instruction

  // Memory depths (in 32-bit words). Sized for simulation — synthesis would
  // replace these with SRAM macros or cache interfaces.
  parameter int unsigned IMEM_DEPTH = 1024;
  parameter int unsigned DMEM_DEPTH = 1024;

  // --------------------------------------------------------------------------
  // 2. Opcodes — RISC-V [6:0] field
  // --------------------------------------------------------------------------
  // The opcode is bits [6:0] of every RV32I instruction. These seven bits
  // tell the control unit the *format* of the instruction, which determines:
  //   - Which pipeline resources are used (ALU, memory, register file)
  //   - How the immediate is extracted (I/S/B/J/U encoding)
  //   - What the ALU decoder needs to look at (funct3, funct7, or nothing)
  //
  // We use a typedef so any signal declared as `opcode_e` gets type-checked.
  // If you accidentally wire a 3-bit funct3 into an opcode port, the
  // simulator / synthesis tool will flag a width mismatch.

  typedef enum logic [6:0] {
    OP_R_TYPE   = 7'b011_0011,  // R-type:  ADD, SUB, SLL, SLT, XOR, SRL, SRA, OR, AND
    OP_I_TYPE   = 7'b001_0011,  // I-type:  ADDI, SLTI, XORI, ORI, ANDI, SLLI, SRLI, SRAI
    OP_LOAD     = 7'b000_0011,  // I-type:  LB, LH, LW, LBU, LHU
    OP_STORE    = 7'b010_0011,  // S-type:  SB, SH, SW
    OP_BRANCH   = 7'b110_0011,  // B-type:  BEQ, BNE, BLT, BGE, BLTU, BGEU
    OP_JAL      = 7'b110_1111,  // J-type:  JAL
    OP_JALR     = 7'b110_0111,  // I-type:  JALR (same imm format as I, but distinct opcode)
    OP_LUI      = 7'b011_0111,  // U-type:  LUI
    OP_AUIPC    = 7'b001_0111   // U-type:  AUIPC
  } opcode_e;

  // --------------------------------------------------------------------------
  // 3. ALU operation encoding
  // --------------------------------------------------------------------------
  // This is the *resolved* operation the ALU executes. The ALU decoder
  // combines ALUOp (from main decoder), funct3, and funct7 to produce this.
  //
  // Why 4 bits? RV32I has 10 distinct ALU operations. 3 bits only gives 8
  // encodings — not enough. 4 bits gives us 16, with room for M-extension
  // (MUL, DIV, REM) later.
  //
  // Interview tip: At Apple, the ALU is typically the *fastest* logic in the
  // execute stage. The critical path usually runs through the adder/subtractor.
  // That's why SLT is implemented as "subtract, then check the sign bit" —
  // it reuses the adder rather than adding a separate comparator.

  typedef enum logic [3:0] {
    ALU_ADD   = 4'b0000,  // Addition           (ADD, ADDI, loads, stores, AUIPC)
    ALU_SUB   = 4'b0001,  // Subtraction         (SUB, branches)
    ALU_AND   = 4'b0010,  // Bitwise AND         (AND, ANDI)
    ALU_OR    = 4'b0011,  // Bitwise OR          (OR, ORI)
    ALU_XOR   = 4'b0100,  // Bitwise XOR         (XOR, XORI)
    ALU_SLT   = 4'b0101,  // Set less than       (SLT, SLTI)      — signed compare
    ALU_SLTU  = 4'b0110,  // Set less than uns.  (SLTU, SLTIU)    — unsigned compare
    ALU_SLL   = 4'b0111,  // Shift left logical  (SLL, SLLI)
    ALU_SRL   = 4'b1000,  // Shift right logical (SRL, SRLI)
    ALU_SRA   = 4'b1001,  // Shift right arith.  (SRA, SRAI)
    ALU_LUI   = 4'b1010   // Pass B through      (LUI — imm goes straight to rd)
  } alu_op_e;

  // --------------------------------------------------------------------------
  // 4. ALUOp — Main decoder's hint to the ALU decoder
  // --------------------------------------------------------------------------
  // This 2-bit signal tells the ALU decoder *how hard to work*:
  //
  //   ALU_OP_ADD  (00) — Just add. Used by loads, stores, AUIPC, JALR.
  //                       The ALU decoder ignores funct3/funct7 entirely.
  //
  //   ALU_OP_SUB  (01) — Subtract. Used by branches (BEQ/BNE/BLT/BGE).
  //                       The ALU computes A - B and checks flags.
  //
  //   ALU_OP_FUNC (10) — Look at funct3 + funct7 to decide. Used by R-type
  //                       and I-type arithmetic. This is where the full decode
  //                       table lives.
  //
  //   ALU_OP_LUI  (11) — Pass the immediate through (LUI).
  //
  // Interview question: "Why not just always decode funct3/funct7?"
  // Answer: Power. In a real chip, the ALU decoder has combinational logic
  // that switches on every cycle. If 60% of instructions are loads/stores,
  // you're wasting energy decoding funct3 when the answer is always "add."
  // The 2-bit ALUOp lets the decoder short-circuit.

  typedef enum logic [1:0] {
    ALU_OP_ADD  = 2'b00,  // Force ADD (loads, stores, JALR, AUIPC)
    ALU_OP_SUB  = 2'b01,  // Force SUB (branches)
    ALU_OP_FUNC = 2'b10,  // Decode from funct3/funct7 (R-type, I-type)
    ALU_OP_LUI  = 2'b11   // Pass B (LUI)
  } alu_op_hint_e;

  // --------------------------------------------------------------------------
  // 5. Immediate source encoding
  // --------------------------------------------------------------------------
  // The RISC-V ISA scatters immediate bits across the instruction in five
  // different patterns. The immediate generator (sign_extend module) uses
  // this selector to know which bits to extract and sign-extend.
  //
  // The original repo only handled I-type and S-type (2'b00 and 2'b01).
  // That meant branches, JAL, LUI, and AUIPC all got garbage immediates.
  // We handle all five:
  //
  //   I-type:  imm[11:0]                = instr[31:20]
  //   S-type:  imm[11:5|4:0]            = instr[31:25|11:7]
  //   B-type:  imm[12|10:5|4:1|11]      = instr[31|30:25|11:8|7]  (x2 aligned)
  //   J-type:  imm[20|10:1|11|19:12]    = instr[31|30:21|20|19:12] (x2 aligned)
  //   U-type:  imm[31:12]               = instr[31:12] << 12

  typedef enum logic [2:0] {
    IMM_I = 3'b000,  // I-type immediate
    IMM_S = 3'b001,  // S-type immediate
    IMM_B = 3'b010,  // B-type immediate (branch offset)
    IMM_J = 3'b011,  // J-type immediate (JAL offset)
    IMM_U = 3'b100   // U-type immediate (LUI / AUIPC upper)
  } imm_src_e;

  // --------------------------------------------------------------------------
  // 6. Result source — writeback mux select
  // --------------------------------------------------------------------------
  // Determines what value gets written back to the register file in WB stage.
  //
  // The original repo used 1 bit: ALU or memory. That breaks JAL/JALR, which
  // need to write PC+4 (the return address) to rd. We use 2 bits:
  //
  //   RESULT_ALU  — ALU output (R-type, I-type, LUI, AUIPC)
  //   RESULT_MEM  — Data memory read (loads)
  //   RESULT_PC4  — PC + 4 (JAL, JALR — link address)

  typedef enum logic [1:0] {
    RESULT_ALU = 2'b00,
    RESULT_MEM = 2'b01,
    RESULT_PC4 = 2'b10
  } result_src_e;

  // --------------------------------------------------------------------------
  // 7. Forwarding mux select
  // --------------------------------------------------------------------------
  // In the execute stage, operands might come from:
  //   - The register file (no hazard — normal path)
  //   - The MEM stage (EX→MEM forwarding, 1-cycle-old result)
  //   - The WB stage  (EX→WB forwarding, 2-cycle-old result)
  //
  // Priority: MEM > WB > register file. If both MEM and WB have the same rd,
  // MEM is newer, so it wins. The hazard unit encodes this as:
  //
  //   FWD_NONE  — Use register file value
  //   FWD_WB    — Forward from writeback stage
  //   FWD_MEM   — Forward from memory stage (higher priority)

  typedef enum logic [1:0] {
    FWD_NONE = 2'b00,
    FWD_WB   = 2'b01,
    FWD_MEM  = 2'b10
  } forward_e;

  // --------------------------------------------------------------------------
  // 8. Branch function (funct3 encoding for B-type)
  // --------------------------------------------------------------------------
  // When the main decoder sees a branch opcode, the funct3 field tells us
  // *which* branch condition to evaluate. The execute stage uses these to
  // pick the right comparison from the ALU flags.
  //
  // Note: BLT/BGE are signed, BLTU/BGEU are unsigned. This distinction
  // matters for the ALU — signed comparison checks the overflow-corrected
  // sign bit, unsigned checks the carry flag.

  typedef enum logic [2:0] {
    FUNCT3_BEQ  = 3'b000,
    FUNCT3_BNE  = 3'b001,
    FUNCT3_BLT  = 3'b100,
    FUNCT3_BGE  = 3'b101,
    FUNCT3_BLTU = 3'b110,
    FUNCT3_BGEU = 3'b111
  } branch_funct3_e;

  // --------------------------------------------------------------------------
  // 9. Pipeline control bundle — ID/EX register
  // --------------------------------------------------------------------------
  // Grouping control signals into a struct keeps the pipeline registers clean.
  // Instead of 8 separate reg declarations in the decode stage, you get one
  // struct that moves atomically through the pipeline.
  //
  // Interview tip: In real Apple RTL, control bundles are structs that flow
  // through the pipe. It makes flush logic trivial — you just assign the
  // struct to '0 and every control signal zeros out in one statement.

  typedef struct packed {
    logic           reg_write;    // Write to register file in WB
    result_src_e    result_src;   // Writeback mux select
    logic           mem_write;    // Write to data memory in MEM
    logic           branch;       // Instruction is a branch
    logic           jump;         // Instruction is JAL or JALR
    alu_op_e        alu_ctrl;     // Resolved ALU operation
    logic           alu_src;      // 0 = rs2, 1 = immediate for ALU operand B
    logic           alu_a_pc;     // 0 = rs1, 1 = PC for ALU operand A (AUIPC)
  } ctrl_ex_t;

endpackage : rv32i_pkg
