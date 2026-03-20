# RV32I 5-Stage Pipelined Processor

A fully verified, industry-style 5-stage pipelined RISC-V processor implementing the **RV32I Base Integer Instruction Set**, written in **SystemVerilog** with a **C++ golden reference model** (ISS).

**302 tests passing** across 16 testbenches. RTL output verified bit-for-bit against the ISS.

## Features

**Full RV32I coverage** — all 40 base integer instructions including R-type, I-type, loads (LB/LH/LW/LBU/LHU), stores (SB/SH/SW), all 6 branch conditions (BEQ/BNE/BLT/BGE/BLTU/BGEU), JAL, JALR, LUI, and AUIPC.

**Complete hazard resolution** — MEM→EX and WB→EX data forwarding with correct priority, load-use stall with automatic bubble insertion, and branch/jump flush for IF and ID stages.

**Industry SystemVerilog style** — `always_ff`/`always_comb` separation, `typedef enum` for all control signals, `struct packed` control bundles through pipeline registers, synchronous reset, active-low naming conventions (`rst_ni`, `_i`/`_o` suffixes), and lint-clean under Verilator with `-Wall`.

**C++ Instruction Set Simulator** — a standalone golden reference model that executes the same hex programs as the RTL, producing a per-instruction trace log for comparison. Designed for later integration as a UVM DPI-C scoreboard.

## Quick Start

**Prerequisites:** Icarus Verilog 12+, Verilator 5+ (for lint), g++ with C++17.

```bash
# Clone
git clone https://github.com/<your-username>/rv32i-pipeline.git
cd rv32i-pipeline

# Run full regression (ISS + all 16 RTL testbenches)
make test

# Lint the full design
make lint

# Run a single testbench
make tb_alu
make tb_pipeline_top

# Build and run the ISS independently
make test_iss

# Clean all build artifacts
make clean
```

## Architecture

```
 IF          ID          EX          MEM         WB
┌─────┐    ┌─────┐    ┌─────┐    ┌─────┐    ┌─────┐
│ PC  │    │Ctrl │    │ FwdA│    │Data │    │ Mux │
│IMEM │───▶│RegF │───▶│ FwdB│───▶│ Mem │───▶│ 3:1 │──▶ RegFile
│ +4  │    │ Ext │    │ ALU │    │     │    │     │
└──┬──┘    └──┬──┘    └──┬──┘    └──┬──┘    └─────┘
 IF/ID      ID/EX      EX/MEM     MEM/WB
   ▲          ▲          │          │          │
   └──────────┴──────────┴──────────┴──────────┘
                    Hazard Unit
              (forward / stall / flush)
```

The processor resolves hazards as follows:

| Hazard | Mechanism | Penalty |
|--------|-----------|---------|
| RAW (register-register) | Forwarding from MEM or WB | 0 cycles |
| Load-use | Stall IF/ID + bubble in EX, then forward | 1 cycle |
| Control (branch/jump) | Flush IF/ID and ID/EX | 2 cycles (taken branch) |

For full details including the control signal truth table and branch resolution logic, see [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md).

## Project Structure

```
rv32i-pipeline/
├── rtl/                        SystemVerilog source (20 modules)
│   ├── rv32i_pkg.sv               Shared package (enums, types, params)
│   ├── pc_reg.sv                  Program counter with stall support
│   ├── pc_adder.sv                32-bit adder (PC+4, branch target)
│   ├── mux2.sv                    Parameterized 2:1 multiplexer
│   ├── mux3.sv                    Parameterized 3:1 multiplexer
│   ├── instr_mem.sv               Instruction memory (ROM, $readmemh)
│   ├── data_mem.sv                Data memory (byte/half/word, little-endian)
│   ├── register_file.sv           32×32 regfile with write-through
│   ├── sign_extend.sv             Immediate generator (I/S/B/J/U)
│   ├── alu.sv                     ALU (11 operations, overflow-correct SLT)
│   ├── alu_decoder.sv             ALU control decoder (funct3/funct7)
│   ├── main_decoder.sv            Main control decoder (opcode)
│   ├── control_unit.sv            Two-level decode wrapper
│   ├── hazard_unit.sv             Forwarding + stall + flush logic
│   ├── fetch_stage.sv             IF stage + IF/ID pipeline register
│   ├── decode_stage.sv            ID stage + ID/EX pipeline register
│   ├── execute_stage.sv           EX stage + EX/MEM pipeline register
│   ├── memory_stage.sv            MEM stage + MEM/WB pipeline register
│   ├── writeback_stage.sv         WB stage (3:1 result mux)
│   └── pipeline_top.sv            Top-level processor
├── tb/                         Directed testbenches (16 files)
│   ├── tb_pc_reg.sv               9 tests: reset, update, stall
│   ├── tb_pc_adder.sv             8 tests: add, overflow, negative offset
│   ├── tb_mux.sv                  14 tests: mux2 + mux3, parameterized
│   ├── tb_instr_mem.sv            10 tests: hex load, alignment, OOB
│   ├── tb_register_file.sv        21 tests: x0 hardwire, write-through
│   ├── tb_sign_extend.sv          21 tests: all 5 immediate formats
│   ├── tb_alu.sv                  37 tests: all ops, SLT overflow edge
│   ├── tb_alu_decoder.sv          24 tests: full funct3 decode table
│   ├── tb_main_decoder.sv         10 tests: all 9 opcodes + default
│   ├── tb_control_unit.sv         16 tests: end-to-end decode chain
│   ├── tb_data_mem.sv             18 tests: byte/half/word, endianness
│   ├── tb_hazard_unit.sv          20 tests: fwd, stall, flush, priority
│   ├── tb_fetch_stage.sv          13 tests: sequential, stall, branch
│   ├── tb_decode_stage.sv         34 tests: decode, register, flush
│   ├── tb_execute_stage.sv        22 tests: ALU, fwd, all 6 branches
│   └── tb_pipeline_top.sv         25 tests: full ISS comparison
├── iss/                        C++ golden reference model
│   ├── rv32i_iss.h                ISS class interface
│   ├── rv32i_iss.cpp              Decode, execute, trace for all RV32I
│   ├── main.cpp                   ISS driver program
│   ├── test_comprehensive.hex     Test program (shared with RTL)
│   └── Makefile                   ISS build
├── doc/
│   └── ARCHITECTURE.md            Microarchitecture reference
├── Makefile                    Top-level build and regression
├── LICENSE                     MIT
└── README.md
```

