// ============================================================================
// File:    tb_mux.sv
// Desc:    Directed testbench for mux2 and mux3.
//          Tests all select values, verifies forwarding mux priority logic,
//          and checks parameterized width works for non-32-bit instances.
// ============================================================================

module tb_mux;

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check32(string name, logic [31:0] got, logic [31:0] expected);
    if (got === expected) begin
      $display("[PASS] %s: got 0x%08h", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: got 0x%08h, expected 0x%08h", name, got, expected);
      fail_count++;
    end
  endtask

  task automatic check5(string name, logic [4:0] got, logic [4:0] expected);
    if (got === expected) begin
      $display("[PASS] %s: got %02d", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: got %02d, expected %02d", name, got, expected);
      fail_count++;
    end
  endtask

  // ==========================================================================
  // DUT: mux2 (32-bit — PC mux / ALU src)
  // ==========================================================================
  logic             sel2;
  logic [31:0]      a2, b2, y2;

  mux2 #(.WIDTH(32)) u_mux2 (
    .sel_i (sel2),
    .a_i   (a2),
    .b_i   (b2),
    .y_o   (y2)
  );

  // ==========================================================================
  // DUT: mux2 (5-bit — register address mux, tests parameterization)
  // ==========================================================================
  logic        sel2_5;
  logic [4:0]  a2_5, b2_5, y2_5;

  mux2 #(.WIDTH(5)) u_mux2_5bit (
    .sel_i (sel2_5),
    .a_i   (a2_5),
    .b_i   (b2_5),
    .y_o   (y2_5)
  );

  // ==========================================================================
  // DUT: mux3 (32-bit — forwarding mux)
  // ==========================================================================
  logic [1:0]  sel3;
  logic [31:0] a3, b3, c3, y3;

  mux3 #(.WIDTH(32)) u_mux3 (
    .sel_i (sel3),
    .a_i   (a3),
    .b_i   (b3),
    .c_i   (c3),
    .y_o   (y3)
  );

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_mux.vcd");
    $dumpvars(0, tb_mux);

    // =============================================
    // mux2 (32-bit) tests
    // =============================================
    $display("\n--- mux2 (32-bit) ---");

    // Test 1: sel=0 selects A (PC+4 path)
    sel2 = 0; a2 = 32'h0000_0004; b2 = 32'h0000_0100;
    #1; check32("mux2 sel=0 → A", y2, 32'h0000_0004);

    // Test 2: sel=1 selects B (branch target path)
    sel2 = 1; a2 = 32'h0000_0004; b2 = 32'h0000_0100;
    #1; check32("mux2 sel=1 → B", y2, 32'h0000_0100);

    // Test 3: Verify no X leakage — both inputs same
    sel2 = 0; a2 = 32'hDEAD_BEEF; b2 = 32'hDEAD_BEEF;
    #1; check32("mux2 both same", y2, 32'hDEAD_BEEF);

    // Test 4: All zeros
    sel2 = 0; a2 = 32'h0; b2 = 32'h0;
    #1; check32("mux2 all zero", y2, 32'h0);

    // Test 5: All ones
    sel2 = 1; a2 = 32'h0; b2 = 32'hFFFF_FFFF;
    #1; check32("mux2 all ones", y2, 32'hFFFF_FFFF);

    // =============================================
    // mux2 (5-bit) — parameterization test
    // =============================================
    $display("\n--- mux2 (5-bit) ---");

    // Test 6: Select register address x5
    sel2_5 = 0; a2_5 = 5'd5; b2_5 = 5'd10;
    #1; check5("mux2_5 sel=0 → x5", y2_5, 5'd5);

    // Test 7: Select register address x10
    sel2_5 = 1; a2_5 = 5'd5; b2_5 = 5'd10;
    #1; check5("mux2_5 sel=1 → x10", y2_5, 5'd10);

    // =============================================
    // mux3 (32-bit) — forwarding mux tests
    // =============================================
    $display("\n--- mux3 (32-bit, forwarding) ---");

    // Set up realistic forwarding scenario:
    //   a = register file value    (0x0000_000A = 10)
    //   b = WB stage result        (0x0000_0014 = 20)
    //   c = MEM stage ALU result   (0x0000_001E = 30)
    a3 = 32'h0000_000A;
    b3 = 32'h0000_0014;
    c3 = 32'h0000_001E;

    // Test 8: FWD_NONE (00) — no hazard, use register file
    sel3 = 2'b00;
    #1; check32("mux3 FWD_NONE → regfile (10)", y3, 32'h0000_000A);

    // Test 9: FWD_WB (01) — forward from writeback stage
    sel3 = 2'b01;
    #1; check32("mux3 FWD_WB → wb_result (20)", y3, 32'h0000_0014);

    // Test 10: FWD_MEM (10) — forward from memory stage (highest priority)
    sel3 = 2'b10;
    #1; check32("mux3 FWD_MEM → mem_result (30)", y3, 32'h0000_001E);

    // Test 11: sel=11 — should output zero (safety default)
    sel3 = 2'b11;
    #1; check32("mux3 default → zero", y3, 32'h0000_0000);

    // =============================================
    // Writeback mux scenario (mux3 reused)
    // =============================================
    $display("\n--- mux3 (writeback mux scenario) ---");

    // Writeback mux: sel=00 → ALU, sel=01 → mem read, sel=10 → PC+4
    a3 = 32'h0000_0008;  // ALU result (e.g., ADD = 8)
    b3 = 32'h0000_00FF;  // Memory read (e.g., LW = 0xFF)
    c3 = 32'h0000_0054;  // PC + 4 (e.g., JAL link address)

    sel3 = 2'b00;
    #1; check32("WB sel=ALU (8)", y3, 32'h0000_0008);

    sel3 = 2'b01;
    #1; check32("WB sel=MEM (0xFF)", y3, 32'h0000_00FF);

    sel3 = 2'b10;
    #1; check32("WB sel=PC4 (0x54)", y3, 32'h0000_0054);

    // ---- Summary ----
    $display("\n===================================");
    $display("  mux testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_mux
