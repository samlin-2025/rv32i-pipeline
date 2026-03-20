// ============================================================================
// File:    tb_instr_mem.sv
// Desc:    Directed testbench for instr_mem.
//          Tests: hex file loading, sequential PC reads, word alignment,
//          out-of-bounds address returns NOP.
// ============================================================================

module tb_instr_mem;

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check(string name, logic [31:0] got, logic [31:0] expected);
    if (got === expected) begin
      $display("[PASS] %s: instr = 0x%08h", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: instr = 0x%08h, expected 0x%08h", name, got, expected);
      fail_count++;
    end
  endtask

  // --------------------------------------------------------------------------
  // DUT signals
  // --------------------------------------------------------------------------
  logic [31:0] addr;
  logic [31:0] instr;

  // --------------------------------------------------------------------------
  // DUT — instruction memory loaded with test hex
  // --------------------------------------------------------------------------
  // The hex file contains 5 instructions at word addresses 0-4:
  //   word 0: 0x00500293  (ADDI x5,  x0, 5)
  //   word 1: 0x00300313  (ADDI x6,  x0, 3)
  //   word 2: 0x006283B3  (ADD  x7,  x5, x6)
  //   word 3: 0x40628433  (SUB  x8,  x5, x6)
  //   word 4: 0x0062F4B3  (AND  x9,  x5, x6)

  instr_mem #(
    .DEPTH     (1024),
    .INIT_FILE ("tb/imem_test.hex")
  ) dut (
    .addr_i   (addr),
    .instr_o  (instr)
  );

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_instr_mem.vcd");
    $dumpvars(0, tb_instr_mem);

    // ---- Test 1: Read instruction at byte address 0x00 (word 0) ----
    addr = 32'h0000_0000;
    #1; check("Addr 0x00 → ADDI x5,x0,5", instr, 32'h00500293);

    // ---- Test 2: Read at byte address 0x04 (word 1) ----
    addr = 32'h0000_0004;
    #1; check("Addr 0x04 → ADDI x6,x0,3", instr, 32'h00300313);

    // ---- Test 3: Read at byte address 0x08 (word 2) ----
    addr = 32'h0000_0008;
    #1; check("Addr 0x08 → ADD x7,x5,x6", instr, 32'h006283B3);

    // ---- Test 4: Read at byte address 0x0C (word 3) ----
    addr = 32'h0000_000C;
    #1; check("Addr 0x0C → SUB x8,x5,x6", instr, 32'h40628433);

    // ---- Test 5: Read at byte address 0x10 (word 4) ----
    addr = 32'h0000_0010;
    #1; check("Addr 0x10 → AND x9,x5,x6", instr, 32'h0062F4B3);

    // ---- Test 6: Read past loaded instructions (should be 0 or X) ----
    // Memory beyond the loaded hex is zero-initialized by $readmemh.
    // Zero (0x00000000) is not a valid opcode, but it's what uninit mem gives.
    addr = 32'h0000_0100;
    #1; check("Addr 0x100 → uninitialized (0)", instr, 32'h00000000);

    // ---- Test 7: Out of bounds — should return NOP ----
    // Address 0x00100000 → word index 0x40000 → exceeds DEPTH (1024).
    // Our bounds check should return NOP (0x00000013).
    addr = 32'h0010_0000;
    #1; check("Addr 0x100000 → OOB NOP", instr, 32'h00000013);

    // ---- Test 8: Max in-bounds address ----
    // DEPTH = 1024, so word index 1023 (byte addr 0xFFC) is the last valid.
    addr = 32'h0000_0FFC;
    #1; check("Addr 0xFFC → last valid word", instr, 32'h00000000);

    // ---- Test 9: One past max → OOB NOP ----
    addr = 32'h0000_1000;
    #1; check("Addr 0x1000 → OOB NOP", instr, 32'h00000013);

    // ---- Test 10: Byte address alignment ----
    // Byte addresses 0x00 and 0x02 both map to word 0 (bits [1:0] ignored).
    // This tests that misaligned reads still produce the whole word.
    addr = 32'h0000_0002;
    #1; check("Addr 0x02 → same as 0x00 (aligned)", instr, 32'h00500293);

    // ---- Summary ----
    $display("\n===================================");
    $display("  instr_mem testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_instr_mem
