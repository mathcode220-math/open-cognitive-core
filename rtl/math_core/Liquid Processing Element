// ============================================================================
// Liquid Processing Element (LPE) - 
// ============================================================================
// Implements a time-continuous recurrent unit based on Liquid Neural Network
// (LNN) principles, adapted for hardware synthesis.
//
// Mathematical Model:
//   h(t+dt) = h(t) + dt * [ gate(f(W*x + b)) * x + (1 - gate) * h(t) - h(t) ]
//           = h(t) + dt * gate * (x - h(t))
//           = h(t) * (1 - dt*gate) + x * dt*gate
//
// Fixed-Point Format: Q(BIT_WIDTH-FRAC_BITS).FRAC_BITS (default Q8.8)
//   Range:    [-(2^(BIT_WIDTH-1))/2^FRAC_BITS, +(2^(BIT_WIDTH-1)-1)/2^FRAC_BITS]
//   Default:  [-128.0, +127.996]
//   Precision: 1 / 2^FRAC_BITS = 0.00390625
//
// Parameters:
//   BIT_WIDTH      - Total bit width (default: 16)
//   FRAC_BITS      - Fractional bits (default: 8)
//   USE_SATURATION - Enable saturation arithmetic (default: 1)
//   USE_DELTA_T    - Enable time-step adaptation (default: 1)
//
// Critical Fixes Applied:
//   1. Corrected state update equation: gate*x + (1-gate)*h (was reversed)
//   2. Fixed tanh_approx: replaced abs() with direct comparisons to avoid
//      Two's Complement overflow on MIN_VALUE (-32768 in 16-bit)
// ============================================================================

