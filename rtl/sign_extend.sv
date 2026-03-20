// ============================================================================
// File:    sign_extend.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    Immediate generator — extracts and sign-extends the immediate
//          value from all five RV32I instruction formats.
//
//          The RISC-V ISA scatters immediate bits across the 32-bit
//          instruction word in format-specific patterns. This module
//          reassembles them and sign-extends to 32 bits.
//
//          Supported formats:
//            IMM_I (000) — I-type: ADDI, SLTI, loads, JALR, shifts
//            IMM_S (001) — S-type: SB, SH, SW
//            IMM_B (010) — B-type: BEQ, BNE, BLT, BGE, BLTU, BGEU
//            IMM_J (011) — J-type: JAL
//            IMM_U (100) — U-type: LUI, AUIPC
//
// Ports:
//   instr_i    — Full 32-bit instruction
//   imm_src_i  — 3-bit selector from main decoder (imm_src_e enum)
//   imm_ext_o  — 32-bit sign-extended immediate
//
// Cross-validation:
//   This module must produce identical results to the C++ ISS's decode()
//   function for every instruction. The ISS test trace provides ground
//   truth for every immediate value.
// ============================================================================

module sign_extend
  import rv32i_pkg::*;
(
  // Bits [6:0] (opcode) and portions of [14:12] (funct3) and [19:15] (rs1)
  // are not used for immediate extraction — those fields are consumed by
  // the decoder which provides imm_src_i. We accept the full instruction
  // as input for interface simplicity.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0] instr_i,      // Full instruction word
  /* verilator lint_on UNUSEDSIGNAL */
  input  imm_src_e    imm_src_i,    // Immediate format selector
  output logic [31:0] imm_ext_o     // Sign-extended immediate
);

  // --------------------------------------------------------------------------
  // Immediate extraction and sign extension
  // --------------------------------------------------------------------------
  // Each case reassembles the immediate bits from their scattered positions
  // in the instruction word, then sign-extends from the MSB.
  //
  // Notation:  {N{instr_i[31]}} means "replicate the sign bit N times"
  //            This is the sign extension — filling upper bits with the
  //            sign bit to preserve the two's complement value.
  //
  // RISC-V design insight: instr[31] is ALWAYS the sign bit across all
  // formats. This lets the hardware start sign-extending before the
  // format is fully decoded, reducing the critical path through this module.

  always_comb begin
    unique case (imm_src_i)

      // --------------------------------------------------------------------
      // I-type: imm[11:0] = instr[31:20]
      // --------------------------------------------------------------------
      // Used by: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, LB, LH, LW, LBU,
      //          LHU, JALR, SLLI, SRLI, SRAI
      //
      // Layout:  [31]  [30:25]  [24:21]  [20]
      //           ↓      ↓        ↓       ↓
      //         sign  imm[10:5] imm[4:1] imm[0]
      //
      // 12-bit immediate, sign-extended to 32 bits. Range: -2048 to +2047.

      IMM_I: begin
        imm_ext_o = {{20{instr_i[31]}}, instr_i[31:20]};
      end

      // --------------------------------------------------------------------
      // S-type: imm[11:0] = {instr[31:25], instr[11:7]}
      // --------------------------------------------------------------------
      // Used by: SB, SH, SW
      //
      // The immediate is split: upper 7 bits in [31:25], lower 5 bits in
      // [11:7]. This split exists because rs2 occupies bits [24:20] —
      // the immediate has to go around it.
      //
      // Layout:  [31:25]         [11:7]
      //            ↓                ↓
      //         imm[11:5]       imm[4:0]
      //
      // 12-bit immediate, sign-extended. Range: -2048 to +2047.

      IMM_S: begin
        imm_ext_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
      end

      // --------------------------------------------------------------------
      // B-type: imm[12:1] = {instr[31], instr[7], instr[30:25], instr[11:8]}
      // --------------------------------------------------------------------
      // Used by: BEQ, BNE, BLT, BGE, BLTU, BGEU
      //
      // Bit 0 is implicitly 0 (branches are 2-byte aligned). The ISA
      // doesn't encode bit 0, giving one extra bit of range: ±4 KiB.
      //
      // Layout:  [31]  [7]   [30:25]    [11:8]     implicit
      //           ↓     ↓      ↓          ↓           ↓
      //        imm[12] imm[11] imm[10:5] imm[4:1]   imm[0]=0
      //
      // 13-bit immediate (but bit 0 is always 0), sign-extended.
      // Range: -4096 to +4094, always even.
      //
      // Note: the bit ordering looks weird (bit 12 at [31], bit 11 at [7]).
      // This is intentional — it keeps instr[31] as the sign bit (same as
      // all other formats) and minimizes mux cost in the hardware.

      IMM_B: begin
        imm_ext_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                     instr_i[30:25], instr_i[11:8], 1'b0};
      end

      // --------------------------------------------------------------------
      // J-type: imm[20:1] = {instr[31], instr[19:12], instr[20], instr[30:21]}
      // --------------------------------------------------------------------
      // Used by: JAL
      //
      // Bit 0 is implicitly 0 (same as B-type). 21-bit immediate gives
      // ±1 MiB range — enough to reach any function in a typical program.
      //
      // Layout:  [31]    [19:12]    [20]      [30:21]     implicit
      //           ↓        ↓         ↓          ↓            ↓
      //        imm[20]  imm[19:12] imm[11]   imm[10:1]    imm[0]=0
      //
      // The bit scramble looks bizarre but it's optimized so that bits
      // shared with other formats (like [30:25]) are in the same position.
      // This means the hardware muxes are simpler because some wires
      // don't need to be swizzled at all.

      IMM_J: begin
        imm_ext_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                     instr_i[20], instr_i[30:21], 1'b0};
      end

      // --------------------------------------------------------------------
      // U-type: imm[31:12] = instr[31:12], imm[11:0] = 0
      // --------------------------------------------------------------------
      // Used by: LUI, AUIPC
      //
      // The 20-bit immediate occupies the upper 20 bits. Lower 12 bits
      // are zero. No sign extension needed — the immediate IS the upper
      // 32 bits.
      //
      // Layout:  [31:12]                        zeros
      //            ↓                              ↓
      //         imm[31:12]                    imm[11:0] = 0
      //
      // LUI: rd = imm (upper 20 bits, lower 12 zero)
      // AUIPC: rd = PC + imm
      //
      // Combined with ADDI (which adds a 12-bit signed immediate), you
      // can construct any 32-bit constant in two instructions:
      //   LUI  x5, 0x12345       → x5 = 0x12345000
      //   ADDI x5, x5, 0x678     → x5 = 0x12345678

      IMM_U: begin
        imm_ext_o = {instr_i[31:12], 12'b0};
      end

      // --------------------------------------------------------------------
      // Default: output zero (R-type has no immediate)
      // --------------------------------------------------------------------
      default: begin
        imm_ext_o = 32'h0;
      end

    endcase
  end

endmodule : sign_extend
