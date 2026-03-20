# Microarchitecture Reference

## Pipeline Overview

```
   ┌──────┐    ┌──────┐    ┌──────┐    ┌──────┐    ┌──────┐
   │  IF  │───▶│  ID  │───▶│  EX  │───▶│ MEM  │───▶│  WB  │
   │      │    │      │    │      │    │      │    │      │
   │ PC   │    │ Ctrl │    │ ALU  │    │ Data │    │Result│
   │ IMEM │    │ RegF │    │ Fwd  │    │ Mem  │    │ Mux  │
   │ PC+4 │    │ Ext  │    │ BrEv │    │      │    │      │
   └──┬───┘    └──┬───┘    └──┬───┘    └──┬───┘    └──┬───┘
      │           │           │           │           │
   IF/ID reg   ID/EX reg   EX/MEM reg  MEM/WB reg    │
      ▲           ▲           │           │           │
      │           │           ▼           ▼           ▼
      │           │     ┌──────────────────────────────┐
      │           │     │        Hazard Unit           │
      │           │     │  Forwarding │ Stall │ Flush  │
      │           │     └──────────────────────────────┘
      │           │           │
      ◀───────────◀───────────┘  (stall/flush control)
```

## Supported Instructions (RV32I Base Integer)

| Type    | Instructions                                           |
|---------|--------------------------------------------------------|
| R-type  | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND      |
| I-type  | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI  |
| Load    | LB, LH, LW, LBU, LHU                                  |
| Store   | SB, SH, SW                                             |
| Branch  | BEQ, BNE, BLT, BGE, BLTU, BGEU                        |
| Jump    | JAL, JALR                                              |
| Upper   | LUI, AUIPC                                            |

**Total: 40 instructions** (full RV32I base, excluding FENCE/ECALL/EBREAK/CSR)

## Hazard Resolution

### Data Hazards — Forwarding (Zero Penalty)

```
 Producer in MEM:   EX/MEM.rd == ID/EX.rs1  →  forward_a = FWD_MEM
 Producer in WB:    MEM/WB.rd == ID/EX.rs1  →  forward_a = FWD_WB
 Priority:          MEM > WB (more recent instruction wins)
 x0 protection:     Never forward when rd == x0
```

### Load-Use Hazard — Stall (1-Cycle Penalty)

```
 Condition:  ID/EX.result_src == RESULT_MEM     (instruction in EX is a load)
             AND ID/EX.rd == IF/ID.rs1 or rs2   (next instruction depends on it)
             AND ID/EX.rd != x0

 Action:     stall_if = 1    (freeze PC)
             stall_id = 1    (freeze IF/ID register)
             flush_ex = 1    (insert bubble into ID/EX)

 After stall: Load data available in WB → normal WB forwarding
```

### Control Hazards — Flush (1-2 Cycle Penalty)

```
 Condition:  Branch taken OR JAL OR JALR  (pc_src_ex = 1)

 Action:     flush_id = 1    (zero IF/ID register — wrong-path instr in IF)
             flush_ex = 1    (zero ID/EX register — wrong-path instr in ID)
             PC loads branch/jump target on next cycle
```

## Control Signal Encoding

### ALU Operations (`alu_op_e`, 4-bit)

| Value | Name     | Operation                |
|-------|----------|--------------------------|
| 0000  | ALU_ADD  | A + B                    |
| 0001  | ALU_SUB  | A - B                    |
| 0010  | ALU_AND  | A & B                    |
| 0011  | ALU_OR   | A \| B                   |
| 0100  | ALU_XOR  | A ^ B                    |
| 0101  | ALU_SLT  | (A < B) signed ? 1 : 0   |
| 0110  | ALU_SLTU | (A < B) unsigned ? 1 : 0 |
| 0111  | ALU_SLL  | A << B[4:0]              |
| 1000  | ALU_SRL  | A >> B[4:0] logical      |
| 1001  | ALU_SRA  | A >> B[4:0] arithmetic   |
| 1010  | ALU_LUI  | Pass B through           |

### Main Decoder Truth Table

| Opcode     | reg_wr | result_src | mem_wr | alu_src | imm_src | alu_op | branch | jump | alu_a_pc |
|------------|--------|------------|--------|---------|---------|--------|--------|------|----------|
| R-TYPE     | 1      | ALU        | 0      | rs2     | -       | FUNC   | 0      | 0    | 0        |
| I-TYPE ALU | 1      | ALU        | 0      | imm     | I       | FUNC   | 0      | 0    | 0        |
| LOAD       | 1      | MEM        | 0      | imm     | I       | ADD    | 0      | 0    | 0        |
| STORE      | 0      | -          | 1      | imm     | S       | ADD    | 0      | 0    | 0        |
| BRANCH     | 0      | -          | 0      | rs2     | B       | SUB    | 1      | 0    | 0        |
| JAL        | 1      | PC+4       | 0      | -       | J       | -      | 0      | 1    | 0        |
| JALR       | 1      | PC+4       | 0      | imm     | I       | ADD    | 0      | 1    | 0        |
| LUI        | 1      | ALU        | 0      | imm     | U       | LUI    | 0      | 0    | 0        |
| AUIPC      | 1      | ALU        | 0      | imm     | U       | ADD    | 0      | 0    | 1        |

### Branch Resolution (funct3 → condition)

| funct3 | Branch | Condition                   |
|--------|--------|-----------------------------|
| 000    | BEQ    | zero                        |
| 001    | BNE    | !zero                       |
| 100    | BLT    | negative XOR overflow       |
| 101    | BGE    | !(negative XOR overflow)    |
| 110    | BLTU   | !carry                      |
| 111    | BGEU   | carry                       |
