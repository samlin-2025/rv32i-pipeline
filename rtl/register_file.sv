// ============================================================================
// File:    register_file.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    32×32-bit register file with 2 read ports, 1 write port.
//
//          Architectural properties:
//            - x0 is hardwired to zero (reads always return 0, writes ignored)
//            - Two combinational read ports (rs1, rs2) in decode stage
//            - One synchronous write port (rd) from writeback stage
//            - Internal write-through: if reading and writing the same
//              register on the same clock edge, the read returns the NEW
//              value being written (not the stale stored value)
//
// Ports:
//   clk_i     — System clock
//   rst_ni    — Active-low synchronous reset (zeros all registers)
//
//   -- Write port (from WB stage) --
//   we_i      — Write enable
//   wr_addr_i — Write address (rd from WB)
//   wr_data_i — Write data (result from WB)
//
//   -- Read port 1 (rs1) --
//   rs1_addr_i — Read address 1 (instr[19:15])
//   rs1_data_o — Read data 1
//
//   -- Read port 2 (rs2) --
//   rs2_addr_i — Read address 2 (instr[24:20])
//   rs2_data_o — Read data 2
//
// Write-through forwarding:
//   When we_i=1 and wr_addr_i matches a read address, the read port
//   bypasses the register array and outputs wr_data_i directly. This
//   resolves the WB→ID same-cycle hazard without relying on the
//   external forwarding unit.
//
//   Without this, the ID stage would read the stale value of the register
//   (from before the WB write takes effect), causing a 1-cycle-old result
//   to be used. The forwarding unit could catch this, but handling it
//   internally is cleaner and is standard industry practice.
// ============================================================================

module register_file
  import rv32i_pkg::*;
(
  input  logic        clk_i,
  input  logic        rst_ni,

  // Write port (from writeback stage)
  input  logic        we_i,          // Write enable
  input  logic [4:0]  wr_addr_i,     // Destination register address
  input  logic [31:0] wr_data_i,     // Data to write

  // Read port 1 (rs1)
  input  logic [4:0]  rs1_addr_i,    // Source register 1 address
  output logic [31:0] rs1_data_o,    // Source register 1 data

  // Read port 2 (rs2)
  input  logic [4:0]  rs2_addr_i,    // Source register 2 address
  output logic [31:0] rs2_data_o     // Source register 2 data
);

  // --------------------------------------------------------------------------
  // Register array
  // --------------------------------------------------------------------------
  // 32 registers × 32 bits each. In a real ASIC, this would be a custom
  // SRAM macro or a register file compiler output — not inferred flip-flops.
  // For synthesis on FPGA, the tool infers distributed RAM (LUTs) or
  // block RAM depending on size and access patterns.
  //
  // We declare index [1:31] instead of [0:31] because x0 doesn't need
  // storage — it's hardwired to zero. This saves 32 flip-flops and makes
  // the x0 invariant structurally enforced, not just logically checked.

  logic [31:0] regs [1:31];

  // --------------------------------------------------------------------------
  // Write logic — synchronous, x0-protected
  // --------------------------------------------------------------------------
  // Writes happen on the rising clock edge (from WB stage).
  // x0 protection: we only write if wr_addr != 0. The array index [1:31]
  // also structurally prevents writing to index 0 — belt and suspenders.
  //
  // Reset: All registers zeroed. In a real chip, register file contents
  // are undefined after reset (the software initializer sets them up).
  // We zero them for simulation cleanliness — prevents X-propagation.

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int i = 1; i < 32; i++) begin
        regs[i] <= 32'h0;
      end
    end else if (we_i && (wr_addr_i != 5'd0)) begin
      regs[wr_addr_i] <= wr_data_i;
    end
  end

  // --------------------------------------------------------------------------
  // Read logic — combinational with write-through forwarding
  // --------------------------------------------------------------------------
  // Read port behavior:
  //   1. If reading x0 → always return 0 (hardwired)
  //   2. If reading the same register being written this cycle → return
  //      the WRITE data (forwarding bypass)
  //   3. Otherwise → return the stored value from the register array
  //
  // The write-through check (condition 2) handles the case where WB is
  // writing register N at the exact same time ID is reading register N.
  // Without this bypass, the read would return the pre-write value (stale
  // by one cycle), which is architecturally incorrect.
  //
  // Why `always_comb` instead of `assign`? Because we have if/else
  // branching logic (three conditions). `always_comb` is the correct
  // SystemVerilog construct for combinational blocks with branches.

  always_comb begin
    // Read port 1
    if (rs1_addr_i == 5'd0) begin
      rs1_data_o = 32'h0;
    end else if (we_i && (wr_addr_i == rs1_addr_i)) begin
      rs1_data_o = wr_data_i;    // Write-through bypass
    end else begin
      rs1_data_o = regs[rs1_addr_i];
    end

    // Read port 2
    if (rs2_addr_i == 5'd0) begin
      rs2_data_o = 32'h0;
    end else if (we_i && (wr_addr_i == rs2_addr_i)) begin
      rs2_data_o = wr_data_i;    // Write-through bypass
    end else begin
      rs2_data_o = regs[rs2_addr_i];
    end
  end

endmodule : register_file
