//=============================================================================
// Module: systolic_array_param
// Description: Parameterized systolic array with proper overflow handling
// Fixes Applied:
//   - PE output now includes EXTRA_BITS (no silent truncation)
//   - Top-level output width matches full accumulator width
//   - Removed incorrect truncation that defeated overflow protection
//=============================================================================

module pe #(
    parameter DATA_WIDTH  = 8,
    parameter ARRAY_SIZE  = 4,
    parameter EXTRA_BITS  = $clog2(ARRAY_SIZE) + 1
)(
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    input  logic clr,
    input  logic signed [DATA_WIDTH-1:0] in_a,
    input  logic signed [DATA_WIDTH-1:0] in_b,
    output logic signed [DATA_WIDTH-1:0] out_a,
    output logic signed [DATA_WIDTH-1:0] out_b,
    // FIX: Output width now includes EXTRA_BITS for true overflow protection
    output logic signed [(2*DATA_WIDTH + EXTRA_BITS)-1:0] accum
);

    logic signed [(2*DATA_WIDTH + EXTRA_BITS)-1:0] accum_extended;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_a          <= '0;
            out_b          <= '0;
            accum_extended <= '0;
        end else if (en) begin
            out_a <= in_a;
            out_b <= in_b;
            if (clr) begin
                accum_extended <= '0;
            end else begin
                accum_extended <= accum_extended + 
                                  ($signed(in_a) * $signed(in_b));
            end
        end
    end

    // FIX: Assign FULL width (no truncation) - preserves overflow protection
    assign accum = accum_extended;

endmodule


//=============================================================================
// Top-Level Systolic Array
//=============================================================================

module systolic_array_param #(
    parameter DATA_WIDTH  = 8,
    parameter ARRAY_ROWS  = 4,
    parameter ARRAY_COLS  = 4,
    parameter EXTRA_BITS  = $clog2(ARRAY_ROWS * ARRAY_COLS) + 1,
    parameter ACCUM_WIDTH = 2*DATA_WIDTH + EXTRA_BITS
)(
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    input  logic clr,
    // Input interfaces
    input  logic signed [ARRAY_ROWS-1:0][DATA_WIDTH-1:0] inputs_a,
    input  logic signed [ARRAY_COLS-1:0][DATA_WIDTH-1:0] inputs_b,
    // FIX: Output width includes EXTRA_BITS
    output logic signed [ARRAY_ROWS-1:0][ARRAY_COLS-1:0][ACCUM_WIDTH-1:0] outputs
);

    // Internal wires for systolic connections
    logic signed [ARRAY_ROWS-1:0][ARRAY_COLS-1:0][DATA_WIDTH-1:0] a_wire;
    logic signed [ARRAY_ROWS-1:0][ARRAY_COLS-1:0][DATA_WIDTH-1:0] b_wire;

    // Generate systolic array
    genvar r, c;
    generate
        for (r = 0; r < ARRAY_ROWS; r++) begin : row_gen
            for (c = 0; c < ARRAY_COLS; c++) begin : col_gen

                // Input routing
                logic signed [DATA_WIDTH-1:0] pe_in_a;
                logic signed [DATA_WIDTH-1:0] pe_in_b;

                if (c == 0) begin : first_col
                    assign pe_in_a = inputs_a[r];
                end else begin : other_col
                    assign pe_in_a = a_wire[r][c-1];
                end

                if (r == 0) begin : first_row
                    assign pe_in_b = inputs_b[c];
                end else begin : other_row
                    assign pe_in_b = b_wire[r-1][c];
                end

                // PE instantiation
                pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ARRAY_SIZE(ARRAY_ROWS * ARRAY_COLS),
                    .EXTRA_BITS(EXTRA_BITS)
                ) pe_inst (
                    .clk    (clk),
                    .rst_n  (rst_n),
                    .en     (en),
                    .clr    (clr),
                    .in_a   (pe_in_a),
                    .in_b   (pe_in_b),
                    .out_a  (a_wire[r][c]),
                    .out_b  (b_wire[r][c]),
                    .accum  (outputs[r][c])
                );

            end : col_gen
        end : row_gen
    endgenerate

endmodule
