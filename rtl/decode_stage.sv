// ============================================================================
// File:    decode_stage.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Instruction Decode (ID) stage + ID/EX pipeline register.
//
//          Combinational logic in this stage:
//            - Control unit: opcode/funct3/funct7 → all control signals
//            - Register file: read rs1 and rs2 (+ write port from WB)
//            - Sign extender: extract and extend immediate
//            - Field extraction: rs1_addr, rs2_addr, rd_addr
//
//          The ID/EX pipeline register captures:
//            - Control bundle (ctrl_ex_t struct)
//            - rs1 data, rs2 data, sign-extended immediate
//            - rs1 addr, rs2 addr, rd addr (for hazard detection)
//            - PC and PC+4 (for branch target and JAL link)
//
//          Hazard control:
//            flush_i — Zero control signals (branch taken / load-use bubble)
//            stall_i — Hold ID/EX register contents (load-use hazard)
//
// Inputs from IF/ID:
//   instr_id_i, pc_id_i, pc_plus4_id_i
//
// Inputs from WB (register file write-back):
//   reg_write_wb_i, rd_wb_i, result_wb_i
//
// Outputs to EX (ID/EX pipeline register):
//   ctrl_ex_o — packed control struct
//   rs1_data_ex_o, rs2_data_ex_o, imm_ext_ex_o
//   rs1_addr_ex_o, rs2_addr_ex_o, rd_addr_ex_o
//   pc_ex_o, pc_plus4_ex_o
//
// Outputs to hazard unit (combinational, from current ID instruction):
//   rs1_addr_id_o, rs2_addr_id_o
// ============================================================================

module decode_stage
  import rv32i_pkg::*;
