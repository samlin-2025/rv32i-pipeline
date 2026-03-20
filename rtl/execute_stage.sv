// ============================================================================
// File:    execute_stage.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Execute (EX) stage + EX/MEM pipeline register.
//
//          Datapath:
//            1. Forwarding mux A → selects rs1 / MEM fwd / WB fwd
//            2. Forwarding mux B → selects rs2 / MEM fwd / WB fwd
//            3. ALU src A mux   → selects forwarded rs1 or PC (AUIPC)
//            4. ALU src B mux   → selects forwarded rs2 or immediate
//            5. ALU              → computes result
//            6. Branch adder    → PC + immediate (branch/JAL target)
//            7. Branch resolver → funct3 + ALU flags → taken?
//            8. PC target mux   → branch adder or ALU (JALR)
//
//          Outputs to pipeline:
//            pc_src_o     — redirect PC (branch taken or jump)
//            pc_target_o  — new PC value
//            EX/MEM register: control, ALU result, write data, rd, PC+4, funct3
//
// Inputs from ID/EX:
//   ctrl_ex_i, rs1_data, rs2_data, imm_ext, addresses, PC, PC+4, funct3
//
// Inputs from hazard unit:
//   forward_a_i, forward_b_i (forwarding mux selects)
//
// Inputs from downstream (forwarding data):
//   alu_result_mem_i — forwarded result from MEM stage
//   result_wb_i      — forwarded result from WB stage
// ============================================================================

module execute_stage
  import rv32i_pkg::*;
