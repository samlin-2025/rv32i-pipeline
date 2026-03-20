// ============================================================================
// File:    tb_control_unit.sv
// Desc:    Integration testbench for control_unit.
//          Feeds real instruction field extractions (from ISS test program)
//          and verifies the complete decode chain: opcode → main decoder →
//          alu_op hint → ALU decoder → resolved alu_ctrl.
//
//          This catches handoff bugs between the two decoders that unit
//          tests on each half individually would miss.
// ============================================================================

module tb_control_unit;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic [6:0]  opcode;
  logic [2:0]  funct3;
  logic        funct7_5, op_5;

  logic        reg_write, mem_write, alu_src, branch, jump;
  result_src_e result_src;
  imm_src_e    imm_src;
  alu_op_e     alu_ctrl;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  control_unit dut (
    .opcode_i     (opcode),
    .funct3_i     (funct3),
    .funct7_5_i   (funct7_5),
    .op_5_i       (op_5),
    .reg_write_o  (reg_write),
    .result_src_o (result_src),
    .mem_write_o  (mem_write),
    .alu_src_o    (alu_src),
    .imm_src_o    (imm_src),
    .alu_ctrl_o   (alu_ctrl),
    .branch_o     (branch),
    .jump_o       (jump)
  );

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  // Helper: extract instruction fields and apply to DUT inputs
  task automatic apply_instr(logic [31:0] instr);
    opcode  = instr[6:0];
    funct3  = instr[14:12];
    funct7_5 = instr[30];
    op_5    = instr[5];
  endtask

  // Check key outputs for a given instruction
  task automatic check(
    string     name,
    alu_op_e   exp_alu_ctrl,
    logic      exp_reg_write,
    logic      exp_mem_write,
    logic      exp_branch,
    logic      exp_jump
  );
    int ok = 1;

    if (alu_ctrl !== exp_alu_ctrl) begin
      $display("  [FAIL] %s: alu_ctrl = 0x%01h, expected 0x%01h", name, alu_ctrl, exp_alu_ctrl);
      ok = 0;
    end
    if (reg_write !== exp_reg_write) begin
      $display("  [FAIL] %s: reg_write = %0b, expected %0b", name, reg_write, exp_reg_write);
      ok = 0;
    end
    if (mem_write !== exp_mem_write) begin
      $display("  [FAIL] %s: mem_write = %0b, expected %0b", name, mem_write, exp_mem_write);
      ok = 0;
    end
    if (branch !== exp_branch) begin
      $display("  [FAIL] %s: branch = %0b, expected %0b", name, branch, exp_branch);
      ok = 0;
    end
    if (jump !== exp_jump) begin
      $display("  [FAIL] %s: jump = %0b, expected %0b", name, jump, exp_jump);
      ok = 0;
    end

    if (ok) begin
      $display("[PASS] %s", name);
      pass_count++;
    end else begin
      fail_count++;
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence — using real instructions from ISS test program
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_control_unit.vcd");
    $dumpvars(0, tb_control_unit);

    // =============================================
    $display("\n--- R-type instructions ---");
    // =============================================

    // ADD x7, x5, x6 → 0x006283B3
    //          alu_ctrl     rw  mw  br  jmp
    apply_instr(32'h006283B3); #1;
    check("ADD",  ALU_ADD,   1,  0,  0,  0);

    // SUB x8, x5, x6 → 0x40628433
    apply_instr(32'h40628433); #1;
    check("SUB",  ALU_SUB,   1,  0,  0,  0);

    // AND x9, x5, x6 → 0x0062F4B3
    apply_instr(32'h0062F4B3); #1;
    check("AND",  ALU_AND,   1,  0,  0,  0);

    // OR x10, x5, x6 → 0x0062E533
    apply_instr(32'h0062E533); #1;
    check("OR",   ALU_OR,    1,  0,  0,  0);

    // XOR x11, x5, x6 → 0x0062C5B3
    apply_instr(32'h0062C5B3); #1;
    check("XOR",  ALU_XOR,   1,  0,  0,  0);

    // SLT x12, x5, x6 → 0x0062A633
    apply_instr(32'h0062A633); #1;
    check("SLT",  ALU_SLT,   1,  0,  0,  0);

    // =============================================
    $display("\n--- I-type ALU instructions ---");
    // =============================================

    // ADDI x5, x0, 5 → 0x00500293
    apply_instr(32'h00500293); #1;
    check("ADDI", ALU_ADD,   1,  0,  0,  0);

    // SLLI x14, x5, 2 → 0x00229713
    apply_instr(32'h00229713); #1;
    check("SLLI", ALU_SLL,   1,  0,  0,  0);

    // SRLI x15, x6, 1 → 0x00135793
    apply_instr(32'h00135793); #1;
    check("SRLI", ALU_SRL,   1,  0,  0,  0);

    // =============================================
    $display("\n--- Load and Store ---");
    // =============================================

    // LW x18, 0(x0) → 0x00002903
    apply_instr(32'h00002903); #1;
    check("LW",   ALU_ADD,   1,  0,  0,  0);

    // SW x7, 0(x0) → 0x00702023
    apply_instr(32'h00702023); #1;
    check("SW",   ALU_ADD,   0,  1,  0,  0);

    // =============================================
    $display("\n--- Branch ---");
    // =============================================

    // BNE x20, x21, -8 → 0xFF5A1CE3
    apply_instr(32'hFF5A1CE3); #1;
    check("BNE",  ALU_SUB,   0,  0,  1,  0);

    // =============================================
    $display("\n--- JAL / JALR ---");
    // =============================================

    // JAL x1, +8 → 0x008000EF
    apply_instr(32'h008000EF); #1;
    check("JAL",  ALU_ADD,   1,  0,  0,  1);

    // JALR x0, x1, 0 → 0x000080E7  (hypothetical: return from function)
    apply_instr(32'h000080E7); #1;
    check("JALR", ALU_ADD,   1,  0,  0,  1);

    // =============================================
    $display("\n--- LUI / AUIPC ---");
    // =============================================

    // LUI x16, 0x12345 → 0x12345837
    apply_instr(32'h12345837); #1;
    check("LUI",   ALU_LUI,  1,  0,  0,  0);

    // AUIPC x5, 0x12345 → 0x12345297
    apply_instr(32'h12345297); #1;
    check("AUIPC", ALU_ADD,  1,  0,  0,  0);

    // ---- Summary ----
    $display("\n===================================");
    $display("  control_unit testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_control_unit
