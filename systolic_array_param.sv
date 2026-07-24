// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: systolic_array_param.sv
// Description: Unified Parameterized Systolic Array with global clock enable
//              and its internal Processing Element (PE) for AI matrix acceleration.
// License: CERN Open Hardware Licence v2 - Weakly Reciprocal (CERN-OHL-W)
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Processing Element (PE) Module
// -----------------------------------------------------------------------------
module pe #(
    parameter DATA_WIDTH = 16
)(
    input  logic                    clk,
    input  logic                    rst_n, // Asynchronous active-low reset
    input  logic                    en,    // Clock enabling signal for power saving & stalling
    input  logic                    clr,   // Synchronous accumulator clear (restarts MAC)
    input  logic [DATA_WIDTH-1:0]   in_a,  // Activation input from left
    input  logic [DATA_WIDTH-1:0]   in_b,  // Weight input from top
    output logic [DATA_WIDTH-1:0]   out_a, // Registered data output to right
    output logic [DATA_WIDTH-1:0]   out_b, // Registered data output downwards
    output logic [(2*DATA_WIDTH)-1:0] accum // 2x bit-width to prevent overflow during MAC
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_a <= '0;
            out_b <= '0;
            accum <= '0;
        end else if (en) begin
            out_a <= in_a;
            out_b <= in_b;
            if (clr) begin
                accum <= '0;
            end else begin
                accum <= accum + (in_a * in_b);
            end
        end
    end

endmodule


// -----------------------------------------------------------------------------
// 2. Top-Level Parameterized Systolic Array Module
// -----------------------------------------------------------------------------
module systolic_array_param #(
    parameter DATA_WIDTH = 16,        // Bit-width of input data (e.g., INT16/FP16)
    parameter ARRAY_ROWS = 16,        // Scalable number of rows in the array
    parameter ARRAY_COLS = 16         // Scalable number of columns in the array
)(
    input  logic                                                      clk,
    input  logic                                                      rst_n,
    input  logic                                                      en,        // Global execution enable (Stalls pipeline when low)
    input  logic                                                      clr,       // Synchronously resets all internal PE accumulators
    
    // Parallel input interfaces
    input  logic [ARRAY_ROWS-1:0][DATA_WIDTH-1:0]                     inputs_A,  // Input stream from the left (Activations)
    input  logic [ARRAY_COLS-1:0][DATA_WIDTH-1:0]                     inputs_B,  // Input stream from the top (Weights)
    
    // Multi-dimensional output interface
    output logic [ARRAY_ROWS-1:0][ARRAY_COLS-1:0][(2*DATA_WIDTH)-1:0] outputs
);

    // Internal inter-PE propagation wires
    logic [ARRAY_ROWS-1:0][ARRAY_COLS:0][DATA_WIDTH-1:0] wire_a;
    logic [ARRAY_ROWS:0][ARRAY_COLS-1:0][DATA_WIDTH-1:0] wire_b;

    // Connect external boundaries to internal mesh edges
    genvar r, c;
    generate
        for (r = 0; r < ARRAY_ROWS; r++) begin : connect_inputs_a
            assign wire_a[r][0] = inputs_A[r];
        end
        for (c = 0; c < ARRAY_COLS; c++) begin : connect_inputs_b
            assign wire_b[0][c] = inputs_B[c];
        end
    endgenerate

    // Hardware generation block for the structural execution grid
    generate
        for (r = 0; r < ARRAY_ROWS; r++) begin : row_gen
            for (c = 0; c < ARRAY_COLS; c++) begin : col_gen
                pe #(
                    .DATA_WIDTH(DATA_WIDTH)
                ) pe_inst (
                    .clk   (clk),
                    .rst_n (rst_n),
                    .en    (en),               // Propagates active execution state
                    .clr   (clr),              // Resets MAC for new operations
                    .in_a  (wire_a[r][c]),
                    .in_b  (wire_b[r][c]),
                    .out_a (wire_a[r][c+1]),   // Safe horizontal step
                    .out_b (wire_b[r+1][c]),   // Safe vertical step
                    .accum (outputs[r][c])
                );
            end
        end
    endgenerate

endmodule
