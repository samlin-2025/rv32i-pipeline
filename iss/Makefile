# ============================================================================
# Makefile — RV32I ISS (Instruction Set Simulator)
# ============================================================================

CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -O2

ISS_DIR  := .
BUILD    := build
TARGET   := rv32i_iss

SRCS     := $(ISS_DIR)/rv32i_iss.cpp $(ISS_DIR)/main.cpp
HDRS     := $(ISS_DIR)/rv32i_iss.h

# ---- Build -----------------------------------------------------------------
$(TARGET): $(SRCS) $(HDRS)
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) -I$(ISS_DIR) $(SRCS) -o $(BUILD)/$(TARGET)
	@echo "Built: $(BUILD)/$(TARGET)"

# ---- Test ------------------------------------------------------------------
test: $(TARGET)
	$(BUILD)/$(TARGET) test_comprehensive.hex 200

# ---- Clean -----------------------------------------------------------------
clean:
	rm -rf $(BUILD) iss_trace.log

.PHONY: test clean
