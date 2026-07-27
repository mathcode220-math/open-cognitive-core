// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: open_cognitive_top.sv
// Description: Top-level module integrating all HDC and ML accelerator components
//              - AXI4-Lite control interface
//              - SRAM skew buffer for systolic array timing
//              - Systolic array for matrix multiplication
//              - ReLU activation
//              - Softmax output
//              - HDC distance computation
//              - HDC N-gram encoder
// Author: OCCP Contributors
// Version: 1.0.0
// License: CERN-OHL-W v2
// =============================================================================
// Copyright (c) 2024 OCCP Contributors
// 
// Licensed under the CERN Open Hardware Licence v2 - Weakly Reciprocal.
// =============================================================================

`ifndef SYNTHESIS
`timescale 1ns/1ps
`endif

module open_cognitive_top #(
    // Data path parameters
    parameter DATA_WIDTH     = 16,
    parameter VECTOR_SIZE    = 4,
    parameter ARRAY_ROWS     = 4,
    parameter ARRAY_COLS     = 4,
    
    // HDC parameters
    parameter HV_DIM         = 1024,
    parameter NGRAM_SIZE     = 3,
    parameter TOKEN_WIDTH    = 16,
    
    // AXI4-Lite parameters
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32
)(
    // Clock and reset
    input  logic                        clk,
    input  logic                        rst_n,
    
    // AXI4-Lite Slave Interface (Core Control)
    input  logic [AXI_ADDR_WIDTH-1:0]   axi_awaddr,
    input  logic                        axi_awvalid,
    output logic                        axi_awready,
    input  logic [AXI_DATA_WIDTH-1:0]   axi_wdata,
    input  logic [AXI_DATA_WIDTH/8-1:0] axi_wstrb,
    input  logic                        axi_wvalid,
    output logic                        axi_wready,
    output logic [1:0]                  axi_bresp,
    output logic                        axi_bvalid,
    input  logic                        axi_bready,
    input  logic [AXI_ADDR_WIDTH-1:0]   axi_araddr,
    input  logic                        axi_arvalid,
    output logic                        axi_arready,
    output logic [AXI_DATA_WIDTH-1:0]   axi_rdata,
    output logic [1:0]                  axi_rresp,
    output logic                        axi_rvalid,
    input  logic                        axi_rready,
    
    // HDC Input Interface
    input  logic                        hdc_en,
    input  logic                        hdc_clear_context,
    input  logic [TOKEN_WIDTH-1:0]      hdc_token_in,
    output logic [HV_DIM-1:0]           hdc_query_hv,
    output logic [HV_DIM-1:0]           hdc_result_hv,
    output logic                        hdc_distance_valid,
    output logic [31:0]                 hdc_hamming_distance,
    
    // Systolic Array Interface
    input  logic                        sa_en,
    input  logic                        sa_start,
    input  logic [ARRAY_ROWS-1:0][(2*DATA_WIDTH)-1:0] sa_matrix_a,
    input  logic [ARRAY_COLS-1:0][(2*DATA_WIDTH)-1:0] sa_matrix_b,
    output logic [ARRAY_ROWS-1:0][(2*DATA_WIDTH)-1:0] sa_result,
    output logic                        sa_done,
    
    // Softmax Interface
    input  logic                        softmax_en,
    input  logic                        softmax_start,
    input  logic [VECTOR_SIZE-1:0][(2*DATA_WIDTH)-1:0] softmax_input,
    output logic [VECTOR_SIZE-1:0][DATA_WIDTH-1:0]     softmax_probs,
    output logic                        softmax_done
);

    // Internal wires for AXI4-Lite controller
    logic axi_reg_write_en;
    logic axi_reg_read_en;
    logic [AXI_ADDR_WIDTH-1:0] axi_reg_addr;
    logic [AXI_DATA_WIDTH-1:0] axi_reg_wdata;
    logic [AXI_DATA_WIDTH-1:0] axi_reg_rdata;
    
    // Internal wires for data path
    logic [ARRAY_ROWS-1:0][(2*DATA_WIDTH)-1:0] skewed_data;
    logic [ARRAY_ROWS-1:0][(2*DATA_WIDTH)-1:0] relu_output;
    logic [VECTOR_SIZE-1:0][(2*DATA_WIDTH)-1:0] softmax_vector;
    
    // HDC internal signals
    logic [HV_DIM-1:0] ngram_hv;
    logic [HV_DIM-1:0] reference_hv [0:7];  // 8 reference vectors
    logic hdc_compute_en;
    
    // =========================================================================
    // AXI4-Lite Controller
    // =========================================================================
    axi4_lite_core_ctrl #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_axi_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI Slave
        .axi_awaddr(axi_awaddr),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),
        .axi_araddr(axi_araddr),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready),
        
        // Register interface
        .reg_write_en(axi_reg_write_en),
        .reg_read_en(axi_reg_read_en),
        .reg_addr(axi_reg_addr),
        .reg_wdata(axi_reg_wdata),
        .reg_rdata(axi_reg_rdata)
    );
    
    // =========================================================================
    // SRAM Skew Buffer
    // =========================================================================
    sram_skew_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .ARRAY_SIZE(ARRAY_ROWS)
    ) u_skew (
        .clk(clk),
        .rst_n(rst_n),
        .en(sa_en),
        .data_in(sa_matrix_a),
        .data_out(skewed_data)
    );
    
    // =========================================================================
    // Systolic Array
    // =========================================================================
    systolic_array_param #(
        .DATA_WIDTH(DATA_WIDTH),
        .ARRAY_ROWS(ARRAY_ROWS),
        .ARRAY_COLS(ARRAY_COLS)
    ) u_systolic (
        .clk(clk),
        .rst_n(rst_n),
        .en(sa_en),
        .start(sa_start),
        .inputs_A(skewed_data),
        .inputs_B(sa_matrix_b),
        .result(sa_result),
        .done(sa_done)
    );
    
    // =========================================================================
    // ReLU Activation
    // =========================================================================
    relu_activation #(
        .DATA_WIDTH(DATA_WIDTH),
        .VECTOR_SIZE(VECTOR_SIZE)
    ) u_relu (
        .clk(clk),
        .rst_n(rst_n),
        .en(sa_en),
        .in_vector({sa_result[0][2*DATA_WIDTH-1:DATA_WIDTH],
                    sa_result[1][2*DATA_WIDTH-1:DATA_WIDTH],
                    sa_result[2][2*DATA_WIDTH-1:DATA_WIDTH],
                    sa_result[3][2*DATA_WIDTH-1:DATA_WIDTH]}),
        .out_vector(relu_output)
    );
    
    // =========================================================================
    // Softmax
    // =========================================================================
    softmax_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .VECTOR_SIZE(VECTOR_SIZE),
        .FRAC_WIDTH(DATA_WIDTH)
    ) u_softmax (
        .clk(clk),
        .rst_n(rst_n),
        .en(softmax_en),
        .start(softmax_start),
        .in_vector(softmax_input),
        .out_probs(softmax_probs),
        .done(softmax_done)
    );
    
    // =========================================================================
    // HDC N-gram Encoder
    // =========================================================================
    hdc_ngram_encoder_v3 #(
        .HV_DIM(HV_DIM),
        .NGRAM_SIZE(NGRAM_SIZE),
        .TOKEN_WIDTH(TOKEN_WIDTH)
    ) u_ngram (
        .clk(clk),
        .rst_n(rst_n),
        .en(hdc_en),
        .clear_context(hdc_clear_context),
        .token_in(hdc_token_in),
        .ngram_hv(ngram_hv)
    );
    
    // Assign query HV from N-gram encoder
    assign hdc_query_hv = ngram_hv;
    
    // =========================================================================
    // HDC Distance Core (placeholder for reference HVs)
    // =========================================================================
    // Note: Reference HVs should be loaded via AXI register interface
    // This is a simplified connection - full implementation needs memory
    
    hdc_distance_core_v3 #(
        .DIM(HV_DIM)
    ) u_hdc_dist (
        .clk(clk),
        .rst_n(rst_n),
        .en(hdc_compute_en),
        .query_hv(hdc_query_hv),
        .ref_hv(reference_hv[0]),  // Use first reference for demo
        .hamming_dist(hdc_hamming_distance),
        .distance_valid(hdc_distance_valid)
    );
    
    // Simple state machine to trigger HDC computation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hdc_compute_en <= 1'b0;
        end else begin
            hdc_compute_en <= hdc_en;
        end
    end
    
    // Default initialization for reference HVs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) begin
                reference_hv[i] <= '0;
            end
        end
        // Reference HVs would be loaded via AXI in full implementation
    end
    
endmodule
