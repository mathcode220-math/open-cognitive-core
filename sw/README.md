# OCCP Software Bridge & Driver Layer

This directory contains the **low-level software interface** that connects high-level AI applications (like Pocket-LLM) to the physical OCCP silicon co-processor.

## Overview

The OCCP co-processor is designed in SystemVerilog and communicates via the **AXI4-Lite** protocol. This software layer provides:

1. **Memory-Mapped I/O (MMIO)**: Direct access to hardware registers
2. **SRAM Buffer Management**: Streaming weights into skew buffers
3. **Hardware Synchronization**: Timeout protection and status polling
4. **Co-Simulation Mode**: Test the full pipeline without physical hardware

## Architecture

```
+------------------------------------------+
|  High-Level AI Application (Pocket-LLM)  |
|  - Model weights                         |
|  - Inference requests                    |
+------------------------------------------+
                    |
                    | float matrices
                    v
+------------------------------------------+
|  OCCP Bridge API (this directory)        |
|  - occp_init()                           |
|  - occp_dispatch_matrix_multiply()       |
|  - occp_reset()                          |
+------------------------------------------+
                    |
                    | AXI4-Lite transactions
                    v
+------------------------------------------+
|  OCCP Silicon Co-Processor (../rtl/)     |
|  - axi4_lite_core_ctrl.sv                |
|  - sram_skew_buffer.sv                   |
|  - systolic_array_param.sv               |
+------------------------------------------+
```

## Files

| File | Purpose |
|------|---------|
| `occp_bridge.h` | Public API header with register definitions |
| `occp_bridge.c` | Driver implementation with simulation support |
| `Makefile` | Build system for compilation and testing |

## Quick Start

### Build the Test Executable

```bash
make
```

This compiles `occp_bridge_test`, which includes a built-in test suite.

### Run the Test

```bash
make test
```

Expected output:
```
=== OCCP Bridge Test Suite ===

[OCCP Bridge] Initializing hardware connection...
[OCCP Bridge] Physical hardware not detected. Running in Co-Simulation Mode.
[OCCP Bridge] Simulation buffers allocated.
[OCCP Bridge] Initialization complete.

Input Matrix A:
  [1.0  2.0]
  [3.0  4.0]

Input Matrix B:
  [5.0  6.0]
  [7.0  8.0]

[OCCP Bridge] Checking hardware status...
[OCCP Bridge] Hardware ready. Streaming weights into SRAM Skew Buffers...
[OCCP Bridge] Data streaming complete. Triggering systolic array...
[OCCP Bridge] Processing neural calculations on silicon...
[OCCP Bridge] Computation complete. Retrieving results...
[OCCP Bridge] Execution complete! Result sent back to application.

Result Matrix C (A x B):
  [19.0  22.0]
  [43.0  50.0]

Expected result:
  [19.0  22.0]
  [43.0  50.0]

=== Test Complete ===
```

## API Reference

### `int occp_init(void)`

Initialize the hardware bridge. Maps memory addresses and sets up communication.

**Returns**: `0` on success, `-1` on failure

### `int occp_dispatch_matrix_multiply(const float *matrix_A, const float *matrix_B, float *matrix_out)`

Execute a 2x2 matrix multiplication on the OCCP co-processor.

**Parameters**:
- `matrix_A`: Input matrix A (flattened array of 4 floats)
- `matrix_B`: Input matrix B (flattened array of 4 floats)
- `matrix_out`: Output matrix (flattened array of 4 floats)

**Returns**: `0` on success, `-1` on timeout or error

### `int occp_reset(void)`

Reset the co-processor to idle state and clear all buffers.

**Returns**: `0` on success, `-1` on error

### `int occp_is_hardware_available(void)`

Check if physical hardware is detected.

**Returns**: `1` if hardware present, `0` if running in simulation mode

## Memory Map

| Address | Register | Description |
|---------|----------|-------------|
| `0x40000000` | Control | Start/Reset commands |
| `0x40000004` | Status | Ready/Busy/Done signals |
| `0x40000010` | SRAM A | Matrix input buffer A |
| `0x40000020` | SRAM B | Matrix input buffer B |
| `0x40000030` | SRAM Result | Output buffer |

## Integration with Pocket-LLM

The typical workflow:

1. **Pocket-LLM Compiler** reads model weights and tiles them into 2x2 matrices
2. Compiled weights are saved as `compiled_model.bin`
3. This C driver reads the binary file and calls `occp_dispatch_matrix_multiply()` for each tile
4. Results are streamed back to Pocket-LLM for text generation

## Troubleshooting

### "Hardware timeout! Chip not responding."

This error indicates the co-processor did not respond within `OCCP_TIMEOUT_CYCLES` (10M cycles).

**Possible causes**:
- Hardware is busy with previous computation
- AXI4-Lite interface is misconfigured in RTL
- Clock domain crossing issue in SystemVerilog

**Solution**: Check the RTL simulation logs and verify the `axi4_lite_core_ctrl.sv` module.

### "NULL pointer in matrix arguments."

You passed a NULL pointer to `occp_dispatch_matrix_multiply()`.

**Solution**: Ensure all matrix arrays are properly allocated before calling the function.

## Hardware Implementation

To use with real hardware (FPGA or ASIC):

1. Implement `mmap()` in `occp_init()` to map physical addresses
2. Configure DMA for faster data transfers
3. Add interrupt handling for asynchronous completion
4. Implement power management hooks

## License

This software is part of the Open Cognitive Core Project and is licensed under the **CERN Open Hardware Licence v2 - Weakly Reciprocal (CERN-OHL-W)**.

## Contributing

We welcome contributions in:
- Real hardware support (Linux kernel module with `mmap`)
- DMA (Direct Memory Access) implementation for faster transfers
- Multi-threading support for parallel tile processing
- Integration with real FPGA boards

See the main repository `CONTRIBUTING.md` for guidelines.