(
  input  logic        clk_i,
  input  logic        rst_ni,

  // Hazard control
  input  logic        flush_i,        // Zero ID/EX controls (flush)
  input  logic        stall_i,        // Hold ID/EX register (stall)

  // From IF/ID pipeline register
  input  logic [31:0] instr_id_i,     // Instruction
  input  logic [31:0] pc_id_i,        // PC
  input  logic [31:0] pc_plus4_id_i,  // PC + 4

  // Write-back from WB stage (into register file)
  input  logic        reg_write_wb_i, // Write enable
  input  logic [4:0]  rd_wb_i,        // Destination register
  input  logic [31:0] result_wb_i,    // Data to write

  // ID/EX pipeline register outputs → execute stage
  output ctrl_ex_t    ctrl_ex_o,      // Packed control bundle
  output logic [31:0] rs1_data_ex_o,  // rs1 value (or forwarded)
  output logic [31:0] rs2_data_ex_o,  // rs2 value (or forwarded)
  output logic [31:0] imm_ext_ex_o,   // Sign-extended immediate
  output logic [4:0]  rs1_addr_ex_o,  // rs1 address (for forwarding)
  output logic [4:0]  rs2_addr_ex_o,  // rs2 address (for forwarding)
  output logic [4:0]  rd_addr_ex_o,   // rd address (for hazard detection)
  output logic [2:0]  funct3_ex_o,    // funct3 (for branch type / mem width)
  output logic [31:0] pc_ex_o,        // PC (for branch target / AUIPC)
  output logic [31:0] pc_plus4_ex_o,  // PC+4 (for JAL/JALR link)

  // Hazard unit outputs (combinational — current ID instruction)
  output logic [4:0]  rs1_addr_id_o,  // rs1 addr for load-use detection
  output logic [4:0]  rs2_addr_id_o   // rs2 addr for load-use detection
);

  // --------------------------------------------------------------------------
  // Instruction field extraction
  // --------------------------------------------------------------------------
  // RISC-V fixed-format fields — always in the same bit positions.

  logic [6:0] opcode;
  logic [4:0] rd_d, rs1_d, rs2_d;
  logic [2:0] funct3;
  logic       funct7_5, op_5;

  assign opcode  = instr_id_i[6:0];
  assign rd_d    = instr_id_i[11:7];
  assign funct3  = instr_id_i[14:12];
  assign rs1_d   = instr_id_i[19:15];
  assign rs2_d   = instr_id_i[24:20];
  assign funct7_5 = instr_id_i[30];
  assign op_5    = instr_id_i[5];

  // Pass rs1/rs2 addresses to hazard unit for load-use detection.
  // These are combinational (not registered) — the hazard unit needs
  // them in the same cycle the instruction is in ID.
  assign rs1_addr_id_o = rs1_d;
  assign rs2_addr_id_o = rs2_d;

  // --------------------------------------------------------------------------
  // Control unit — produces all control signals from instruction fields
  // --------------------------------------------------------------------------
  logic        reg_write_d;
  result_src_e result_src_d;
  logic        mem_write_d;
  logic        alu_src_d;
  imm_src_e    imm_src_d;
  alu_op_e     alu_ctrl_d;
  logic        branch_d;
  logic        jump_d;
  logic        alu_a_pc_d;

  control_unit u_control_unit (
    .opcode_i     (opcode),
    .funct3_i     (funct3),
    .funct7_5_i   (funct7_5),
    .op_5_i       (op_5),
    .reg_write_o  (reg_write_d),
    .result_src_o (result_src_d),
    .mem_write_o  (mem_write_d),
    .alu_src_o    (alu_src_d),
    .imm_src_o    (imm_src_d),
    .alu_ctrl_o   (alu_ctrl_d),
    .branch_o     (branch_d),
    .jump_o       (jump_d),
    .alu_a_pc_o   (alu_a_pc_d)
  );

  // --------------------------------------------------------------------------
  // Register file — dual read, single write
  // --------------------------------------------------------------------------
  // Read ports: rs1 and rs2 from current ID instruction.
  // Write port: driven by WB stage (result_wb_i → rd_wb_i).
  // Write-through forwarding is handled inside the register file.

  logic [31:0] rs1_data_d, rs2_data_d;

  register_file u_register_file (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .we_i       (reg_write_wb_i),
    .wr_addr_i  (rd_wb_i),
    .wr_data_i  (result_wb_i),
    .rs1_addr_i (rs1_d),
    .rs1_data_o (rs1_data_d),
    .rs2_addr_i (rs2_d),
    .rs2_data_o (rs2_data_d)
  );

  // --------------------------------------------------------------------------
  // Sign extender — immediate extraction
  // --------------------------------------------------------------------------
  logic [31:0] imm_ext_d;

  sign_extend u_sign_extend (
    .instr_i    (instr_id_i),
    .imm_src_i  (imm_src_d),
    .imm_ext_o  (imm_ext_d)
  );

  // --------------------------------------------------------------------------
  // Control bundle assembly
  // --------------------------------------------------------------------------
  // Pack all control signals into the struct for clean pipeline register
  // handling. This is what the ID/EX register stores and passes to EX.

  ctrl_ex_t ctrl_d;

  assign ctrl_d.reg_write  = reg_write_d;
  assign ctrl_d.result_src = result_src_d;
  assign ctrl_d.mem_write  = mem_write_d;
  assign ctrl_d.branch     = branch_d;
  assign ctrl_d.jump       = jump_d;
  assign ctrl_d.alu_ctrl   = alu_ctrl_d;
  assign ctrl_d.alu_src    = alu_src_d;
  assign ctrl_d.alu_a_pc   = alu_a_pc_d;

  // --------------------------------------------------------------------------
  // ID/EX Pipeline Register
  // --------------------------------------------------------------------------
  // Priority: reset > flush > stall > normal
  //
  // Flush: Zero the control struct only. Data fields (rs1_data, rs2_data,
  //   imm, addresses, PC) don't need zeroing because without control
  //   signals enabling their use, they're harmless. This saves power.
  //
  // Stall: Hold all values. The decode stage reprocesses the same
  //   instruction for another cycle.
  //
  // Normal: Capture all decoded values from ID.

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      ctrl_ex_o     <= '0;
      rs1_data_ex_o <= 32'h0;
      rs2_data_ex_o <= 32'h0;
      imm_ext_ex_o  <= 32'h0;
      rs1_addr_ex_o <= 5'd0;
      rs2_addr_ex_o <= 5'd0;
      rd_addr_ex_o  <= 5'd0;
      funct3_ex_o   <= 3'd0;
      pc_ex_o       <= 32'h0;
      pc_plus4_ex_o <= 32'h0;
    end else if (flush_i) begin
      // Flush: zero control signals only (NOP injection).
      // Data fields are don't-care when controls are zero.
      ctrl_ex_o     <= '0;
      // Also zero rd to prevent false hazard detection on flushed bubble
      rd_addr_ex_o  <= 5'd0;
      rs1_addr_ex_o <= 5'd0;
      rs2_addr_ex_o <= 5'd0;
    end else if (!stall_i) begin
      // Normal: capture decoded values
      ctrl_ex_o     <= ctrl_d;
      rs1_data_ex_o <= rs1_data_d;
      rs2_data_ex_o <= rs2_data_d;
      imm_ext_ex_o  <= imm_ext_d;
      rs1_addr_ex_o <= rs1_d;
      rs2_addr_ex_o <= rs2_d;
      rd_addr_ex_o  <= rd_d;
      funct3_ex_o   <= funct3;
      pc_ex_o       <= pc_id_i;
      pc_plus4_ex_o <= pc_plus4_id_i;
    end
    // else: stall — hold current values (implicit)
  end

endmodule : decode_stage
