// ============================================================================
// File:    tb_pc_adder.sv
// Desc:    Directed testbench for pc_adder.
//          Tests: basic addition, PC+4, branch offsets (positive/negative),
//          32-bit overflow wrapping, zero operands.
// ============================================================================

module tb_pc_adder;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic [31:0] a, b, sum;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  pc_adder dut (
    .a_i   (a),
    .b_i   (b),
    .sum_o (sum)
  );

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check(string name, logic [31:0] expected);
    #1;  // Let combinational logic settle
    if (sum === expected) begin
      $display("[PASS] %s: 0x%08h + 0x%08h = 0x%08h", name, a, b, sum);
      pass_count++;
    end else begin
      $display("[FAIL] %s: 0x%08h + 0x%08h = 0x%08h, expected 0x%08h",
               name, a, b, sum, expected);
      fail_count++;
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_pc_adder.vcd");
    $dumpvars(0, tb_pc_adder);

    // ---- Test 1: PC + 4 (the most common operation) ----
    a = 32'h0000_0000; b = 32'h0000_0004;
    check("PC=0x0 + 4", 32'h0000_0004);

    // ---- Test 2: Sequential advance ----
    a = 32'h0000_0004; b = 32'h0000_0004;
    check("PC=0x4 + 4", 32'h0000_0008);

    // ---- Test 3: Larger PC value ----
    a = 32'h0000_0100; b = 32'h0000_0004;
    check("PC=0x100 + 4", 32'h0000_0104);

    // ---- Test 4: Positive branch offset (forward branch) ----
    // PC = 0x40, branch target = PC + 0x10 = 0x50
    a = 32'h0000_0040; b = 32'h0000_0010;
    check("Forward branch +16", 32'h0000_0050);

    // ---- Test 5: Negative branch offset (backward branch — loops) ----
    // PC = 0x4C, branch offset = -8 (0xFFFFFFF8 in two's complement)
    // Target = 0x4C + (-8) = 0x44
    a = 32'h0000_004C; b = 32'hFFFF_FFF8;
    check("Backward branch -8", 32'h0000_0044);

    // ---- Test 6: Zero + zero ----
    a = 32'h0000_0000; b = 32'h0000_0000;
    check("Zero + zero", 32'h0000_0000);

    // ---- Test 7: 32-bit overflow wrapping ----
    // 0xFFFFFFFC + 4 = 0x100000000, but 32-bit wraps to 0x00000000
    // This actually happens if PC reaches the top of address space.
    a = 32'hFFFF_FFFC; b = 32'h0000_0004;
    check("Overflow wrap", 32'h0000_0000);

    // ---- Test 8: Large offset (JAL range: ±1 MiB) ----
    a = 32'h0000_1000; b = 32'h000F_F000;
    check("Large JAL offset", 32'h0010_0000);

    // ---- Summary ----
    $display("\n===================================");
    $display("  pc_adder testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_pc_adder
