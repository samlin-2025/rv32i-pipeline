// ============================================================================
// File:    tb_hazard_unit.sv
// Desc:    Directed testbench for hazard_unit.
//          Tests every hazard scenario: MEM/WB forwarding, priority,
//          x0 suppression, load-use stall, branch flush, combined cases.
//
//          Each test sets up a realistic pipeline state (which instructions
//          are in which stage) and verifies the hazard unit's outputs.
// ============================================================================

module tb_hazard_unit;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  // ID stage
  logic [4:0]  rs1_id, rs2_id;

  // EX stage
  logic [4:0]  rs1_ex, rs2_ex, rd_ex;
  logic        reg_write_ex;
  result_src_e result_src_ex;

  // MEM stage
  logic [4:0]  rd_mem;
  logic        reg_write_mem;

  // WB stage
  logic [4:0]  rd_wb;
  logic        reg_write_wb;

  // Control
  logic        pc_src_ex;

  // Outputs
  forward_e    fwd_a, fwd_b;
  logic        stall_if, stall_id, flush_id, flush_ex;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  hazard_unit dut (
    .rs1_id_i         (rs1_id),
    .rs2_id_i         (rs2_id),
    .rs1_ex_i         (rs1_ex),
    .rs2_ex_i         (rs2_ex),
    .rd_ex_i          (rd_ex),
    .reg_write_ex_i   (reg_write_ex),
    .result_src_ex_i  (result_src_ex),
    .rd_mem_i         (rd_mem),
    .reg_write_mem_i  (reg_write_mem),
    .rd_wb_i          (rd_wb),
    .reg_write_wb_i   (reg_write_wb),
    .pc_src_ex_i      (pc_src_ex),
    .forward_a_ex_o   (fwd_a),
    .forward_b_ex_o   (fwd_b),
    .stall_if_o       (stall_if),
    .stall_id_o       (stall_id),
    .flush_id_o       (flush_id),
    .flush_ex_o       (flush_ex)
  );

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check_fwd(string name, forward_e got_a, forward_e exp_a,
                                        forward_e got_b, forward_e exp_b);
    int ok = 1;
    if (got_a !== exp_a) begin
      $display("  [FAIL] %s: fwd_a = %0d, expected %0d", name, got_a, exp_a);
      ok = 0;
    end
    if (got_b !== exp_b) begin
      $display("  [FAIL] %s: fwd_b = %0d, expected %0d", name, got_b, exp_b);
      ok = 0;
    end
    if (ok) begin
      $display("[PASS] %s", name);
      pass_count++;
    end else fail_count++;
  endtask

  task automatic check_ctrl(string name,
                            logic exp_stall_if, logic exp_stall_id,
                            logic exp_flush_id, logic exp_flush_ex);
    int ok = 1;
    if (stall_if !== exp_stall_if) begin
      $display("  [FAIL] %s: stall_if = %0b, expected %0b", name, stall_if, exp_stall_if);
      ok = 0;
    end
    if (stall_id !== exp_stall_id) begin
      $display("  [FAIL] %s: stall_id = %0b, expected %0b", name, stall_id, exp_stall_id);
      ok = 0;
    end
    if (flush_id !== exp_flush_id) begin
      $display("  [FAIL] %s: flush_id = %0b, expected %0b", name, flush_id, exp_flush_id);
      ok = 0;
    end
    if (flush_ex !== exp_flush_ex) begin
      $display("  [FAIL] %s: flush_ex = %0b, expected %0b", name, flush_ex, exp_flush_ex);
      ok = 0;
    end
    if (ok) begin
      $display("[PASS] %s", name);
      pass_count++;
    end else fail_count++;
  endtask

  // Helper: reset all inputs to "no hazard" state
  task automatic clear();
    rs1_id = 5'd0; rs2_id = 5'd0;
    rs1_ex = 5'd0; rs2_ex = 5'd0;
    rd_ex = 5'd0; reg_write_ex = 0; result_src_ex = RESULT_ALU;
    rd_mem = 5'd0; reg_write_mem = 0;
    rd_wb = 5'd0; reg_write_wb = 0;
    pc_src_ex = 0;
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_hazard_unit.vcd");
    $dumpvars(0, tb_hazard_unit);

    clear();

    // =============================================
    $display("\n--- No hazard baseline ---");
    // =============================================

    // Pipeline: ADD x7,x1,x2 (EX) | NOP (MEM) | NOP (WB)
    // No dependencies → no forwarding, no stall, no flush
    clear();
    rs1_ex = 5'd1; rs2_ex = 5'd2; rd_ex = 5'd7; reg_write_ex = 1;
    #1;
    check_fwd("No hazard", fwd_a, FWD_NONE, fwd_b, FWD_NONE);
    check_ctrl("No hazard ctrl", 0, 0, 0, 0);

    // =============================================
    $display("\n--- MEM forwarding (1-cycle RAW) ---");
    // =============================================

    // Pipeline: SUB x6,x5,x3 (EX) | ADD x5,x1,x2 (MEM) | NOP (WB)
    // EX reads x5 as rs1, MEM writes x5 → forward A from MEM
    clear();
    rs1_ex = 5'd5; rs2_ex = 5'd3;
    rd_mem = 5'd5; reg_write_mem = 1;
    #1;
    check_fwd("MEM fwd A (rs1=rd_mem=x5)", fwd_a, FWD_MEM, fwd_b, FWD_NONE);

    // Same but for rs2: OR x6,x3,x5 (EX) | ADD x5,... (MEM)
    clear();
    rs1_ex = 5'd3; rs2_ex = 5'd5;
    rd_mem = 5'd5; reg_write_mem = 1;
    #1;
    check_fwd("MEM fwd B (rs2=rd_mem=x5)", fwd_a, FWD_NONE, fwd_b, FWD_MEM);

    // Both operands from MEM: ADD x6,x5,x5 (EX) | ADD x5,... (MEM)
    clear();
    rs1_ex = 5'd5; rs2_ex = 5'd5;
    rd_mem = 5'd5; reg_write_mem = 1;
    #1;
    check_fwd("MEM fwd A+B (both x5)", fwd_a, FWD_MEM, fwd_b, FWD_MEM);

    // =============================================
    $display("\n--- WB forwarding (2-cycle RAW) ---");
    // =============================================

    // Pipeline: SUB x6,x5,x3 (EX) | NOP (MEM) | ADD x5,... (WB)
    clear();
    rs1_ex = 5'd5; rs2_ex = 5'd3;
    rd_wb = 5'd5; reg_write_wb = 1;
    #1;
    check_fwd("WB fwd A (rs1=rd_wb=x5)", fwd_a, FWD_WB, fwd_b, FWD_NONE);

    // WB forward on rs2
    clear();
    rs1_ex = 5'd3; rs2_ex = 5'd5;
    rd_wb = 5'd5; reg_write_wb = 1;
    #1;
    check_fwd("WB fwd B (rs2=rd_wb=x5)", fwd_a, FWD_NONE, fwd_b, FWD_WB);

    // =============================================
    $display("\n--- MEM > WB priority ---");
    // =============================================

    // Both MEM and WB write x5. MEM is newer → MEM wins.
    // Pipeline: SUB x6,x5,x3 (EX) | ADD x5,... (MEM) | OR x5,... (WB)
    clear();
    rs1_ex = 5'd5; rs2_ex = 5'd3;
    rd_mem = 5'd5; reg_write_mem = 1;
    rd_wb = 5'd5; reg_write_wb = 1;
    #1;
    check_fwd("Priority: MEM > WB for A", fwd_a, FWD_MEM, fwd_b, FWD_NONE);

    // Different operands from different stages:
    // rs1=x5 from MEM, rs2=x6 from WB
    clear();
    rs1_ex = 5'd5; rs2_ex = 5'd6;
    rd_mem = 5'd5; reg_write_mem = 1;
    rd_wb = 5'd6; reg_write_wb = 1;
    #1;
    check_fwd("A from MEM(x5), B from WB(x6)", fwd_a, FWD_MEM, fwd_b, FWD_WB);

    // =============================================
    $display("\n--- x0 suppression ---");
    // =============================================

    // MEM writes x0, EX reads x0 → must NOT forward (x0 is always 0)
    clear();
    rs1_ex = 5'd0; rs2_ex = 5'd0;
    rd_mem = 5'd0; reg_write_mem = 1;
    #1;
    check_fwd("x0 suppression (MEM)", fwd_a, FWD_NONE, fwd_b, FWD_NONE);

    // WB writes x0
    clear();
    rs1_ex = 5'd0;
    rd_wb = 5'd0; reg_write_wb = 1;
    #1;
    check_fwd("x0 suppression (WB)", fwd_a, FWD_NONE, fwd_b, FWD_NONE);

    // =============================================
    $display("\n--- reg_write = 0 suppression ---");
    // =============================================

    // MEM has rd=x5 but reg_write=0 (e.g., store) → no forward
    clear();
    rs1_ex = 5'd5;
    rd_mem = 5'd5; reg_write_mem = 0;
    #1;
    check_fwd("No fwd when reg_write=0", fwd_a, FWD_NONE, fwd_b, FWD_NONE);

    // =============================================
    $display("\n--- Load-use stall ---");
    // =============================================

    // Pipeline: ADD x6,x5,x3 (ID) | LW x5,0(x0) (EX)
    // EX is a load writing x5, ID reads x5 → stall
    clear();
    rs1_id = 5'd5; rs2_id = 5'd3;
    rd_ex = 5'd5; reg_write_ex = 1; result_src_ex = RESULT_MEM;
    #1;
    check_ctrl("Load-use stall (rs1)", 1, 1, 0, 1);

    // Load-use on rs2: SW x5,0(x3) (ID) | LW x5,... (EX)
    clear();
    rs1_id = 5'd3; rs2_id = 5'd5;
    rd_ex = 5'd5; reg_write_ex = 1; result_src_ex = RESULT_MEM;
    #1;
    check_ctrl("Load-use stall (rs2)", 1, 1, 0, 1);

    // Load to x0 → no stall (x0 writes are discarded)
    clear();
    rs1_id = 5'd0;
    rd_ex = 5'd0; reg_write_ex = 1; result_src_ex = RESULT_MEM;
    #1;
    check_ctrl("No stall for load to x0", 0, 0, 0, 0);

    // ALU instruction (not a load) writing x5 → no stall
    clear();
    rs1_id = 5'd5;
    rd_ex = 5'd5; reg_write_ex = 1; result_src_ex = RESULT_ALU;
    #1;
    check_ctrl("No stall for ALU (not load)", 0, 0, 0, 0);

    // =============================================
    $display("\n--- Branch/Jump flush ---");
    // =============================================

    // Branch taken: flush IF/ID and ID/EX
    clear();
    pc_src_ex = 1;
    #1;
    check_ctrl("Branch taken flush", 0, 0, 1, 1);

    // Branch not taken: no flush
    clear();
    pc_src_ex = 0;
    #1;
    check_ctrl("Branch not taken", 0, 0, 0, 0);

    // =============================================
    $display("\n--- Combined: branch flush with forwarding ---");
    // =============================================

    // Branch taken AND MEM forwarding active simultaneously.
    // Forwarding should still work (for the branch comparison in EX).
    // Flush signals should be set.
    clear();
    rs1_ex = 5'd5; rs2_ex = 5'd6;
    rd_mem = 5'd5; reg_write_mem = 1;
    pc_src_ex = 1;
    #1;
    check_fwd("Fwd during flush", fwd_a, FWD_MEM, fwd_b, FWD_NONE);
    check_ctrl("Flush during fwd", 0, 0, 1, 1);

    // ---- Summary ----
    $display("\n===================================");
    $display("  hazard_unit testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_hazard_unit
