// ============================================================================
// File:    pipeline_top.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Top-level module for the 5-stage pipelined RV32I processor.
//
//          Instantiates and wires together:
//            1. Fetch stage     (IF)  — PC, instruction memory, IF/ID reg
//            2. Decode stage    (ID)  — Control unit, register file, sign ext
//            3. Execute stage   (EX)  — ALU, forwarding muxes, branch resolve
//            4. Memory stage    (MEM) — Data memory, MEM/WB reg
//            5. Writeback stage (WB)  — Result mux
//            6. Hazard unit           — Forwarding, stall, flush control
//
//          Signal naming convention:
//            _if, _id, _ex, _mem, _wb suffix indicates which pipeline
//            stage the signal belongs to / originates from.
//
// Ports:
//   clk_i   — System clock
//   rst_ni  — Active-low synchronous reset
// ============================================================================

module pipeline_top
  import rv32i_pkg::*;
#(
  parameter IMEM_INIT_FILE = "memfile.hex"
) (
  input logic clk_i,
  input logic rst_ni
);

  // ==========================================================================
  // Inter-stage wires
  // ==========================================================================

  // ---- IF → ID (IF/ID pipeline register outputs) ----
  logic [31:0] instr_id;
  logic [31:0] pc_id;
  logic [31:0] pc_plus4_id;

  // ---- ID → EX (ID/EX pipeline register outputs) ----
  ctrl_ex_t    ctrl_ex;
  logic [31:0] rs1_data_ex;
  logic [31:0] rs2_data_ex;
  logic [31:0] imm_ext_ex;
  logic [4:0]  rs1_addr_ex;
  logic [4:0]  rs2_addr_ex;
  logic [4:0]  rd_addr_ex;
  logic [2:0]  funct3_ex;
  logic [31:0] pc_ex;
  logic [31:0] pc_plus4_ex;

  // ---- ID → Hazard unit (combinational, not registered) ----
  logic [4:0]  rs1_addr_id;
  logic [4:0]  rs2_addr_id;

  // ---- EX → IF (branch/jump redirect) ----
  logic        pc_src_ex;
  logic [31:0] pc_target_ex;

  // ---- EX → MEM (EX/MEM pipeline register outputs) ----
  logic        reg_write_mem;
  result_src_e result_src_mem;
  logic        mem_write_mem;
  logic [31:0] alu_result_mem;
  logic [31:0] write_data_mem;
  logic [4:0]  rd_addr_mem;
  logic [31:0] pc_plus4_mem;
  logic [2:0]  funct3_mem;

  // ---- MEM → WB (MEM/WB pipeline register outputs) ----
  logic        reg_write_wb;
  result_src_e result_src_wb;
  logic [31:0] alu_result_wb;
  logic [31:0] read_data_wb;
  logic [4:0]  rd_addr_wb;
  logic [31:0] pc_plus4_wb;

  // ---- WB → ID (register file writeback) ----
  logic [31:0] result_wb;

  // ---- Hazard unit outputs ----
  forward_e    forward_a_ex;
  forward_e    forward_b_ex;
  logic        stall_if;
  logic        stall_id;
  logic        flush_id;
  logic        flush_ex;

  // ==========================================================================
  // Stage 1: Instruction Fetch (IF)
  // ==========================================================================
  fetch_stage #(
    .IMEM_INIT_FILE (IMEM_INIT_FILE)
  ) u_fetch (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .stall_i        (stall_if),
    .flush_i        (flush_id),       // Flush IF/ID on branch taken
    .pc_src_i       (pc_src_ex),      // Branch/jump redirect from EX
    .pc_target_i    (pc_target_ex),   // Target address from EX
    .instr_id_o     (instr_id),
    .pc_id_o        (pc_id),
    .pc_plus4_id_o  (pc_plus4_id)
  );

  // ==========================================================================
  // Stage 2: Instruction Decode (ID)
  // ==========================================================================
  decode_stage u_decode (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .flush_i        (flush_ex),       // Flush ID/EX on branch or load-use
    .stall_i        (stall_id),
    .instr_id_i     (instr_id),
    .pc_id_i        (pc_id),
    .pc_plus4_id_i  (pc_plus4_id),
    // WB writeback into register file
    .reg_write_wb_i (reg_write_wb),
    .rd_wb_i        (rd_addr_wb),
    .result_wb_i    (result_wb),
    // ID/EX outputs → EX stage
    .ctrl_ex_o      (ctrl_ex),
    .rs1_data_ex_o  (rs1_data_ex),
    .rs2_data_ex_o  (rs2_data_ex),
    .imm_ext_ex_o   (imm_ext_ex),
    .rs1_addr_ex_o  (rs1_addr_ex),
    .rs2_addr_ex_o  (rs2_addr_ex),
    .rd_addr_ex_o   (rd_addr_ex),
    .funct3_ex_o    (funct3_ex),
    .pc_ex_o        (pc_ex),
    .pc_plus4_ex_o  (pc_plus4_ex),
    // Combinational outputs → hazard unit
    .rs1_addr_id_o  (rs1_addr_id),
    .rs2_addr_id_o  (rs2_addr_id)
  );

  // ==========================================================================
  // Stage 3: Execute (EX)
  // ==========================================================================
  execute_stage u_execute (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .ctrl_ex_i          (ctrl_ex),
    .rs1_data_ex_i      (rs1_data_ex),
    .rs2_data_ex_i      (rs2_data_ex),
    .imm_ext_ex_i       (imm_ext_ex),
    .rd_addr_ex_i       (rd_addr_ex),
    .funct3_ex_i        (funct3_ex),
    .pc_ex_i            (pc_ex),
    .pc_plus4_ex_i      (pc_plus4_ex),
    // Forwarding from hazard unit
    .forward_a_i        (forward_a_ex),
    .forward_b_i        (forward_b_ex),
    // Forwarding data from downstream
    .alu_result_mem_i   (alu_result_mem),
    .result_wb_i        (result_wb),
    // Branch/jump → fetch stage
    .pc_src_o           (pc_src_ex),
    .pc_target_o        (pc_target_ex),
    // EX/MEM outputs → memory stage
    .reg_write_mem_o    (reg_write_mem),
    .result_src_mem_o   (result_src_mem),
    .mem_write_mem_o    (mem_write_mem),
    .alu_result_mem_o   (alu_result_mem),
    .write_data_mem_o   (write_data_mem),
    .rd_addr_mem_o      (rd_addr_mem),
    .pc_plus4_mem_o     (pc_plus4_mem),
    .funct3_mem_o       (funct3_mem)
  );

  // ==========================================================================
  // Stage 4: Memory (MEM)
  // ==========================================================================
  memory_stage u_memory (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .reg_write_i     (reg_write_mem),
    .result_src_i    (result_src_mem),
    .mem_write_i     (mem_write_mem),
    .alu_result_i    (alu_result_mem),
    .write_data_i    (write_data_mem),
    .rd_addr_i       (rd_addr_mem),
    .pc_plus4_i      (pc_plus4_mem),
    .funct3_i        (funct3_mem),
    // MEM/WB outputs → writeback stage
    .reg_write_wb_o  (reg_write_wb),
    .result_src_wb_o (result_src_wb),
    .alu_result_wb_o (alu_result_wb),
    .read_data_wb_o  (read_data_wb),
    .rd_addr_wb_o    (rd_addr_wb),
    .pc_plus4_wb_o   (pc_plus4_wb)
  );

  // ==========================================================================
  // Stage 5: Writeback (WB)
  // ==========================================================================
  writeback_stage u_writeback (
    .result_src_i  (result_src_wb),
    .alu_result_i  (alu_result_wb),
    .read_data_i   (read_data_wb),
    .pc_plus4_i    (pc_plus4_wb),
    .result_o      (result_wb)
  );

  // ==========================================================================
  // Hazard Unit
  // ==========================================================================
  hazard_unit u_hazard (
    // ID stage source registers (combinational)
    .rs1_id_i         (rs1_addr_id),
    .rs2_id_i         (rs2_addr_id),
    // EX stage source/destination registers
    .rs1_ex_i         (rs1_addr_ex),
    .rs2_ex_i         (rs2_addr_ex),
    .rd_ex_i          (rd_addr_ex),
    .reg_write_ex_i   (ctrl_ex.reg_write),
    .result_src_ex_i  (ctrl_ex.result_src),
    // MEM stage destination
    .rd_mem_i         (rd_addr_mem),
    .reg_write_mem_i  (reg_write_mem),
    // WB stage destination
    .rd_wb_i          (rd_addr_wb),
    .reg_write_wb_i   (reg_write_wb),
    // Branch/jump taken
    .pc_src_ex_i      (pc_src_ex),
    // Forwarding outputs
    .forward_a_ex_o   (forward_a_ex),
    .forward_b_ex_o   (forward_b_ex),
    // Stall outputs
    .stall_if_o       (stall_if),
    .stall_id_o       (stall_id),
    // Flush outputs
    .flush_id_o       (flush_id),
    .flush_ex_o       (flush_ex)
  );

endmodule : pipeline_top
