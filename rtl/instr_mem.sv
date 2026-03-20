// ============================================================================
// File:    instr_mem.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Instruction memory — read-only, word-addressed, combinational read.
//
//          Stores the program as an array of 32-bit words. The PC (byte
//          address) is converted to a word index via addr_i[31:2], since
//          all RV32I instructions are 4-byte aligned.
//
//          This is the Harvard-architecture instruction store. In a real
//          SoC, this would be an L1 I-cache. For simulation, it's a simple
//          array loaded from a hex file via $readmemh.
//
// Ports:
//   addr_i   — Byte address from the PC (bits [1:0] ignored)
//   instr_o  — 32-bit instruction at that address
//
// Loading:
//   The hex file path is set via the INIT_FILE parameter. Format is
//   $readmemh compatible:
//     @00000000       — word address (not byte address)
//     00500293        — 32-bit hex instruction
//
// Safety:
//   Out-of-bounds addresses return NOP (ADDI x0, x0, 0 = 0x00000013).
//   This prevents X-propagation if the PC goes wild due to a branch bug.
// ============================================================================

module instr_mem
  import rv32i_pkg::*;
#(
  parameter int    DEPTH     = IMEM_DEPTH,           // Number of 32-bit words
  parameter        INIT_FILE = "memfile.hex"          // Hex file to load
) (
  // Bits [1:0] of addr_i are intentionally unused — RV32I instructions are
  // 4-byte aligned, so these bits are always 00. We accept the full 32-bit
  // PC as input to keep the interface clean (no bit-slicing at instantiation).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0] addr_i,     // Byte address (from PC)
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [31:0] instr_o     // Instruction output
);

  // --------------------------------------------------------------------------
  // Memory array
  // --------------------------------------------------------------------------
  // Each entry is one 32-bit instruction word.
  // DEPTH defaults to 1024 words = 4 KB of instruction space.
  //
  // Style note: In SystemVerilog, unpacked arrays use `logic [31:0] mem [DEPTH]`
  // syntax. The `[DEPTH]` is the unpacked dimension (number of words), and
  // `[31:0]` is the packed dimension (bits per word).

  logic [31:0] mem [DEPTH];

  // --------------------------------------------------------------------------
  // Hex file loading
  // --------------------------------------------------------------------------
  // $readmemh loads at elaboration time (before simulation starts).
  // The hex file uses word addresses: @00000000 means word 0, not byte 0.
  // This matches the original repo's format and our ISS test files.

  initial begin
    // Zero-initialize entire array first. Without this, $readmemh only sets
    // the words listed in the hex file — everything else stays X (unknown).
    // In a real chip, SRAM powers up with random values. For simulation,
    // explicit zeroing prevents X-propagation through the pipeline if the
    // PC ever reads beyond the loaded program.
    for (int i = 0; i < DEPTH; i++) begin
      mem[i] = 32'h0000_0000;
    end
    $readmemh(INIT_FILE, mem);
  end

  // --------------------------------------------------------------------------
  // Combinational read
  // --------------------------------------------------------------------------
  // Convert byte address to word index: drop bits [1:0] (always 00 for
  // aligned 32-bit instructions).
  //
  // Bounds check: if the word index exceeds DEPTH, return NOP instead of
  // reading undefined memory. NOP = ADDI x0, x0, 0 = 0x00000013.
  //
  // Why NOP and not zero? Zero (0x00000000) is an illegal instruction in
  // RV32I — it doesn't map to any valid opcode. NOP is a real instruction
  // that the pipeline processes harmlessly. Using NOP for out-of-bounds
  // means a runaway PC produces a stream of NOPs (safe) rather than
  // undefined behavior.
  //
  // Interview note: Some designs use a dedicated "valid" signal instead of
  // returning NOP. That's cleaner architecturally but adds complexity to
  // every downstream stage (they all need to check valid). For a 5-stage
  // educational pipeline, NOP-fill is the pragmatic choice.

  localparam logic [31:0] NOP = 32'h0000_0013;  // ADDI x0, x0, 0

  // Word index: byte address >> 2. Use $clog2(DEPTH) bits to match array width.
  localparam int ADDR_W = $clog2(DEPTH);

  logic [ADDR_W-1:0] word_idx;
  assign word_idx = addr_i[ADDR_W+1:2];  // Extract just the bits we need

  always_comb begin
    if (addr_i[31:ADDR_W+2] == '0) begin
      // Upper address bits are zero → index is within array bounds
      instr_o = mem[word_idx];
    end else begin
      // Address exceeds memory depth → return NOP
      instr_o = NOP;
    end
  end

endmodule : instr_mem