`timescale 1ns / 1ps

module liquid_processing_element #(
    parameter  int BIT_WIDTH      = 16,
    parameter  int FRAC_BITS      = 8,
    parameter  bit USE_SATURATION = 1'b1,
    parameter  bit USE_DELTA_T    = 1'b1
)(
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     en,              // Enable (power gating)
    input  logic signed [BIT_WIDTH-1:0] x_input,       // Quantized input
    input  logic signed [BIT_WIDTH-1:0] h_prev,        // Previous hidden state
    input  logic signed [BIT_WIDTH-1:0] delta_t,       // Adaptive time step
    input  logic signed [BIT_WIDTH-1:0] w_f,           // Configurable weight
    input  logic signed [BIT_WIDTH-1:0] bias,          // Configurable bias
    output logic signed [BIT_WIDTH-1:0] h_next,        // Updated hidden state
    output logic                     overflow_flag     // Saturation indicator
);

    // -------------------------------------------------------------------------
    // Constants and Parameters
    // -------------------------------------------------------------------------
    localparam int EXT_WIDTH = 2 * BIT_WIDTH;

    // Fixed-point constants in Q-format
    localparam logic signed [BIT_WIDTH-1:0] ONE_FP     = (1 <<< FRAC_BITS);      // 1.0
    localparam logic signed [BIT_WIDTH-1:0] HALF_FP    = (1 <<< (FRAC_BITS-1));  // 0.5
    localparam logic signed [BIT_WIDTH-1:0] QUARTER_FP = (1 <<< (FRAC_BITS-2));  // 0.25

    // Pre-computed tanh approximation boundaries (avoids runtime addition)
    localparam logic signed [BIT_WIDTH-1:0] TANH_B1 = HALF_FP;           // 0.5
    localparam logic signed [BIT_WIDTH-1:0] TANH_B2 = ONE_FP;            // 1.0
    localparam logic signed [BIT_WIDTH-1:0] TANH_B3 = (2 <<< FRAC_BITS); // 2.0

    // Saturation limits
    localparam logic signed [BIT_WIDTH-1:0] SAT_MAX_POS = {1'b0, {(BIT_WIDTH-1){1'b1}}};
    localparam logic signed [BIT_WIDTH-1:0] SAT_MAX_NEG = {1'b1, {(BIT_WIDTH-1){1'b0}}};

    // -------------------------------------------------------------------------
    // Pure Combinational Functions
    // -------------------------------------------------------------------------

    // =========================================================================
    // Piecewise Linear Approximation of tanh(x)
    // =========================================================================
    //   tanh(x) ~  x                    if |x| < 0.5
    //              0.5*x + 0.25*sign(x) if 0.5 <= |x| < 1.0
    //              0.25*x + 0.5*sign(x) if 1.0 <= |x| < 2.0
    //              +/-0.9961            if |x| >= 2.0
    //
    // Maximum error: ~0.08 (at x ~ +/-1.4)
    // Hardware cost: 2 multipliers, 1 adder, comparators
    //
    // CRITICAL: Do NOT use abs() here. In Two's Complement, -MIN_VALUE
    // overflows (e.g., -(-32768) = -32768 in 16-bit). Instead, use direct
    // signed comparisons against positive and negative boundaries.
    // =========================================================================
    function automatic logic signed [BIT_WIDTH-1:0] tanh_approx (
        input logic signed [BIT_WIDTH-1:0] val
    );
        logic signed [EXT_WIDTH-1:0] mult_result;

        // Region 1: |x| < 0.5
        if (val > -TANH_B1 && val < TANH_B1) begin
            return val;
        end
        // Region 2: 0.5 <= x < 1.0
        else if (val >= TANH_B1 && val < TANH_B2) begin
            mult_result = val * HALF_FP;
            return (mult_result >>> FRAC_BITS) + QUARTER_FP;
        end
        // Region 3: -1.0 < x <= -0.5
        else if (val > -TANH_B2 && val <= -TANH_B1) begin
            mult_result = val * HALF_FP;
            return (mult_result >>> FRAC_BITS) - QUARTER_FP;
        end
        // Region 4: 1.0 <= x < 2.0
        else if (val >= TANH_B2 && val < TANH_B3) begin
            mult_result = val * QUARTER_FP;
            return (mult_result >>> FRAC_BITS) + HALF_FP;
        end
        // Region 5: -2.0 < x <= -1.0
        else if (val > -TANH_B3 && val <= -TANH_B2) begin
            mult_result = val * QUARTER_FP;
            return (mult_result >>> FRAC_BITS) - HALF_FP;
        end
        // Region 6: Saturation (|x| >= 2.0) — safely handles MIN_VALUE
        else begin
            return (val > 0) ? (ONE_FP - 1) : -(ONE_FP - 1);
        end
    endfunction

    // =========================================================================
    // Saturation function for BIT_WIDTH precision
    // =========================================================================
    function automatic logic signed [BIT_WIDTH-1:0] saturate (
        input logic signed [EXT_WIDTH-1:0] val
    );
        if (val > SAT_MAX_POS)      return SAT_MAX_POS;
        else if (val < SAT_MAX_NEG) return SAT_MAX_NEG;
        else                        return val[BIT_WIDTH-1:0];
    endfunction

    // =========================================================================
    // Saturation function for EXT_WIDTH precision (48-bit intermediate)
    // =========================================================================
    function automatic logic signed [EXT_WIDTH-1:0] saturate_ext (
        input logic signed [EXT_WIDTH+BIT_WIDTH-1:0] val
    );
        logic signed [EXT_WIDTH-1:0] max_pos = {1'b0, {(EXT_WIDTH-1){1'b1}}};
        logic signed [EXT_WIDTH-1:0] max_neg = {1'b1, {(EXT_WIDTH-1){1'b0}}};

        if (val > max_pos)      return max_pos;
        else if (val < max_neg) return max_neg;
        else                    return val[EXT_WIDTH-1:0];
    endfunction

    // -------------------------------------------------------------------------
    // Combinational Data Path (always_comb)
    // -------------------------------------------------------------------------
    logic signed [EXT_WIDTH-1:0] raw_f;
    logic signed [BIT_WIDTH-1:0] f_scaled;
    logic signed [EXT_WIDTH-1:0] f_bias_ext;
    logic signed [BIT_WIDTH-1:0] f_with_bias;
    logic signed [BIT_WIDTH-1:0] gating_factor;
    logic signed [BIT_WIDTH-1:0] one_minus_gate;
    logic signed [BIT_WIDTH-1:0] dt_effective;

    // CRITICAL FIX: State update equation corrected.
    // Previous (buggy):  term1 = h_prev * gate,  term2 = x_input * (1-gate)
    //   => state_diff = (1-gate)*(x-h)  [REVERSED LOGIC]
    //
    // Correct: term1 = x_input * gate,  term2 = h_prev * (1-gate)
    //   => state_diff = gate*(x-h)  [MATCHES MATHEMATICAL MODEL]
    logic signed [EXT_WIDTH-1:0] term1, term2;
    logic signed [EXT_WIDTH-1:0] term1_scaled, term2_scaled;
    logic signed [EXT_WIDTH-1:0] sum_raw;

    logic signed [EXT_WIDTH-1:0] h_prev_ext;
    logic signed [EXT_WIDTH-1:0] state_diff;
    logic signed [EXT_WIDTH+BIT_WIDTH-1:0] dt_mult_res;
    logic signed [EXT_WIDTH-1:0] dt_adjusted;
    logic signed [EXT_WIDTH-1:0] final_sum;
    logic signed [BIT_WIDTH-1:0] sat_result;
    logic ov_flag_comb;

    always_comb begin
        // =====================================================================
        // Stage 1: Weighted input + bias
        // =====================================================================
        // f_scaled = (w_f * x_input) >>> FRAC_BITS
        // f_with_bias = saturate( f_scaled + bias )
        // =====================================================================
        raw_f      = x_input * w_f;
        f_scaled   = raw_f >>> FRAC_BITS;

        f_bias_ext = {{(EXT_WIDTH-BIT_WIDTH){f_scaled[BIT_WIDTH-1]}}, f_scaled} + 
                     {{(EXT_WIDTH-BIT_WIDTH){bias[BIT_WIDTH-1]}}, bias};

        if (USE_SATURATION)
            f_with_bias = saturate(f_bias_ext);
        else
            f_with_bias = f_bias_ext[BIT_WIDTH-1:0];

        // =====================================================================
        // Stage 2: Adaptive Gating (the "Liquid" part)
        // =====================================================================
        // gating_factor = tanh_approx( f_with_bias ) in [-1, +1]
        // This creates the time-continuous behavior of the LNN.
        // =====================================================================
        gating_factor = tanh_approx(f_with_bias);

        // =====================================================================
        // Stage 3: Complement and effective time step
        // =====================================================================
        // one_minus_gate = 1.0 - gating_factor
        // dt_effective   = delta_t (if USE_DELTA_T) else 1.0
        // =====================================================================
        one_minus_gate = ONE_FP - gating_factor;
        dt_effective   = USE_DELTA_T ? delta_t : ONE_FP;

        // =====================================================================
        // Stage 4: Core Liquid State Update (CORRECTED)
        // =====================================================================
        // sum_raw = gate*x + (1-gate)*h
        // state_diff = sum_raw - h = gate*(x - h)  [matches mathematical model]
        // =====================================================================
        term1 = x_input * gating_factor;       // gate * x
        term2 = h_prev * one_minus_gate;       // (1 - gate) * h

        term1_scaled = term1 >>> FRAC_BITS;
        term2_scaled = term2 >>> FRAC_BITS;
        sum_raw      = term1_scaled + term2_scaled;

        // =====================================================================
        // Stage 5: Time-step adaptation
        // =====================================================================
        // h_next = h_prev + dt * (sum_raw - h_prev)
        //        = h_prev + dt * gate * (x - h_prev)
        // =====================================================================
        h_prev_ext = {{(EXT_WIDTH-BIT_WIDTH){h_prev[BIT_WIDTH-1]}}, h_prev};

        if (USE_DELTA_T) begin
            state_diff  = sum_raw - h_prev_ext;           // gate * (x - h)
            dt_mult_res = state_diff * dt_effective;      // dt * gate * (x - h)
            dt_adjusted = saturate_ext(dt_mult_res) >>> FRAC_BITS;
            final_sum   = h_prev_ext + dt_adjusted;       // h + dt*gate*(x-h)
        end else begin
            final_sum = sum_raw;
        end

        // =====================================================================
        // Stage 6: Final saturation and overflow flag
        // =====================================================================
        if (USE_SATURATION) begin
            sat_result   = saturate(final_sum);
            ov_flag_comb = (sat_result != final_sum[BIT_WIDTH-1:0]);
        end else begin
            sat_result   = final_sum[BIT_WIDTH-1:0];
            ov_flag_comb = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Sequential Logic - State Registers Only
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            h_next        <= '0;
            overflow_flag <= 1'b0;
        end
        else if (en) begin
            h_next        <= sat_result;
            overflow_flag <= ov_flag_comb;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline Recommendations (for high-frequency synthesis targets)
    // -------------------------------------------------------------------------
    // The combinational path contains 3 multipliers, multiple adders, and
    // saturation logic. If F_max is insufficient, consider pipelining:
    //
    //   Stage 1 (CLK 0->1): raw_f, f_bias_ext, f_with_bias
    //   Stage 2 (CLK 1->2): gating_factor, one_minus_gate, dt_effective
    //   Stage 3 (CLK 2->3): term1, term2, term1_scaled, term2_scaled, sum_raw
    //   Stage 4 (CLK 3->4): state_diff, dt_mult_res, dt_adjusted, final_sum
    //   Stage 5 (CLK 4->5): sat_result, ov_flag_comb -> h_next
    //
    // Latency: 5 cycles | Throughput: 1 result/cycle (with full pipelining)
    //
    // For FPGA synthesis, modern tools (Vivado, Quartus) will infer DSP
    // blocks for the multipliers. To force DSP inference, add:
    //   (* use_dsp = "yes" *) before the multiplier assignments.
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Optional Assertions (simulation only)
    // -------------------------------------------------------------------------
    // assert property (@(posedge clk) disable iff (rst) (FRAC_BITS < BIT_WIDTH));
    // assert property (@(posedge clk) disable iff (rst) (BIT_WIDTH >= 8));
    // assert property (@(posedge clk) disable iff (rst)
    //     (gating_factor <= (ONE_FP-1)) && (gating_factor >= -(ONE_FP-1)));

endmodule
