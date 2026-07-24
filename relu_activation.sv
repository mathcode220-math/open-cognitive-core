// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: relu_activation.sv
// Description: Parameterized Signed ReLU Activation Function. Accommodates 2x
//              accumulator bit-width directly from the Systolic Array outputs.
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

module relu_activation #(
    parameter DATA_WIDTH = 16,      // Matches the base bit-width of the computing grid
    parameter ACCUM_WIDTH = 32      // Accumulator width from systolic array (2x DATA_WIDTH)
)(
    input  logic signed [ACCUM_WIDTH-1:0] accum_in,   // Input from PE accumulator
    output logic signed [DATA_WIDTH-1:0] relu_out     // ReLU output (saturated if needed)
);

    // ReLU: max(0, x) - if negative, output zero; otherwise pass through
    always_comb begin
        if (accum_in < 0)
            relu_out = '0;
        else begin
            // Saturate to maximum positive value if overflow
            if (accum_in > {{(ACCUM_WIDTH-DATA_WIDTH){1'b0}}, {DATA_WIDTH{1'b1}}})
                relu_out = '1;  // All ones for signed max positive
            else
                relu_out = accum_in[DATA_WIDTH-1:0];
        end
    end

endmodule
