// ============================================================================
// File:    data_mem.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Data memory — read/write, byte-addressable, synchronous write,
//          combinational read with byte/half/word access control.
//
//          Supports all RV32I load/store widths via funct3:
//            LB/SB  (funct3=000) — byte access
//            LH/SH  (funct3=001) — halfword (16-bit) access
//            LW/SW  (funct3=010) — word (32-bit) access
//            LBU    (funct3=100) — byte, zero-extended
//            LHU    (funct3=101) — halfword, zero-extended
//
//          RISC-V is little-endian: the least significant byte of a word
//          is stored at the lowest address. This matches our ISS exactly.
//
// Ports:
//   clk_i      — System clock (writes are synchronous)
//   rst_ni     — Active-low synchronous reset
//   we_i       — Write enable (1 = store)
//   funct3_i   — Access width / sign-extension control (instr[14:12])
//   addr_i     — Byte address (from ALU result)
//   wd_i       — Write data (rs2 value for stores)
//   rd_o       — Read data (for loads, sign/zero extended to 32 bits)
//
// Memory model:
//   Internally stored as a byte array (little-endian) for correct
//   byte/halfword access. In a real ASIC, this would be an SRAM macro
//   with byte write-enable pins. For simulation, a byte array gives
//   exact ISS-matching behavior.
// ============================================================================

module data_mem
  import rv32i_pkg::*;
#(
  parameter int DEPTH = DMEM_DEPTH * 4   // Byte capacity (default 4096 bytes)
) (
  input  logic        clk_i,
  // rst_ni is present for interface consistency across all modules.
  // Memory contents are not reset in hardware (SRAM retains data).
  // The initial block handles simulation-only zero-init.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic        rst_ni,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic        we_i,          // Write enable
  input  logic [2:0]  funct3_i,      // Access width selector
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0] addr_i,        // Byte address
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [31:0] wd_i,          // Write data
  output logic [31:0] rd_o           // Read data
);

  // --------------------------------------------------------------------------
  // Memory array — byte-addressable
  // --------------------------------------------------------------------------
  logic [7:0] mem [DEPTH];

  // Zero-initialize for simulation (prevents X-propagation)
  initial begin
    for (int i = 0; i < DEPTH; i++) begin
      mem[i] = 8'h00;
    end
  end

  // --------------------------------------------------------------------------
  // Address bounds helper
  // --------------------------------------------------------------------------
  // We only use the lower bits needed to index into our array.
  // For a 4096-byte memory, that's 12 bits.
  localparam int ADDR_W = $clog2(DEPTH);
  logic [ADDR_W-1:0] byte_addr;
  assign byte_addr = addr_i[ADDR_W-1:0];

  // --------------------------------------------------------------------------
  // Write logic — synchronous, width-controlled by funct3
  // --------------------------------------------------------------------------
  // SB: write 1 byte at addr
  // SH: write 2 bytes at addr (little-endian: LSB at lower address)
  // SW: write 4 bytes at addr (little-endian)
  //
  // The byte_addr alignment is assumed correct per the RISC-V spec:
  //   SH addresses should be 2-byte aligned (addr[0] = 0)
  //   SW addresses should be 4-byte aligned (addr[1:0] = 00)
  // Misaligned accesses would raise an exception in a real core;
  // we don't implement exceptions, so we just do the access.

  always_ff @(posedge clk_i) begin
    if (we_i) begin
      unique case (funct3_i[1:0])  // Only bits [1:0] determine width
        2'b00: begin  // SB — store byte
          mem[byte_addr] <= wd_i[7:0];
        end
        2'b01: begin  // SH — store halfword (little-endian)
          mem[byte_addr]     <= wd_i[7:0];
          mem[byte_addr + 1] <= wd_i[15:8];
        end
        2'b10: begin  // SW — store word (little-endian)
          mem[byte_addr]     <= wd_i[7:0];
          mem[byte_addr + 1] <= wd_i[15:8];
          mem[byte_addr + 2] <= wd_i[23:16];
          mem[byte_addr + 3] <= wd_i[31:24];
        end
        default: begin
          // funct3[1:0] = 11: not a valid store width, do nothing
        end
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // Read logic — combinational, width + sign-extension controlled by funct3
  // --------------------------------------------------------------------------
  // LB  (000): read 1 byte, sign-extend to 32 bits
  // LH  (001): read 2 bytes (little-endian), sign-extend to 32 bits
  // LW  (010): read 4 bytes (little-endian), no extension
  // LBU (100): read 1 byte, zero-extend to 32 bits
  // LHU (101): read 2 bytes (little-endian), zero-extend to 32 bits
  //
  // The distinction between LB and LBU (and LH vs LHU) is whether the
  // upper bits are filled with the sign bit or zeros. This matters for
  // signed vs unsigned data types in software.

  logic [7:0]  byte_val;
  logic [15:0] half_val;
  logic [31:0] word_val;

  // Assemble raw values from byte array (little-endian)
  assign byte_val = mem[byte_addr];
  assign half_val = {mem[byte_addr + 1], mem[byte_addr]};
  assign word_val = {mem[byte_addr + 3], mem[byte_addr + 2],
                     mem[byte_addr + 1], mem[byte_addr]};

  always_comb begin
    unique case (funct3_i)
      3'b000:  rd_o = {{24{byte_val[7]}}, byte_val};    // LB  — sign-extend
      3'b001:  rd_o = {{16{half_val[15]}}, half_val};    // LH  — sign-extend
      3'b010:  rd_o = word_val;                           // LW  — full word
      3'b100:  rd_o = {24'b0, byte_val};                  // LBU — zero-extend
      3'b101:  rd_o = {16'b0, half_val};                  // LHU — zero-extend
      default: rd_o = word_val;                           // Safety: treat as LW
    endcase
  end

endmodule : data_mem
