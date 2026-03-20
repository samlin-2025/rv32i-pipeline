// ============================================================================
// File:    control_unit.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Top-level control unit — structural wrapper combining the main
//          decoder and ALU decoder into a single module.
//
//          The decode stage instantiates this one module and gets all
//          resolved control signals. Internally, the main decoder produces
//          a coarse alu_op hint, which the ALU decoder refines using
//          funct3 and funct7 into the final alu_ctrl.
//
// Inputs (from instruction word):
//   opcode_i   — instr[6:0]
//   funct3_i   — instr[14:12]
//   funct7_5_i — instr[30]     (bit 5 of funct7)
//   op_5_i     — instr[5]      (bit 5 of opcode, for ADD/SUB disambiguation)
//
// Outputs (control signals for the pipeline):
//   reg_write_o  — Write to register file in WB
//   result_src_o — Writeback source: ALU / memory / PC+4
//   mem_write_o  — Write to data memory in MEM
//   alu_src_o    — ALU operand B: rs2 (0) or immediate (1)
//   imm_src_o    — Immediate format selector
//   alu_ctrl_o   — Resolved ALU operation (final, not the hint)
//   branch_o     — Instruction is a conditional branch
//   jump_o       — Instruction is JAL or JALR
// ============================================================================

module control_unit
  import rv32i_pkg::*;
(
  // Instruction field inputs
  input  logic [6:0]  opcode_i,
  input  logic [2:0]  funct3_i,
  input  logic        funct7_5_i,
  input  logic        op_5_i,

  // Resolved control signal outputs
  output logic        reg_write_o,
  output result_src_e result_src_o,
  output logic        mem_write_o,
  output logic        alu_src_o,
  output imm_src_e    imm_src_o,
  output alu_op_e     alu_ctrl_o,    // Final resolved ALU operation
  output logic        branch_o,
  output logic        jump_o,
  output logic        alu_a_pc_o     // ALU operand A = PC (AUIPC)
);

  // --------------------------------------------------------------------------
  // Internal wire: ALU operation hint (main decoder → ALU decoder)
  // --------------------------------------------------------------------------
  alu_op_hint_e alu_op_hint;

  // --------------------------------------------------------------------------
  // Main decoder — opcode → all control signals + alu_op hint
  // --------------------------------------------------------------------------
  main_decoder u_main_decoder (
    .opcode_i     (opcode_i),
    .reg_write_o  (reg_write_o),
    .result_src_o (result_src_o),
    .mem_write_o  (mem_write_o),
    .alu_src_o    (alu_src_o),
    .imm_src_o    (imm_src_o),
    .alu_op_o     (alu_op_hint),    // Internal: flows to ALU decoder
    .branch_o     (branch_o),
    .jump_o       (jump_o),
    .alu_a_pc_o   (alu_a_pc_o)
  );

  // --------------------------------------------------------------------------
  // ALU decoder — alu_op hint + funct3 + funct7 → resolved alu_ctrl
  // --------------------------------------------------------------------------
  alu_decoder u_alu_decoder (
    .alu_op_i    (alu_op_hint),
    .funct3_i    (funct3_i),
    .funct7_5_i  (funct7_5_i),
    .op_5_i      (op_5_i),
    .alu_ctrl_o  (alu_ctrl_o)       // Final output to pipeline
  );

endmodule : control_unit
