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
        0: 16'hFFFF, // e^0
        1: 16'h5E2D, // e^-1
        2: 16'h22A5, // e^-2
        3: 16'h0CBE, // e^-3
        4: 16'h04B0, // e^-4
        5: 16'h01B9, // e^-5
        6: 16'h00A2, // e^-6
        7: 16'h003B, // e^-7
        8: 16'h0015, // e^-8 (clamped)
        9: 16'h0008, // e^-9 (clamped)
        10: 16'h0002, // e^-10 (clamped)
        11: 16'h0001, // e^-11 (clamped)
        12: 16'h0000, // e^-12 (clamped)
        13: 16'h0000, // e^-13 (clamped)
        14: 16'h0000, // e^-14 (clamped)
        15: 16'h0000, // e^-15 (minimum before clamp)
        16: 16'h0000, // e^-16 (clamped)
        17: 16'h0000, // e^-17 (clamped)
        18: 16'h0000, // e^-18 (clamped)
        19: 16'h0000, // e^-19 (clamped)
        20: 16'h0000, // e^-20 (clamped)
        21: 16'h0000, // e^-21 (clamped)
        22: 16'h0000, // e^-22 (clamped)
        23: 16'h0000, // e^-23 (clamped)
        24: 16'h0000, // e^-24 (clamped)
        25: 16'h0000, // e^-25 (clamped)
        26: 16'h0000, // e^-26 (clamped)
        27: 16'h0000, // e^-27 (clamped)
        28: 16'h0000, // e^-28 (clamped)
        29: 16'h0000, // e^-29 (clamped)
        30: 16'h0000, // e^-30 (clamped)
        31: 16'h0000, // e^-31 (clamped)
        32: 16'h0000, // e^-32 (clamped)
        33: 16'h0000, // e^-33 (clamped)
        34: 16'h0000, // e^-34 (clamped)
        35: 16'h0000, // e^-35 (clamped)
        36: 16'h0000, // e^-36 (clamped)
        37: 16'h0000, // e^-37 (clamped)
        38: 16'h0000, // e^-38 (clamped)
        39: 16'h0000, // e^-39 (clamped)
        40: 16'h0000, // e^-40 (clamped)
        41: 16'h0000, // e^-41 (clamped)
        42: 16'h0000, // e^-42 (clamped)
        43: 16'h0000, // e^-43 (clamped)
        44: 16'h0000, // e^-44 (clamped)
        45: 16'h0000, // e^-45 (clamped)
        46: 16'h0000, // e^-46 (clamped)
        47: 16'h0000, // e^-47 (clamped)
        48: 16'h0000, // e^-48 (clamped)
        49: 16'h0000, // e^-49 (clamped)
        50: 16'h0000, // e^-50 (clamped)
        51: 16'h0000, // e^-51 (clamped)
        52: 16'h0000, // e^-52 (clamped)
        53: 16'h0000, // e^-53 (clamped)
        54: 16'h0000, // e^-54 (clamped)
        55: 16'h0000, // e^-55 (clamped)
        56: 16'h0000, // e^-56 (clamped)
        57: 16'h0000, // e^-57 (clamped)
        58: 16'h0000, // e^-58 (clamped)
        59: 16'h0000, // e^-59 (clamped)
        60: 16'h0000, // e^-60 (clamped)
        61: 16'h0000, // e^-61 (clamped)
        62: 16'h0000, // e^-62 (clamped)
        63: 16'h0000, // e^-63 (clamped)
        64: 16'h0000, // e^-64 (clamped)
        65: 16'h0000, // e^-65 (clamped)
        66: 16'h0000, // e^-66 (clamped)
        67: 16'h0000, // e^-67 (clamped)
        68: 16'h0000, // e^-68 (clamped)
        69: 16'h0000, // e^-69 (clamped)
        70: 16'h0000, // e^-70 (clamped)
        71: 16'h0000, // e^-71 (clamped)
        72: 16'h0000, // e^-72 (clamped)
        73: 16'h0000, // e^-73 (clamped)
        74: 16'h0000, // e^-74 (clamped)
        75: 16'h0000, // e^-75 (clamped)
        76: 16'h0000, // e^-76 (clamped)
        77: 16'h0000, // e^-77 (clamped)
        78: 16'h0000, // e^-78 (clamped)
        79: 16'h0000, // e^-79 (clamped)
        80: 16'h0000, // e^-80 (clamped)
        81: 16'h0000, // e^-81 (clamped)
        82: 16'h0000, // e^-82 (clamped)
        83: 16'h0000, // e^-83 (clamped)
        84: 16'h0000, // e^-84 (clamped)
        85: 16'h0000, // e^-85 (clamped)
        86: 16'h0000, // e^-86 (clamped)
        87: 16'h0000, // e^-87 (clamped)
        88: 16'h0000, // e^-88 (clamped)
        89: 16'h0000, // e^-89 (clamped)
        90: 16'h0000, // e^-90 (clamped)
        91: 16'h0000, // e^-91 (clamped)
        92: 16'h0000, // e^-92 (clamped)
        93: 16'h0000, // e^-93 (clamped)
        94: 16'h0000, // e^-94 (clamped)
        95: 16'h0000, // e^-95 (clamped)
        96: 16'h0000, // e^-96 (clamped)
        97: 16'h0000, // e^-97 (clamped)
        98: 16'h0000, // e^-98 (clamped)
        99: 16'h0000, // e^-99 (clamped)
        100: 16'h0000, // e^-100 (clamped)
        101: 16'h0000, // e^-101 (clamped)
        102: 16'h0000, // e^-102 (clamped)
        103: 16'h0000, // e^-103 (clamped)
        104: 16'h0000, // e^-104 (clamped)
        105: 16'h0000, // e^-105 (clamped)
        106: 16'h0000, // e^-106 (clamped)
        107: 16'h0000, // e^-107 (clamped)
        108: 16'h0000, // e^-108 (clamped)
        109: 16'h0000, // e^-109 (clamped)
        110: 16'h0000, // e^-110 (clamped)
        111: 16'h0000, // e^-111 (clamped)
        112: 16'h0000, // e^-112 (clamped)
        113: 16'h0000, // e^-113 (clamped)
        114: 16'h0000, // e^-114 (clamped)
        115: 16'h0000, // e^-115 (clamped)
        116: 16'h0000, // e^-116 (clamped)
        117: 16'h0000, // e^-117 (clamped)
        118: 16'h0000, // e^-118 (clamped)
        119: 16'h0000, // e^-119 (clamped)
        120: 16'h0000, // e^-120 (clamped)
        121: 16'h0000, // e^-121 (clamped)
        122: 16'h0000, // e^-122 (clamped)
        123: 16'h0000, // e^-123 (clamped)
        124: 16'h0000, // e^-124 (clamped)
        125: 16'h0000, // e^-125 (clamped)
        126: 16'h0000, // e^-126 (clamped)
        127: 16'h0000, // e^-127 (clamped)
        128: 16'h0000, // e^-128 (clamped)
        129: 16'h0000, // e^-129 (clamped)
        130: 16'h0000, // e^-130 (clamped)
        131: 16'h0000, // e^-131 (clamped)
        132: 16'h0000, // e^-132 (clamped)
        133: 16'h0000, // e^-133 (clamped)
        134: 16'h0000, // e^-134 (clamped)
        135: 16'h0000, // e^-135 (clamped)
        136: 16'h0000, // e^-136 (clamped)
        137: 16'h0000, // e^-137 (clamped)
        138: 16'h0000, // e^-138 (clamped)
        139: 16'h0000, // e^-139 (clamped)
        140: 16'h0000, // e^-140 (clamped)
        141: 16'h0000, // e^-141 (clamped)
        142: 16'h0000, // e^-142 (clamped)
        143: 16'h0000, // e^-143 (clamped)
        144: 16'h0000, // e^-144 (clamped)
        145: 16'h0000, // e^-145 (clamped)
        146: 16'h0000, // e^-146 (clamped)
        147: 16'h0000, // e^-147 (clamped)
        148: 16'h0000, // e^-148 (clamped)
        149: 16'h0000, // e^-149 (clamped)
        150: 16'h0000, // e^-150 (clamped)
        151: 16'h0000, // e^-151 (clamped)
        152: 16'h0000, // e^-152 (clamped)
        153: 16'h0000, // e^-153 (clamped)
        154: 16'h0000, // e^-154 (clamped)
        155: 16'h0000, // e^-155 (clamped)
        156: 16'h0000, // e^-156 (clamped)
        157: 16'h0000, // e^-157 (clamped)
        158: 16'h0000, // e^-158 (clamped)
        159: 16'h0000, // e^-159 (clamped)
        160: 16'h0000, // e^-160 (clamped)
        161: 16'h0000, // e^-161 (clamped)
        162: 16'h0000, // e^-162 (clamped)
        163: 16'h0000, // e^-163 (clamped)
        164: 16'h0000, // e^-164 (clamped)
        165: 16'h0000, // e^-165 (clamped)
        166: 16'h0000, // e^-166 (clamped)
        167: 16'h0000, // e^-167 (clamped)
        168: 16'h0000, // e^-168 (clamped)
        169: 16'h0000, // e^-169 (clamped)
        170: 16'h0000, // e^-170 (clamped)
        171: 16'h0000, // e^-171 (clamped)
        172: 16'h0000, // e^-172 (clamped)
        173: 16'h0000, // e^-173 (clamped)
        174: 16'h0000, // e^-174 (clamped)
        175: 16'h0000, // e^-175 (clamped)
        176: 16'h0000, // e^-176 (clamped)
        177: 16'h0000, // e^-177 (clamped)
        178: 16'h0000, // e^-178 (clamped)
        179: 16'h0000, // e^-179 (clamped)
        180: 16'h0000, // e^-180 (clamped)
        181: 16'h0000, // e^-181 (clamped)
        182: 16'h0000, // e^-182 (clamped)
        183: 16'h0000, // e^-183 (clamped)
        184: 16'h0000, // e^-184 (clamped)
        185: 16'h0000, // e^-185 (clamped)
        186: 16'h0000, // e^-186 (clamped)
        187: 16'h0000, // e^-187 (clamped)
        188: 16'h0000, // e^-188 (clamped)
        189: 16'h0000, // e^-189 (clamped)
        190: 16'h0000, // e^-190 (clamped)
        191: 16'h0000, // e^-191 (clamped)
        192: 16'h0000, // e^-192 (clamped)
        193: 16'h0000, // e^-193 (clamped)
        194: 16'h0000, // e^-194 (clamped)
        195: 16'h0000, // e^-195 (clamped)
        196: 16'h0000, // e^-196 (clamped)
        197: 16'h0000, // e^-197 (clamped)
        198: 16'h0000, // e^-198 (clamped)
        199: 16'h0000, // e^-199 (clamped)
        200: 16'h0000, // e^-200 (clamped)
        201: 16'h0000, // e^-201 (clamped)
        202: 16'h0000, // e^-202 (clamped)
        203: 16'h0000, // e^-203 (clamped)
        204: 16'h0000, // e^-204 (clamped)
        205: 16'h0000, // e^-205 (clamped)
        206: 16'h0000, // e^-206 (clamped)
        207: 16'h0000, // e^-207 (clamped)
        208: 16'h0000, // e^-208 (clamped)
        209: 16'h0000, // e^-209 (clamped)
        210: 16'h0000, // e^-210 (clamped)
        211: 16'h0000, // e^-211 (clamped)
        212: 16'h0000, // e^-212 (clamped)
        213: 16'h0000, // e^-213 (clamped)
        214: 16'h0000, // e^-214 (clamped)
        215: 16'h0000, // e^-215 (clamped)
        216: 16'h0000, // e^-216 (clamped)
        217: 16'h0000, // e^-217 (clamped)
        218: 16'h0000, // e^-218 (clamped)
        219: 16'h0000, // e^-219 (clamped)
        220: 16'h0000, // e^-220 (clamped)
        221: 16'h0000, // e^-221 (clamped)
        222: 16'h0000, // e^-222 (clamped)
        223: 16'h0000, // e^-223 (clamped)
        224: 16'h0000, // e^-224 (clamped)
        225: 16'h0000, // e^-225 (clamped)
        226: 16'h0000, // e^-226 (clamped)
        227: 16'h0000, // e^-227 (clamped)
        228: 16'h0000, // e^-228 (clamped)
        229: 16'h0000, // e^-229 (clamped)
        230: 16'h0000, // e^-230 (clamped)
        231: 16'h0000, // e^-231 (clamped)
        232: 16'h0000, // e^-232 (clamped)
        233: 16'h0000, // e^-233 (clamped)
        234: 16'h0000, // e^-234 (clamped)
        235: 16'h0000, // e^-235 (clamped)
        236: 16'h0000, // e^-236 (clamped)
        237: 16'h0000, // e^-237 (clamped)
        238: 16'h0000, // e^-238 (clamped)
        239: 16'h0000, // e^-239 (clamped)
        240: 16'h0000, // e^-240 (clamped)
        241: 16'h0000, // e^-241 (clamped)
        242: 16'h0000, // e^-242 (clamped)
        243: 16'h0000, // e^-243 (clamped)
        244: 16'h0000, // e^-244 (clamped)
        245: 16'h0000, // e^-245 (clamped)
        246: 16'h0000, // e^-246 (clamped)
        247: 16'h0000, // e^-247 (clamped)
        248: 16'h0000, // e^-248 (clamped)
        249: 16'h0000, // e^-249 (clamped)
        250: 16'h0000, // e^-250 (clamped)
        251: 16'h0000, // e^-251 (clamped)
        252: 16'h0000, // e^-252 (clamped)
        253: 16'h0000, // e^-253 (clamped)
        254: 16'h0000, // e^-254 (clamped)
        255: 16'h0000, // e^-255 (clamped)
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
                            // CRITICAL FIX: Proper division to normalize probabilities
                            // Formula: out_probs[i] = exp_vector[i] / sum_exp
                            // Using fixed-point arithmetic: (exp_vector[i] << FRAC_WIDTH) / sum_exp
                            automatic logic [63:0] numerator;
                            automatic logic [63:0] quotient;
                            numerator = {48'b0, exp_vector[i]} << FRAC_WIDTH;
                            quotient  = numerator / {32'b0, sum_exp[31:0]};
                            out_probs[i] <= quotient[DATA_WIDTH-1:0];
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
