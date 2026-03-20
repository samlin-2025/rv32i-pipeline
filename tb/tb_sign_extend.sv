// ============================================================================
// File:    tb_sign_extend.sv
// Desc:    Directed testbench for sign_extend.
//          Tests all 5 immediate formats with real instruction encodings
//          from the ISS test program. Expected values are cross-validated
//          against the C++ ISS's decode() output.
// ============================================================================

module tb_sign_extend;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic [31:0] instr;
  imm_src_e    imm_src;
  logic [31:0] imm_ext;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  sign_extend dut (
    .instr_i    (instr),
    .imm_src_i  (imm_src),
    .imm_ext_o  (imm_ext)
  );

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check(string name, logic [31:0] got, logic [31:0] expected);
    if (got === expected) begin
      $display("[PASS] %s: imm = 0x%08h (%0d)", name, got, $signed(got));
      pass_count++;
    end else begin
      $display("[FAIL] %s: imm = 0x%08h, expected 0x%08h", name, got, expected);
      fail_count++;
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_sign_extend.vcd");
    $dumpvars(0, tb_sign_extend);

    // =============================================
    $display("\n--- I-type immediates ---");
    // =============================================

    // ADDI x5, x0, 5  →  0x00500293
    // imm[11:0] = instr[31:20] = 0x005 = 5
    instr = 32'h00500293; imm_src = IMM_I;
    #1; check("ADDI x5,x0,5 (imm=5)", imm_ext, 32'h0000_0005);

    // ADDI x6, x0, 3  →  0x00300313
    // imm[11:0] = 0x003 = 3
    instr = 32'h00300313; imm_src = IMM_I;
    #1; check("ADDI x6,x0,3 (imm=3)", imm_ext, 32'h0000_0003);

    // ADDI x17, x17, 0x678  →  0x67888893
    // imm[11:0] = 0x678 = 1656
    instr = 32'h67888893; imm_src = IMM_I;
    #1; check("ADDI x17,x17,0x678 (imm=1656)", imm_ext, 32'h0000_0678);

    // Negative I-type: ADDI x5, x0, -1  →  0xFFF00293
    // imm[11:0] = 0xFFF → sign-extend → 0xFFFFFFFF = -1
    instr = 32'hFFF00293; imm_src = IMM_I;
    #1; check("ADDI x5,x0,-1 (imm=-1)", imm_ext, 32'hFFFF_FFFF);

    // Negative I-type: ADDI x5, x0, -2048  →  0x80000293
    // imm[11:0] = 0x800 → sign-extend → 0xFFFFF800 = -2048
    instr = 32'h80000293; imm_src = IMM_I;
    #1; check("ADDI x5,x0,-2048 (imm=-2048)", imm_ext, 32'hFFFF_F800);

    // SLLI x14, x5, 2  →  0x00229713
    // imm[11:0] = 0x002 (shift amount = 2)
    instr = 32'h00229713; imm_src = IMM_I;
    #1; check("SLLI x14,x5,2 (imm=2)", imm_ext, 32'h0000_0002);

    // LW x18, 0(x0)  →  0x00002903
    // imm[11:0] = 0x000 = 0
    instr = 32'h00002903; imm_src = IMM_I;
    #1; check("LW x18,0(x0) (imm=0)", imm_ext, 32'h0000_0000);

    // =============================================
    $display("\n--- S-type immediates ---");
    // =============================================

    // SW x7, 0(x0)  →  0x00702023
    // imm = {instr[31:25], instr[11:7]} = {0000000, 00000} = 0
    instr = 32'h00702023; imm_src = IMM_S;
    #1; check("SW x7,0(x0) (imm=0)", imm_ext, 32'h0000_0000);

    // SW x5, 4(x10)  →  0x00552223
    // instr[31:25] = 0000000, instr[11:7] = 00100 → imm = 4
    instr = 32'h00552223; imm_src = IMM_S;
    #1; check("SW x5,4(x10) (imm=4)", imm_ext, 32'h0000_0004);

    // SW x5, -4(x10)  →  0xFE552E23
    // instr[31:25] = 1111111, instr[11:7] = 11100
    // imm = 0xFFC = sign-extend → 0xFFFFFFFC = -4
    instr = 32'hFE552E23; imm_src = IMM_S;
    #1; check("SW x5,-4(x10) (imm=-4)", imm_ext, 32'hFFFF_FFFC);

    // =============================================
    $display("\n--- B-type immediates ---");
    // =============================================

    // BNE x20, x21, -8  →  0xFF5A1CE3
    // B-type: imm = {[31],[7],[30:25],[11:8],0}
    //   [31]=1, [7]=1, [30:25]=111111, [11:8]=1100, 0
    //   imm = 1_1_111111_1100_0 = 13'b1_1111_1111_1000
    //   sign-extend from bit 12 → 0xFFFFFFF8 = -8
    instr = 32'hFF5A1CE3; imm_src = IMM_B;
    #1; check("BNE x20,x21,-8 (imm=-8)", imm_ext, 32'hFFFF_FFF8);

    // BEQ x0, x0, +16  →  0x00000863
    // [31]=0, [7]=0, [30:25]=000000, [11:8]=1000, 0
    // imm = 0_0_000000_1000_0 = 16
    instr = 32'h00000863; imm_src = IMM_B;
    #1; check("BEQ x0,x0,+16 (imm=16)", imm_ext, 32'h0000_0010);

    // BLT x1, x2, +4  →  0x00200263 (testing smallest forward branch)
    // [31]=0, [7]=0, [30:25]=000000, [11:8]=0010, 0
    // imm = 4
    instr = 32'h00200263; imm_src = IMM_B;
    #1; check("BLT x1,x2,+4 (imm=4)", imm_ext, 32'h0000_0004);

    // =============================================
    $display("\n--- J-type immediates ---");
    // =============================================

    // JAL x1, +8  →  0x008000EF
    // J-type: imm = {[31],[19:12],[20],[30:21],0}
    //   [31]=0, [19:12]=00000000, [20]=1, [30:21]=0000000000 (wait...)
    // Let me decode 0x008000EF:
    //   bits: 0000 0000 1000 0000 0000 0000 1110 1111
    //   [31]=0, [30:21]=0000000100, [20]=0, [19:12]=00000000
    //   imm = 0_00000000_0_0000000100_0 = 8
    instr = 32'h008000EF; imm_src = IMM_J;
    #1; check("JAL x1,+8 (imm=8)", imm_ext, 32'h0000_0008);

    // JAL x0, -4  (backward jump)
    // Python-verified encoding: imm[10:1]=1111111110, imm[11]=1,
    // imm[19:12]=11111111, imm[20]=1 → 0xFFDFF06F
    instr = 32'hFFDFF06F; imm_src = IMM_J;
    #1; check("JAL x0,-4 (imm=-4)", imm_ext, 32'hFFFF_FFFC);

    // JAL x1, +2048
    // +2048 as 21-bit: imm[20]=0, [19:12]=00000000, [11]=1, [10:1]=0000000000
    // [31]=0, [30:21]=0000000000, [20]=1, [19:12]=00000000, rd=00001
    instr = 32'h001000EF; imm_src = IMM_J;
    #1; check("JAL x1,+2048 (imm=2048)", imm_ext, 32'h0000_0800);

    // =============================================
    $display("\n--- U-type immediates ---");
    // =============================================

    // LUI x16, 0x12345  →  0x12345837
    // imm = {instr[31:12], 12'b0} = 0x12345000
    instr = 32'h12345837; imm_src = IMM_U;
    #1; check("LUI x16,0x12345 (imm=0x12345000)", imm_ext, 32'h1234_5000);

    // LUI x17, 0x12345  →  0x123458B7
    instr = 32'h123458B7; imm_src = IMM_U;
    #1; check("LUI x17,0x12345 (imm=0x12345000)", imm_ext, 32'h1234_5000);

    // LUI with sign bit set: LUI x5, 0xFFFFF  →  0xFFFFF2B7
    // imm = 0xFFFFF000 (upper 20 bits all 1, lower 12 zero)
    instr = 32'hFFFFF2B7; imm_src = IMM_U;
    #1; check("LUI x5,0xFFFFF (imm=0xFFFFF000)", imm_ext, 32'hFFFF_F000);

    // LUI x5, 0x00001  →  0x000012B7
    // imm = 0x00001000
    instr = 32'h000012B7; imm_src = IMM_U;
    #1; check("LUI x5,0x1 (imm=0x1000)", imm_ext, 32'h0000_1000);

    // =============================================
    $display("\n--- Default (R-type, no immediate) ---");
    // =============================================

    // ADD x7, x5, x6  →  0x006283B3, imm_src = some invalid value
    // Should output 0
    instr = 32'h006283B3; imm_src = imm_src_e'(3'b111);
    #1; check("R-type default (imm=0)", imm_ext, 32'h0000_0000);

    // ---- Summary ----
    $display("\n===================================");
    $display("  sign_extend testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_sign_extend
