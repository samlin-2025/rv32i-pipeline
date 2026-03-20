// ============================================================================
// File:    tb_fetch_stage.sv
// Desc:    Directed testbench for fetch_stage.
//          Tests: reset, sequential fetch, branch redirect, stall hold,
//          flush zeroing, and stall release.
//
// Hex file (fetch_test.hex):
//   word 0 (0x00): 0x00500293  ADDI x5, x0, 5
//   word 1 (0x04): 0x00300313  ADDI x6, x0, 3
//   word 2 (0x08): 0x006283B3  ADD  x7, x5, x6
//   word 3 (0x0C): 0x40628433  SUB  x8, x5, x6
//   word 4 (0x10): 0x0062F4B3  AND  x9, x5, x6
//   word 5 (0x14): 0x0062E533  OR   x10, x5, x6
//   word 6 (0x18): 0x0062C5B3  XOR  x11, x5, x6
//   word 7 (0x1C): 0x0062A633  SLT  x12, x5, x6
// ============================================================================

module tb_fetch_stage;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic        clk, rst_n;
  logic        stall, flush, pc_src;
  logic [31:0] pc_target;

  logic [31:0] instr_id, pc_id, pc_plus4_id;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  fetch_stage #(
    .IMEM_INIT_FILE("tb/fetch_test.hex")
  ) dut (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .stall_i       (stall),
    .flush_i       (flush),
    .pc_src_i      (pc_src),
    .pc_target_i   (pc_target),
    .instr_id_o    (instr_id),
    .pc_id_o       (pc_id),
    .pc_plus4_id_o (pc_plus4_id)
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

  task automatic check(string name,
                       logic [31:0] got_instr, logic [31:0] exp_instr,
                       logic [31:0] got_pc, logic [31:0] exp_pc);
    int ok = 1;
    if (got_instr !== exp_instr) begin
      $display("  [FAIL] %s: instr = 0x%08h, expected 0x%08h", name, got_instr, exp_instr);
      ok = 0;
    end
    if (got_pc !== exp_pc) begin
      $display("  [FAIL] %s: pc = 0x%08h, expected 0x%08h", name, got_pc, exp_pc);
      ok = 0;
    end
    if (ok) begin
      $display("[PASS] %s: instr=0x%08h pc=0x%08h", name, got_instr, got_pc);
      pass_count++;
    end else begin
      fail_count++;
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_fetch_stage.vcd");
    $dumpvars(0, tb_fetch_stage);

    // Initialize
    rst_n     = 0;
    stall     = 0;
    flush     = 0;
    pc_src    = 0;
    pc_target = 32'h0;

    // =============================================
    $display("\n--- Reset ---");
    // =============================================

    @(posedge clk); #1;
    check("Reset cycle 1", instr_id, 32'h0, pc_id, 32'h0);

    @(posedge clk); #1;
    check("Reset cycle 2", instr_id, 32'h0, pc_id, 32'h0);

    // =============================================
    $display("\n--- Sequential fetch ---");
    // =============================================
    // Release reset. On the next rising edge, the PC register loads PC+4
    // from the mux (since pc_src=0). But the IF/ID register captures the
    // instruction at the CURRENT PC (which was 0 during reset).
    //
    // Cycle timeline:
    //   Reset releases → PC=0, IMEM reads word 0
    //   Clock edge 1: IF/ID captures {word0, PC=0, PC+4=4}; PC loads 4
    //   Clock edge 2: IF/ID captures {word1, PC=4, PC+4=8}; PC loads 8
    //   etc.

    rst_n = 1;

    // First cycle after reset: IF/ID captures instruction at PC=0
    @(posedge clk); #1;
    check("Fetch word0 (PC=0x00)", instr_id, 32'h00500293, pc_id, 32'h0000_0000);

    // Second cycle: PC advanced to 4
    @(posedge clk); #1;
    check("Fetch word1 (PC=0x04)", instr_id, 32'h00300313, pc_id, 32'h0000_0004);

    // Third cycle: PC = 8
    @(posedge clk); #1;
    check("Fetch word2 (PC=0x08)", instr_id, 32'h006283B3, pc_id, 32'h0000_0008);

    // Fourth cycle: PC = 0x0C
    @(posedge clk); #1;
    check("Fetch word3 (PC=0x0C)", instr_id, 32'h40628433, pc_id, 32'h0000_000C);

    // =============================================
    $display("\n--- Stall (load-use hazard) ---");
    // =============================================
    // Assert stall. PC should freeze, IF/ID should hold current values.
    // Currently: PC=0x10 in IF, word3 just entered ID.

    stall = 1;

    // Stall cycle 1: IF/ID should still hold word4 at PC=0x10
    // (wait — the IF/ID captured word3 at PC=0x0C last cycle.
    //  This cycle, PC=0x10 is being fetched. Stall prevents IF/ID update.)
    // So IF/ID still holds the previous value: word3 at PC=0x0C.
    @(posedge clk); #1;
    check("Stall hold cycle 1", instr_id, 32'h40628433, pc_id, 32'h0000_000C);

    // Stall cycle 2: still holding
    @(posedge clk); #1;
    check("Stall hold cycle 2", instr_id, 32'h40628433, pc_id, 32'h0000_000C);

    // Release stall: IF/ID should now capture the instruction that was
    // waiting in IF (word4 at PC=0x10)
    stall = 0;
    @(posedge clk); #1;
    check("Stall release (PC=0x10)", instr_id, 32'h0062F4B3, pc_id, 32'h0000_0010);

    // Normal fetch resumes: PC=0x14
    @(posedge clk); #1;
    check("Resume word5 (PC=0x14)", instr_id, 32'h0062E533, pc_id, 32'h0000_0014);

    // =============================================
    $display("\n--- Branch redirect ---");
    // =============================================
    // Redirect PC to address 0x04 (word1). Assert pc_src for one cycle.
    // The IF/ID register should be flushed (the instruction in IF is
    // from the old path).

    pc_src    = 1;
    pc_target = 32'h0000_0004;
    flush     = 1;

    // On this clock edge:
    //   PC loads 0x04 (branch target)
    //   IF/ID is flushed → outputs zero
    @(posedge clk); #1;
    check("Branch flush", instr_id, 32'h0, pc_id, 32'h0);

    // Deassert branch control
    pc_src = 0;
    flush  = 0;

    // Next cycle: IF/ID captures instruction at new PC=0x04
    @(posedge clk); #1;
    check("After branch (PC=0x04)", instr_id, 32'h00300313, pc_id, 32'h0000_0004);

    // Sequential continues from 0x08
    @(posedge clk); #1;
    check("Continue (PC=0x08)", instr_id, 32'h006283B3, pc_id, 32'h0000_0008);

    // ---- Summary ----
    $display("\n===================================");
    $display("  fetch_stage testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_fetch_stage
