// ============================================================================
// File:    writeback_stage.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Writeback (WB) stage — selects the result to write to the
//          register file.
//
//          This is a pure combinational stage (no pipeline register after
//          it — WB is the last stage). The 3:1 mux selects between:
//            RESULT_ALU (00) — ALU computation result
//            RESULT_MEM (01) — Data memory read value (loads)
//            RESULT_PC4 (10) — PC + 4 (JAL/JALR link address)
//
//          The selected result, along with reg_write and rd_addr from
//          MEM/WB, is fed back to the register file in the decode stage.
//
// Inputs from MEM/WB:
//   result_src_i   — Mux select
//   alu_result_i   — ALU result
//   read_data_i    — Memory read data
//   pc_plus4_i     — PC + 4
//
// Output:
//   result_o       — Selected value for register file write
// ============================================================================

module writeback_stage
  import rv32i_pkg::*;
(
  input  result_src_e result_src_i,    // Mux select
  input  logic [31:0] alu_result_i,    // From ALU (R/I-type, LUI, AUIPC)
  input  logic [31:0] read_data_i,     // From data memory (loads)
  input  logic [31:0] pc_plus4_i,      // PC + 4 (JAL/JALR link)
  output logic [31:0] result_o         // Selected result → register file
);

  // --------------------------------------------------------------------------
  // Writeback mux
  // --------------------------------------------------------------------------
  mux3 #(.WIDTH(32)) u_wb_mux (
    .sel_i (result_src_i),
    .a_i   (alu_result_i),    // sel=00: ALU result
    .b_i   (read_data_i),     // sel=01: memory read
    .c_i   (pc_plus4_i),      // sel=10: PC + 4
    .y_o   (result_o)
  );

endmodule : writeback_stage
