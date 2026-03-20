// ============================================================================
// File:    mux3.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Parameterized 3-to-1 multiplexer.
//
//          Primary use: forwarding muxes in the execute stage.
//          Each ALU source operand (A and B) passes through a 3:1 mux
//          that selects between:
//            sel=00  →  Register file value   (no hazard)
//            sel=01  →  Writeback result      (forward from WB stage)
//            sel=10  →  Memory stage result   (forward from MEM stage)
//
//          Also used for the writeback result mux (expanded from original's
//          2:1 to support three sources: ALU result, memory read, PC+4).
//
// Ports:
//   sel_i    — 2-bit select
//   a_i      — Input A (sel=00)  — default / no-hazard path
//   b_i      — Input B (sel=01)  — WB forward / memory read
//   c_i      — Input C (sel=10)  — MEM forward / PC+4
//   y_o      — Output
//
// Safety:   sel=11 outputs zero to avoid propagating X in simulation.
//           In a real design, the hazard unit guarantees sel=11 never occurs,
//           but defensive coding prevents X-propagation in verification.
// ============================================================================

module mux3 #(
  parameter int WIDTH = 32
) (
  input  logic [1:0]       sel_i,    // 2-bit select
  input  logic [WIDTH-1:0] a_i,      // Input A (sel=00)
  input  logic [WIDTH-1:0] b_i,      // Input B (sel=01)
  input  logic [WIDTH-1:0] c_i,      // Input C (sel=10)
  output logic [WIDTH-1:0] y_o       // Output
);

  // --------------------------------------------------------------------------
  // Mux logic
  // --------------------------------------------------------------------------
  // Style note: We use `always_comb` with a `unique case` here instead of a
  // nested ternary. Reasons:
  //
  //   1. `unique case` tells the synthesis tool that all valid cases are
  //      enumerated and exactly one will match. This allows it to optimize
  //      the mux into parallel logic rather than priority-encoded if/else.
  //      For a forwarding mux on the critical path, this matters.
  //
  //   2. If sel_i hits an unenumerated value (11), the `default` fires.
  //      In simulation, `unique` also generates a runtime warning if the
  //      default is reached, helping you catch hazard unit bugs.
  //
  //   3. Readability: a case statement clearly shows "these are the N
  //      options" — easier to review than nested ternaries.

  always_comb begin
    unique case (sel_i)
      2'b00:   y_o = a_i;
      2'b01:   y_o = b_i;
      2'b10:   y_o = c_i;
      default: y_o = '0;   // Safety: should never be reached
    endcase
  end

endmodule : mux3
