# =============================================================================
# Open Cognitive Core Project - Simulation Makefile
# =============================================================================

RTL_DIR    := ../rtl
TB_DIR     := ../tb
BUILD_DIR  := ./build
TB ?= tb_matrix_multiply_2x2

RTL_SRCS := $(wildcard $(RTL_DIR)/math_core/*.sv) \
            $(wildcard $(RTL_DIR)/memory/*.sv) \
            $(wildcard $(RTL_DIR)/bus/*.sv)
TB_SRCS  := $(TB_DIR)/$(TB).sv

VERILATOR_FLAGS := -Wall --trace --cc --exe --top-module $(TB) -Mdir $(BUILD_DIR)

.PHONY: all verilator clean help

all: verilator

verilator:
mkdir -p $(BUILD_DIR)
verilator $(VERILATOR_FLAGS) $(RTL_SRCS) $(TB_SRCS)
make -C $(BUILD_DIR) -f V$(TB).mk
cd $(BUILD_DIR) && ./V$(TB)

clean:
rm -rf $(BUILD_DIR)

help:
@echo "Usage: make [target] TB=<testbench>"
@echo "Targets: verilator, clean"
