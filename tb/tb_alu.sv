// ============================================================================
// File:    tb_alu.sv
// Desc:    Directed testbench for alu.
//          Tests all 11 ALU operations including SLT/SLTU overflow edge cases,
//          shift boundaries, flag correctness, and ISS-matching values.
// ============================================================================

module tb_alu;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic [31:0] a, b, result;
  alu_op_e     ctrl;
  logic        zero, negative, carry, overflow;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  alu dut (
    .a_i         (a),
    .b_i         (b),
    .alu_ctrl_i  (ctrl),
    .result_o    (result),
    .zero_o      (zero),
    .negative_o  (negative),
    .carry_o     (carry),
    .overflow_o  (overflow)
  );

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check(string name, logic [31:0] got, logic [31:0] expected);
    if (got === expected) begin
      $display("[PASS] %s: result = 0x%08h", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: result = 0x%08h, expected 0x%08h", name, got, expected);
      fail_count++;
    end
  endtask

  task automatic check_flag(string name, logic got, logic expected);
    if (got === expected) begin
      $display("[PASS] %s: flag = %0b", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: flag = %0b, expected %0b", name, got, expected);
      fail_count++;
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_alu.vcd");
    $dumpvars(0, tb_alu);

    // =============================================
    $display("\n--- ADD ---");
    // =============================================

    // ISS cross-check: ADD x7, x5, x6 → 5 + 3 = 8
    a = 32'd5; b = 32'd3; ctrl = ALU_ADD;
    #1; check("5 + 3", result, 32'd8);

    // Zero + zero
    a = 32'd0; b = 32'd0; ctrl = ALU_ADD;
    #1; check("0 + 0", result, 32'd0);
    check_flag("0+0 zero flag", zero, 1'b1);

    // Overflow: max_pos + 1 → wraps to min_neg
    a = 32'h7FFF_FFFF; b = 32'd1; ctrl = ALU_ADD;
    #1; check("max_pos + 1 (overflow)", result, 32'h8000_0000);
    check_flag("overflow flag set", overflow, 1'b1);

    // =============================================
    $display("\n--- SUB ---");
    // =============================================

    a = 32'd5; b = 32'd3; ctrl = ALU_SUB;
    #1; check("5 - 3", result, 32'd2);

    a = 32'd42; b = 32'd42; ctrl = ALU_SUB;
    #1; check("42 - 42", result, 32'd0);
    check_flag("42-42 zero flag", zero, 1'b1);

    a = 32'd3; b = 32'd5; ctrl = ALU_SUB;
    #1; check("3 - 5", result, 32'hFFFF_FFFE);
    check_flag("3-5 negative", negative, 1'b1);

    // =============================================
    $display("\n--- AND ---");
    // =============================================

    a = 32'd5; b = 32'd3; ctrl = ALU_AND;
    #1; check("5 & 3", result, 32'd1);

    a = 32'hFF00_FF00; b = 32'h0F0F_0F0F; ctrl = ALU_AND;
    #1; check("mask AND", result, 32'h0F00_0F00);

    // =============================================
    $display("\n--- OR ---");
    // =============================================

    a = 32'd5; b = 32'd3; ctrl = ALU_OR;
    #1; check("5 | 3", result, 32'd7);

    a = 32'hFF00_0000; b = 32'h00FF_0000; ctrl = ALU_OR;
    #1; check("mask OR", result, 32'hFFFF_0000);

    // =============================================
    $display("\n--- XOR ---");
    // =============================================

    a = 32'd5; b = 32'd3; ctrl = ALU_XOR;
    #1; check("5 ^ 3", result, 32'd6);

    a = 32'hDEAD_BEEF; b = 32'hDEAD_BEEF; ctrl = ALU_XOR;
    #1; check("self XOR (clear)", result, 32'd0);
    check_flag("self XOR zero", zero, 1'b1);

    // =============================================
    $display("\n--- SLT (signed) ---");
    // =============================================

    a = 32'd5; b = 32'd3; ctrl = ALU_SLT;
    #1; check("5 < 3 signed (false)", result, 32'd0);

    a = 32'd3; b = 32'd5; ctrl = ALU_SLT;
    #1; check("3 < 5 signed (true)", result, 32'd1);

    a = 32'd7; b = 32'd7; ctrl = ALU_SLT;
    #1; check("7 < 7 signed (false)", result, 32'd0);

    a = 32'hFFFF_FFFF; b = 32'd1; ctrl = ALU_SLT;
    #1; check("-1 < 1 signed (true)", result, 32'd1);

    // CRITICAL: overflow edge case
    a = 32'h7FFF_FFFF; b = 32'h8000_0000; ctrl = ALU_SLT;
    #1; check("max_pos < min_neg (false, overflow!)", result, 32'd0);

    a = 32'h8000_0000; b = 32'h7FFF_FFFF; ctrl = ALU_SLT;
    #1; check("min_neg < max_pos (true, overflow!)", result, 32'd1);

    // =============================================
    $display("\n--- SLTU (unsigned) ---");
    // =============================================

    a = 32'd3; b = 32'd5; ctrl = ALU_SLTU;
    #1; check("3 < 5 unsigned (true)", result, 32'd1);

    a = 32'd5; b = 32'd3; ctrl = ALU_SLTU;
    #1; check("5 < 3 unsigned (false)", result, 32'd0);

    a = 32'hFFFF_FFFF; b = 32'd1; ctrl = ALU_SLTU;
    #1; check("0xFFFFFFFF < 1 unsigned (false)", result, 32'd0);

    a = 32'd0; b = 32'd1; ctrl = ALU_SLTU;
    #1; check("0 < 1 unsigned (true)", result, 32'd1);

    a = 32'd0; b = 32'd0; ctrl = ALU_SLTU;
    #1; check("0 < 0 unsigned (false)", result, 32'd0);

    // =============================================
    $display("\n--- SLL (shift left logical) ---");
    // =============================================

    a = 32'd5; b = 32'd2; ctrl = ALU_SLL;
    #1; check("5 << 2", result, 32'd20);

    a = 32'hDEAD_BEEF; b = 32'd0; ctrl = ALU_SLL;
    #1; check("shift left 0", result, 32'hDEAD_BEEF);

    a = 32'd1; b = 32'd31; ctrl = ALU_SLL;
    #1; check("1 << 31", result, 32'h8000_0000);

    // =============================================
    $display("\n--- SRL (shift right logical) ---");
    // =============================================

    a = 32'd3; b = 32'd1; ctrl = ALU_SRL;
    #1; check("3 >> 1", result, 32'd1);

    a = 32'hF000_0000; b = 32'd4; ctrl = ALU_SRL;
    #1; check("0xF0000000 >> 4 logical", result, 32'h0F00_0000);

    // =============================================
    $display("\n--- SRA (shift right arithmetic) ---");
    // =============================================

    a = 32'hF000_0000; b = 32'd4; ctrl = ALU_SRA;
    #1; check("0xF0000000 >>> 4 arithmetic", result, 32'hFF00_0000);

    a = 32'h7000_0000; b = 32'd4; ctrl = ALU_SRA;
    #1; check("0x70000000 >>> 4 (positive)", result, 32'h0700_0000);

    a = 32'h8000_0000; b = 32'd31; ctrl = ALU_SRA;
    #1; check("0x80000000 >>> 31", result, 32'hFFFF_FFFF);

    // =============================================
    $display("\n--- LUI passthrough ---");
    // =============================================

    a = 32'd0; b = 32'h1234_5000; ctrl = ALU_LUI;
    #1; check("LUI passthrough", result, 32'h1234_5000);

    // ---- Summary ----
    $display("\n===================================");
    $display("  alu testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_alu
