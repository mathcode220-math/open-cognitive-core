// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: sram_skew_buffer.sv
// Description: Parameterized On-Chip SRAM Buffer with an integrated hardware
//              shift-register network to automatically skew data for the
//              Systolic Array edges. Removes timing burdens from the main CPU.
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

module sram_skew_buffer #(
    parameter DATA_WIDTH = 16,        // Bit-width of each data element
    parameter ARRAY_SIZE = 16         // Number of channels matching the array rows/cols
)(
    input  logic                               clk,
    input  logic                               rst_n,   // Asynchronous active-low reset
    input  logic                               en,      // Execution enable for shifting
    input  logic                               wr_en,   // Write enable to load fresh matrix data
    
    // Parallel bus interface to load a full vector row/column from memory
    input  logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] write_data,
    
    // Skewed serial outputs to systolic array
    output logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] skewed_data
);

    genvar i;
    generate
        for (i = 0; i < ARRAY_SIZE; i++) begin : skew_gen
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    skewed_data[i] <= '0;
                else if (wr_en)
                    skewed_data[i] <= write_data[i];
                else if (en && i > 0)
                    skewed_data[i] <= skewed_data[i-1];
            end
        end
    endgenerate

endmodule
