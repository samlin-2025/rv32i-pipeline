// ============================================================================
// File:    tb_pc_reg.sv
// Desc:    Directed testbench for pc_reg — verifies reset, update, and stall.
// ============================================================================

module tb_pc_reg;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic        clk;
  logic        rst_n;
  logic        en;
  logic [31:0] pc_next;
  logic [31:0] pc;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  pc_reg dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .en_i      (en),
    .pc_next_i (pc_next),
    .pc_o      (pc)
  );

  // --------------------------------------------------------------------------
  // Clock generation: 10ns period (100 MHz)
  // --------------------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check(string name, logic [31:0] expected);
    if (pc === expected) begin
      $display("[PASS] %s: pc = 0x%08h", name, pc);
      pass_count++;
    end else begin
      $display("[FAIL] %s: pc = 0x%08h, expected 0x%08h", name, pc, expected);
      fail_count++;
    end
  endtask

  initial begin
    $dumpfile("tb_pc_reg.vcd");
    $dumpvars(0, tb_pc_reg);

    // Initialize
    rst_n   = 0;
    en      = 1;
    pc_next = 32'h0000_0000;

    // ---- Test 1: Reset ----
    // Hold reset for 2 cycles, PC should be 0
    @(posedge clk); #1;
    check("Reset cycle 1", 32'h0000_0000);

    @(posedge clk); #1;
    check("Reset cycle 2", 32'h0000_0000);

    // ---- Test 2: Release reset, load PC+4 ----
    rst_n   = 1;
    pc_next = 32'h0000_0004;
    @(posedge clk); #1;
    check("First update (PC=4)", 32'h0000_0004);

    // ---- Test 3: Sequential advance ----
    pc_next = 32'h0000_0008;
    @(posedge clk); #1;
    check("Second update (PC=8)", 32'h0000_0008);

    // ---- Test 4: Stall — PC should hold ----
    en      = 0;        // Stall asserted
    pc_next = 32'h0000_000C;  // This should be IGNORED
    @(posedge clk); #1;
    check("Stall (PC holds at 8)", 32'h0000_0008);

    // ---- Test 5: Still stalled ----
    pc_next = 32'h0000_0010;  // Still ignored
    @(posedge clk); #1;
    check("Stall hold (PC still 8)", 32'h0000_0008);

    // ---- Test 6: Release stall, PC updates ----
    en      = 1;
    pc_next = 32'h0000_000C;
    @(posedge clk); #1;
    check("Stall release (PC=C)", 32'h0000_000C);

    // ---- Test 7: Branch target ----
    pc_next = 32'h0000_0100;  // Branch target far away
    @(posedge clk); #1;
    check("Branch target (PC=100)", 32'h0000_0100);

    // ---- Test 8: Reset during operation ----
    rst_n = 0;
    @(posedge clk); #1;
    check("Mid-operation reset", 32'h0000_0000);

    // ---- Summary ----
    $display("\n===================================");
    $display("  pc_reg testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_pc_reg
