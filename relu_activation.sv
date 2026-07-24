// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: relu_activation.sv
// Description: Parameterized Signed ReLU Activation Function. Accommodates 2x 
//              accumulator bit-width directly from the Systolic Array outputs.
// License: CERN Open Hardware Licence v2 - Weakly Reciprocal (CERN-OHL-W)
// =============================================================================

module relu_activation #(
    parameter DATA_WIDTH = 16 // Matches the base bit-width of the computing grid
)(
    input  logic                                  clk,
    input  logic                                  rst_n, // Asynchronous active-low reset
    input  logic                                  en,    // Clock enable for power saving
    
    // Accepts 2x DATA_WIDTH signed inputs directly from the systolic array accumulators
    input  logic signed [(2*DATA_WIDTH)-1:0]      in_data,  
    output logic signed [(2*DATA_WIDTH)-1:0]      out_data  
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data <= '0;
        end else if (en) begin
            // Explicit signed comparison (Handles two's complement cleanly)
            if (in_data < 0) begin
                out_data <= '0; // Clamp negative values to zero
            end else begin
                out_data <= in_data; // Pass positive values unchanged
            end
        end
    end

endmodule
