// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: matrix_multiply_2x2.sv
// Description: 2x2 Signed Matrix Multiplication Core
//              C = A × B where each element c_ij = sum(a_ik * b_kj) for k=0..1
//              Supports signed 8-bit inputs, produces signed 17-bit outputs
//              to prevent overflow: (-128)*(-128)*2 = 32768 requires 17 bits
// Author: OCCP Contributors
// Version: 1.0.0
// License: CERN Open Hardware Licence v2 - Weakly Reciprocal (CERN-OHL-W)
//          https://ohwr.org/license/CERN-OHL-W
// =============================================================================
// Copyright (c) 2024 OCCP Contributors
// 
// Licensed under the CERN Open Hardware Licence v2 - Weakly Reciprocal.
// You may redistribute and modify this work under the terms of the CERN-OHL-W.
// This work is provided "AS IS" without warranty of any kind.
// =============================================================================

`ifndef SYNTHESIS
`timescale 1ns/1ps
`endif

module matrix_multiply_2x2 #(
    parameter DATA_WIDTH = 8           // Input data width (signed)
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         en,              // Global enable
    
    // Matrix A inputs (2x2 signed)
    input  logic signed [DATA_WIDTH-1:0] a00, a01, a10, a11,
    
    // Matrix B inputs (2x2 signed)
    input  logic signed [DATA_WIDTH-1:0] b00, b01, b10, b11,
    
    // Matrix C outputs (2x2 signed) - 17 bits to prevent overflow
    output logic signed [2*DATA_WIDTH:0] c00, c01, c10, c11,
    
    output logic                         valid            // Output valid handshake
);

    // Internal registers for pipeline stages
    logic signed [2*DATA_WIDTH:0] c00_reg, c01_reg, c10_reg, c11_reg;
    logic valid_reg;
    
    // Matrix multiplication equations:
    // c00 = a00*b00 + a01*b10
    // c01 = a00*b01 + a01*b11
    // c10 = a10*b00 + a11*b10
    // c11 = a10*b01 + a11*b11
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c00_reg <= '0;
            c01_reg <= '0;
            c10_reg <= '0;
            c11_reg <= '0;
            valid_reg <= 1'b0;
        end else if (en) begin
            // Single-cycle combinational multiplication with registered outputs
            c00_reg <= $signed(a00) * $signed(b00) + $signed(a01) * $signed(b10);
            c01_reg <= $signed(a00) * $signed(b01) + $signed(a01) * $signed(b11);
            c10_reg <= $signed(a10) * $signed(b00) + $signed(a11) * $signed(b10);
            c11_reg <= $signed(a10) * $signed(b01) + $signed(a11) * $signed(b11);
            valid_reg <= 1'b1;
        end else begin
            valid_reg <= 1'b0;
        end
    end
    
    // Assign outputs
    assign c00 = c00_reg;
    assign c01 = c01_reg;
    assign c10 = c10_reg;
    assign c11 = c11_reg;
    assign valid = valid_reg;

endmodule
