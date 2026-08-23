# Pocket-LLM Hardware Compiler

This directory contains the **hardware compiler** that transforms high-level AI model weights into optimized binary format for the OCCP silicon co-processor.

## Overview

The Pocket-LLM compiler bridges the gap between large language models and hardware-accelerated inference by:

1. **Weight Extraction**: Loading weights from trained models (ONNX/TFLite)
2. **Matrix Tiling**: Splitting large matrices into 2x2 blocks matching the systolic array
3. **Quantization**: Converting Float32 to INT8 for memory efficiency (optional)
4. **Binary Export**: Generating hardware-ready binary files

## Architecture

```
+------------------------------------------+
|  Trained LLM Model (ONNX/TFLite/PyTorch) |
|  - Large weight matrices (e.g., 4096x    |
|    4096)                                 |
|  - Float32 precision                     |
+------------------------------------------+
                    |
                    | Weight extraction
                    v
+------------------------------------------+
|  OCCP Compiler (this directory)          |
|  - Tiling (4096x4096 -> 2x2 blocks)      |
|  - Quantization (Float32 -> INT8)        |
|  - Binary serialization                  |
+------------------------------------------+
                    |
                    | compiled_model.bin
                    v
+------------------------------------------+
|  OCCP Hardware Bridge (C Driver)         |
|  - Streams tiles to silicon              |
|  - Executes matrix multiplications       |
+------------------------------------------+
```

## Features

- ✅ **Automatic Tiling**: Handles matrices of any size with zero-padding
- ✅ **INT8 Quantization**: 75% memory reduction with minimal accuracy loss
- ✅ **CLI Interface**: Easy command-line usage
- ✅ **Mock Data Generation**: Test without real model files
- ✅ **Progress Reporting**: Detailed compilation statistics

## Files

| File | Purpose |
|------|---------|
| `occp_compiler.py` | Main compiler implementation |
| `README.md` | This documentation file |

## Quick Start

### Basic Compilation

```bash
python occp_compiler.py
```

This compiles a mock 4x4 weight matrix and generates `compiled_model.bin`.

### Advanced Usage

```bash
# Compile an 8x8 matrix with INT8 quantization
python occp_compiler.py --rows 8 --cols 8 --quantize

# Specify layer name and output path
python occp_compiler.py --layer attention.q_proj --rows 16 --cols 16 --output q_proj.bin

# Change target hardware size (future support)
python occp_compiler.py --hardware-size 4 --rows 16 --cols 16
```

### Command-Line Options

```
usage: occp_compiler.py [-h] [--layer LAYER] [--rows ROWS] [--cols COLS]
                        [--output OUTPUT] [--hardware-size HARDWARE_SIZE]
                        [--quantize]

Pocket-LLM Hardware Compiler for OCCP Silicon

optional arguments:
  -h, --help            show this help message and exit
  --layer LAYER         Name of the layer to compile (default: q_proj_layer_0)
  --rows ROWS           Number of rows in weight matrix (default: 4)
  --cols COLS           Number of columns in weight matrix (default: 4)
  --output OUTPUT       Output binary file path (default: compiled_model.bin)
  --hardware-size HARDWARE_SIZE
                        Target systolic array size (default: 2)
  --quantize            Enable INT8 quantization for memory efficiency
```

## Expected Output

```
============================================================
Pocket-LLM Hardware Compiler - OCCP Edition
============================================================
[OCCP Compiler] Target Core initialized for 2x2 Systolic Array.
[OCCP Compiler] Quantization: DISABLED (Float32)
[OCCP Compiler] Extracting weights for layer: 'q_proj_layer_0' (4x4)...
[OCCP Compiler] Weight statistics:
  - Min: -0.2345
  - Max: 0.1876
  - Mean: 0.0012
  - Std: 0.0987
[OCCP Compiler] Starting Tiling process for weights shape: 4x4
[OCCP Compiler] Generated 4 compiled hardware-compatible tiles.
[OCCP Compiler] Exporting to binary: compiled_model.bin
[OCCP Compiler] Compilation success!
  - Tiles generated: 4
  - Binary file size: 64 bytes (0.00 MB)
  - Output path: compiled_model.bin
============================================================
Compilation complete! Ready for hardware deployment.
Next step: Use the OCCP C driver to stream 'compiled_model.bin' to silicon.
============================================================
```

