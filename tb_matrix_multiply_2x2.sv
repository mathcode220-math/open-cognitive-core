// =======================================================================
// Project: Open Cognitive Core Project (OCCP)
// Module: tb_matrix_multiply_2x2 (SystemVerilog Testbench)
// Description: Advanced verification environment to validate the 2x2 
//              matrix multiplication core logic across critical corner cases.
// License: CERN-OHL-W
// =======================================================================

`timescale 1ns / 1ps

module tb_matrix_multiply_2x2;

    // Simulation Clock & Control Signals
    reg        clk;
    reg        rst_n;
    reg        en;
    
    // Matrix A & B Stimulus Registers (8-bit Signed)
    reg signed [7:0]  a00, a01, a10, a11;
    reg signed [7:0]  b00, b01, b10, b11;

    // Output Connections from Device Under Test (DUT)
    wire signed [15:0] c00, c01, c10, c11;
    wire               valid;

    // Instantiate the Design Under Test (DUT)
    matrix_multiply_2x2 uut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .a00(a00), .a01(a01), .a10(a10), .a11(a11),
        .b00(b00), .b01(b01), .b10(b10), .b11(b11),
        .c00(c00), .c01(c01), .c10(c10), .c11(c11),
        .valid(valid)
    );

    // Clock Generation: 50 MHz (20ns Period)
    always #10 clk = ~clk;

    // Automatic Verification Task to Avoid Race Conditions
    task automatic run_test(
        input signed [7:0]  ta00, ta01, ta10, ta11,
        input signed [7:0]  tb00, tb01, tb10, tb11,
        input signed [15:0] exp_c00, exp_c01, exp_c10, exp_c11,
        input string        test_name
    );
        // Drive stimulus on the negative edge to ensure stable setup time
        @(negedge clk);  
        en  = 1'b1;
        a00 = ta00; a01 = ta01; a10 = ta10; a11 = ta11;
        b00 = tb00; b01 = tb01; b10 = tb10; b11 = tb11;

        // Wait for the synchronous design cycle to process inputs
        @(posedge clk);   // Capture input signals
        @(posedge clk);   // Pipeline delay to assert output registers

        // Evaluate Outputs against Golden Reference Models
        if (valid) begin
            if (c00 !== exp_c00 || c01 !== exp_c01 || 
                c10 !== exp_c10 || c11 !== exp_c11) begin
                $error("[FAILED] %s: Expected (%d,%d,%d,%d), Got (%d,%d,%d,%d)",
                       test_name, exp_c00, exp_c01, exp_c10, exp_c11, c00, c01, c10, c11);
            end else begin
                $display("[PASSED] %s Successfully Verified.", test_name);
            end
        end else begin
            $error("[FAILED] %s: Handshake signal 'valid' was not asserted.", test_name);
        end
        
        en = 1'b0;
        @(negedge clk);  // Tiny separation window between distinct test batches
    endtask

    // Main Test Stimulus Sequence
    initial begin
        // Reset Phase Configuration
        clk   = 1'b0;
        rst_n = 1'b0;
        en    = 1'b0;
        
        // Clear all stimulus vectors on startup to prevent unknown states 'x'
        a00 = 8'sd0; a01 = 8'sd0; a10 = 8'sd0; a11 = 8'sd0;
        b00 = 8'sd0; b01 = 8'sd0; b10 = 8'sd0; b11 = 8'sd0;

        // Hold reset active for 3 complete clock cycles
        repeat (3) @(posedge clk);
        rst_n = 1'b1; // Release asynchronous active-low reset
        repeat (2) @(posedge clk);

        // Case 1: Standard Positive Integers
        run_test(
            8'sd2, 8'sd3, 8'sd1, 8'sd4,   // Matrix A
            8'sd5, 8'sd6, 8'sd7, 8'sd8,   // Matrix B
            16'sd31, 16'sd36, 16'sd33, 16'sd38, // Expected C
            "Simple Positive Matrix"
        );

        // Case 2: Identity Matrix Verification
        run_test(
            8'sd1, 8'sd0, 8'sd0, 8'sd1,   // Matrix A (Identity)
            8'sd4, 8'sd5, 8'sd6, 8'sd7,   // Matrix B
            16'sd4, 16'sd5, 16'sd6, 16'sd7,
            "Identity Matrix Multiplier"
        );

        // Case 3: Negative Integer Sign Extension Test
        run_test(
            -8'sd1, -8'sd2, -8'sd3, -8'sd4,
            8'sd1, 8'sd2, 8'sd3, 8'sd4,
            -16'sd7, -16'sd10, -16'sd15, -16'sd22,
            "Negative Valued Elements"
        );

        // Case 4: Upper Limit Corner Bound (Maximum INT8 Positive Overflows)
        run_test(
            8'sd127, 8'sd127, 8'sd127, 8'sd127,
            8'sd127, 8'sd127, 8'sd127, 8'sd127,
            16'sd32258, 16'sd32258, 16'sd32258, 16'sd32258,
            "Maximum Positive Corner Overflow"
        );

        // Case 5: Lower Limit Corner Bound (Minimum INT8 Negative Overflows)
        run_test(
            -8'sd128, -8'sd128, -8'sd128, -8'sd128,
            -8'sd128, -8'sd128, -8'sd128, -8'sd128,
            16'sd32768, 16'sd32768, 16'sd32768, 16'sd32768,
            "Minimum Negative Corner Overflow"
        );

        // Finish and wrap up simulation execution
        $finish;
    end

endmodule