(
  input  logic        clk_i,
  input  logic        rst_ni,

  // From ID/EX pipeline register
  input  ctrl_ex_t    ctrl_ex_i,       // Control bundle
  input  logic [31:0] rs1_data_ex_i,   // rs1 from register file
  input  logic [31:0] rs2_data_ex_i,   // rs2 from register file
  input  logic [31:0] imm_ext_ex_i,    // Sign-extended immediate
  input  logic [4:0]  rd_addr_ex_i,    // Destination register
  input  logic [2:0]  funct3_ex_i,     // funct3 (branch type / mem width)
  input  logic [31:0] pc_ex_i,         // PC of this instruction
  input  logic [31:0] pc_plus4_ex_i,   // PC + 4 (link address)

  // Forwarding control from hazard unit
  input  forward_e    forward_a_i,     // Forwarding select for operand A
  input  forward_e    forward_b_i,     // Forwarding select for operand B

  // Forwarding data from downstream stages
  input  logic [31:0] alu_result_mem_i, // From MEM stage (1-cycle-old result)
  input  logic [31:0] result_wb_i,      // From WB stage (2-cycle-old result)

  // Branch/jump control outputs → fetch stage
  output logic        pc_src_o,        // Redirect PC (taken branch or jump)
  output logic [31:0] pc_target_o,     // Branch/jump target address

  // EX/MEM pipeline register outputs → memory stage
  output logic        reg_write_mem_o,  // Write to register file
  output result_src_e result_src_mem_o, // Writeback source
  output logic        mem_write_mem_o,  // Write to data memory
  output logic [31:0] alu_result_mem_o, // ALU computation result
  output logic [31:0] write_data_mem_o, // Store data (rs2, forwarded)
  output logic [4:0]  rd_addr_mem_o,    // Destination register
  output logic [31:0] pc_plus4_mem_o,   // PC+4 for JAL/JALR link
  output logic [2:0]  funct3_mem_o      // funct3 for memory access width
);

  // --------------------------------------------------------------------------
  // Forwarding mux A — ALU operand A source selection
  // --------------------------------------------------------------------------
  // Selects between:
  //   FWD_NONE (00) → register file value (rs1_data_ex_i)
  //   FWD_WB   (01) → result from WB stage (2 cycles old)
  //   FWD_MEM  (10) → result from MEM stage (1 cycle old)

  logic [31:0] fwd_a_out;

  mux3 #(.WIDTH(32)) u_fwd_mux_a (
    .sel_i (forward_a_i),
    .a_i   (rs1_data_ex_i),     // No forward
    .b_i   (result_wb_i),       // WB forward
    .c_i   (alu_result_mem_i),  // MEM forward
    .y_o   (fwd_a_out)
  );

  // --------------------------------------------------------------------------
  // Forwarding mux B — ALU operand B source selection (before alu_src mux)
  // --------------------------------------------------------------------------
  logic [31:0] fwd_b_out;

  mux3 #(.WIDTH(32)) u_fwd_mux_b (
    .sel_i (forward_b_i),
    .a_i   (rs2_data_ex_i),
    .b_i   (result_wb_i),
    .c_i   (alu_result_mem_i),
    .y_o   (fwd_b_out)
  );

  // --------------------------------------------------------------------------
  // ALU operand A mux — rs1 or PC (for AUIPC)
  // --------------------------------------------------------------------------
  // AUIPC needs ALU.A = PC. All other instructions use the forwarded rs1.

  logic [31:0] alu_a;

  mux2 #(.WIDTH(32)) u_alu_a_mux (
    .sel_i (ctrl_ex_i.alu_a_pc),
    .a_i   (fwd_a_out),       // Normal: forwarded rs1
    .b_i   (pc_ex_i),         // AUIPC: PC
    .y_o   (alu_a)
  );

  // --------------------------------------------------------------------------
  // ALU operand B mux — rs2 or immediate
  // --------------------------------------------------------------------------
  // R-type: ALU.B = forwarded rs2 (alu_src = 0)
  // I-type, loads, stores, LUI, AUIPC: ALU.B = immediate (alu_src = 1)

  logic [31:0] alu_b;

  mux2 #(.WIDTH(32)) u_alu_b_mux (
    .sel_i (ctrl_ex_i.alu_src),
    .a_i   (fwd_b_out),       // rs2 (forwarded)
    .b_i   (imm_ext_ex_i),    // Immediate
    .y_o   (alu_b)
  );

  // --------------------------------------------------------------------------
  // ALU — computation
  // --------------------------------------------------------------------------
  logic [31:0] alu_result;
  logic        alu_zero, alu_negative, alu_carry, alu_overflow;

  alu u_alu (
    .a_i         (alu_a),
    .b_i         (alu_b),
    .alu_ctrl_i  (ctrl_ex_i.alu_ctrl),
    .result_o    (alu_result),
    .zero_o      (alu_zero),
    .negative_o  (alu_negative),
    .carry_o     (alu_carry),
    .overflow_o  (alu_overflow)
  );

  // --------------------------------------------------------------------------
  // Branch target adder — PC + immediate
  // --------------------------------------------------------------------------
  // Computes the branch/JAL target: current PC + sign-extended offset.
  // This runs in parallel with the ALU — both compute simultaneously.

  logic [31:0] branch_target;

  pc_adder u_branch_adder (
    .a_i   (pc_ex_i),
    .b_i   (imm_ext_ex_i),
    .sum_o (branch_target)
  );

  // --------------------------------------------------------------------------
  // Branch resolution — is the branch taken?
  // --------------------------------------------------------------------------
  // Uses ALU flags (from the rs1 - rs2 subtraction) and funct3 to determine
  // if a conditional branch should be taken.
  //
  // The ALU always computes A - B (via ALU_SUB for branches). The flags tell us:
  //   zero      → A == B (for BEQ/BNE)
  //   negative ^ overflow → A < B signed (for BLT/BGE)
  //   ~carry    → A < B unsigned (for BLTU/BGEU)

  logic branch_taken;

  always_comb begin
    branch_taken = 1'b0;
    if (ctrl_ex_i.branch) begin
      unique case (funct3_ex_i)
        3'b000:  branch_taken = alu_zero;                          // BEQ
        3'b001:  branch_taken = ~alu_zero;                         // BNE
        3'b100:  branch_taken = (alu_negative ^ alu_overflow);     // BLT
        3'b101:  branch_taken = ~(alu_negative ^ alu_overflow);    // BGE
        3'b110:  branch_taken = ~alu_carry;                        // BLTU
        3'b111:  branch_taken = alu_carry;                         // BGEU
        default: branch_taken = 1'b0;
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // PC source — redirect fetch?
  // --------------------------------------------------------------------------
  // PC redirects on: taken branch OR unconditional jump (JAL/JALR)

  assign pc_src_o = branch_taken | ctrl_ex_i.jump;

  // --------------------------------------------------------------------------
  // PC target mux — branch/JAL target vs JALR target
  // --------------------------------------------------------------------------
  // Branches and JAL: target = PC + immediate (from branch adder)
  // JALR: target = (rs1 + immediate) & ~1 (from ALU result, bit 0 cleared)
  //
  // We detect JALR as: jump=1 AND NOT branch. Specifically, we use the ALU
  // result (which computed rs1 + imm for JALR since alu_op=ADD, alu_src=1)
  // and clear bit 0 per the RISC-V spec.
  //
  // For JAL: jump=1, the branch_target (PC + J-imm) is correct.
  // For branches: branch=1, the branch_target (PC + B-imm) is correct.
  // For JALR: jump=1, we need ALU result with bit 0 cleared.
  //
  // Simple implementation: if jump && !branch, use ALU result. Else branch_target.

  logic        jalr_sel;
  logic [31:0] jalr_target;

  // JALR is the only jump instruction that uses the ALU for target
  // computation (rs1 + imm). JAL uses the branch adder (PC + imm).
  // JALR: jump=1, alu_src=1 (ALU computes rs1 + imm)
  // JAL:  jump=1, alu_src=0 (ALU unused for target, branch adder used)
  assign jalr_sel    = ctrl_ex_i.jump & ctrl_ex_i.alu_src;
  assign jalr_target = {alu_result[31:1], 1'b0};  // Clear bit 0

  mux2 #(.WIDTH(32)) u_pc_target_mux (
    .sel_i (jalr_sel),
    .a_i   (branch_target),    // Branches and JAL: PC + immediate
    .b_i   (jalr_target),      // JALR: (rs1 + imm) & ~1
    .y_o   (pc_target_o)
  );

  // --------------------------------------------------------------------------
  // EX/MEM Pipeline Register
  // --------------------------------------------------------------------------
  // Captures: control signals needed by MEM and WB, ALU result,
  // store data (forwarded rs2), rd address, PC+4, and funct3.
  //
  // No stall input — the EX/MEM register always updates. Stalls only
  // affect IF and ID (upstream). Flushes only affect IF/ID and ID/EX.
  // The EX/MEM register doesn't need flush because any flushed instruction
  // has already been zeroed in ID/EX before it reaches here.

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      reg_write_mem_o  <= 1'b0;
      result_src_mem_o <= RESULT_ALU;
      mem_write_mem_o  <= 1'b0;
      alu_result_mem_o <= 32'h0;
      write_data_mem_o <= 32'h0;
      rd_addr_mem_o    <= 5'd0;
      pc_plus4_mem_o   <= 32'h0;
      funct3_mem_o     <= 3'd0;
    end else begin
      reg_write_mem_o  <= ctrl_ex_i.reg_write;
      result_src_mem_o <= ctrl_ex_i.result_src;
      mem_write_mem_o  <= ctrl_ex_i.mem_write;
      alu_result_mem_o <= alu_result;
      write_data_mem_o <= fwd_b_out;      // Forwarded rs2 for stores
      rd_addr_mem_o    <= rd_addr_ex_i;
      pc_plus4_mem_o   <= pc_plus4_ex_i;
      funct3_mem_o     <= funct3_ex_i;
    end
  end

endmodule : execute_stage
