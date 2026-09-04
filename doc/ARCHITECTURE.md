# Open Cognitive Core Architecture

## Overview

The Open Cognitive Core Project (OCCP) is a hardware accelerator for Hyperdimensional Computing (HDC) and lightweight neural network operations, designed for FPGA implementation.

## Data Pipeline & Hardware Handshake

The compilation artifacts from **Pocket-LLM** directly feed into the core hardware registers. Below is the precise interaction map:

1. **Pocket-LLM Compiler** processes tensors ➡️ Outputs `compiled_model.bin` (Row-Major format).
2. **Open-Cognitive-Core (C-Driver)** loads the binary ➡️ Streams data directly into the **SRAM Skew Buffers**.

```
+-------------------+     compiled_model.bin     +---------------------------+
|   Pocket-LLM      | -------------------------> |  Open-Cognitive-Core      |
|   Compiler        |  (Row-Major Binary Format) |  (C-Driver / Silicon)     |
|                   |                            |                           |
| - Loads ONNX/     |                            | - occp_bridge.c           |
|   PyTorch models  |                            | - Memory-mapped I/O       |
| - Tiles matrices  |                            | - AXI4-Lite interface     |
| - Quantizes to    |                            |                           |
|   INT8/Float32    |                            | +-----------------------+ |
| - Exports binary  |                            | | SRAM Skew Buffer      | |
+-------------------+                            | | (Cycle delays for     | |
                                                 | |  systolic timing)     | |
                                                 | +----------+------------+ |
                                                 |            |              |
                                                 |            v              |
                                                 | +----------+------------+ |
                                                 | | Systolic Array        | |
                                                 | | (Matrix multiply      | |
                                                 | |  engine)              | |
                                                 | +----------+------------+ |
                                                 |            |              |
                                                 |            v              |
                                                 | +----------+------------+ |
                                                 | | ReLU / Softmax        | |
                                                 | | (Activation units)    | |
                                                 | +-----------------------+ |
                                                 +---------------------------+
```

For the low-level silicon implementation and C-Driver specifications, please refer to the main repository: [Open-Cognitive-Core](https://github.com/mathcode220-math/open-cognitive-core).

## System Architecture

```
+------------------------------------------------------------------+
|                     AXI4-Lite Control Bus                         |
|  (RISC-V / CPU Control Interface)                                |
+------------------------------------------------------------------+
                              |
        +---------------------+---------------------+
        |                                           |
        v                                           v
+-------------------+                   +-------------------+
|   HDC Subsystem   |                   |   ML Subsystem    |
|                   |                   |                   |
|  +-------------+  |                   |  +-------------+  |
|  | N-gram      |  |                   |  | SRAM Skew   |  |
|  | Encoder     |--+                   |  | Buffer      |--+
|  +-------------+  |                   |  +-------------+  |
|        |          |                   |        |          |
|        v          |                   |        v          |
|  +-------------+  |                   |  +-------------+  |
|  | Distance    |  |                   |  | Systolic    |  |
|  | Core        |  |                   |  | Array       |  |
|  +-------------+  |                   |  +-------------+  |
|                   |                   |        |          |
+-------------------+                   |        v          |
                                        |  +-------------+  |
                                        |  | ReLU        |  |
                                        |  +-------------+  |
                                        |        |          |
                                        |        v          |
                                        |  +-------------+  |
                                        |  | Softmax     |  |
                                        |  +-------------+  |
                                        +-------------------+
```

## Module Descriptions

### HDC Subsystem

| Module | Function | Status |
|--------|----------|--------|
| `hdc_ngram_encoder_v3` | Encodes token sequences into hypervectors | Complete |
| `hdc_distance_core_v3` | Computes Hamming distance between HVs | Complete |

### ML Subsystem

| Module | Function | Status |
|--------|----------|--------|
| `sram_skew_buffer` | Cycle delays for systolic timing | Complete |
| `systolic_array_param` | Matrix multiplication engine | Complete |
| `relu_activation` | ReLU activation function | Complete |
| `softmax_core` | Safe softmax with LUT | Fixed v1.0.1 |

### Control & Interface

| Module | Function | Status |
|--------|----------|--------|
| `axi4_lite_core_ctrl` | AXI4-Lite slave interface | Complete |
| `open_cognitive_top` | Top-level integration | Complete |

## License

CERN-OHL-W v2
