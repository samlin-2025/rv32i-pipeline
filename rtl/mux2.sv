// ============================================================================
// File:    mux2.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Parameterized 2-to-1 multiplexer.
//
//          Used throughout the pipeline:
//            - PC mux:      sel=0 → PC+4,  sel=1 → branch target
//            - ALU src B:   sel=0 → rs2,   sel=1 → immediate
//            - Various control path selections
//
//          Parameterized width so a single module definition serves 32-bit
//          data paths, 5-bit register addresses, and any other width needed.
//
// Ports:
//   sel_i    — Select: 0 → port A, 1 → port B
//   a_i      — Input A (selected when sel = 0)
//   b_i      — Input B (selected when sel = 1)
//   y_o      — Output
//
// Convention: "A is the default / common path, B is the override."
//   - PC mux:    A = PC+4 (normal), B = branch target (taken)
//   - ALU src:   A = rs2 (R-type),  B = immediate (I-type)
//   This convention makes the control signal intuitive: 0 = normal, 1 = special.
// ============================================================================

module mux2 #(
  parameter int WIDTH = 32
) (
  input  logic             sel_i,    // Select
  input  logic [WIDTH-1:0] a_i,      // Input A (sel=0)
  input  logic [WIDTH-1:0] b_i,      // Input B (sel=1)
  output logic [WIDTH-1:0] y_o       // Output
);

  assign y_o = sel_i ? b_i : a_i;

endmodule : mux2
