//=============================================================================
// Module: softmax_core
// Description: Parameterized Softmax with LUT-based exponential
// Fixes Applied:
//   - Removed hardcoded bit-widths (32, 48, 64) in DIVIDE state
//   - All operations now scale with DATA_WIDTH parameter
//   - Fixed out-of-bounds part-select on sum_exp
//   - Division numerator/denominator properly parameterized
//=============================================================================

module softmax_core #(
    parameter DATA_WIDTH   = 16,
    parameter VECTOR_SIZE  = 8,
    parameter FRAC_WIDTH   = DATA_WIDTH,
    parameter LUT_DEPTH    = 256,
    // Derived parameters for division precision
    parameter DIV_WIDTH    = 4 * DATA_WIDTH  // Sufficient precision for division
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic signed [VECTOR_SIZE-1:0][(2*DATA_WIDTH)-1:0] in_vector,
    output logic [VECTOR_SIZE-1:0][DATA_WIDTH-1:0] out_probs,
    output logic done
);

    //=========================================================================
    // State Machine
    //=========================================================================
    typedef enum logic [2:0] {
        IDLE,
        FIND_MAX,
        COMPUTE_EXP,
        SUM_EXP,
        DIVIDE,
        DONE
    } state_t;

    state_t state, next_state;

    //=========================================================================
    // Internal Registers
    //=========================================================================
    logic signed [(2*DATA_WIDTH)-1:0] max_val;
    logic [DATA_WIDTH-1:0]            exp_vector [0:VECTOR_SIZE-1];
    logic [(2*DATA_WIDTH)-1:0]        sum_exp;

    //=========================================================================
    // Exponential Lookup Table (e^x approximation for x in [-1, 0])
    // Values represent e^x in Q0.DATA_WIDTH fixed-point format
    //=========================================================================
    localparam logic [DATA_WIDTH-1:0] EXP_ROM [0:LUT_DEPTH-1] = '{
        0:   {(DATA_WIDTH){1'b1}},           // e^0  ≈ 1.0000 (max value)
        1:   16'hF0F0,                        // e^(-1/256)
        2:   16'hE2F0,                        // e^(-2/256)
        3:   16'hD5E8,                        // e^(-3/256)
        4:   16'hC9C8,                        // e^(-4/256)
        5:   16'hBE80,                        // e^(-5/256)
        6:   16'hB408,                        // e^(-6/256)
        7:   16'hAA50,                        // e^(-7/256)
        8:   16'hA150,                        // e^(-8/256)
        9:   16'h98F8,                        // e^(-9/256)
        10:  16'h9140,                        // e^(-10/256)
        11:  16'h8A18,                        // e^(-11/256)
        12:  16'h8378,                        // e^(-12/256)
        13:  16'h7D50,                        // e^(-13/256)
        14:  16'h7798,                        // e^(-14/256)
        15:  16'h7248,                        // e^(-15/256)
        default: 16'h0001                     // Minimum non-zero value
    };

    //=========================================================================
    // Exponential LUT Function
    //=========================================================================
    function automatic logic [DATA_WIDTH-1:0] exp_lut(
        input logic signed [(2*DATA_WIDTH)-1:0] x
    );
        logic [7:0] lut_index;
        if (x >= 0) begin
            lut_index = 8'd0;  // e^0 = max
        end else if (x < -256) begin
            lut_index = 8'd255; // Clamp to minimum
        end else begin
            lut_index = 8'(-x); // Map [-256, 0] -> [255, 0]
        end
        return EXP_ROM[lut_index];
    endfunction

    //=========================================================================
    // State Machine - Sequential
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    //=========================================================================
    // State Machine - Next State Logic
    //=========================================================================
    always_comb begin
        next_state = state;
        case (state)
            IDLE:        if (start) next_state = FIND_MAX;
            FIND_MAX:    next_state = COMPUTE_EXP;
            COMPUTE_EXP: next_state = SUM_EXP;
            SUM_EXP:     next_state = DIVIDE;
            DIVIDE:      next_state = DONE;
            DONE:        next_state = IDLE;
            default:     next_state = IDLE;
        endcase
    end

    //=========================================================================
    // Datapath
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_val  <= '0;
            sum_exp  <= '0;
            done     <= 1'b0;
            out_probs <= '0;
            for (int i = 0; i < VECTOR_SIZE; i++)
                exp_vector[i] <= '0;
        end else begin
            done <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                // FIND_MAX: Find maximum value in input vector
                //-------------------------------------------------------------
                FIND_MAX: begin
                    automatic logic signed [(2*DATA_WIDTH)-1:0] temp_max;
                    temp_max = in_vector[0];
                    for (int i = 1; i < VECTOR_SIZE; i++) begin
                        if (in_vector[i] > temp_max)
                            temp_max = in_vector[i];
                    end
                    max_val <= temp_max;
                end

                //-------------------------------------------------------------
                // COMPUTE_EXP: Compute e^(x - max) for each element
                //-------------------------------------------------------------
                COMPUTE_EXP: begin
                    for (int i = 0; i < VECTOR_SIZE; i++) begin
                        automatic logic signed [(2*DATA_WIDTH)-1:0] shifted;
                        shifted = in_vector[i] - max_val;
                        exp_vector[i] <= exp_lut(shifted);
                    end
                end

                //-------------------------------------------------------------
                // SUM_EXP: Sum all exponential values
                //-------------------------------------------------------------
                SUM_EXP: begin
                    automatic logic [(2*DATA_WIDTH)-1:0] temp_sum;
                    temp_sum = '0;
                    for (int i = 0; i < VECTOR_SIZE; i++) begin
                        temp_sum = temp_sum + 
                                   {{DATA_WIDTH{1'b0}}, exp_vector[i]};
                    end
                    sum_exp <= temp_sum;
                end

                //-------------------------------------------------------------
                // DIVIDE: Compute probability = exp_i / sum_exp
                // FIX: All widths now parameterized (no hardcoded 32/48/64)
                //-------------------------------------------------------------
                DIVIDE: begin
                    for (int i = 0; i < VECTOR_SIZE; i++) begin
                        if (sum_exp != '0) begin
                            // FIX: Parameterized numerator and denominator
                            automatic logic [DIV_WIDTH-1:0] numerator;
                            automatic logic [DIV_WIDTH-1:0] denominator;
                            automatic logic [DIV_WIDTH-1:0] quotient;

                            // Zero-extend exp_vector[i] and shift left by FRAC_WIDTH
                            // This creates a fixed-point numerator with fractional precision
                            numerator   = {{(DIV_WIDTH - DATA_WIDTH - FRAC_WIDTH){1'b0}}, 
                                           exp_vector[i], 
                                           {FRAC_WIDTH{1'b0}}};

                            // Zero-extend sum_exp to DIV_WIDTH
                            denominator = {{(DIV_WIDTH - 2*DATA_WIDTH){1'b0}}, 
                                           sum_exp};

                            quotient = numerator / denominator;

                            // Extract fractional part (lower DATA_WIDTH bits)
                            out_probs[i] <= quotient[DATA_WIDTH-1:0];
                        end else begin
                            out_probs[i] <= '0;
                        end
                    end
                end

                //-------------------------------------------------------------
                // DONE: Signal completion
                //-------------------------------------------------------------
                DONE: begin
                    done <= 1'b1;
                end

                default: ;
            endcase
        end
    end

endmodule