## Test Results

All 302 assertions pass with zero failures:

```
$ make test_rtl
  tb_pc_reg                      9 PASSED
  tb_pc_adder                    8 PASSED
  tb_mux                         14 PASSED
  tb_instr_mem                   10 PASSED
  tb_register_file               21 PASSED
  tb_sign_extend                 21 PASSED
  tb_alu                         37 PASSED
  tb_alu_decoder                 24 PASSED
  tb_main_decoder                10 PASSED
  tb_control_unit                16 PASSED
  tb_data_mem                    18 PASSED
  tb_hazard_unit                 20 PASSED
  tb_fetch_stage                 13 PASSED
  tb_decode_stage                34 PASSED
  tb_execute_stage               22 PASSED
  tb_pipeline_top                25 PASSED

  Total: 302 passed, 0 failed
```

The integration test (`tb_pipeline_top`) runs a program that exercises all instruction types — R-type ALU, I-type immediates, LUI+ADDI constant construction, SW/LW memory round-trip, a 10-iteration BNE loop, and JAL — then compares every register against the C++ ISS golden reference.

## Design Methodology

The project follows a verification-first development flow:

1. **C++ ISS** built first as the architectural golden reference — defines correct behavior for every instruction before any RTL exists.

2. **Bottom-up RTL construction** — leaf modules (ALU, register file, muxes) built and individually tested before being composed into pipeline stages.

3. **Every module has a directed testbench** — not just "it compiles," but explicit assertions checking expected values for normal operation, edge cases, and error conditions.

4. **ISS-RTL comparison** — the integration test runs the identical hex program through both the ISS and the pipelined RTL, then asserts register-for-register equality.

## Differences from Reference Implementation

This project was inspired by [Varunkumar0610/RISC-V-32I-5-stage-Pipeline-Core](https://github.com/Varunkumar0610/RISC-V-32I-5-stage-Pipeline-Core) (Verilog) and rebuilt from scratch in SystemVerilog with significant architectural improvements:

| Feature | Reference (Verilog) | This Project (SystemVerilog) |
|---------|--------------------|-----------------------------|
| Immediate formats | I, S only | I, S, B, J, U (all five) |
| ALU operations | 5 | 11 (full RV32I) |
| Opcodes supported | R, I, Load, Store, Branch | + JAL, JALR, LUI, AUIPC |
| Branch types | BEQ only (Zero flag) | All 6 (BEQ/BNE/BLT/BGE/BLTU/BGEU) |
| Load-use stall | None | Stall + bubble injection |
| Branch flush | None | IF/ID + ID/EX flush |
| Writeback mux | 2:1 (ALU / memory) | 3:1 (ALU / memory / PC+4) |
| Data memory | Word only, wrong addressing | Byte/half/word, little-endian |
| Register file | No write-through | Write-through forwarding |
| Control encoding | Magic numbers | Enum-typed, struct-bundled |
| Reset style | Asynchronous | Synchronous |
| Signal naming | `wire`/`reg`, non-ANSI ports | `logic`, `always_ff`/`always_comb`, `_i`/`_o` |
| Testing | 1 testbench, no assertions | 16 testbenches, 302 assertions |
| Golden reference | None | C++ ISS with trace logging |

## Roadmap

- [ ] **SVA inline assertions** — formal properties for pipeline invariants (x0 never written, stall/flush mutual exclusion)
- [ ] **Branch predictor** — 2-bit saturating counter BHT + BTB for reduced branch penalty
- [ ] **Performance counters** — cycle count, instruction count, stall/flush counts → IPC measurement
- [ ] **UVM testbench** — constrained-random stimulus with DPI-C ISS scoreboard
- [ ] **Functional coverage** — covergroups for all ALU ops, hazard types, branch outcomes

## References

- [RISC-V Unprivileged ISA Specification v20191213](https://riscv.org/specifications/)
- Harris & Harris, *Digital Design and Computer Architecture: RISC-V Edition*
- Patterson & Hennessy, *Computer Organization and Design: RISC-V Edition*

## License

MIT — see [LICENSE](LICENSE).
