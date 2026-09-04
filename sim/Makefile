# =============================================================================
# Project: Open Cognitive Core Project (OCCP)
# File: Makefile
# Description: Build and simulation makefile for Verilator and XSIM
# License: CERN-OHL-W v2
# =============================================================================

# Tool selection (default to Verilator)
SIM ?= verilator
TOP_MODULE ?= tb_matrix_multiply_2x2

# Directories
RTL_DIR    := ../rtl
TB_DIR     := ../tb
BUILD_DIR  := ./build
OBJ_DIR    := $(BUILD_DIR)/objdir

# Source files
RTL_SRCS := $(wildcard $(RTL_DIR)/math_core/*.sv) \
            $(wildcard $(RTL_DIR)/memory/*.sv) \
            $(wildcard $(RTL_DIR)/hdc/*.sv) \
            $(wildcard $(RTL_DIR)/bus/*.sv) \
            $(wildcard $(RTL_DIR)/top/*.sv)

TB_SRCS  := $(wildcard $(TB_DIR)/*.sv)

# Verilator flags
VERILATOR_FLAGS := -Wall --trace --cc --exe \
                   --Mdir $(OBJ_DIR) \
                   --top-module $(TOP_MODULE) \
                   --timing \
                   -CFLAGS "-std=c++17" \
                   -j

# XSIM flags (Vivado)
XSIM_FLAGS := -nolog -norecompile

.PHONY: all clean verilator xsim help run-verilator

all: verilator

verilator: $(BUILD_DIR)/V$(TOP_MODULE)
	@echo "✓ Simulation binary ready: $(BUILD_DIR)/V$(TOP_MODULE)"

$(BUILD_DIR)/V$(TOP_MODULE): $(RTL_SRCS) $(TB_SRCS)
	@mkdir -p $(BUILD_DIR)
	verilator $(VERILATOR_FLAGS) \
	$(RTL_SRCS) $(TB_SRCS)
	$(MAKE) -C $(OBJ_DIR) -f V$(TOP_MODULE).mk

run-verilator: $(BUILD_DIR)/V$(TOP_MODULE)
	$(BUILD_DIR)/V$(TOP_MODULE)

xsim: 
	@echo "Compiling with XSIM (Vivado)..."
	xvlog $(RTL_SRCS) $(TB_SRCS)
	xelab $(XSIM_FLAGS) $(TOP_MODULE)
	xsim $(TOP_MODULE) $(XSIM_FLAGS)

clean:
	rm -rf $(BUILD_DIR) *.log *.jou xelab.* xsim.dir/ *.wdb

help:
	@echo "Open Cognitive Core Project - Build System"
	@echo "============================================="
	@echo ""
	@echo "Usage:"
	@echo "  make              - Build with Verilator (default)"
	@echo "  make verilator    - Build with Verilator"
	@echo "  make xsim         - Build with XSIM (Vivado)"
	@echo "  make run-verilator - Run Verilator simulation"
	@echo "  make clean        - Remove build artifacts"
	@echo ""
	@echo "Environment Variables:"
	@echo "  SIM=<tool>        - Select simulator (verilator|xsim)"
	@echo "  TOP_MODULE=<name> - Top module for simulation"
	@echo ""
	@echo "Examples:"
	@echo "  make TOP_MODULE=tb_softmax"
	@echo "  make xsim TOP_MODULE=tb_axi4_lite"
