// =======================================================================
// Project: Open Cognitive Core Project (OCCP)
// Module: tb_matrix_multiply_2x2 (SystemVerilog Testbench)
// Description: Advanced verification environment to validate the 2x2
//              matrix multiplication core logic across critical corner cases.
// Author: OCCP Contributors
// Version: 1.0.0
// License: CERN Open Hardware Licence v2 - Weakly Reciprocal (CERN-OHL-W)
//          https://ohwr.org/license/CERN-OHL-W
// =======================================================================
// Copyright (c) 2024 OCCP Contributors
// 
// Licensed under the CERN Open Hardware Licence v2 - Weakly Reciprocal.
// You may redistribute and modify this work under the terms of the CERN-OHL-W.
// This work is provided "AS IS" without warranty of any kind.
// =======================================================================

`timescale 1ns / 1ps

module tb_matrix_multiply_2x2;

    localparam DATA_WIDTH = 8;
    localparam OUT_WIDTH = 17;  // 17 bits to handle (-128)*(-128)*2 = 32768

    logic clk = 0;
    logic rst_n = 0;
    logic en = 0;

    // Matrix A inputs
    logic signed [DATA_WIDTH-1:0] a00, a01, a10, a11;
    // Matrix B inputs
    logic signed [DATA_WIDTH-1:0] b00, b01, b10, b11;

    // Outputs
    logic signed [OUT_WIDTH-1:0] c00, c01, c10, c11;
    logic valid;

    // Clock generation
    always #5 clk = ~clk;

    // Instantiate DUT
    matrix_multiply_2x2 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .a00(a00), .a01(a01), .a10(a10), .a11(a11),
        .b00(b00), .b01(b01), .b10(b10), .b11(b11),
        .c00(c00), .c01(c01), .c10(c10), .c11(c11),
        .valid(valid)
    );

    // Test task
    task run_test;
        input [31:0] test_num;
        input signed [DATA_WIDTH-1:0] ta00, ta01, ta10, ta11;
        input signed [DATA_WIDTH-1:0] tb00, tb01, tb10, tb11;
        input signed [OUT_WIDTH-1:0] exp_c00, exp_c01, exp_c10, exp_c11;
        begin
            $display("\n[Test %0d] Running...", test_num);
            a00 = ta00; a01 = ta01; a10 = ta10; a11 = ta11;
            b00 = tb00; b01 = tb01; b10 = tb10; b11 = tb11;
            en = 1;
            @(posedge clk);
            en = 0;
            wait(valid);
            @(posedge clk);
            
            if (c00 === exp_c00 && c01 === exp_c01 && c10 === exp_c10 && c11 === exp_c11)
                $display("[Test %0d] PASS", test_num);
            else begin
                $display("[Test %0d] FAIL", test_num);
                $display("  Expected: c00=%0d, c01=%0d, c10=%0d, c11=%0d", exp_c00, exp_c01, exp_c10, exp_c11);
                $display("  Got:      c00=%0d, c01=%0d, c10=%0d, c11=%0d", c00, c01, c10, c11);
            end
        end
    endtask

    initial begin
        $display("========================================");
        $display("Matrix Multiply 2x2 Testbench");
        $display("========================================");

        // Reset
        rst_n = 0;
        #12;
        rst_n = 1;
        #10;

        // Case 1: Identity matrix
        run_test(1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1);

        // Case 2: Simple multiplication (A=[[3,0],[2,1]], B=[[4,6],[8,0]])
        // C00=3*4+0*8=12, C01=3*6+0*0=18, C10=2*4+1*8=16, C11=2*6+1*0=12
        run_test(2, 3, 0, 2, 1, 4, 6, 8, 0, 12, 18, 16, 12);

        // Case 3: Negative values
        run_test(3, -1, 2, -3, 4, 5, -6, 7, -8, -19, 22, -43, 50);

        // Case 4: All zeros
        run_test(4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

        // Case 5: Overflow boundary (-128 * -128 * 2 = 32768)
        run_test(5, -128, -128, -128, -128, -128, -128, -128, -128, 32768, 32768, 32768, 32768);

        $display("\n========================================");
        $display("All tests completed!");
        $display("========================================");
        #20;
        $finish;
    end

endmodule
