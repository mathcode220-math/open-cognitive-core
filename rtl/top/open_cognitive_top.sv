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
// Integration fixes:
//   - Re-wired every sub-module to its actual port list / parameter names.
//     The previous draft used invented interfaces (reg_write_en/reg_read_en,
//     data_in/data_out, inputs_A/inputs_B/result/done, in_vector/out_vector,
//     query_hv/ref_hv/hamming_dist, DIM) that matched no real module.
//   - syst_accum now reflects systolic_array_param's true accumulator width
//     (2*DATA_WIDTH + $clog2(ROWS*COLS) + 1) instead of 2*DATA_WIDTH.
//   - ReLU is instantiated per element (its real interface is 1-in/1-out).
//   - Softmax is fed from the systolic->ReLU row-0 chain (was a dead input).
//   - HDC n-gram uses the actual module name hdc_ngram_encoder_v4_pipelined
//     and its ready/valid handshake drives the distance core.
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
    // Systolic accumulator width (must match systolic_array_param)
    parameter EXTRA_BITS     = $clog2(ARRAY_ROWS * ARRAY_COLS) + 1,
    parameter ACCUM_WIDTH    = 2*DATA_WIDTH + EXTRA_BITS,

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
    input  logic [ARRAY_ROWS-1:0][DATA_WIDTH-1:0]     sa_matrix_a,
    input  logic [ARRAY_COLS-1:0][DATA_WIDTH-1:0]     sa_matrix_b,
    output logic [ARRAY_ROWS-1:0][ARRAY_COLS-1:0][ACCUM_WIDTH-1:0] sa_result,
    output logic                        sa_done,

    // Softmax Interface
    input  logic                        softmax_en,
    input  logic                        softmax_start,
    output logic [VECTOR_SIZE-1:0][DATA_WIDTH-1:0]     softmax_probs,
    output logic                        softmax_done
);

    // AXI4-Lite controller control outputs
    logic ctrl_global_en;
    logic ctrl_array_clr;
    logic ctrl_softmax_start;

    // Effective enable signals (local AXI control OR external enables)
    logic sa_en_eff;
    logic softmax_start_eff;
    logic hdc_en_eff;

    // Skew buffer
    logic [ARRAY_ROWS-1:0][DATA_WIDTH-1:0] skewed_data;

    // ReLU outputs (applied to systolic row 0 that feeds the softmax)
    logic [ARRAY_COLS-1:0][DATA_WIDTH-1:0] relu_output;

    // Softmax vector (zero-extended ReLU outputs)
    logic [VECTOR_SIZE-1:0][(2*DATA_WIDTH)-1:0] softmax_vector;

    // HDC internal signals
    logic [HV_DIM-1:0] ngram_hv;
    logic [HV_DIM-1:0] reference_hv [0:7];  // 8 reference vectors
    logic ngram_valid;
    logic hdc_s_ready;
    logic [$clog2(HV_DIM):0] hamming_dist;

    // =========================================================================
    // AXI4-Lite Controller
    // =========================================================================
    axi4_lite_core_ctrl #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_axi_ctrl (
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(rst_n),

        // AXI Slave
        .S_AXI_AWADDR(axi_awaddr),
        .S_AXI_AWVALID(axi_awvalid),
        .S_AXI_AWREADY(axi_awready),
        .S_AXI_WDATA(axi_wdata),
        .S_AXI_WSTRB(axi_wstrb),
        .S_AXI_WVALID(axi_wvalid),
        .S_AXI_WREADY(axi_wready),
        .S_AXI_BRESP(axi_bresp),
        .S_AXI_BVALID(axi_bvalid),
        .S_AXI_BREADY(axi_bready),
        .S_AXI_ARADDR(axi_araddr),
        .S_AXI_ARVALID(axi_arvalid),
        .S_AXI_ARREADY(axi_arready),
        .S_AXI_RDATA(axi_rdata),
        .S_AXI_RRESP(axi_rresp),
        .S_AXI_RVALID(axi_rvalid),
        .S_AXI_RREADY(axi_rready),

        // Control / status interface
        .ctrl_global_en(ctrl_global_en),
        .ctrl_array_clr(ctrl_array_clr),
        .ctrl_softmax_start(ctrl_softmax_start),
        .core_softmax_done(softmax_done)
    );

    // Effective enables: local AXI control OR external interface enables
    assign sa_en_eff         = sa_en | ctrl_global_en;
    assign softmax_start_eff = (softmax_start | ctrl_softmax_start) &
                               (softmax_en | ctrl_global_en);
    assign hdc_en_eff        = (hdc_en | ctrl_global_en) &
                               (hdc_s_ready | ~ngram_valid);

    // =========================================================================
    // SRAM Skew Buffer
    // =========================================================================
    sram_skew_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .ARRAY_SIZE(ARRAY_ROWS)
    ) u_skew (
        .clk(clk),
        .rst_n(rst_n),
        .en(sa_en_eff),
        .wr_en(sa_start),
        .write_data(sa_matrix_a),
        .skewed_data(skewed_data)
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
        .en(sa_en_eff),
        .clr(ctrl_array_clr),
        .inputs_a(skewed_data),
        .inputs_b(sa_matrix_b),
        .outputs(sa_result)
    );

    // One-cycle completion pulse following a systolic start
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sa_done <= 1'b0;
        end else begin
            sa_done <= sa_start;
        end
    end

    // =========================================================================
    // ReLU Activation (combinational, applied to systolic row 0)
    // =========================================================================
    genvar c;
    generate
        for (c = 0; c < ARRAY_COLS; c++) begin : relu_col
            relu_activation #(
                .DATA_WIDTH(DATA_WIDTH),
                .ACCUM_WIDTH(ACCUM_WIDTH)
            ) u_relu (
                .accum_in(sa_result[0][c]),
                .relu_out(relu_output[c])
            );
        end
    endgenerate

    // Build the softmax input vector from the ReLU outputs of systolic row 0
    genvar c2;
    generate
        for (c2 = 0; c2 < VECTOR_SIZE; c2++) begin : softmax_vec_gen
            assign softmax_vector[c2] = {{DATA_WIDTH{1'b0}}, relu_output[c2]};
        end
    endgenerate

    // =========================================================================
    // Softmax
    // =========================================================================
    softmax_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .VECTOR_SIZE(VECTOR_SIZE)
    ) u_softmax (
        .clk(clk),
        .rst_n(rst_n),
        .start(softmax_start_eff),
        .in_vector(softmax_vector),
        .out_probs(softmax_probs),
        .done(softmax_done)
    );

    // =========================================================================
    // HDC N-gram Encoder
    // =========================================================================
    hdc_ngram_encoder_v4_pipelined #(
        .HV_DIM(HV_DIM),
        .NGRAM_SIZE(NGRAM_SIZE),
        .TOKEN_WIDTH(TOKEN_WIDTH)
    ) u_ngram (
        .clk(clk),
        .rst_n(rst_n),
        .en(hdc_en_eff),
        .clear_context(hdc_clear_context),
        .token_in(hdc_token_in),
        .ngram_hv(ngram_hv),
        .ngram_valid(ngram_valid)
    );

    // Assign query HV from N-gram encoder
    assign hdc_query_hv = ngram_hv;

    // =========================================================================
    // HDC Distance Core
    // =========================================================================
    // Note: Reference HVs should be loaded via AXI register interface.
    // This is a simplified connection - full implementation needs memory.
    hdc_distance_core_v3 #(
        .VECTOR_SIZE(HV_DIM)
    ) u_hdc_dist (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(ngram_valid),
        .s_ready(hdc_s_ready),
        .vector_a(hdc_query_hv),
        .vector_b(reference_hv[0]),  // Use first reference for demo
        .m_valid(hdc_distance_valid),
        .m_ready(1'b1),
        .hamming_distance(hamming_dist)
    );

    assign hdc_hamming_distance = {{(32 - ($clog2(HV_DIM) + 1)){1'b0}}, hamming_dist};

    // Placeholder result HV (would come from a trained model memory)
    assign hdc_result_hv = reference_hv[0];

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
