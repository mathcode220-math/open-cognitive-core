// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: hdc_ngram_encoder_v3.sv
// Description: N-gram encoder for HDC using circular shift register
//              - Supports configurable n-gram size (2-4)
//              - Integrated with clear_context for sequence boundaries
//              - Compatible with hdc_distance_core_v3
// Author: OCCP Contributors
// Version: 1.0.0
// License: CERN-OHL-W v2
// =============================================================================
// Copyright (c) 2024 OCCP Contributors
// 
// Licensed under the CERN Open Hardware Licence v2 - Weakly Reciprocal.
// =============================================================================

`ifndef SYNTHESIS
`timescale 1ns/1ps
`endif

module hdc_ngram_encoder_v3 #(
    parameter HV_DIM      = 1024,           // Hypervector dimensionality
    parameter NGRAM_SIZE  = 3,              // N-gram size (2, 3, or 4)
    parameter TOKEN_WIDTH = 16              // Input token width
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,
    input  logic                    clear_context,  // Reset shift register on sequence boundary
    input  logic [TOKEN_WIDTH-1:0]  token_in,       // Current token
    output logic [HV_DIM-1:0]       ngram_hv        // Output N-gram hypervector
);

    // Shift register to hold last N tokens
    localparam NUM_SHIFTS = NGRAM_SIZE - 1;
    logic [TOKEN_WIDTH-1:0] token_shift [0:NUM_SHIFTS-1];
    
    // Circular shift registers for each position in N-gram
    logic [HV_DIM-1:0] shift_reg [0:NUM_SHIFTS-1];
    
    // Generate permutation matrices (circular shifts)
    function automatic logic [HV_DIM-1:0] permute_cw(
        input logic [HV_DIM-1:0] hv,
        input int shift_amount
    );
        return (hv << shift_amount) | (hv >> (HV_DIM - shift_amount));
    endfunction
    
    // Token-to-HV lookup (simple hash-based, replace with learned embeddings if needed)
    function automatic logic [HV_DIM-1:0] token_to_hv(
        input logic [TOKEN_WIDTH-1:0] token
    );
        logic [HV_DIM-1:0] result;
        for (int i = 0; i < HV_DIM; i++) begin
            // Simple XOR hash - replace with proper embedding table for production
            result[i] = ^token[7:0] ^ ^(token >> 8);
        end
        return result;
    endfunction
    
    // Shift register update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear_context) begin
            for (int i = 0; i < NUM_SHIFTS; i++) begin
                token_shift[i] <= '0;
                shift_reg[i]   <= '0;
            end
        end else if (en) begin
            // Shift tokens
            for (int i = NUM_SHIFTS-1; i > 0; i--) begin
                token_shift[i] <= token_shift[i-1];
                shift_reg[i]   <= shift_reg[i-1];
            end
            token_shift[0] <= token_in;
            shift_reg[0]   <= token_to_hv(token_in);
        end
    end
    
    // Bind N-gram using element-wise multiplication (XOR for bipolar)
    // For binary HV: use AND. For bipolar: use XNOR
    always_comb begin
        ngram_hv = token_to_hv(token_in);  // Current token HV
        
        for (int i = 0; i < NUM_SHIFTS; i++) begin
            if (shift_reg[i] != '0) begin
                // Permute by position and bind
                automatic logic [HV_DIM-1:0] permuted;
                permuted = permute_cw(shift_reg[i], (i+1) * 17);  // Prime shift for orthogonality
                ngram_hv = ngram_hv & permuted;  // AND binding for binary HV
            end
        end
    end
    
endmodule
