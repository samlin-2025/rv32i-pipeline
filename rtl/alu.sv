// ============================================================================
// File:    alu.sv
// Author:  Sam Lin
// Date:    2026-03-20
// Desc:    RV32I Arithmetic Logic Unit — executes all base integer operations.
//
//          Supported operations (selected by alu_ctrl_i):
//            ALU_ADD  (0000) — Addition
//            ALU_SUB  (0001) — Subtraction
//            ALU_AND  (0010) — Bitwise AND
//            ALU_OR   (0011) — Bitwise OR
//            ALU_XOR  (0100) — Bitwise XOR
//            ALU_SLT  (0101) — Set if A < B (signed)
//            ALU_SLTU (0110) — Set if A < B (unsigned)
//            ALU_SLL  (0111) — Shift left logical
//            ALU_SRL  (1000) — Shift right logical
//            ALU_SRA  (1001) — Shift right arithmetic
//            ALU_LUI  (1010) — Pass B through (for LUI immediate)
//
//          Status flags (used by branch instructions):
//            zero_o     — Result is zero (BEQ/BNE)
//            negative_o — Result MSB is 1 (sign bit)
//            carry_o    — Unsigned overflow from add/sub
//            overflow_o — Signed overflow from add/sub
//
// Ports:
//   a_i         — Operand A (rs1 value, or forwarded result)
//   b_i         — Operand B (rs2, immediate, or forwarded result)
//   alu_ctrl_i  — Operation select (alu_op_e from rv32i_pkg)
//   result_o    — 32-bit result
//   zero_o      — Result == 0
//   negative_o  — Result[31] == 1
//   carry_o     — Carry/borrow from adder
//   overflow_o  — Signed arithmetic overflow
//
// Critical path:
//   The adder (ADD/SUB) is typically the slowest path. Shifts can also be
//   expensive if implemented as a barrel shifter. In Apple's designs, the
//   ALU is heavily optimized — parallel prefix adders, Booth multipliers
//   (for M-extension), and dedicated shift networks.
// ============================================================================

module alu
  import rv32i_pkg::*;
