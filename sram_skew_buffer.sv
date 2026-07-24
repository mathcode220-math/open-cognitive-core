// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: sram_skew_buffer.sv
// Description: Parameterized On-Chip SRAM Buffer with an integrated hardware
//              shift-register network to automatically skew data for the 
//              Systolic Array edges. Removes timing burdens from the main CPU.
// License: CERN Open Hardware Licence v2 - Weakly Reciprocal (CERN-OHL-W)
// =============================================================================

module sram_skew_buffer #(
    parameter DATA_WIDTH = 16,        // Bit-width of each data element
    parameter ARRAY_SIZE = 16         // Number of channels matching the array rows/cols
)(
    input  logic                               clk,
    input  logic                               rst_n,   // Asynchronous active-low reset
    input  logic                               en,      // Execution enable for shifting
    input  logic                               wr_en,   // Write enable to load fresh matrix data
    
    // Parallel bus interface to load a full vector row/column from memory
    input  logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] write_data,
    
    // Automatically skewed outputs ready to plug directly into inputs_A or inputs_B
    output logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] skewed_outputs
);

    // Internal SRAM storage array for keeping local weights or activations
    logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] sram_storage;

    // Shift register pipelines to create the necessary hardware delay waves (Skewing Effect)
    // Row 0 needs 0 delays, Row 1 needs 1 delay, Row N needs N delays.
    // We dynamically generate arrays of shift registers with increasing depths.
    genvar i, d;
    generate
        for (i = 0; i < ARRAY_SIZE; i++) begin : skew_pipeline
            if (i == 0) begin : no_delay
                // Row 0 bypasses the pipeline and connects directly to the output
                assign skewed_outputs[0] = sram_storage[0];
            end else begin : delay_chain
                // Internal registers for tracking the delay pipeline stages
                logic [i-1:0][DATA_WIDTH-1:0] delay_regs;

                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        delay_regs <= '0;
                    end else if (en) begin
                        // Shift the historical data through the pipe
                        delay_regs[0] <= sram_storage[i];
                        for (int stage = 1; stage < i; stage++) begin
                            delay_regs[stage] <= delay_regs[stage-1];
                        end
                    end
                end
                // Connect the last stage of the delay pipeline to the physical array output
                assign skewed_outputs[i] = delay_regs[i-1];
            end
        end
    endgenerate

    // Asynchronous or synchronous interface to load weights/activations into local SRAM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sram_storage <= '0;
        end else if (wr_en) begin
            sram_storage <= write_data; // Parallel latching of matrix vectors
        end
    end

endmodule
