// ============================================================================
// File:    pc_adder.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Pure combinational 32-bit adder.
//
//          Used in two places in the pipeline:
//            1. Fetch stage:    PC + 4          → next sequential PC
//            2. Execute stage:  PC + immediate  → branch/jump target
//
//          No clock, no state — purely combinational. The synthesis tool
//          will infer a ripple-carry or carry-lookahead adder depending on
//          the target technology and timing constraints.
//
// Ports:
//   a_i     — First operand  (e.g., current PC)
//   b_i     — Second operand (e.g., 32'd4 or sign-extended immediate)
//   sum_o   — Result: a_i + b_i
//
// Critical path note:
//   In the fetch stage, this adder runs in parallel with the instruction
//   memory read. The mux selecting between PC+4 and branch target is
//   downstream of both — so the adder's delay must be less than the
//   memory access time, or it becomes the bottleneck.
// ============================================================================

module pc_adder
  import rv32i_pkg::*;
(
  input  logic [31:0] a_i,     // Operand A (typically PC)
  input  logic [31:0] b_i,     // Operand B (typically 4 or immediate)
  output logic [31:0] sum_o    // Result: A + B
);

  // --------------------------------------------------------------------------
  // Combinational adder
  // --------------------------------------------------------------------------
  // Style note: `always_comb` vs `assign`
  //
  // For a single expression like this, `assign` is perfectly fine and
  // preferred — it's concise and unambiguous. We reserve `always_comb`
  // for blocks with branching logic (if/case). Using always_comb for a
  // single assign would be over-engineering.
  //
  // The synthesis tool sees the same hardware either way. The choice is
  // purely about readability.

  assign sum_o = a_i + b_i;

endmodule : pc_adder
