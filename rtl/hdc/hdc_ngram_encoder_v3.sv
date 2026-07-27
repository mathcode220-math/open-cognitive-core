// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: hdc_ngram_encoder_v3.sv
// Description: N-gram encoder for Hyperdimensional Computing (HDC)
//   - Configurable n-gram size (2-4)
//   - LFSR-based token-to-hypervector mapping
//   - Circular shift permutation for positional encoding
//   - AND-binding for n-gram composition
//   - clear_context support for sequence boundaries
//   - ngram_valid output for downstream handshake
//
// Architecture:
//   token_in -> token_to_hv() -> shift_reg[] -> permute_cw() -> AND-bind -> ngram_hv
//
// Latency: 1 clock cycle (combinational binding after registered shift)
// Interface: Simple valid/enable handshake
//
// Author: OCCP Contributors
// Version: 1.1.0 (bugfix release)
// License: CERN-OHL-W v2
// =============================================================================

`ifndef SYNTHESIS
`timescale 1ns/1ps
`endif

module hdc_ngram_encoder_v3 #(
    parameter HV_DIM      = 1024,   // Hypervector dimensionality
    parameter NGRAM_SIZE  = 3,      // N-gram window size (2, 3, or 4)
    parameter TOKEN_WIDTH = 16      // Input token bit-width
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,             // Encoding enable
    input  logic                    clear_context,  // Reset sequence state
    input  logic [TOKEN_WIDTH-1:0]  token_in,       // Current input token
    output logic [HV_DIM-1:0]       ngram_hv,       // Encoded n-gram hypervector
    output logic                    ngram_valid     // Valid when full n-gram available
);

    // =========================================================================
    // Parameter Validation
    // =========================================================================
    initial begin
        if (NGRAM_SIZE < 2 || NGRAM_SIZE > 4)
            $fatal(1, "NGRAM_SIZE must be 2, 3, or 4. Got: %0d", NGRAM_SIZE);
        if (HV_DIM < 64 || HV_DIM % 64 != 0)
            $fatal(1, "HV_DIM must be a multiple of 64 and >= 64. Got: %0d", HV_DIM);
    end

    // =========================================================================
    // Local Parameters
    // =========================================================================
    localparam NUM_SHIFTS = NGRAM_SIZE - 1;  // Number of history slots

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic [TOKEN_WIDTH-1:0] token_shift  [0:NUM_SHIFTS-1];  // Token history
    logic [HV_DIM-1:0]      shift_reg    [0:NUM_SHIFTS-1];  // HV history
    logic                   valid_shift  [0:NUM_SHIFTS-1];  // Validity tracking

    // =========================================================================
    // Function: permute_cw
    // Circular left-shift permutation for positional encoding.
    // Uses modulo to prevent undefined behavior when shift >= HV_DIM.
    // =========================================================================
    function automatic logic [HV_DIM-1:0] permute_cw(
        input logic [HV_DIM-1:0] hv,
        input int unsigned       shift_amount
    );
        int unsigned safe_shift;
        safe_shift   = shift_amount % HV_DIM;
        permute_cw   = (hv << safe_shift) | (hv >> (HV_DIM - safe_shift));
    endfunction

    // =========================================================================
    // Function: token_to_hv
    // Maps a token to a pseudo-random hypervector using a 32-bit LFSR.
    // Each output bit depends on both the token value AND its position (i),
    // ensuring non-degenerate, approximately balanced output (~50% ones).
    //
    // LFSR polynomial: x^32 + x^22 + x^2 + x + 1 (maximal-length)
    // =========================================================================
    function automatic logic [HV_DIM-1:0] token_to_hv(
        input logic [TOKEN_WIDTH-1:0] token
    );
        logic [HV_DIM-1:0] result;
        logic [31:0]       lfsr;
        logic              feedback;

        // Seed LFSR with token-derived value (XOR with constant for diffusion)
        lfsr = {16'b0, token} ^ 32'hDEADBEEF;

        for (int i = 0; i < HV_DIM; i++) begin
            // LFSR feedback: taps at bits 31, 21, 1, 0
            feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];
            lfsr     = {lfsr[30:0], feedback};

            // Output bit: XOR of multiple LFSR taps for better distribution
            result[i] = lfsr[15] ^ lfsr[7] ^ lfsr[0];
        end

        return result;
    endfunction

    // =========================================================================
    // Shift Register Update (Sequential)
    // On each valid clock: shift history and insert new token/HV.
    // clear_context resets all history for sequence boundary handling.
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear_context) begin
            for (int i = 0; i < NUM_SHIFTS; i++) begin
                token_shift[i] <= '0;
                shift_reg[i]   <= '0;
                valid_shift[i] <= 1'b0;
            end
        end else if (en) begin
            // Shift history: slot[i] <- slot[i-1]
            for (int i = NUM_SHIFTS-1; i > 0; i--) begin
                token_shift[i] <= token_shift[i-1];
                shift_reg[i]   <= shift_reg[i-1];
                valid_shift[i] <= valid_shift[i-1];
            end
            // Insert current token at slot[0]
            token_shift[0] <= token_in;
            shift_reg[0]   <= token_to_hv(token_in);
            valid_shift[0] <= 1'b1;
        end
    end

    // =========================================================================
    // N-gram Binding (Combinational)
    // Binds current token HV with permuted history HVs using AND operation.
    // Position i is permuted by (i+1)*17 bits for orthogonality.
    // Only valid history entries participate in binding.
    // =========================================================================
    logic [HV_DIM-1:0] permuted_hv [0:NUM_SHIFTS-1];
    logic [HV_DIM-1:0] bound_hv;

    // Compute permuted hypervectors for each history position
    always_comb begin
        for (int i = 0; i < NUM_SHIFTS; i++) begin
            permuted_hv[i] = permute_cw(shift_reg[i], (i + 1) * 17);
        end
    end

    // AND-binding: current HV & permuted_history[0] & permuted_history[1] & ...
    always_comb begin
        bound_hv = token_to_hv(token_in);
        for (int i = 0; i < NUM_SHIFTS; i++) begin
            if (valid_shift[i]) begin
                bound_hv = bound_hv & permuted_hv[i];
            end
        end
    end

    assign ngram_hv = bound_hv;

    // =========================================================================
    // Output Valid Generation
    // ngram_valid is asserted only when:
    //   1. en is active (current token is valid)
    //   2. All history slots are filled (full n-gram window available)
    // =========================================================================
    always_comb begin
        ngram_valid = en;
        for (int i = 0; i < NUM_SHIFTS; i++) begin
            ngram_valid = ngram_valid & valid_shift[i];
        end
    end

    // =========================================================================
    // Simulation-Only Assertions
    // =========================================================================
`ifndef SYNTHESIS

    // Assert: output HV must not be degenerate (all-zeros or all-ones)
    assert property (@(posedge clk) disable iff (!rst_n)
        (en && ngram_valid) |-> (ngram_hv != '0) && (ngram_hv != '1)
    ) else $warning("HDC_NGRAM: Degenerate hypervector detected!");

    // Assert: ngram_valid must deassert after clear_context
    assert property (@(posedge clk) disable iff (!rst_n)
        clear_context |=> !ngram_valid
    ) else $error("HDC_NGRAM: ngram_valid not cleared after clear_context!");

    // Assert: valid_shift propagation consistency
    assert property (@(posedge clk) disable iff (!rst_n)
        (clear_context) |=> (valid_shift[0] == 1'b0)
    ) else $error("HDC_NGRAM: valid_shift[0] not reset!");

`endif

endmodule
