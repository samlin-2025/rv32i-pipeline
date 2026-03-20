// ============================================================================
// File:    pc_reg.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Program counter register with synchronous reset and stall support.
//
//          The PC is the address of the instruction being fetched. On each
//          rising clock edge, it either:
//            - Loads `pc_next_i` (normal operation, en_i = 1)
//            - Holds its current value (stall, en_i = 0)
//            - Resets to 0 (rst_ni = 0)
//
//          The enable signal is critical for load-use hazard handling:
//          when a load's destination is needed by the very next instruction,
//          the hazard unit deasserts en_i for one cycle, freezing the PC
//          (and the IF/ID register) so the load has time to complete.
//
// Ports:
//   clk_i     — System clock (rising-edge triggered)
//   rst_ni    — Active-low synchronous reset
//   en_i      — Enable: 1 = update PC, 0 = stall (hold current value)
//   pc_next_i — Next PC value (from PC mux: either PC+4 or branch target)
//   pc_o      — Current PC output (drives instruction memory address)
//
// Reset:     PC resets to 0x00000000 (configurable via parameter).
// Encoding:  Synchronous reset chosen over async for cleaner timing closure
//            and to avoid reset glitches on the instruction memory address bus.
// ============================================================================

module pc_reg
  import rv32i_pkg::*;
#(
  parameter logic [31:0] RESET_ADDR = 32'h0000_0000  // Boot address
) (
  input  logic        clk_i,       // Clock
  input  logic        rst_ni,      // Active-low synchronous reset
  input  logic        en_i,        // Enable (0 = stall)
  input  logic [31:0] pc_next_i,   // Next PC from mux
  output logic [31:0] pc_o         // Current PC to instruction memory
);

  // --------------------------------------------------------------------------
  // PC flip-flop
  // --------------------------------------------------------------------------
  // Style notes for interview discussion:
  //
  //   1. `always_ff` — not `always @(posedge clk)`. This is a SystemVerilog
  //      keyword that tells the synthesis tool "this block MUST infer flip-
  //      flops." If you accidentally write combinational logic inside an
  //      always_ff, the tool errors out instead of silently creating latches.
  //      Verilog's `always @(posedge clk)` has no such safety net.
  //
  //   2. `rst_ni` (active-low, suffix `_ni`) — Industry convention from the
  //      Lowrisc/OpenTitan style guide. The `_n` means active-low, the `_i`
  //      means input. Every signal name tells you its polarity and direction
  //      without reading the port declaration.
  //
  //   3. Synchronous reset (checked inside `posedge clk`) — The original used
  //      async reset (`always @(posedge clk or negedge rst)`). Synchronous
  //      reset is preferred in modern ASIC design because:
  //        - No reset recovery/removal timing violations
  //        - Cleaner STA (static timing analysis) — reset is just another
  //          data input to the flop
  //        - Reset tree is balanced by the clock tree automatically
  //      Apple's design methodology uses synchronous reset.
  //
  //   4. Enable gating (`en_i`) — When deasserted, the flop holds its value.
  //      In real silicon, this would be implemented as a clock-gate or a
  //      mux-based enable. The synthesis tool chooses the optimal implementation.

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pc_o <= RESET_ADDR;
    end else if (en_i) begin
      pc_o <= pc_next_i;
    end
    // else: hold current value (implicit latch-free by always_ff semantics)
  end

endmodule : pc_reg