(
  input  logic [31:0] a_i,          // Operand A
  input  logic [31:0] b_i,          // Operand B
  input  alu_op_e     alu_ctrl_i,   // Operation select

  output logic [31:0] result_o,     // ALU result
  output logic        zero_o,       // Result is zero
  output logic        negative_o,   // Result is negative (MSB)
  output logic        carry_o,      // Carry out (unsigned overflow)
  output logic        overflow_o    // Signed overflow
);

  // --------------------------------------------------------------------------
  // Internal signals
  // --------------------------------------------------------------------------
  // The adder handles both ADD and SUB. For SUB, we invert B and set
  // carry-in to 1, which computes A + (~B) + 1 = A + (-B) = A - B.
  // This is the standard two's complement subtraction trick.
  //
  // We compute the 33-bit sum to capture the carry-out bit.

  logic        sub_flag;     // 1 = subtract, 0 = add
  logic [31:0] b_operand;    // B or ~B depending on sub_flag
  logic [32:0] adder_out;    // 33-bit: {carry, sum}
  logic [31:0] sum;          // Lower 32 bits of adder output
  logic        cout;         // Carry out (bit 32)

  logic [4:0]  shamt;        // Shift amount (lower 5 bits of B)

  // --------------------------------------------------------------------------
  // Adder — shared by ADD, SUB, SLT, SLTU, and branch comparisons
  // --------------------------------------------------------------------------
  // The sub_flag is set for operations that need subtraction:
  //   SUB, SLT, SLTU (explicit subtraction/comparison)
  //
  // For ADD, loads, stores, AUIPC: sub_flag = 0, just add normally.
  //
  // Interview insight: Why share one adder instead of having separate
  // add and subtract units? Area. A 32-bit adder is expensive (hundreds
  // of gates for carry-lookahead). Having two would double the area for
  // the most-used resource. The XOR-and-carry-in trick costs just 32
  // extra XOR gates — trivial.

  assign sub_flag  = (alu_ctrl_i == ALU_SUB)  ||
                     (alu_ctrl_i == ALU_SLT)  ||
                     (alu_ctrl_i == ALU_SLTU);

  assign b_operand = sub_flag ? ~b_i : b_i;
  assign adder_out = {1'b0, a_i} + {1'b0, b_operand} + {32'b0, sub_flag};
  assign sum       = adder_out[31:0];
  assign cout      = adder_out[32];

  // Shift amount: only lower 5 bits of B (per RISC-V spec, §2.4.2)
  assign shamt = b_i[4:0];

  // --------------------------------------------------------------------------
  // Result mux
  // --------------------------------------------------------------------------
  always_comb begin
    unique case (alu_ctrl_i)
      // -- Arithmetic --
      ALU_ADD:  result_o = sum;
      ALU_SUB:  result_o = sum;

      // -- Logic --
      ALU_AND:  result_o = a_i & b_i;
      ALU_OR:   result_o = a_i | b_i;
      ALU_XOR:  result_o = a_i ^ b_i;

      // -- Set less than (signed) --
      // A < B (signed) = negative XOR overflow after computing A - B.
      //
      // Why? Subtraction can overflow. When it does, the sign bit of the
      // result is the *opposite* of what the true comparison would give.
      // XORing with the overflow flag corrects for this.
      //
      // Example where naive sign-bit check fails:
      //   A = 0x7FFFFFFF (max positive), B = 0x80000000 (min negative)
      //   A - B = 0xFFFFFFFF (looks negative, but A > B!)
      //   overflow = 1, negative = 1 → 1 XOR 1 = 0 → not less than ✓
      ALU_SLT:  result_o = {31'b0, sum[31] ^ overflow_o};

      // -- Set less than (unsigned) --
      // A < B (unsigned) = NOT carry-out from A - B.
      //
      // When subtracting unsigned numbers, a borrow occurs (carry-out = 0)
      // if A < B. Our adder computes A + ~B + 1; the carry-out is 1 when
      // A >= B and 0 when A < B. So ~cout gives us the less-than result.
      ALU_SLTU: result_o = {31'b0, ~cout};

      // -- Shifts --
      // SLL: shift left logical, fill with zeros from right
      ALU_SLL:  result_o = a_i << shamt;

      // SRL: shift right logical, fill with zeros from left
      ALU_SRL:  result_o = a_i >> shamt;

      // SRA: shift right arithmetic, fill with sign bit from left.
      // The $signed() cast tells SystemVerilog to use arithmetic shift
      // (>>>) which preserves the sign bit, instead of logical shift (>>)
      // which fills with zeros.
      //
      // Example: 0xF0000000 >>> 4 = 0xFF000000 (sign bit replicated)
      //          0xF0000000 >>  4 = 0x0F000000 (zeros filled — wrong for SRA)
      ALU_SRA:  result_o = $signed(a_i) >>> shamt;

      // -- LUI passthrough --
      // LUI needs to write the immediate directly to rd. The immediate
      // arrives on the B input (from the sign extender). We just pass it
      // through. Operand A is unused (it's rs1, which is x0 for LUI).
      ALU_LUI:  result_o = b_i;

      default:  result_o = 32'h0;
    endcase
  end

  // --------------------------------------------------------------------------
  // Status flags
  // --------------------------------------------------------------------------
  // These flags are computed from the adder output and used by the branch
  // resolution logic in the execute stage.
  //
  // zero_o:     Used by BEQ (branch if equal: A - B == 0 means A == B)
  //             and BNE (branch if not equal: A - B != 0).
  //
  // negative_o: The raw sign bit of the subtraction result. Combined with
  //             overflow_o to determine signed less-than for BLT/BGE.
  //
  // carry_o:    The carry-out from unsigned subtraction. Used for BLTU/BGEU.
  //             carry_o = 1 means A >= B unsigned.
  //
  // overflow_o: Signed overflow. Occurs when adding two positives gives
  //             negative, or adding two negatives gives positive.
  //             Formula: overflow = (A_sign != Sum_sign) AND (A_sign == B_adj_sign)
  //             where B_adj is B for add, ~B for subtract.

  assign zero_o     = (result_o == 32'h0);
  assign negative_o = sum[31];
  assign carry_o    = cout;

  // Signed overflow detection:
  // Overflow occurs when the signs of the operands (after adjusting B for
  // sub) are the same, but the sign of the result differs.
  //   - For ADD: overflow if A>0 + B>0 = negative, or A<0 + B<0 = positive
  //   - For SUB: overflow if A>0 - B<0 = negative, or A<0 - B>0 = positive
  // b_operand already handles the inversion for SUB.
  assign overflow_o = (a_i[31] == b_operand[31]) && (a_i[31] != sum[31]);

endmodule : alu
