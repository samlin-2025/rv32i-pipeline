// ============================================================================
// File:    main_decoder.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Main control decoder — first level of the two-level decode.
//
//          Examines the 7-bit opcode and generates all pipeline control
//          signals. The alu_op output feeds into the ALU decoder (second
//          level) which refines it using funct3/funct7.
//
//          Supports all RV32I base opcodes:
//            R-type (0110011), I-type ALU (0010011), Load (0000011),
//            Store (0100011), Branch (1100011), JAL (1101111),
//            JALR (1100111), LUI (0110111), AUIPC (0010111)
//
// Ports:
//   opcode_i    — instr[6:0]
//   reg_write_o — Write to register file in WB stage
//   result_src_o— Writeback mux: 00=ALU, 01=memory, 10=PC+4
//   mem_write_o — Write to data memory in MEM stage
//   alu_src_o   — ALU operand B: 0=rs2, 1=immediate
//   imm_src_o   — Immediate format selector (I/S/B/J/U)
//   alu_op_o    — ALU operation hint for ALU decoder
//   branch_o    — Instruction is a conditional branch
//   jump_o      — Instruction is JAL or JALR
// ============================================================================

module main_decoder
  import rv32i_pkg::*;
(
  input  logic [6:0]    opcode_i,

  output logic           reg_write_o,
  output result_src_e    result_src_o,
  output logic           mem_write_o,
  output logic           alu_src_o,
  output imm_src_e       imm_src_o,
  output alu_op_hint_e   alu_op_o,
  output logic           branch_o,
  output logic           jump_o,
  output logic           alu_a_pc_o    // 1 = ALU operand A is PC (AUIPC)
);

  // --------------------------------------------------------------------------
  // Control signal generation
  // --------------------------------------------------------------------------
  // This is a pure combinational decode — no state, no clock. The opcode
  // arrives from the IF/ID register, and all control signals are produced
  // in the same cycle for use by the ID/EX pipeline register.
  //
  // Style note: We use a single always_comb block with a case statement
  // rather than individual assign statements (like the original). Reasons:
  //
  //   1. Single point of truth — all signals for a given opcode are on
  //      the same line, making it easy to verify the truth table.
  //
  //   2. Default assignment — signals get safe defaults at the top. This
  //      prevents latches from incomplete case branches and ensures that
  //      unrecognized opcodes produce NOP-like behavior (no writes).
  //
  //   3. Readability — an Apple reviewer can scan the case statement and
  //      verify each opcode's behavior at a glance.

  always_comb begin
    // ------------------------------------------------------------------
    // Defaults: NOP behavior — no writes, no branches, ALU does nothing
    // ------------------------------------------------------------------
    // These defaults fire for any unrecognized opcode. They're safe:
    // no register write, no memory write, no branch, no jump.
    // The pipeline processes the instruction harmlessly.
    reg_write_o  = 1'b0;
    result_src_o = RESULT_ALU;
    mem_write_o  = 1'b0;
    alu_src_o    = 1'b0;
    imm_src_o    = IMM_I;
    alu_op_o     = ALU_OP_ADD;
    branch_o     = 1'b0;
    jump_o       = 1'b0;
    alu_a_pc_o   = 1'b0;

    unique case (opcode_i)

      // ---- R-type: register-register ALU (ADD, SUB, AND, OR, ...) ----
      // Both operands from register file. No immediate. Full funct3/funct7
      // decode needed (alu_op = FUNC). Result written to rd.
      OP_R_TYPE: begin
        reg_write_o  = 1'b1;
        result_src_o = RESULT_ALU;
        alu_src_o    = 1'b0;        // B = rs2
        alu_op_o     = ALU_OP_FUNC; // Decode funct3/funct7
      end

      // ---- I-type ALU: register-immediate (ADDI, SLTI, ANDI, ...) ----
      // Operand A from register, operand B from I-type immediate.
      // Full funct3 decode needed. Result written to rd.
      OP_I_TYPE: begin
        reg_write_o  = 1'b1;
        result_src_o = RESULT_ALU;
        alu_src_o    = 1'b1;        // B = immediate
        imm_src_o    = IMM_I;
        alu_op_o     = ALU_OP_FUNC; // Decode funct3
      end

      // ---- Load: memory read (LB, LH, LW, LBU, LHU) ----
      // Address = rs1 + I-type immediate (ALU computes ADD).
      // Data memory read in MEM stage. Result from memory written to rd.
      OP_LOAD: begin
        reg_write_o  = 1'b1;
        result_src_o = RESULT_MEM;  // Writeback from memory
        alu_src_o    = 1'b1;        // B = immediate (address offset)
        imm_src_o    = IMM_I;
        alu_op_o     = ALU_OP_ADD;  // Address calculation
      end

      // ---- Store: memory write (SB, SH, SW) ----
      // Address = rs1 + S-type immediate (ALU computes ADD).
      // Data from rs2 written to memory. No register writeback.
      OP_STORE: begin
        mem_write_o  = 1'b1;
        alu_src_o    = 1'b1;        // B = immediate (address offset)
        imm_src_o    = IMM_S;
        alu_op_o     = ALU_OP_ADD;  // Address calculation
      end

      // ---- Branch: conditional PC-relative jump ----
      // ALU subtracts rs1 - rs2 to set flags. The branch resolution
      // logic uses funct3 and flags to decide taken/not-taken.
      // B-type immediate is the PC offset. No register writeback.
      OP_BRANCH: begin
        alu_src_o    = 1'b0;        // B = rs2 (for comparison)
        imm_src_o    = IMM_B;
        alu_op_o     = ALU_OP_SUB;  // Subtract for flag generation
        branch_o     = 1'b1;
      end

      // ---- JAL: unconditional jump, PC-relative ----
      // Target = PC + J-type immediate (computed in execute stage).
      // Link address (PC+4) written to rd. The ALU is not involved
      // in the target calculation (we use the branch adder), so
      // alu_op is don't-care. result_src selects PC+4 for writeback.
      OP_JAL: begin
        reg_write_o  = 1'b1;
        result_src_o = RESULT_PC4;  // Write PC+4 (return address) to rd
        imm_src_o    = IMM_J;
        jump_o       = 1'b1;
      end

      // ---- JALR: unconditional jump, register-indirect ----
      // Target = (rs1 + I-type immediate) & ~1.
      // The ALU computes rs1 + imm (via ADD). The &~1 is handled
      // downstream. Link address (PC+4) written to rd.
      OP_JALR: begin
        reg_write_o  = 1'b1;
        result_src_o = RESULT_PC4;  // Write PC+4 to rd
        alu_src_o    = 1'b1;        // B = immediate
        imm_src_o    = IMM_I;
        alu_op_o     = ALU_OP_ADD;  // Compute rs1 + imm
        jump_o       = 1'b1;
      end

      // ---- LUI: load upper immediate ----
      // The immediate (upper 20 bits) passes through the ALU to rd.
      // ALU_LUI passes B (the immediate) directly to the result.
      // rs1 is x0 by convention, but the ALU ignores A for LUI.
      OP_LUI: begin
        reg_write_o  = 1'b1;
        result_src_o = RESULT_ALU;
        alu_src_o    = 1'b1;        // B = U-type immediate
        imm_src_o    = IMM_U;
        alu_op_o     = ALU_OP_LUI;  // Pass B through
      end

      // ---- AUIPC: add upper immediate to PC ----
      // ALU computes PC + U-type immediate. The execute stage will
      // route PC (not rs1) to the ALU's A input for this instruction.
      // For now, we set alu_op = ADD and alu_src = 1 (immediate on B).
      OP_AUIPC: begin
        reg_write_o  = 1'b1;
        result_src_o = RESULT_ALU;
        alu_src_o    = 1'b1;        // B = U-type immediate
        imm_src_o    = IMM_U;
        alu_op_o     = ALU_OP_ADD;  // PC + imm
        alu_a_pc_o   = 1'b1;        // A = PC (not rs1)
      end

      default: begin
        // All outputs keep their safe defaults (NOP behavior)
      end

    endcase
  end

endmodule : main_decoder
