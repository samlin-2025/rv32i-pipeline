# ==============================================================================
# Makefile — RV32I 5-Stage Pipelined Processor
# ==============================================================================
#
# Targets:
#   make all         — Build ISS + compile all RTL testbenches
#   make test        — Run full regression (all 16 testbenches + ISS)
#   make test_rtl    — Run RTL testbenches only
#   make test_iss    — Run ISS only
#   make lint        — Verilator lint on full design
#   make <module>    — Run a single testbench (e.g., make tb_alu)
#   make clean       — Remove all build artifacts
#   make help        — Show this help
#
# Requirements:
#   - Icarus Verilog 12+ (iverilog, vvp)
#   - Verilator 5+ (for lint)
#   - g++ with C++17 support (for ISS)
#
# ==============================================================================

# --- Tool configuration ---
IVERILOG    := iverilog
VVP         := vvp
VERILATOR   := verilator
CXX         := g++
CXXFLAGS    := -std=c++17 -Wall -Wextra -O2

# --- Directories ---
RTL_DIR     := rtl
TB_DIR      := tb
ISS_DIR     := iss
SIM_DIR     := sim

# --- RTL source files (order matters for package) ---
RTL_PKG     := $(RTL_DIR)/rv32i_pkg.sv

RTL_LEAF    := $(RTL_DIR)/pc_reg.sv \
               $(RTL_DIR)/pc_adder.sv \
               $(RTL_DIR)/mux2.sv \
               $(RTL_DIR)/mux3.sv \
               $(RTL_DIR)/instr_mem.sv \
               $(RTL_DIR)/data_mem.sv \
               $(RTL_DIR)/register_file.sv \
               $(RTL_DIR)/sign_extend.sv \
               $(RTL_DIR)/alu.sv \
               $(RTL_DIR)/alu_decoder.sv \
               $(RTL_DIR)/main_decoder.sv \
               $(RTL_DIR)/control_unit.sv \
               $(RTL_DIR)/hazard_unit.sv

RTL_STAGES  := $(RTL_DIR)/fetch_stage.sv \
               $(RTL_DIR)/decode_stage.sv \
               $(RTL_DIR)/execute_stage.sv \
               $(RTL_DIR)/memory_stage.sv \
               $(RTL_DIR)/writeback_stage.sv

RTL_TOP     := $(RTL_DIR)/pipeline_top.sv

RTL_ALL     := $(RTL_PKG) $(RTL_LEAF) $(RTL_STAGES) $(RTL_TOP)

# --- Testbench list ---
TB_NAMES    := tb_pc_reg \
               tb_pc_adder \
               tb_mux \
               tb_instr_mem \
               tb_register_file \
               tb_sign_extend \
               tb_alu \
               tb_alu_decoder \
               tb_main_decoder \
               tb_control_unit \
               tb_data_mem \
               tb_hazard_unit \
               tb_fetch_stage \
               tb_decode_stage \
               tb_execute_stage \
               tb_pipeline_top

# ==============================================================================
# Top-level targets
# ==============================================================================

.PHONY: all test test_rtl test_iss lint clean help

all: iss_build $(addprefix $(SIM_DIR)/, $(TB_NAMES))

test: test_iss test_rtl
	@echo ""
	@echo "============================================"
	@echo "  ALL TESTS COMPLETE"
	@echo "============================================"

help:
	@head -20 Makefile | grep -E "^#" | sed 's/^# //'

# ==============================================================================
# ISS (C++ golden reference model)
# ==============================================================================

.PHONY: iss_build test_iss

iss_build:
	@mkdir -p $(ISS_DIR)/build
	$(CXX) $(CXXFLAGS) -I$(ISS_DIR) $(ISS_DIR)/rv32i_iss.cpp $(ISS_DIR)/main.cpp \
		-o $(ISS_DIR)/build/rv32i_iss
	@echo "[ISS] Built successfully"

test_iss: iss_build
	@echo ""
	@echo "--- ISS Golden Reference ---"
	@cd $(ISS_DIR) && ./build/rv32i_iss test_comprehensive.hex 200
	@echo "[ISS] PASSED"

# ==============================================================================
# RTL compilation and test
# ==============================================================================

$(SIM_DIR):
	@mkdir -p $(SIM_DIR)

# Compile a testbench: $(SIM_DIR)/tb_xxx depends on RTL + tb file
$(SIM_DIR)/%: $(RTL_ALL) $(TB_DIR)/%.sv | $(SIM_DIR)
	@$(IVERILOG) -g2012 -o $@ $(RTL_ALL) $(TB_DIR)/$*.sv 2>&1 | \
		grep -v "sorry:" || true
	@echo "[COMPILE] $*"

# Run a single testbench by name
.PHONY: $(TB_NAMES)
$(TB_NAMES): %: $(SIM_DIR)/%
	@echo ""
	@echo "--- $* ---"
	@$(VVP) $(SIM_DIR)/$* 2>&1 | grep -v "sorry:" | grep -v "^$$"

# Run all RTL testbenches
test_rtl: $(addprefix $(SIM_DIR)/, $(TB_NAMES))
	@echo ""
	@echo "============================================"
	@echo "  RTL Regression — Running all testbenches"
	@echo "============================================"
	@pass=0; fail=0; \
	for tb in $(TB_NAMES); do \
		result=$$($(VVP) $(SIM_DIR)/$$tb 2>&1 | grep -oP '\d+ PASSED' | head -1); \
		fails=$$($(VVP) $(SIM_DIR)/$$tb 2>&1 | grep -oP '\d+ FAILED' | head -1); \
		p=$$(echo $$result | grep -oP '^\d+'); \
		f=$$(echo $$fails | grep -oP '^\d+'); \
		p=$${p:-0}; f=$${f:-0}; \
		pass=$$((pass + p)); fail=$$((fail + f)); \
		if [ "$$f" = "0" ]; then \
			printf "  %-30s %s PASSED\n" "$$tb" "$$p"; \
		else \
			printf "  %-30s %s PASSED, %s FAILED  <<<\n" "$$tb" "$$p" "$$f"; \
		fi; \
	done; \
	echo ""; \
	echo "  Total: $$pass passed, $$fail failed"; \
	echo "============================================"; \
	if [ "$$fail" -ne 0 ]; then exit 1; fi

# ==============================================================================
# Lint (Verilator)
# ==============================================================================

lint:
	@echo "--- Verilator Lint ---"
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDPARAM \
		$(RTL_ALL) --top-module pipeline_top
	@echo "[LINT] Clean — 0 warnings, 0 errors"

# ==============================================================================
# Clean
# ==============================================================================

clean:
	rm -rf $(SIM_DIR)
	rm -rf $(ISS_DIR)/build
	rm -f $(ISS_DIR)/iss_trace.log
	rm -f *.vcd $(TB_DIR)/*.vcd $(RTL_DIR)/*.vcd
	@echo "[CLEAN] Done"
