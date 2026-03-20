// ============================================================================
// File:    memory_stage.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Memory (MEM) stage + MEM/WB pipeline register.
//
//          Datapath:
//            - Data memory: read (loads) or write (stores) using ALU result
//              as address and forwarded rs2 as write data.
//            - Pass-through: ALU result, PC+4, and rd flow to MEM/WB register.
//
//          The funct3 field controls memory access width (LB/LH/LW/LBU/LHU
//          for loads, SB/SH/SW for stores). This is passed to data_mem.
//
//          No stall or flush on MEM/WB — by this point, all hazards have
//          been resolved upstream. The MEM/WB register always captures.
//
// Inputs from EX/MEM:
//   reg_write_i, result_src_i, mem_write_i — control signals
//   alu_result_i — ALU result (memory address or computation result)
//   write_data_i — Store data (forwarded rs2)
//   rd_addr_i    — Destination register
//   pc_plus4_i   — PC+4 for JAL/JALR link
//   funct3_i     — Memory access width
//
// Outputs to WB (MEM/WB pipeline register):
//   reg_write_wb_o, result_src_wb_o — control for writeback
//   alu_result_wb_o  — ALU result (pass-through)
//   read_data_wb_o   — Data from memory (loads)
//   rd_addr_wb_o     — Destination register
//   pc_plus4_wb_o    — PC+4 (pass-through)
// ============================================================================

module memory_stage
  import rv32i_pkg::*;
(
  input  logic        clk_i,
  input  logic        rst_ni,

  // From EX/MEM pipeline register
  input  logic        reg_write_i,
  input  result_src_e result_src_i,
  input  logic        mem_write_i,
  input  logic [31:0] alu_result_i,     // Address for loads/stores, result otherwise
  input  logic [31:0] write_data_i,     // Store data (forwarded rs2)
  input  logic [4:0]  rd_addr_i,
  input  logic [31:0] pc_plus4_i,
  input  logic [2:0]  funct3_i,         // Memory access width

  // MEM/WB pipeline register outputs → writeback stage
  output logic        reg_write_wb_o,
  output result_src_e result_src_wb_o,
  output logic [31:0] alu_result_wb_o,
  output logic [31:0] read_data_wb_o,
  output logic [4:0]  rd_addr_wb_o,
  output logic [31:0] pc_plus4_wb_o
);

  // --------------------------------------------------------------------------
  // Data memory
  // --------------------------------------------------------------------------
  // The ALU result is the byte address. For loads, read_data comes back
  // combinationally. For stores, write happens on the rising clock edge.
  // funct3 controls width (byte/half/word) and sign extension (loads).

  logic [31:0] read_data_m;

  data_mem u_data_mem (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .we_i     (mem_write_i),
    .funct3_i (funct3_i),
    .addr_i   (alu_result_i),
    .wd_i     (write_data_i),
    .rd_o     (read_data_m)
  );

  // --------------------------------------------------------------------------
  // MEM/WB Pipeline Register
  // --------------------------------------------------------------------------
  // No flush or stall — this register always updates. By the time an
  // instruction reaches MEM, it's committed (all hazards resolved upstream).

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      reg_write_wb_o  <= 1'b0;
      result_src_wb_o <= RESULT_ALU;
      alu_result_wb_o <= 32'h0;
      read_data_wb_o  <= 32'h0;
      rd_addr_wb_o    <= 5'd0;
      pc_plus4_wb_o   <= 32'h0;
    end else begin
      reg_write_wb_o  <= reg_write_i;
      result_src_wb_o <= result_src_i;
      alu_result_wb_o <= alu_result_i;
      read_data_wb_o  <= read_data_m;
      rd_addr_wb_o    <= rd_addr_i;
      pc_plus4_wb_o   <= pc_plus4_i;
    end
  end

endmodule : memory_stage
