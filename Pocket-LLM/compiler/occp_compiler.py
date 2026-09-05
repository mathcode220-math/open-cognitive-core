#!/usr/bin/env python3
"""
Pocket-LLM Hardware Compiler for OCCP Silicon
============================================================
Transforms high-level AI model weights into optimized binary format
for the OCCP silicon co-processor.

License: MIT
"""

import argparse
import os
import struct
import sys

# Try importing numpy, or fallback to pure Python lists
try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False


class OCCPCompiler:
    def __init__(self, target_hardware_size=2, enable_quantization=False):
        """
        Initialize the compiler with target hardware specifications.

        :param target_hardware_size: Size of the systolic array (e.g. 2 for 2x2)
        :param enable_quantization: Whether to quantize weights to INT8
        """
        self.hardware_size = target_hardware_size
        self.quantize = enable_quantization
        print(f"[OCCP Compiler] Target Core initialized for {self.hardware_size}x{self.hardware_size} Systolic Array.")
        print(f"[OCCP Compiler] Quantization: {'ENABLED (INT8)' if self.quantize else 'DISABLED (Float32)'}")

    def load_mock_llm_weights(self, layer_name, rows, cols):
        """
        Generates mock Float32 weight matrix for testing.
        """
        print(f"[OCCP Compiler] Extracting weights for layer: '{layer_name}' ({rows}x{cols})...")

        # Deterministic pseudo-random generation based on layer params
        weights = []
        seed = len(layer_name) + rows * 31 + cols * 17
        for r in range(rows):
            row_vals = []
            for c in range(cols):
                seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
                # Map to range [-0.5, 0.5]
                val = ((seed / 0x7FFFFFFF) - 0.5)
                row_vals.append(val)
            weights.append(row_vals)

        # Print statistics
        flat_vals = [v for row in weights for v in row]
        min_v = min(flat_vals)
        max_v = max(flat_vals)
        mean_v = sum(flat_vals) / len(flat_vals)
        variance = sum((x - mean_v) ** 2 for x in flat_vals) / len(flat_vals)
        std_v = variance ** 0.5

        print("[OCCP Compiler] Weight statistics:")
        print(f"  - Min: {min_v:.4f}")
        print(f"  - Max: {max_v:.4f}")
        print(f"  - Mean: {mean_v:.4f}")
        print(f"  - Std: {std_v:.4f}")

        return weights

    def compile_and_tile_weights(self, weights):
        """
        Tiles a large weight matrix into hardware_size x hardware_size blocks (e.g., 2x2).
        Pads with zeros if matrix dimensions are not multiples of hardware_size.
        """
        rows = len(weights)
        cols = len(weights[0]) if rows > 0 else 0

        print(f"[OCCP Compiler] Starting Tiling process for weights shape: {rows}x{cols}")

        pad_rows = (self.hardware_size - (rows % self.hardware_size)) % self.hardware_size
        pad_cols = (self.hardware_size - (cols % self.hardware_size)) % self.hardware_size

        padded_rows = rows + pad_rows
        padded_cols = cols + pad_cols

        # Create padded matrix
        padded_weights = []
        for r in range(padded_rows):
            if r < rows:
                row_vals = list(weights[r]) + [0.0] * pad_cols
            else:
                row_vals = [0.0] * padded_cols
            padded_weights.append(row_vals)

        # Generate tiles
        tiles = []
        for r in range(0, padded_rows, self.hardware_size):
            for c in range(0, padded_cols, self.hardware_size):
                tile = []
                for tr in range(self.hardware_size):
                    tile_row = []
                    for tc in range(self.hardware_size):
                        tile_row.append(padded_weights[r + tr][c + tc])
                    tile.append(tile_row)
                tiles.append(tile)

        print(f"[OCCP Compiler] Generated {len(tiles)} compiled hardware-compatible tiles.")
        return tiles

    def quantize_tiles(self, tiles):
        """
        Quantizes float32 tiles to int8 (range [-128, 127]).
        """
        quantized_tiles = []
        for tile in tiles:
            q_tile = []
            for row in tile:
                q_row = []
                for val in row:
                    # Scale float [-1.0, 1.0] to int8 [-128, 127]
                    scaled = int(round(val * 127.0))
                    clamped = max(-128, min(127, scaled))
                    q_row.append(clamped)
                q_tile.append(q_row)
            quantized_tiles.append(q_tile)
        return quantized_tiles

    def export_to_binary(self, tiles, output_path="compiled_model.bin"):
        """
        Exports tiled weights to a binary file in row-major order.
        """
        print(f"[OCCP Compiler] Exporting to binary: {output_path}")

        with open(output_path, "wb") as f:
            for tile in tiles:
                for row in tile:
                    for val in row:
                        if self.quantize:
                            # Pack int8
                            f.write(struct.pack("b", int(val)))
                        else:
                            # Pack float32
                            f.write(struct.pack("f", float(val)))

        file_size = os.path.getsize(output_path)
        mb_size = file_size / (1024 * 1024)
        print("[OCCP Compiler] Compilation success!")
        print(f"  - Tiles generated: {len(tiles)}")
        print(f"  - Binary file size: {file_size} bytes ({mb_size:.2f} MB)")
        print(f"  - Output path: {output_path}")
        return output_path

    def compile_model(self, layer_name="q_proj_layer_0", rows=4, cols=4, output_path="compiled_model.bin"):
        """
        Full compilation pipeline: load -> tile -> quantize (if enabled) -> export.
        """
        weights = self.load_mock_llm_weights(layer_name, rows, cols)
        tiles = self.compile_and_tile_weights(weights)
        if self.quantize:
            tiles = self.quantize_tiles(tiles)
        return self.export_to_binary(tiles, output_path)


def main():
    parser = argparse.ArgumentParser(description="Pocket-LLM Hardware Compiler for OCCP Silicon")
    parser.add_argument("--layer", type=str, default="q_proj_layer_0", help="Name of the layer to compile")
    parser.add_argument("--rows", type=int, default=4, help="Number of rows in weight matrix")
    parser.add_argument("--cols", type=int, default=4, help="Number of columns in weight matrix")
    parser.add_argument("--output", type=str, default="compiled_model.bin", help="Output binary file path")
    parser.add_argument("--hardware-size", type=int, default=2, help="Target systolic array size")
    parser.add_argument("--quantize", action="store_true", help="Enable INT8 quantization")

    args = parser.parse_args()

    print("=" * 60)
    print("Pocket-LLM Hardware Compiler - OCCP Edition")
    print("=" * 60)

    compiler = OCCPCompiler(
        target_hardware_size=args.hardware_size,
        enable_quantization=args.quantize
    )

    compiler.compile_model(
        layer_name=args.layer,
        rows=args.rows,
        cols=args.cols,
        output_path=args.output
    )

    print("=" * 60)
    print("Compilation complete! Ready for hardware deployment.")
    print(f"Next step: Use the OCCP C driver to stream '{args.output}' to silicon.")
    print("=" * 60)


if __name__ == "__main__":
    main()
