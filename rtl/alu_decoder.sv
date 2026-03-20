// ============================================================================
// File:    alu_decoder.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    ALU decoder — second level of the two-level control decode.
//
//          Takes the coarse ALUOp hint from the main decoder and refines it
//          using funct3 and funct7 into the precise alu_op_e that drives
//          the ALU.
//
//          Decode priority:
//            ALU_OP_ADD  (00) → ALU_ADD immediately (loads, stores, JALR, AUIPC)
//            ALU_OP_SUB  (01) → ALU_SUB immediately (branches)
//            ALU_OP_LUI  (11) → ALU_LUI immediately (LUI)
//            ALU_OP_FUNC (10) → Decode funct3 + funct7 (R-type / I-type ALU)
//
// Ports:
//   alu_op_i   — 2-bit hint from main decoder (alu_op_hint_e)
//   funct3_i   — instr[14:12] — operation variant
//   funct7_5_i — instr[30]    — SUB/SRA flag (bit 5 of funct7)
//   op_5_i     — instr[5]     — R-type vs I-type (bit 5 of opcode)
//   alu_ctrl_o — Resolved ALU operation (alu_op_e)
//
// Key insight:
//   SUB and SRA share the same distinguishing bit: funct7[5] = 1.
//   But SUBI doesn't exist — only SUB (R-type). So we check both
//   op[5] (R-type indicator) and funct7[5] to avoid treating ADDI
//   with a garbage funct7 field as SUB.
// ============================================================================

module alu_decoder
  import rv32i_pkg::*;
(
  input  alu_op_hint_e alu_op_i,     // Coarse hint from main decoder
  input  logic [2:0]   funct3_i,     // instr[14:12]
  input  logic         funct7_5_i,   // instr[30] (bit 5 of funct7)
  input  logic         op_5_i,       // instr[5]  (bit 5 of opcode)
  output alu_op_e      alu_ctrl_o    // Resolved ALU operation
);

  // --------------------------------------------------------------------------
  // Decode logic
  // --------------------------------------------------------------------------
  // The outer case on alu_op_i handles the fast-path operations (ADD, SUB,
  // LUI) that don't need funct3/funct7 inspection. Only ALU_OP_FUNC (10)
  // enters the full funct3 decode.
  //
  // Style note: Nested unique case statements. The outer case dispatches
  // on alu_op_i (4 possibilities). The inner case dispatches on funct3
  // (8 possibilities). This maps directly to a two-level mux tree in
  // hardware, which is efficient for both area and timing.

  always_comb begin
    unique case (alu_op_i)

      // Fast paths — no funct3/funct7 inspection needed
      ALU_OP_ADD: alu_ctrl_o = ALU_ADD;    // Loads, stores, JALR, AUIPC
      ALU_OP_SUB: alu_ctrl_o = ALU_SUB;    // Branches (compare via subtract)
      ALU_OP_LUI: alu_ctrl_o = ALU_LUI;    // LUI passthrough

      // Full decode — R-type and I-type ALU instructions
      ALU_OP_FUNC: begin
        unique case (funct3_i)

          // funct3 = 000: ADD or SUB
          // ADD:  R-type  → op[5]=1, funct7[5]=0  → {1,0}
          // SUB:  R-type  → op[5]=1, funct7[5]=1  → {1,1}
          // ADDI: I-type  → op[5]=0, funct7[5]=x  → {0,x} → always ADD
          //
          // SUB only when BOTH op[5]=1 AND funct7[5]=1
          3'b000: begin
            if (op_5_i & funct7_5_i)
              alu_ctrl_o = ALU_SUB;
            else
              alu_ctrl_o = ALU_ADD;
          end

          // funct3 = 001: SLL / SLLI
          3'b001: alu_ctrl_o = ALU_SLL;

          // funct3 = 010: SLT / SLTI
          3'b010: alu_ctrl_o = ALU_SLT;

          // funct3 = 011: SLTU / SLTIU
          3'b011: alu_ctrl_o = ALU_SLTU;

          // funct3 = 100: XOR / XORI
          3'b100: alu_ctrl_o = ALU_XOR;

          // funct3 = 101: SRL / SRLI or SRA / SRAI
          // Distinguished by funct7[5]: 0 = logical, 1 = arithmetic
          // This works for both R-type and I-type shifts because the
          // RISC-V spec places the shift type bit in the same position
          // (instr[30]) for both SRLI/SRAI and SRL/SRA.
          3'b101: begin
            if (funct7_5_i)
              alu_ctrl_o = ALU_SRA;
            else
              alu_ctrl_o = ALU_SRL;
          end

          // funct3 = 110: OR / ORI
          3'b110: alu_ctrl_o = ALU_OR;

          // funct3 = 111: AND / ANDI
          3'b111: alu_ctrl_o = ALU_AND;

          default: alu_ctrl_o = ALU_ADD;  // Safety fallback

        endcase
      end

      default: alu_ctrl_o = ALU_ADD;  // Safety fallback

    endcase
  end

endmodule : alu_decoder
