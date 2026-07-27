//=============================================================================
// Module: relu_activation
// Description: Parameterized signed ReLU activation with proper saturation
// Fixes Applied:
//   - Corrected saturation threshold to signed max (2^(DATA_WIDTH-1) - 1)
//   - Corrected saturation output value (was -1, now true signed max)
//=============================================================================

module relu_activation #(
    parameter DATA_WIDTH   = 16,
    parameter ACCUM_WIDTH  = 32
)(
    input  logic signed [ACCUM_WIDTH-1:0]  accum_in,
    output logic signed [DATA_WIDTH-1:0]   relu_out
);

    // Signed maximum positive value: 2^(DATA_WIDTH-1) - 1
    // For DATA_WIDTH=16: 0x7FFF = 32767
    localparam logic signed [ACCUM_WIDTH-1:0] SIGNED_MAX = 
        {{(ACCUM_WIDTH - DATA_WIDTH + 1){1'b0}}, {(DATA_WIDTH-1){1'b1}}};

    always_comb begin
        if (accum_in <= 0) begin
            // Negative or zero -> output 0
            relu_out = '0;
        end else if (accum_in > SIGNED_MAX) begin
            // Overflow -> saturate to maximum positive signed value
            // Correct: 0 followed by (DATA_WIDTH-1) ones = 0x7FFF for 16-bit
            relu_out = {1'b0, {(DATA_WIDTH-1){1'b1}}};
        end else begin
            // Normal range -> truncate lower bits (value fits in DATA_WIDTH)
            relu_out = accum_in[DATA_WIDTH-1:0];
        end
    end

endmodule
