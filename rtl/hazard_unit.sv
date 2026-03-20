// ============================================================================
// File:    hazard_unit.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Pipeline hazard detection and resolution unit.
//
//          Handles three types of hazards:
//            1. RAW data hazards → forwarding (zero penalty)
//            2. Load-use hazards → stall 1 cycle + forward (1 cycle penalty)
//            3. Control hazards  → flush (1-2 cycle penalty)
//
//          This module is purely combinational — it observes the current
//          pipeline state and immediately produces the correct control
//          signals. No clock, no state.
//
// ==========================================================================
// FORWARDING LOGIC (RAW data hazards)
// ==========================================================================
//
// Condition: A preceding instruction writes to a register that the current
// EX-stage instruction reads as rs1 or rs2.
//
// Priority: MEM stage (1 cycle old) > WB stage (2 cycles old).
// If both MEM and WB write to the same register, MEM's value is newer.
//
// Forward A (ALU operand A = rs1):
//   FWD_MEM (10): RegWriteM && (RdM != 0) && (RdM == Rs1E)
//   FWD_WB  (01): RegWriteW && (RdW != 0) && (RdW == Rs1E) && !(MEM match)
//   FWD_NONE(00): otherwise
//
// Forward B (ALU operand B = rs2, before alu_src mux):
//   Same logic but comparing against Rs2E.
//
// ==========================================================================
// LOAD-USE STALL LOGIC
// ==========================================================================
//
// Condition: The instruction in EX is a LOAD (result_src == RESULT_MEM),
// and the instruction in ID reads the load's destination as rs1 or rs2.
//
//   lw_stall = ResultSrcE == RESULT_MEM
//              && (RdE == Rs1D || RdE == Rs2D)
//              && RdE != 0
//
// Action: Stall IF and ID for 1 cycle, flush EX (insert bubble).
// After the stall, the load data arrives in WB and is forwarded normally.
//
// ==========================================================================
// CONTROL HAZARD FLUSH LOGIC
// ==========================================================================
//
// Condition: A branch is taken or a jump executes (pc_src_ex = 1).
// The instructions in IF and ID are from the wrong path.
//
// Action: Flush IF/ID and ID/EX registers (zero out all control signals).
// The correct target instruction arrives in IF on the next cycle.
//
// ==========================================================================

module hazard_unit
  import rv32i_pkg::*;
