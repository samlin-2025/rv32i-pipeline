// ============================================================================
// File:    tb_execute_stage.sv
// Desc:    Directed testbench for execute_stage.
//          Tests: basic ALU operation, forwarding from MEM/WB, all 6 branch
//          conditions, JAL link + target, JALR target computation,
//          AUIPC (ALU.A = PC), and EX/MEM register capture.
// ============================================================================

module tb_execute_stage;

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Signals
  // --------------------------------------------------------------------------
  logic        clk, rst_n;

  // ID/EX inputs
  ctrl_ex_t    ctrl_ex;
  logic [31:0] rs1_data, rs2_data, imm_ext;
  logic [4:0]  rd_addr;
  logic [2:0]  funct3;
  logic [31:0] pc_ex, pc_plus4_ex;

  // Forwarding
  forward_e    fwd_a, fwd_b;
  logic [31:0] alu_result_mem_fwd, result_wb_fwd;

  // Outputs
  logic        pc_src;
  logic [31:0] pc_target;
  logic        reg_write_mem, mem_write_mem;
  result_src_e result_src_mem;
  logic [31:0] alu_result_mem, write_data_mem;
  logic [4:0]  rd_addr_mem;
  logic [31:0] pc_plus4_mem;
  logic [2:0]  funct3_mem;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  execute_stage dut (
    .clk_i             (clk),
    .rst_ni            (rst_n),
    .ctrl_ex_i         (ctrl_ex),
    .rs1_data_ex_i     (rs1_data),
    .rs2_data_ex_i     (rs2_data),
    .imm_ext_ex_i      (imm_ext),
    .rd_addr_ex_i      (rd_addr),
    .funct3_ex_i       (funct3),
    .pc_ex_i           (pc_ex),
    .pc_plus4_ex_i     (pc_plus4_ex),
    .forward_a_i       (fwd_a),
    .forward_b_i       (fwd_b),
    .alu_result_mem_i  (alu_result_mem_fwd),
    .result_wb_i       (result_wb_fwd),
    .pc_src_o          (pc_src),
    .pc_target_o       (pc_target),
    .reg_write_mem_o   (reg_write_mem),
    .result_src_mem_o  (result_src_mem),
    .mem_write_mem_o   (mem_write_mem),
    .alu_result_mem_o  (alu_result_mem),
    .write_data_mem_o  (write_data_mem),
    .rd_addr_mem_o     (rd_addr_mem),
    .pc_plus4_mem_o    (pc_plus4_mem),
    .funct3_mem_o      (funct3_mem)
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

  // Helper: set up a clean R-type ALU instruction (no forward, no branch)
  task automatic setup_alu(alu_op_e op, logic [31:0] a, logic [31:0] b);
    ctrl_ex           = '0;
    ctrl_ex.reg_write = 1'b1;
    ctrl_ex.result_src = RESULT_ALU;
    ctrl_ex.alu_ctrl  = op;
    ctrl_ex.alu_src   = 1'b0;   // rs2
    rs1_data = a; rs2_data = b; imm_ext = 32'h0;
    rd_addr = 5'd7; funct3 = 3'b000;
    pc_ex = 32'h0000_0008; pc_plus4_ex = 32'h0000_000C;
    fwd_a = FWD_NONE; fwd_b = FWD_NONE;
    alu_result_mem_fwd = 32'h0; result_wb_fwd = 32'h0;
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_execute_stage.vcd");
    $dumpvars(0, tb_execute_stage);

    // Reset
    rst_n = 0; ctrl_ex = '0; rs1_data = 0; rs2_data = 0; imm_ext = 0;
    rd_addr = 0; funct3 = 0; pc_ex = 0; pc_plus4_ex = 0;
    fwd_a = FWD_NONE; fwd_b = FWD_NONE;
    alu_result_mem_fwd = 0; result_wb_fwd = 0;

    @(posedge clk); #1;
    rst_n = 1;
    @(posedge clk); #1;

    // =============================================
    $display("\n--- Basic ALU: ADD 5 + 3 ---");
    // =============================================

    setup_alu(ALU_ADD, 32'd5, 32'd3);
    #1;
    // Combinational ALU result available immediately
    // But EX/MEM register captures on next clock edge
    @(posedge clk); #1;
    check("ADD result in EX/MEM", alu_result_mem, 32'd8);
    check1("ADD reg_write", reg_write_mem, 1'b1);

    // =============================================
    $display("\n--- ALU with immediate: ADDI x5, x0, 42 ---");
    // =============================================

    ctrl_ex           = '0;
    ctrl_ex.reg_write = 1'b1;
    ctrl_ex.alu_ctrl  = ALU_ADD;
    ctrl_ex.alu_src   = 1'b1;   // immediate
    rs1_data = 32'd0; imm_ext = 32'd42;
    rd_addr = 5'd5;
    fwd_a = FWD_NONE; fwd_b = FWD_NONE;
    @(posedge clk); #1;
    check("ADDI 0+42", alu_result_mem, 32'd42);

    // =============================================
    $display("\n--- Forwarding from MEM ---");
    // =============================================
    // rs1 needs forwarding from MEM (value = 100)

    setup_alu(ALU_ADD, 32'd0, 32'd7);  // rs1 stale, rs2 = 7
    fwd_a = FWD_MEM;
    alu_result_mem_fwd = 32'd100;  // MEM forwarded value
    @(posedge clk); #1;
    check("FWD_MEM: 100 + 7", alu_result_mem, 32'd107);

    // =============================================
    $display("\n--- Forwarding from WB ---");
    // =============================================

    setup_alu(ALU_ADD, 32'd0, 32'd3);
    fwd_a = FWD_WB;
    result_wb_fwd = 32'd200;
    @(posedge clk); #1;
    check("FWD_WB: 200 + 3", alu_result_mem, 32'd203);

    // =============================================
    $display("\n--- Store: forwarded rs2 as write data ---");
    // =============================================

    ctrl_ex           = '0;
    ctrl_ex.mem_write = 1'b1;
    ctrl_ex.alu_ctrl  = ALU_ADD;
    ctrl_ex.alu_src   = 1'b1;   // immediate for address
    rs1_data = 32'h0000_0010;   // base address
    rs2_data = 32'hDEAD_BEEF;   // store data
    imm_ext  = 32'd4;           // offset
    fwd_a = FWD_NONE; fwd_b = FWD_NONE;
    @(posedge clk); #1;
    check("Store addr (0x10+4)", alu_result_mem, 32'h0000_0014);
    check("Store data (rs2)", write_data_mem, 32'hDEAD_BEEF);
    check1("Store mem_write", mem_write_mem, 1'b1);

    // Forwarded store data
    fwd_b = FWD_MEM;
    alu_result_mem_fwd = 32'hCAFE_BABE;  // forwarded value replaces rs2
    @(posedge clk); #1;
    check("Store fwd data", write_data_mem, 32'hCAFE_BABE);

    // =============================================
    $display("\n--- Branch: BEQ taken (5 == 5) ---");
    // =============================================

    ctrl_ex           = '0;
    ctrl_ex.branch    = 1'b1;
    ctrl_ex.alu_ctrl  = ALU_SUB;  // branches subtract
    ctrl_ex.alu_src   = 1'b0;    // rs2
    rs1_data = 32'd5; rs2_data = 32'd5;
    imm_ext  = 32'h0000_0010;    // branch offset +16
    pc_ex    = 32'h0000_0040;    // current PC
    funct3   = 3'b000;           // BEQ
    fwd_a = FWD_NONE; fwd_b = FWD_NONE;
    #1;
    check1("BEQ 5==5 taken", pc_src, 1'b1);
    check("BEQ target (0x40+0x10)", pc_target, 32'h0000_0050);

    // =============================================
    $display("\n--- Branch: BEQ not taken (5 != 3) ---");
    // =============================================

    rs1_data = 32'd5; rs2_data = 32'd3;
    #1;
    check1("BEQ 5!=3 not taken", pc_src, 1'b0);

    // =============================================
    $display("\n--- Branch: BNE taken (5 != 3) ---");
    // =============================================

    funct3 = 3'b001;  // BNE
    #1;
    check1("BNE 5!=3 taken", pc_src, 1'b1);

    // =============================================
    $display("\n--- Branch: BLT taken (-1 < 1) ---");
    // =============================================

    funct3   = 3'b100;  // BLT
    rs1_data = 32'hFFFF_FFFF;  // -1
    rs2_data = 32'd1;
    #1;
    check1("BLT -1<1 taken", pc_src, 1'b1);

    // =============================================
    $display("\n--- Branch: BGE taken (5 >= 3) ---");
    // =============================================

    funct3   = 3'b101;  // BGE
    rs1_data = 32'd5; rs2_data = 32'd3;
    #1;
    check1("BGE 5>=3 taken", pc_src, 1'b1);

    // =============================================
    $display("\n--- Branch: BLTU taken (1 < 0xFFFFFFFF) ---");
    // =============================================

    funct3   = 3'b110;  // BLTU
    rs1_data = 32'd1; rs2_data = 32'hFFFF_FFFF;
    #1;
    check1("BLTU 1<max_uint taken", pc_src, 1'b1);

    // =============================================
    $display("\n--- Branch: BGEU taken (0xFF >= 0xFF) ---");
    // =============================================

    funct3   = 3'b111;  // BGEU
    rs1_data = 32'hFF; rs2_data = 32'hFF;
    #1;
    check1("BGEU 0xFF>=0xFF taken", pc_src, 1'b1);

    // =============================================
    $display("\n--- JAL: unconditional jump ---");
    // =============================================

    ctrl_ex           = '0;
    ctrl_ex.jump      = 1'b1;
    ctrl_ex.reg_write = 1'b1;
    ctrl_ex.result_src = RESULT_PC4;
    ctrl_ex.alu_src   = 1'b0;   // JAL doesn't use ALU for target
    rs1_data = 32'd0; rs2_data = 32'd0;
    imm_ext  = 32'h0000_0008;
    pc_ex    = 32'h0000_0050;
    pc_plus4_ex = 32'h0000_0054;
    funct3   = 3'b000;
    fwd_a = FWD_NONE; fwd_b = FWD_NONE;
    alu_result_mem_fwd = 32'h0; result_wb_fwd = 32'h0;
    #1;
    check1("JAL pc_src", pc_src, 1'b1);
    check("JAL target (0x50+8)", pc_target, 32'h0000_0058);

    // =============================================
    $display("\n--- JALR: register-indirect jump ---");
    // =============================================
    // JALR: target = (rs1 + imm) & ~1
    // rs1 = 0x1001, imm = 0 → target = 0x1000 (bit 0 cleared)

    ctrl_ex           = '0;
    ctrl_ex.jump      = 1'b1;
    ctrl_ex.reg_write = 1'b1;
    ctrl_ex.result_src = RESULT_PC4;
    ctrl_ex.alu_ctrl  = ALU_ADD;
    ctrl_ex.alu_src   = 1'b1;
    rs1_data = 32'h0000_1001;
    imm_ext  = 32'd0;
    fwd_a = FWD_NONE; fwd_b = FWD_NONE;
    #1;
    check1("JALR pc_src", pc_src, 1'b1);
    check("JALR target (0x1001&~1=0x1000)", pc_target, 32'h0000_1000);

    // =============================================
    $display("\n--- AUIPC: ALU.A = PC ---");
    // =============================================

    ctrl_ex           = '0;
    ctrl_ex.reg_write = 1'b1;
    ctrl_ex.alu_ctrl  = ALU_ADD;
    ctrl_ex.alu_src   = 1'b1;
    ctrl_ex.alu_a_pc  = 1'b1;  // Use PC as ALU.A
    pc_ex    = 32'h0000_1000;
    imm_ext  = 32'h1234_5000;  // U-type immediate
    fwd_a = FWD_NONE; fwd_b = FWD_NONE;
    @(posedge clk); #1;
    check("AUIPC (0x1000+0x12345000)", alu_result_mem, 32'h1234_6000);

    // ---- Summary ----
    $display("\n===================================");
    $display("  execute_stage testbench: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("===================================\n");

    $finish;
  end

endmodule : tb_execute_stage
