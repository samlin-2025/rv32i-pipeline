// ============================================================================
// File:    tb_pipeline_top.sv
// Desc:    Full integration testbench for the 5-stage pipelined RV32I.
//
//          Loads the same hex program as the C++ ISS and runs it to
//          completion. Then compares final register file state against
//          ISS-predicted values. Any mismatch indicates a pipeline bug.
//
// Test program (test_comprehensive.hex):
//   ADDI, ADD, SUB, AND, OR, XOR, SLT, SLLI, SRLI,
//   LUI, LUI+ADDI combo, SW/LW memory round-trip,
//   BNE loop (count to 10), JAL
//
// Expected register state (from ISS trace):
//   x1  = 0x00000054  x5  = 0x00000005  x6  = 0x00000003
//   x7  = 0x00000008  x8  = 0x00000002  x9  = 0x00000001
//   x10 = 0x00000007  x11 = 0x00000006  x12 = 0x00000000
//   x13 = 0x00000001  x14 = 0x00000014  x15 = 0x00000001
//   x16 = 0x12345000  x17 = 0x12345678  x18 = 0x00000008
//   x20 = 0x0000000A  x21 = 0x0000000A  x23 = 0x0000002A
// ============================================================================

module tb_pipeline_top;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Clock and reset
  // --------------------------------------------------------------------------
  logic clk, rst_n;

  initial clk = 0;
  always #5 clk = ~clk;  // 10ns period (100 MHz)

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  pipeline_top #(
    .IMEM_INIT_FILE("iss/test_comprehensive.hex")
  ) dut (
    .clk_i  (clk),
    .rst_ni (rst_n)
  );

  // --------------------------------------------------------------------------
  // Register file access — reach into the hierarchy for verification
  // --------------------------------------------------------------------------
  // In a real UVM environment, we'd use a monitor interface or DPI-C.
  // For directed testing, hierarchical access is fine.

  function automatic logic [31:0] get_reg(int idx);
    if (idx == 0) return 32'h0;
    return dut.u_decode.u_register_file.regs[idx];
  endfunction

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check_reg(int idx, logic [31:0] expected);
    logic [31:0] got;
    got = get_reg(idx);
    if (got === expected) begin
      $display("[PASS] x%-2d = 0x%08h", idx, got);
      pass_count++;
    end else begin
      $display("[FAIL] x%-2d = 0x%08h, expected 0x%08h", idx, got, expected);
      fail_count++;
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_pipeline_top.vcd");
    $dumpvars(0, tb_pipeline_top);

    // ---- Reset ----
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;

    // ---- Run the program ----
    // The test program has ~49 ISS instructions. With pipeline overhead
    // (fill, stalls, flushes), we need more cycles. 500 is generous.
    repeat (500) @(posedge clk);

    // ---- Check register file against ISS golden reference ----
    $display("\n===================================================");
    $display("  Pipeline Integration Test — Register File Check");
    $display("  Comparing against C++ ISS golden reference");
    $display("===================================================\n");

    // x0 must always be zero
    check_reg(0,  32'h0000_0000);

    // ISS-predicted values
    check_reg(1,  32'h0000_0054);   // JAL link address
    check_reg(5,  32'h0000_0005);   // ADDI x5, x0, 5
    check_reg(6,  32'h0000_0003);   // ADDI x6, x0, 3
    check_reg(7,  32'h0000_0008);   // ADD  x7, x5, x6 = 8
    check_reg(8,  32'h0000_0002);   // SUB  x8, x5, x6 = 2
    check_reg(9,  32'h0000_0001);   // AND  x9, x5, x6 = 1
    check_reg(10, 32'h0000_0007);   // OR   x10, x5, x6 = 7
    check_reg(11, 32'h0000_0006);   // XOR  x11, x5, x6 = 6
    check_reg(12, 32'h0000_0000);   // SLT  x12, x5, x6 = 0 (5 < 3? no)
    check_reg(13, 32'h0000_0001);   // SLT  x13, x6, x5 = 1 (3 < 5? yes)
    check_reg(14, 32'h0000_0014);   // SLLI x14, x5, 2 = 20
    check_reg(15, 32'h0000_0001);   // SRLI x15, x6, 1 = 1
    check_reg(16, 32'h1234_5000);   // LUI  x16, 0x12345
    check_reg(17, 32'h1234_5678);   // LUI + ADDI combo
    check_reg(18, 32'h0000_0008);   // SW x7 then LW → 8
    check_reg(20, 32'h0000_000A);   // BNE loop counter final = 10
    check_reg(21, 32'h0000_000A);   // Loop limit = 10
    check_reg(23, 32'h0000_002A);   // ADDI after JAL = 42

    // Registers that should be untouched (still zero from reset)
    check_reg(2,  32'h0000_0000);
    check_reg(3,  32'h0000_0000);
    check_reg(4,  32'h0000_0000);
    check_reg(19, 32'h0000_0000);
    check_reg(22, 32'h0000_0000);
    check_reg(31, 32'h0000_0000);

    $display("\n===================================================");
    $display("  RESULT: %0d PASSED, %0d FAILED out of %0d checks",
             pass_count, fail_count, pass_count + fail_count);
    if (fail_count == 0)
      $display("  *** ALL TESTS PASSED — RTL matches ISS! ***");
    else
      $display("  *** FAILURES DETECTED — debug needed ***");
    $display("===================================================\n");

    $finish;
  end

endmodule : tb_pipeline_top
