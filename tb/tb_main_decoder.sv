// ============================================================================
// File:    tb_main_decoder.sv
// Desc:    Directed testbench for main_decoder.
//          Verifies every opcode row of the control truth table.
// ============================================================================

module tb_main_decoder;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic [6:0]    opcode;
  logic          reg_write, mem_write, alu_src, branch, jump;
  result_src_e   result_src;
  imm_src_e      imm_src;
  alu_op_hint_e  alu_op;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  main_decoder dut (
    .opcode_i     (opcode),
    .reg_write_o  (reg_write),
    .result_src_o (result_src),
    .mem_write_o  (mem_write),
    .alu_src_o    (alu_src),
    .imm_src_o    (imm_src),
    .alu_op_o     (alu_op),
    .branch_o     (branch),
    .jump_o       (jump)
  );

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  // Check all 8 control signals at once for a given opcode
  task automatic check_row(
    string         name,
    logic          exp_reg_write,
    result_src_e   exp_result_src,
    logic          exp_mem_write,
    logic          exp_alu_src,
    imm_src_e      exp_imm_src,
    alu_op_hint_e  exp_alu_op,
    logic          exp_branch,
    logic          exp_jump
  );
    int ok = 1;

    if (reg_write !== exp_reg_write) begin
      $display("  [FAIL] %s: reg_write = %0b, expected %0b", name, reg_write, exp_reg_write);
      ok = 0;
    end
    if (result_src !== exp_result_src) begin
      $display("  [FAIL] %s: result_src = %0d, expected %0d", name, result_src, exp_result_src);
      ok = 0;
    end
    if (mem_write !== exp_mem_write) begin
      $display("  [FAIL] %s: mem_write = %0b, expected %0b", name, mem_write, exp_mem_write);
      ok = 0;
    end
    if (alu_src !== exp_alu_src) begin
      $display("  [FAIL] %s: alu_src = %0b, expected %0b", name, alu_src, exp_alu_src);
      ok = 0;
    end
    if (imm_src !== exp_imm_src) begin
      $display("  [FAIL] %s: imm_src = %0d, expected %0d", name, imm_src, exp_imm_src);
      ok = 0;
    end
    if (alu_op !== exp_alu_op) begin
      $display("  [FAIL] %s: alu_op = %0d, expected %0d", name, alu_op, exp_alu_op);
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
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_main_decoder.vcd");
    $dumpvars(0, tb_main_decoder);

    // ---- R-type: register-register ALU ----
    //              rw  rsrc        mw  asrc  imm    aluop       br  jmp
    opcode = OP_R_TYPE; #1;
    check_row("R-TYPE",
              1,  RESULT_ALU, 0,  0,    IMM_I, ALU_OP_FUNC, 0,  0);

    // ---- I-type ALU: register-immediate ----
    opcode = OP_I_TYPE; #1;
    check_row("I-TYPE ALU",
              1,  RESULT_ALU, 0,  1,    IMM_I, ALU_OP_FUNC, 0,  0);

    // ---- Load ----
    opcode = OP_LOAD; #1;
    check_row("LOAD",
              1,  RESULT_MEM, 0,  1,    IMM_I, ALU_OP_ADD,  0,  0);

    // ---- Store ----
    opcode = OP_STORE; #1;
    check_row("STORE",
              0,  RESULT_ALU, 1,  1,    IMM_S, ALU_OP_ADD,  0,  0);

    // ---- Branch ----
    opcode = OP_BRANCH; #1;
    check_row("BRANCH",
              0,  RESULT_ALU, 0,  0,    IMM_B, ALU_OP_SUB,  1,  0);

    // ---- JAL ----
    opcode = OP_JAL; #1;
    check_row("JAL",
              1,  RESULT_PC4, 0,  0,    IMM_J, ALU_OP_ADD,  0,  1);

    // ---- JALR ----
    opcode = OP_JALR; #1;
    check_row("JALR",
              1,  RESULT_PC4, 0,  1,    IMM_I, ALU_OP_ADD,  0,  1);

    // ---- LUI ----
    opcode = OP_LUI; #1;
    check_row("LUI",
              1,  RESULT_ALU, 0,  1,    IMM_U, ALU_OP_LUI,  0,  0);

    // ---- AUIPC ----
    opcode = OP_AUIPC; #1;
    check_row("AUIPC",
              1,  RESULT_ALU, 0,  1,    IMM_U, ALU_OP_ADD,  0,  0);

    // ---- Unknown opcode: should default to safe NOP ----
    opcode = 7'b1111111; #1;
    check_row("UNKNOWN (safe NOP)",
              0,  RESULT_ALU, 0,  0,    IMM_I, ALU_OP_ADD,  0,  0);

    // ---- Summary ----
    $display("\n===================================");
    $display("  main_decoder testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_main_decoder