(
  // -- Source registers in ID stage (for load-use detection) --
  input  logic [4:0]  rs1_id_i,
  input  logic [4:0]  rs2_id_i,

  // -- Source registers in EX stage (for forwarding) --
  input  logic [4:0]  rs1_ex_i,
  input  logic [4:0]  rs2_ex_i,

  // -- Destination register and write-enable in EX stage --
  input  logic [4:0]  rd_ex_i,
  input  logic        reg_write_ex_i,
  input  result_src_e result_src_ex_i,    // Detect loads (RESULT_MEM)

  // -- Destination register and write-enable in MEM stage --
  input  logic [4:0]  rd_mem_i,
  input  logic        reg_write_mem_i,

  // -- Destination register and write-enable in WB stage --
  input  logic [4:0]  rd_wb_i,
  input  logic        reg_write_wb_i,

  // -- Branch/jump taken signal from EX stage --
  input  logic        pc_src_ex_i,

  // -- Forwarding mux selects --
  output forward_e    forward_a_ex_o,     // ALU operand A forwarding
  output forward_e    forward_b_ex_o,     // ALU operand B forwarding

  // -- Stall signals --
  output logic        stall_if_o,         // Freeze PC and IF/ID register
  output logic        stall_id_o,         // Freeze ID/EX register

  // -- Flush signals --
  output logic        flush_id_o,         // Zero out IF/ID register
  output logic        flush_ex_o          // Zero out ID/EX register
);

  // --------------------------------------------------------------------------
  // Load-use hazard detection
  // --------------------------------------------------------------------------
  // A load-use hazard exists when:
  //   1. The instruction in EX is a load (its result comes from memory)
  //   2. The instruction in ID needs the load's destination as a source
  //   3. The destination is not x0 (writing to x0 is a no-op)
  //
  // When detected, we stall IF and ID for one cycle and insert a bubble
  // (flush) into EX. After the stall:
  //   - The load moves from EX → MEM (memory read happens)
  //   - The dependent instruction stays in ID
  //   - Next cycle: load moves to WB, dependent enters EX
  //   - WB→EX forwarding delivers the load data with zero additional stall

  logic lw_stall;

  assign lw_stall = (result_src_ex_i == RESULT_MEM)
                  & reg_write_ex_i
                  & (rd_ex_i != 5'd0)
                  & ((rd_ex_i == rs1_id_i) | (rd_ex_i == rs2_id_i));

  // --------------------------------------------------------------------------
  // Forwarding logic — ALU operand A (rs1 in EX stage)
  // --------------------------------------------------------------------------
  // Check MEM stage first (higher priority — more recent instruction).
  // Then check WB stage. If neither matches, no forwarding needed.
  //
  // The (rd != 0) check is critical: if a preceding instruction has rd=x0,
  // its "result" is architecturally 0 (writes to x0 are discarded). We
  // must NOT forward from such an instruction — the register file already
  // returns 0 for x0 reads.

  always_comb begin
    if (reg_write_mem_i && (rd_mem_i != 5'd0) && (rd_mem_i == rs1_ex_i)) begin
      forward_a_ex_o = FWD_MEM;
    end else if (reg_write_wb_i && (rd_wb_i != 5'd0) && (rd_wb_i == rs1_ex_i)) begin
      forward_a_ex_o = FWD_WB;
    end else begin
      forward_a_ex_o = FWD_NONE;
    end
  end

  // --------------------------------------------------------------------------
  // Forwarding logic — ALU operand B (rs2 in EX stage)
  // --------------------------------------------------------------------------
  // Identical logic to operand A, but comparing against rs2.
  //
  // Note: For I-type instructions, rs2 is irrelevant (the ALU uses the
  // immediate instead). But forwarding is harmless in that case — the
  // alu_src mux downstream selects the immediate regardless of what the
  // forwarding mux outputs. We don't need to suppress forwarding for
  // I-type; the mux ordering handles it naturally.

  always_comb begin
    if (reg_write_mem_i && (rd_mem_i != 5'd0) && (rd_mem_i == rs2_ex_i)) begin
      forward_b_ex_o = FWD_MEM;
    end else if (reg_write_wb_i && (rd_wb_i != 5'd0) && (rd_wb_i == rs2_ex_i)) begin
      forward_b_ex_o = FWD_WB;
    end else begin
      forward_b_ex_o = FWD_NONE;
    end
  end

  // --------------------------------------------------------------------------
  // Stall signals
  // --------------------------------------------------------------------------
  // Stall IF and ID on load-use hazard. This freezes:
  //   - The PC register (keeps fetching the same instruction)
  //   - The IF/ID pipeline register (keeps the same instruction in ID)
  //   - The ID/EX register is flushed (see flush_ex below)

  assign stall_if_o = lw_stall;
  assign stall_id_o = lw_stall;

  // --------------------------------------------------------------------------
  // Flush signals
  // --------------------------------------------------------------------------
  // flush_id: Zero out IF/ID register when a branch/jump is taken.
  //   The instruction currently in IF is from the wrong path.
  //
  // flush_ex: Zero out ID/EX register in TWO cases:
  //   1. Branch/jump taken — instruction in ID is from the wrong path
  //   2. Load-use stall — insert a bubble (NOP) into EX so the load
  //      can proceed to MEM without the dependent instruction following
  //
  // Both cases zero out all control signals in the ID/EX register,
  // which effectively turns the instruction into a NOP.

  assign flush_id_o = pc_src_ex_i;
  assign flush_ex_o = pc_src_ex_i | lw_stall;

endmodule : hazard_unit
