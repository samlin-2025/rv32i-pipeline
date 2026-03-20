// ============================================================================
// File:    tb_register_file.sv
// Desc:    Directed testbench for register_file.
//          Tests: x0 hardwire, basic write/read, write-through forwarding,
//          simultaneous reads, reset behavior, and x0 write rejection.
// ============================================================================

module tb_register_file;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic        clk, rst_n;
  logic        we;
  logic [4:0]  wr_addr, rs1_addr, rs2_addr;
  logic [31:0] wr_data, rs1_data, rs2_data;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  register_file dut (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .we_i        (we),
    .wr_addr_i   (wr_addr),
    .wr_data_i   (wr_data),
    .rs1_addr_i  (rs1_addr),
    .rs1_data_o  (rs1_data),
    .rs2_addr_i  (rs2_addr),
    .rs2_data_o  (rs2_data)
  );

  // --------------------------------------------------------------------------
  // Clock: 10ns period
  // --------------------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check(string name, logic [31:0] got, logic [31:0] expected);
    if (got === expected) begin
      $display("[PASS] %s: got 0x%08h", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: got 0x%08h, expected 0x%08h", name, got, expected);
      fail_count++;
    end
  endtask

  // Helper: write a register and wait for it to take effect
  task automatic write_reg(input logic [4:0] addr, input logic [31:0] data);
    we      = 1;
    wr_addr = addr;
    wr_data = data;
    @(posedge clk); #1;
    we      = 0;
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_register_file.vcd");
    $dumpvars(0, tb_register_file);

    // Initialize
    rst_n    = 0;
    we       = 0;
    wr_addr  = 5'd0;
    wr_data  = 32'h0;
    rs1_addr = 5'd0;
    rs2_addr = 5'd0;

    // ---- Reset ----
    @(posedge clk); #1;
    @(posedge clk); #1;

    $display("\n--- Test group 1: x0 hardwire ---");

    // Release reset
    rst_n = 1;
    @(posedge clk); #1;

    // Test 1: Read x0 — must always be zero
    rs1_addr = 5'd0;
    rs2_addr = 5'd0;
    #1; check("x0 read port1", rs1_data, 32'h0);
    #1; check("x0 read port2", rs2_data, 32'h0);

    // Test 2: Try to write x0, then read it — must still be zero
    write_reg(5'd0, 32'hDEAD_BEEF);
    rs1_addr = 5'd0;
    #1; check("x0 after write attempt", rs1_data, 32'h0);

    // ==================================================
    $display("\n--- Test group 2: Basic write and read ---");

    // Test 3: Write x5 = 42, then read it back
    write_reg(5'd5, 32'h0000_002A);
    rs1_addr = 5'd5;
    #1; check("x5 = 42", rs1_data, 32'h0000_002A);

    // Test 4: Write x10 = 0xCAFEBABE, read on port 2
    write_reg(5'd10, 32'hCAFE_BABE);
    rs2_addr = 5'd10;
    #1; check("x10 = 0xCAFEBABE", rs2_data, 32'hCAFE_BABE);

    // Test 5: Read both ports simultaneously (different registers)
    rs1_addr = 5'd5;
    rs2_addr = 5'd10;
    #1; check("Dual read port1 (x5)", rs1_data, 32'h0000_002A);
    #1; check("Dual read port2 (x10)", rs2_data, 32'hCAFE_BABE);

    // Test 6: Read same register on both ports
    rs1_addr = 5'd5;
    rs2_addr = 5'd5;
    #1; check("Same reg port1 (x5)", rs1_data, 32'h0000_002A);
    #1; check("Same reg port2 (x5)", rs2_data, 32'h0000_002A);

    // ==================================================
    $display("\n--- Test group 3: Write-through forwarding ---");

    // Test 7: Simultaneously write x5 = 99 and read x5
    // The read should see the NEW value (99), not the old one (42).
    // This is the critical write-through test.
    we       = 1;
    wr_addr  = 5'd5;
    wr_data  = 32'h0000_0063;  // 99
    rs1_addr = 5'd5;
    rs2_addr = 5'd5;
    // Check BEFORE clock edge — at this point, combinational bypass is active
    #1; check("Write-through port1 (x5=99)", rs1_data, 32'h0000_0063);
    #1; check("Write-through port2 (x5=99)", rs2_data, 32'h0000_0063);

    // Let the write actually happen
    @(posedge clk); #1;
    we = 0;

    // Verify the write persisted
    rs1_addr = 5'd5;
    #1; check("x5 after write-through (99)", rs1_data, 32'h0000_0063);

    // Test 8: Write-through to x0 — should still read 0
    we       = 1;
    wr_addr  = 5'd0;
    wr_data  = 32'hFFFF_FFFF;
    rs1_addr = 5'd0;
    #1; check("Write-through x0 (still 0)", rs1_data, 32'h0);
    @(posedge clk); #1;
    we = 0;

    // Test 9: Write x20, read x10 on same cycle — no forwarding needed
    // x10 should still be 0xCAFEBABE, unaffected by x20 write
    we       = 1;
    wr_addr  = 5'd20;
    wr_data  = 32'h1234_5678;
    rs1_addr = 5'd10;
    #1; check("No false forward (x10)", rs1_data, 32'hCAFE_BABE);
    @(posedge clk); #1;
    we = 0;

    // Verify x20 got written
    rs1_addr = 5'd20;
    #1; check("x20 = 0x12345678", rs1_data, 32'h1234_5678);

    // ==================================================
    $display("\n--- Test group 4: Overwrite and boundary ---");

    // Test 10: Overwrite x5 with new value
    write_reg(5'd5, 32'hAAAA_BBBB);
    rs1_addr = 5'd5;
    #1; check("x5 overwritten", rs1_data, 32'hAAAA_BBBB);

    // Test 11: Write to x31 (highest register)
    write_reg(5'd31, 32'hFFFF_0000);
    rs1_addr = 5'd31;
    #1; check("x31 = 0xFFFF0000", rs1_data, 32'hFFFF_0000);

    // Test 12: Write to x1 (lowest non-zero register)
    write_reg(5'd1, 32'h0000_0001);
    rs1_addr = 5'd1;
    #1; check("x1 = 1", rs1_data, 32'h0000_0001);

    // ==================================================
    $display("\n--- Test group 5: Reset clears all ---");

    // Test 13: Assert reset, all registers should go to 0
    rst_n = 0;
    @(posedge clk); #1;
    rs1_addr = 5'd5;
    rs2_addr = 5'd10;
    #1; check("x5 after reset", rs1_data, 32'h0);
    #1; check("x10 after reset", rs2_data, 32'h0);

    rst_n = 1;
    @(posedge clk); #1;

    // Verify x31 also cleared
    rs1_addr = 5'd31;
    #1; check("x31 after reset", rs1_data, 32'h0);

    // ---- Summary ----
    $display("\n===================================");
    $display("  register_file testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_register_file
