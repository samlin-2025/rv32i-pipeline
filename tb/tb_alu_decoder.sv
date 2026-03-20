// ============================================================================
// File:    tb_alu_decoder.sv
// Desc:    Directed testbench for alu_decoder.
//          Tests every row of the decode table: fast-path (ADD/SUB/LUI),
//          all funct3 variants under ALU_OP_FUNC, and the critical
//          {op[5], funct7[5]} disambiguation for ADD vs SUB vs ADDI.
// ============================================================================

module tb_alu_decoder;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  alu_op_hint_e alu_op;
  logic [2:0]   funct3;
  logic         funct7_5;
  logic         op_5;
  alu_op_e      alu_ctrl;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  alu_decoder dut (
    .alu_op_i    (alu_op),
    .funct3_i    (funct3),
    .funct7_5_i  (funct7_5),
    .op_5_i      (op_5),
    .alu_ctrl_o  (alu_ctrl)
  );

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task automatic check(string name, alu_op_e got, alu_op_e expected);
    if (got === expected) begin
      $display("[PASS] %s: alu_ctrl = %s", name, got.name());
      pass_count++;
    end else begin
      $display("[FAIL] %s: alu_ctrl = %s, expected %s", name, got.name(), expected.name());
      fail_count++;
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_alu_decoder.vcd");
    $dumpvars(0, tb_alu_decoder);

    // =============================================
    $display("\n--- Fast paths (ALU_OP_ADD / SUB / LUI) ---");
    // =============================================

    // ALU_OP_ADD: loads, stores, JALR, AUIPC → always ALU_ADD
    // funct3/funct7 should be completely ignored
    alu_op = ALU_OP_ADD; funct3 = 3'b000; funct7_5 = 0; op_5 = 0;
    #1; check("ALU_OP_ADD (funct3=000)", alu_ctrl, ALU_ADD);

    alu_op = ALU_OP_ADD; funct3 = 3'b111; funct7_5 = 1; op_5 = 1;
    #1; check("ALU_OP_ADD (funct3=111, garbage)", alu_ctrl, ALU_ADD);

    // ALU_OP_SUB: branches → always ALU_SUB
    alu_op = ALU_OP_SUB; funct3 = 3'b000; funct7_5 = 0; op_5 = 0;
    #1; check("ALU_OP_SUB (branches)", alu_ctrl, ALU_SUB);

    // ALU_OP_LUI: LUI → always ALU_LUI
    alu_op = ALU_OP_LUI; funct3 = 3'b000; funct7_5 = 0; op_5 = 0;
    #1; check("ALU_OP_LUI", alu_ctrl, ALU_LUI);

    // =============================================
    $display("\n--- ALU_OP_FUNC: ADD vs SUB vs ADDI ---");
    // =============================================
    // This is the most critical decode path. Getting this wrong means
    // ADD and SUB are swapped, or ADDI is treated as SUB.

    // ADD (R-type): op[5]=1, funct7[5]=0
    alu_op = ALU_OP_FUNC; funct3 = 3'b000; funct7_5 = 0; op_5 = 1;
    #1; check("ADD (R-type: op5=1, f7_5=0)", alu_ctrl, ALU_ADD);

    // SUB (R-type): op[5]=1, funct7[5]=1
    alu_op = ALU_OP_FUNC; funct3 = 3'b000; funct7_5 = 1; op_5 = 1;
    #1; check("SUB (R-type: op5=1, f7_5=1)", alu_ctrl, ALU_SUB);

    // ADDI (I-type): op[5]=0, funct7[5]=don't care
    alu_op = ALU_OP_FUNC; funct3 = 3'b000; funct7_5 = 0; op_5 = 0;
    #1; check("ADDI (I-type: op5=0, f7_5=0)", alu_ctrl, ALU_ADD);

    // ADDI with garbage funct7: op[5]=0, funct7[5]=1 → still ADD
    alu_op = ALU_OP_FUNC; funct3 = 3'b000; funct7_5 = 1; op_5 = 0;
    #1; check("ADDI (I-type: op5=0, f7_5=1 garbage)", alu_ctrl, ALU_ADD);

    // =============================================
    $display("\n--- ALU_OP_FUNC: All other funct3 ---");
    // =============================================

    // SLL / SLLI (funct3 = 001)
    alu_op = ALU_OP_FUNC; funct3 = 3'b001; funct7_5 = 0; op_5 = 1;
    #1; check("SLL (funct3=001)", alu_ctrl, ALU_SLL);

    alu_op = ALU_OP_FUNC; funct3 = 3'b001; funct7_5 = 0; op_5 = 0;
    #1; check("SLLI (funct3=001, I-type)", alu_ctrl, ALU_SLL);

    // SLT / SLTI (funct3 = 010)
    alu_op = ALU_OP_FUNC; funct3 = 3'b010; funct7_5 = 0; op_5 = 1;
    #1; check("SLT (funct3=010)", alu_ctrl, ALU_SLT);

    alu_op = ALU_OP_FUNC; funct3 = 3'b010; funct7_5 = 0; op_5 = 0;
    #1; check("SLTI (funct3=010, I-type)", alu_ctrl, ALU_SLT);

    // SLTU / SLTIU (funct3 = 011)
    alu_op = ALU_OP_FUNC; funct3 = 3'b011; funct7_5 = 0; op_5 = 1;
    #1; check("SLTU (funct3=011)", alu_ctrl, ALU_SLTU);

    alu_op = ALU_OP_FUNC; funct3 = 3'b011; funct7_5 = 0; op_5 = 0;
    #1; check("SLTIU (funct3=011, I-type)", alu_ctrl, ALU_SLTU);

    // XOR / XORI (funct3 = 100)
    alu_op = ALU_OP_FUNC; funct3 = 3'b100; funct7_5 = 0; op_5 = 1;
    #1; check("XOR (funct3=100)", alu_ctrl, ALU_XOR);

    alu_op = ALU_OP_FUNC; funct3 = 3'b100; funct7_5 = 0; op_5 = 0;
    #1; check("XORI (funct3=100, I-type)", alu_ctrl, ALU_XOR);

    // SRL / SRLI (funct3 = 101, funct7[5] = 0)
    alu_op = ALU_OP_FUNC; funct3 = 3'b101; funct7_5 = 0; op_5 = 1;
    #1; check("SRL (funct3=101, f7_5=0)", alu_ctrl, ALU_SRL);

    alu_op = ALU_OP_FUNC; funct3 = 3'b101; funct7_5 = 0; op_5 = 0;
    #1; check("SRLI (funct3=101, f7_5=0, I-type)", alu_ctrl, ALU_SRL);

    // SRA / SRAI (funct3 = 101, funct7[5] = 1)
    alu_op = ALU_OP_FUNC; funct3 = 3'b101; funct7_5 = 1; op_5 = 1;
    #1; check("SRA (funct3=101, f7_5=1)", alu_ctrl, ALU_SRA);

    alu_op = ALU_OP_FUNC; funct3 = 3'b101; funct7_5 = 1; op_5 = 0;
    #1; check("SRAI (funct3=101, f7_5=1, I-type)", alu_ctrl, ALU_SRA);

    // OR / ORI (funct3 = 110)
    alu_op = ALU_OP_FUNC; funct3 = 3'b110; funct7_5 = 0; op_5 = 1;
    #1; check("OR (funct3=110)", alu_ctrl, ALU_OR);

    alu_op = ALU_OP_FUNC; funct3 = 3'b110; funct7_5 = 0; op_5 = 0;
    #1; check("ORI (funct3=110, I-type)", alu_ctrl, ALU_OR);

    // AND / ANDI (funct3 = 111)
    alu_op = ALU_OP_FUNC; funct3 = 3'b111; funct7_5 = 0; op_5 = 1;
    #1; check("AND (funct3=111)", alu_ctrl, ALU_AND);

    alu_op = ALU_OP_FUNC; funct3 = 3'b111; funct7_5 = 0; op_5 = 0;
    #1; check("ANDI (funct3=111, I-type)", alu_ctrl, ALU_AND);

    // ---- Summary ----
    $display("\n===================================");
    $display("  alu_decoder testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_alu_decoder
