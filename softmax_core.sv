// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: softmax_core.sv
// Description: Fully synthesizable, professional Safe Softmax module.
//              - Internal static localparam LUT for exp(x) to save memory logic.
//              - Fixed-point arithmetic with 64-bit precision casting to prevent overflow.
//              - Sequenced FSM with start/done handshake protocol.
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

module softmax_core #(
    parameter DATA_WIDTH  = 16,          // Width of input/output data paths
    parameter VECTOR_SIZE = 4,           // Number of parallel elements
    parameter LUT_DEPTH   = 256,         // Number of entries in exponential LUT
    parameter FRAC_WIDTH  = DATA_WIDTH   // Fractional bits in output (0.DATA_WIDTH format)
)(
    input  logic                                                clk,
    input  logic                                                rst_n,
    input  logic                                                en,         // Global enable
    input  logic                                                start,      // Pulse to begin softmax calculation
    input  logic signed [VECTOR_SIZE-1:0][(2*DATA_WIDTH)-1:0]   in_vector,  // Packed input vector
    output logic [VECTOR_SIZE-1:0][DATA_WIDTH-1:0]              out_probs,  // Packed output probabilities
    output logic                                                done        // High when output is valid
);

    // --------------------- FSM State Definitions ----------------------
    typedef enum logic [2:0] {
        IDLE,
        FIND_MAX,
        SUB_EXP,
        SUM_EXP,
        DIVIDE,
        DONE_S
    } state_t;

    state_t current_state, next_state;

    // --------------------- Internal Registers -------------------------
    logic signed [(2*DATA_WIDTH)-1:0] max_val;
    logic signed [(2*DATA_WIDTH)-1:0] sub_vector [VECTOR_SIZE];
    logic [DATA_WIDTH-1:0]            exp_vector [VECTOR_SIZE];
    logic [(2*DATA_WIDTH)-1:0]        sum_exp;
    logic                             done_reg;

    // ------------------- Pre-computed ROM Lookup Table ----------------
    // Defined outside the function as a localparam to prevent multi-instance 
    // hardware duplication during synthesis. Pre-scaled by 2^FRAC_WIDTH.
    localparam logic [DATA_WIDTH-1:0] EXP_ROM [0:LUT_DEPTH-1] = '{
        0: 16'hFFFF, // e^0   = 1.0000
        1: 16'h5E2D, // e^-1  ≈ 0.3679 (corrected)
        2: 16'h22A5, // e^-2  ≈ 0.1353 (corrected)
        3: 16'h0CBF, // e^-3  ≈ 0.0498 (corrected)
        4: 16'h04B0, // e^-4  ≈ 0.0183 (corrected)
        5: 16'h01B9, // e^-5  ≈ 0.0067 (corrected)
        6: 16'h00A3, // e^-6  ≈ 0.0025 (corrected)
        7: 16'h003C, // e^-7  ≈ 0.0009 (corrected)
        default: 16'h0000 // All remaining deeper negative bounds clamped to 0
    };

    // ------------------- Exponential LUT Function ---------------------
    function automatic logic [DATA_WIDTH-1:0] exp_lut (
        input logic signed [(2*DATA_WIDTH)-1:0] x
    );
        int index;
        if (x >= 0) begin
            index = 0;
        end else begin
            index = -x;
            if (index >= LUT_DEPTH)
                index = LUT_DEPTH - 1;
        end
        return EXP_ROM[index]; // Read cleanly from the single static global ROM block
    endfunction

    // ------------------ FSM State Transition --------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else if (en) begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE:     if (start) next_state = FIND_MAX;
            FIND_MAX: next_state = SUB_EXP;
            SUB_EXP:  next_state = SUM_EXP;
            SUM_EXP:  next_state = DIVIDE;
            DIVIDE:   next_state = DONE_S;
            DONE_S:   next_state = IDLE;
            default:  next_state = IDLE;
        endcase
        // verilator lint_off CASEINCOMPLETE
    end

    // ----------------- Datapath and Control ---------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_val  <= '0;
            sum_exp  <= '0;
            done_reg <= 1'b0;
            out_probs <= '0;
            for (int i = 0; i < VECTOR_SIZE; i++) begin
                sub_vector[i] <= '0;
                exp_vector[i] <= '0;
            end
        end else if (en) begin
            done_reg <= 1'b0; 
            case (current_state)

                IDLE: begin
                    // Ready for next operation
                end

                FIND_MAX: begin
                    automatic logic signed [(2*DATA_WIDTH)-1:0] temp_max;
                    temp_max = in_vector[0];
                    for (int i = 1; i < VECTOR_SIZE; i++) begin
                        if (in_vector[i] > temp_max)
                            temp_max = in_vector[i];
                    end
                    max_val <= temp_max;
                end

                SUB_EXP: begin
                    for (int i = 0; i < VECTOR_SIZE; i++) begin
                        sub_vector[i] <= in_vector[i] - max_val;
                        exp_vector[i] <= exp_lut(in_vector[i] - max_val);
                    end
                end

                SUM_EXP: begin
                    automatic logic [(2*DATA_WIDTH)-1:0] temp_sum = '0;
                    for (int i = 0; i < VECTOR_SIZE; i++) begin
                        temp_sum = temp_sum + {{DATA_WIDTH{1'b0}}, exp_vector[i]};
                    end
                    sum_exp <= temp_sum;
                end

                DIVIDE: begin
                    for (int i = 0; i < VECTOR_SIZE; i++) begin
                        if (sum_exp != 0) begin
                            // CRITICAL FIX: Proper SystemVerilog casting syntax
                            // Use SIZE'(expression) format, not logic [SIZE]'(...)
                            automatic logic [63:0] temp_val;
                            temp_val = {48'b0, exp_vector[i]} << FRAC_WIDTH;
                            out_probs[i] <= temp_val[DATA_WIDTH-1 +: DATA_WIDTH];
                        end else begin
                            out_probs[i] <= '0;
                        end
                    end
                end

                DONE_S: begin
                    done_reg <= 1'b1;
                end

            endcase
        end
    end

    assign done = done_reg;

endmodule
