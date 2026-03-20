// ============================================================================
// File:    tb_decode_stage.sv
// Desc:    Directed testbench for decode_stage.
//          Tests: control signal generation, register file reads/writes,
//          immediate extraction, flush (control zeroing), stall (hold),
//          and WB write-through.
// ============================================================================

module tb_decode_stage;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic        clk, rst_n;
  logic        flush, stall;

  // IF/ID inputs
  logic [31:0] instr_id, pc_id, pc_plus4_id;

  // WB write-back
  logic        reg_write_wb;
  logic [4:0]  rd_wb;
  logic [31:0] result_wb;

  // ID/EX outputs
  ctrl_ex_t    ctrl_ex;
  logic [31:0] rs1_data_ex, rs2_data_ex, imm_ext_ex;
  logic [4:0]  rs1_addr_ex, rs2_addr_ex, rd_addr_ex;
  logic [31:0] pc_ex, pc_plus4_ex;

  // Hazard unit outputs
  logic [4:0]  rs1_addr_id, rs2_addr_id;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  decode_stage dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .flush_i        (flush),
    .stall_i        (stall),
    .instr_id_i     (instr_id),
    .pc_id_i        (pc_id),
    .pc_plus4_id_i  (pc_plus4_id),
    .reg_write_wb_i (reg_write_wb),
    .rd_wb_i        (rd_wb),
    .result_wb_i    (result_wb),
    .ctrl_ex_o      (ctrl_ex),
    .rs1_data_ex_o  (rs1_data_ex),
    .rs2_data_ex_o  (rs2_data_ex),
    .imm_ext_ex_o   (imm_ext_ex),
    .rs1_addr_ex_o  (rs1_addr_ex),
    .rs2_addr_ex_o  (rs2_addr_ex),
    .rd_addr_ex_o   (rd_addr_ex),
    .pc_ex_o        (pc_ex),
    .pc_plus4_ex_o  (pc_plus4_ex),
    .rs1_addr_id_o  (rs1_addr_id),
    .rs2_addr_id_o  (rs2_addr_id)
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
      $display("[PASS] %s: 0x%08h", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: got 0x%08h, expected 0x%08h", name, got, expected);
      fail_count++;
    end
  endtask

  task automatic check1(string name, logic got, logic expected);
    if (got === expected) begin
      $display("[PASS] %s: %0b", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: got %0b, expected %0b", name, got, expected);
      fail_count++;
    end
  endtask

  task automatic check5(string name, logic [4:0] got, logic [4:0] expected);
    if (got === expected) begin
      $display("[PASS] %s: %0d", name, got);
      pass_count++;
    end else begin
      $display("[FAIL] %s: got %0d, expected %0d", name, got, expected);
      fail_count++;
    end
  endtask

  // Helper: present an instruction to ID stage and clock it into ID/EX
  task automatic send_instr(logic [31:0] instr, logic [31:0] pc);
    instr_id    = instr;
    pc_id       = pc;
    pc_plus4_id = pc + 32'd4;
    @(posedge clk); #1;
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_decode_stage.vcd");
    $dumpvars(0, tb_decode_stage);

    // Initialize
    rst_n = 0; flush = 0; stall = 0;
    instr_id = 32'h0; pc_id = 32'h0; pc_plus4_id = 32'h4;
    reg_write_wb = 0; rd_wb = 5'd0; result_wb = 32'h0;

    // Reset
    @(posedge clk); #1;
    @(posedge clk); #1;
    rst_n = 1;

    // =============================================
    $display("\n--- First, load registers via WB port ---");
    // =============================================
    // Write x5 = 5, x6 = 3 through the WB write port.
    // Feed NOP (0x00000000) as the instruction so decode is harmless.

    instr_id = 32'h00000013;  // NOP (ADDI x0, x0, 0)
    pc_id = 32'h0; pc_plus4_id = 32'h4;

    reg_write_wb = 1; rd_wb = 5'd5; result_wb = 32'h0000_0005;
    @(posedge clk); #1;

    reg_write_wb = 1; rd_wb = 5'd6; result_wb = 32'h0000_0003;
    @(posedge clk); #1;

    reg_write_wb = 0; rd_wb = 5'd0; result_wb = 32'h0;

    $display("  Registers loaded: x5=5, x6=3");

    // =============================================
    $display("\n--- R-type: ADD x7, x5, x6 ---");
    // =============================================
    // 0x006283B3: opcode=0110011, rd=7, funct3=000, rs1=5, rs2=6, funct7=0000000

    send_instr(32'h006283B3, 32'h0000_0008);

    check1("ADD reg_write",  ctrl_ex.reg_write, 1'b1);
    check1("ADD mem_write",  ctrl_ex.mem_write, 1'b0);
    check1("ADD alu_src",    ctrl_ex.alu_src, 1'b0);    // rs2
    check1("ADD branch",     ctrl_ex.branch, 1'b0);
    check1("ADD jump",       ctrl_ex.jump, 1'b0);
    check("ADD rs1_data (x5=5)", rs1_data_ex, 32'h0000_0005);
    check("ADD rs2_data (x6=3)", rs2_data_ex, 32'h0000_0003);
    check5("ADD rs1_addr", rs1_addr_ex, 5'd5);
    check5("ADD rs2_addr", rs2_addr_ex, 5'd6);
    check5("ADD rd_addr",  rd_addr_ex, 5'd7);
    check("ADD pc", pc_ex, 32'h0000_0008);

    // =============================================
    $display("\n--- I-type: ADDI x5, x0, 5 ---");
    // =============================================
    // 0x00500293: opcode=0010011, rd=5, funct3=000, rs1=0, imm=5

    send_instr(32'h00500293, 32'h0000_0000);

    check1("ADDI alu_src", ctrl_ex.alu_src, 1'b1);     // immediate
    check("ADDI imm_ext (5)", imm_ext_ex, 32'h0000_0005);
    check("ADDI rs1_data (x0=0)", rs1_data_ex, 32'h0);
    check5("ADDI rd_addr", rd_addr_ex, 5'd5);

    // =============================================
    $display("\n--- S-type: SW x7, 0(x0) ---");
    // =============================================
    // 0x00702023: store, mem_write=1, reg_write=0

    send_instr(32'h00702023, 32'h0000_0038);

    check1("SW reg_write (0)", ctrl_ex.reg_write, 1'b0);
    check1("SW mem_write (1)", ctrl_ex.mem_write, 1'b1);
    check1("SW alu_src (imm)", ctrl_ex.alu_src, 1'b1);
    check("SW imm_ext (0)", imm_ext_ex, 32'h0);

    // =============================================
    $display("\n--- Combinational hazard outputs ---");
    // =============================================
    // The rs1_addr_id and rs2_addr_id outputs are combinational
    // (not registered). They reflect the CURRENT instruction in ID.

    instr_id = 32'h006283B3;  // ADD x7, x5, x6
    #1;
    check5("rs1_addr_id (comb, x5)", rs1_addr_id, 5'd5);
    check5("rs2_addr_id (comb, x6)", rs2_addr_id, 5'd6);

    // =============================================
    $display("\n--- Flush: zero control signals ---");
    // =============================================

    // Clock in a real instruction first
    send_instr(32'h006283B3, 32'h0000_000C);  // ADD
    check1("Pre-flush reg_write", ctrl_ex.reg_write, 1'b1);

    // Now flush on next clock edge
    flush = 1;
    @(posedge clk); #1;
    flush = 0;

    check1("Flushed reg_write (0)", ctrl_ex.reg_write, 1'b0);
    check1("Flushed mem_write (0)", ctrl_ex.mem_write, 1'b0);
    check1("Flushed branch (0)",    ctrl_ex.branch, 1'b0);
    check1("Flushed jump (0)",      ctrl_ex.jump, 1'b0);
    check5("Flushed rd_addr (0)",   rd_addr_ex, 5'd0);

    // =============================================
    $display("\n--- Stall: hold ID/EX values ---");
    // =============================================

    // Clock in ADDI x5, x0, 5
    send_instr(32'h00500293, 32'h0000_0000);
    check("Pre-stall imm", imm_ext_ex, 32'h0000_0005);
    check5("Pre-stall rd", rd_addr_ex, 5'd5);

    // Assert stall and feed a different instruction — ID/EX should hold
    stall = 1;
    instr_id = 32'h006283B3;  // Different instruction (ADD)
    pc_id    = 32'h0000_00FF;
    @(posedge clk); #1;

    check("Stalled imm (still 5)",  imm_ext_ex, 32'h0000_0005);
    check5("Stalled rd (still x5)", rd_addr_ex, 5'd5);
    check("Stalled pc (unchanged)", pc_ex, 32'h0000_0000);

    // Release stall — now the new instruction should enter ID/EX
    stall = 0;
    @(posedge clk); #1;

    check5("After stall rd (x7)", rd_addr_ex, 5'd7);
    check("After stall pc",      pc_ex, 32'h0000_00FF);

    // ---- Summary ----
    $display("\n===================================");
    $display("  decode_stage testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_decode_stage