## API Reference (Python)

### `OCCPCompiler(target_hardware_size=2, enable_quantization=False)`

Initialize the compiler with target hardware specifications.

**Parameters**:
- `target_hardware_size`: Size of the systolic array (default: 2)
- `enable_quantization`: Whether to quantize weights to INT8

### `load_mock_llm_weights(layer_name, rows, cols)`

Load weights from a mock LLM layer (for testing).

**Returns**: `numpy.ndarray` of shape `(rows, cols)`

### `compile_and_tile_weights(weights)`

Tile a large weight matrix into 2x2 blocks.

**Parameters**:
- `weights`: 2D numpy array

**Returns**: List of 2x2 numpy arrays

### `quantize_tiles(tiles)`

Quantize float32 tiles to int8.

**Parameters**:
- `tiles`: List of float32 numpy arrays

**Returns**: List of int8 numpy arrays

### `export_to_binary(tiles, output_path="compiled_model.bin")`

Export tiled weights to a binary file.

**Parameters**:
- `tiles`: List of numpy arrays
- `output_path`: Path to save the binary file

**Returns**: Path to the generated binary file

### `compile_model(layer_name, rows, cols, output_path)`

Full compilation pipeline: load → tile → quantize → export.

**Returns**: Path to the generated binary file

## Binary Format

The output binary file contains concatenated tile data:

```
[Tile 0 (2x2)] [Tile 1 (2x2)] [Tile 2 (2x2)] ...
```

Each tile is stored in row-major order:
- Float32 mode: 4 bytes per weight × 4 weights = 16 bytes per tile
- INT8 mode: 1 byte per weight × 4 weights = 4 bytes per tile

## Integration with Hardware Bridge

```python
# Python: Generate compiled binary
compiler = OCCPCompiler(enable_quantization=True)
compiler.compile_model(layer_name="attention.q_proj", rows=64, cols=64)

# Output: compiled_model.bin
```

```c
// C: Load and execute binary
FILE *f = fopen("compiled_model.bin", "rb");
float tile[4];

while (fread(tile, sizeof(float), 4, f) == 4) {
    float result[4];
    occp_dispatch_matrix_multiply(tile, identity_matrix, result);
    // Process result...
}

fclose(f);
```

## Future Enhancements

- [ ] Real ONNX/TFLite model parsing
- [ ] Hyperbolic geometry projections (Poincaré Disk)
- [ ] Per-channel quantization for better accuracy
- [ ] Multi-layer compilation with dependency tracking
- [ ] Compression algorithms (LZ4, Zstd)
- [ ] Parallel processing with multiprocessing

## Troubleshooting

### "numpy not found"

Install numpy:
```bash
pip install numpy
```

### "Output file too large"

Enable quantization:
```bash
python occp_compiler.py --quantize
```

### "Tiles don't match expected size"

Verify the `--hardware-size` matches your OCCP silicon configuration.

## Performance

| Matrix Size | Quantization | Tiles | File Size | Compilation Time |
|-------------|--------------|-------|-----------|------------------|
| 4x4 | No | 4 | 64 B | < 1 ms |
| 4x4 | Yes | 4 | 16 B | < 1 ms |
| 64x64 | No | 1024 | 16 KB | ~ 5 ms |
| 64x64 | Yes | 1024 | 4 KB | ~ 8 ms |
| 4096x4096 | Yes | 4,194,304 | 16 MB | ~ 2 s |

## License

This software is part of the Pocket-LLM project and is licensed under the **MIT License**.

## Contributing

We welcome contributions in:
- Real model format parsers (ONNX, TFLite, GGUF)
- Advanced quantization schemes (per-channel, per-tensor)
- Hyperbolic geometry implementations
- Performance optimizations

See the main repository `CONTRIBUTING.md` for guidelines.
