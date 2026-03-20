// ============================================================================
// File:    tb_data_mem.sv
// Desc:    Directed testbench for data_mem.
//          Tests: SW/LW round-trip, SB/LB/LBU with sign extension,
//          SH/LH/LHU, little-endian byte ordering, partial overlap reads.
// ============================================================================

module tb_data_mem;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic        clk, rst_n, we;
  logic [2:0]  funct3;
  logic [31:0] addr, wd, rd;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  data_mem #(.DEPTH(256)) dut (
    .clk_i    (clk),
    .rst_ni   (rst_n),
    .we_i     (we),
    .funct3_i (funct3),
    .addr_i   (addr),
    .wd_i     (wd),
    .rd_o     (rd)
  );

  // --------------------------------------------------------------------------
  // Clock
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
      $display("[PASS] %s: rd = 0x%08h", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: rd = 0x%08h, expected 0x%08h", name, got, expected);
      fail_count++;
    end
  endtask

  // Helper: perform a store (wait one clock for synchronous write)
  task automatic do_store(logic [2:0] f3, logic [31:0] a, logic [31:0] d);
    we     = 1;
    funct3 = f3;
    addr   = a;
    wd     = d;
    @(posedge clk); #1;
    we = 0;
  endtask

  // Helper: perform a read (combinational — just set inputs and wait)
  task automatic do_load(logic [2:0] f3, logic [31:0] a);
    we     = 0;
    funct3 = f3;
    addr   = a;
    #1;
  endtask

  // funct3 constants for readability
  localparam logic [2:0] F3_B  = 3'b000;  // LB / SB
  localparam logic [2:0] F3_H  = 3'b001;  // LH / SH
  localparam logic [2:0] F3_W  = 3'b010;  // LW / SW
  localparam logic [2:0] F3_BU = 3'b100;  // LBU
  localparam logic [2:0] F3_HU = 3'b101;  // LHU

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_data_mem.vcd");
    $dumpvars(0, tb_data_mem);

    rst_n = 0; we = 0; funct3 = F3_W; addr = 0; wd = 0;
    @(posedge clk); #1;
    rst_n = 1;
    @(posedge clk); #1;

    // =============================================
    $display("\n--- SW / LW: Word round-trip ---");
    // =============================================

    // Store 0xDEADBEEF at address 0
    do_store(F3_W, 32'h0, 32'hDEAD_BEEF);
    do_load(F3_W, 32'h0);
    check("SW/LW addr=0", rd, 32'hDEAD_BEEF);

    // Store 0x12345678 at address 4
    do_store(F3_W, 32'h4, 32'h1234_5678);
    do_load(F3_W, 32'h4);
    check("SW/LW addr=4", rd, 32'h1234_5678);

    // Verify addr 0 not corrupted
    do_load(F3_W, 32'h0);
    check("Addr 0 intact", rd, 32'hDEAD_BEEF);

    // =============================================
    $display("\n--- Little-endian byte ordering ---");
    // =============================================
    // After SW 0xDEADBEEF at addr 0:
    //   mem[0] = 0xEF (LSB)
    //   mem[1] = 0xBE
    //   mem[2] = 0xAD
    //   mem[3] = 0xDE (MSB)

    do_load(F3_BU, 32'h0);
    check("Byte 0 of DEADBEEF (0xEF)", rd, 32'h0000_00EF);

    do_load(F3_BU, 32'h1);
    check("Byte 1 of DEADBEEF (0xBE)", rd, 32'h0000_00BE);

    do_load(F3_BU, 32'h2);
    check("Byte 2 of DEADBEEF (0xAD)", rd, 32'h0000_00AD);

    do_load(F3_BU, 32'h3);
    check("Byte 3 of DEADBEEF (0xDE)", rd, 32'h0000_00DE);

    // =============================================
    $display("\n--- SB / LB / LBU: Byte access ---");
    // =============================================

    // Store byte 0x80 (negative if signed) at addr 16
    do_store(F3_B, 32'h10, 32'h0000_0080);

    // LB: sign-extend (bit 7 = 1 → extend with 1s)
    do_load(F3_B, 32'h10);
    check("LB 0x80 (sign-ext → 0xFFFFFF80)", rd, 32'hFFFF_FF80);

    // LBU: zero-extend
    do_load(F3_BU, 32'h10);
    check("LBU 0x80 (zero-ext → 0x00000080)", rd, 32'h0000_0080);

    // Store positive byte 0x7F
    do_store(F3_B, 32'h11, 32'h0000_007F);

    // LB: sign-extend (bit 7 = 0 → extend with 0s)
    do_load(F3_B, 32'h11);
    check("LB 0x7F (sign-ext → 0x0000007F)", rd, 32'h0000_007F);

    // =============================================
    $display("\n--- SH / LH / LHU: Halfword access ---");
    // =============================================

    // Store halfword 0x8000 at addr 32 (negative if signed)
    do_store(F3_H, 32'h20, 32'h0000_8000);

    // LH: sign-extend (bit 15 = 1)
    do_load(F3_H, 32'h20);
    check("LH 0x8000 (sign-ext → 0xFFFF8000)", rd, 32'hFFFF_8000);

    // LHU: zero-extend
    do_load(F3_HU, 32'h20);
    check("LHU 0x8000 (zero-ext → 0x00008000)", rd, 32'h0000_8000);

    // Store positive halfword 0x1234
    do_store(F3_H, 32'h22, 32'h0000_1234);

    // LH: sign-extend (bit 15 = 0)
    do_load(F3_H, 32'h22);
    check("LH 0x1234 (sign-ext → 0x00001234)", rd, 32'h0000_1234);

    // =============================================
    $display("\n--- Cross-width access (store word, read bytes) ---");
    // =============================================

    // Store word 0xAABBCCDD at addr 48
    do_store(F3_W, 32'h30, 32'hAABB_CCDD);

    // Read individual bytes (little-endian)
    do_load(F3_BU, 32'h30);
    check("Byte 0 of AABBCCDD (0xDD)", rd, 32'h0000_00DD);

    do_load(F3_BU, 32'h31);
    check("Byte 1 of AABBCCDD (0xCC)", rd, 32'h0000_00CC);

    // Read halfwords
    do_load(F3_HU, 32'h30);
    check("Half 0 of AABBCCDD (0xCCDD)", rd, 32'h0000_CCDD);

    do_load(F3_HU, 32'h32);
    check("Half 1 of AABBCCDD (0xAABB)", rd, 32'h0000_AABB);

    // =============================================
    $display("\n--- ISS cross-check: SW x7 then LW ---");
    // =============================================
    // From ISS test program: SW x7(=8) at addr 0, then LW → should get 8
    do_store(F3_W, 32'h0, 32'h0000_0008);
    do_load(F3_W, 32'h0);
    check("ISS: SW 8, LW → 8", rd, 32'h0000_0008);

    // ---- Summary ----
    $display("\n===================================");
    $display("  data_mem testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_data_mem
