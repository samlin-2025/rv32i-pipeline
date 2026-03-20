// ============================================================================
// File:    fetch_stage.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Instruction Fetch (IF) stage + IF/ID pipeline register.
//
//          Datapath:
//            PC mux → PC register → Instruction Memory (parallel with)
//                                 → PC + 4 Adder
//            All three outputs (instruction, PC, PC+4) captured by the
//            IF/ID pipeline register on the rising clock edge.
//
//          Hazard control:
//            stall_i  — Hold PC and IF/ID register (load-use hazard)
//            flush_i  — Zero IF/ID register outputs (branch/jump taken)
//
//          The PC mux selects between:
//            pc_src_i = 0 → PC + 4 (sequential fetch)
//            pc_src_i = 1 → pc_target_i (branch/jump target from EX stage)
//
// Inputs:
//   clk_i, rst_ni      — Clock and reset
//   stall_i             — Freeze PC and IF/ID register
//   flush_i             — Zero out IF/ID register
//   pc_src_i            — PC mux select (0=PC+4, 1=target)
//   pc_target_i         — Branch/jump target address from EX stage
//
// Outputs (IF/ID pipeline register → decode stage):
//   instr_id_o          — 32-bit instruction
//   pc_id_o             — PC of this instruction
//   pc_plus4_id_o       — PC + 4 (for JAL/JALR link address)
// ============================================================================

module fetch_stage
  import rv32i_pkg::*;
#(
  parameter IMEM_INIT_FILE = "memfile.hex"
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Hazard control
  input  logic        stall_i,        // Freeze (load-use stall)
  input  logic        flush_i,        // Flush IF/ID (branch taken)

  // PC control from execute stage
  input  logic        pc_src_i,       // 0 = PC+4, 1 = branch target
  input  logic [31:0] pc_target_i,    // Branch/jump target address

  // IF/ID pipeline register outputs → decode stage
  output logic [31:0] instr_id_o,     // Instruction
  output logic [31:0] pc_id_o,        // PC of instruction
  output logic [31:0] pc_plus4_id_o   // PC + 4
);

  // --------------------------------------------------------------------------
  // Internal wires — IF stage combinational signals
  // --------------------------------------------------------------------------
  logic [31:0] pc_next;     // Output of PC mux (next PC to load)
  logic [31:0] pc_f;        // Current PC (output of PC register)
  logic [31:0] pc_plus4_f;  // PC + 4 (from adder)
  logic [31:0] instr_f;     // Instruction (from instruction memory)

  // --------------------------------------------------------------------------
  // PC mux: select next PC
  // --------------------------------------------------------------------------
  // sel = 0 → PC + 4 (sequential)
  // sel = 1 → branch/jump target (redirect)
  mux2 #(.WIDTH(32)) u_pc_mux (
    .sel_i (pc_src_i),
    .a_i   (pc_plus4_f),    // Default: next sequential instruction
    .b_i   (pc_target_i),   // Override: branch/jump target
    .y_o   (pc_next)
  );

  // --------------------------------------------------------------------------
  // PC register: holds current fetch address
  // --------------------------------------------------------------------------
  // Enable is inverted stall: when stalled, PC holds its value.
  // This is the key load-use stall mechanism — the same instruction
  // stays in IF for an extra cycle while the load completes in MEM.
  pc_reg u_pc_reg (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .en_i      (~stall_i),   // Stall freezes the PC
    .pc_next_i (pc_next),
    .pc_o      (pc_f)
  );

  // --------------------------------------------------------------------------
  // Instruction memory: combinational read
  // --------------------------------------------------------------------------
  instr_mem #(
    .DEPTH     (IMEM_DEPTH),
    .INIT_FILE (IMEM_INIT_FILE)
  ) u_instr_mem (
    .addr_i   (pc_f),
    .instr_o  (instr_f)
  );

  // --------------------------------------------------------------------------
  // PC + 4 adder
  // --------------------------------------------------------------------------
  pc_adder u_pc_plus4 (
    .a_i   (pc_f),
    .b_i   (32'd4),
    .sum_o (pc_plus4_f)
  );

  // --------------------------------------------------------------------------
  // IF/ID Pipeline Register
  // --------------------------------------------------------------------------
  // Captures instruction, PC, and PC+4 for the decode stage.
  //
  // Priority: reset > flush > stall > normal update
  //
  // Flush: Zeros all outputs. This happens when a branch is taken —
  //   the instruction we just fetched is from the wrong path and must
  //   be replaced with a NOP (all zeros → the decode stage sees opcode
  //   0000000 which hits the default case and produces no writes).
  //
  // Stall: Holds current values. The decode stage keeps processing the
  //   same instruction for another cycle.
  //
  // Normal: Captures the new instruction from IF.

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      instr_id_o    <= 32'h0;
      pc_id_o       <= 32'h0;
      pc_plus4_id_o <= 32'h0;
    end else if (flush_i) begin
      // Branch taken: instruction in IF is wrong path → NOP
      instr_id_o    <= 32'h0;
      pc_id_o       <= 32'h0;
      pc_plus4_id_o <= 32'h0;
    end else if (!stall_i) begin
      // Normal operation: capture IF outputs
      instr_id_o    <= instr_f;
      pc_id_o       <= pc_f;
      pc_plus4_id_o <= pc_plus4_f;
    end
    // else: stall — hold current values (implicit, no assignment)
  end

endmodule : fetch_stage
