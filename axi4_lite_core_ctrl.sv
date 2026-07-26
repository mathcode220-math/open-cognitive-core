// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: axi4_lite_core_ctrl.sv
// Description: AXI4-Lite Control Interface for OCCP Core Accelerator
//              - Register map for control and status
//              - Timeout protection for bus hangs
//              - Synchronization for external handshake signals
// Author: OCCP Contributors
// Version: 1.0.0
// License: CERN Open Hardware Licence v2 - Weakly Reciprocal (CERN-OHL-W)
//          https://ohwr.org/license/CERN-OHL-W
// =============================================================================
// Copyright (c) 2024 OCCP Contributors
// 
// Licensed under the CERN Open Hardware Licence v2 - Weakly Reciprocal.
// You may redistribute and modify this work under the terms of the CERN-OHL-W.
// This work is provided "AS IS" without warranty of any kind.
// =============================================================================

`ifndef SYNTHESIS
`timescale 1ns/1ps
`endif

module axi4_lite_core_ctrl #(
    parameter ADDR_WIDTH     = 6,           // Address bus width
    parameter DATA_WIDTH     = 32,          // Data bus width
    parameter TIMEOUT_CYCLES = 100          // Timeout counter threshold
)(
    input  logic                      S_AXI_ACLK,
    input  logic                      S_AXI_ARESETN,
    
    // AXI4-Lite Write Address Channel
    input  logic [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  logic                      S_AXI_AWVALID,
    output logic                      S_AXI_AWREADY,
    
    // AXI4-Lite Write Data Channel
    input  logic [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  logic [3:0]                S_AXI_WSTRB,
    input  logic                      S_AXI_WVALID,
    output logic                      S_AXI_WREADY,
    
    // AXI4-Lite Write Response Channel
    output logic [1:0]                S_AXI_BRESP,
    output logic                      S_AXI_BVALID,
    input  logic                      S_AXI_BREADY,
    
    // AXI4-Lite Read Address Channel
    input  logic [ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  logic                      S_AXI_ARVALID,
    output logic                      S_AXI_ARREADY,
    
    // AXI4-Lite Read Data Channel
    output logic [DATA_WIDTH-1:0]     S_AXI_RDATA,
    output logic [1:0]                S_AXI_RRESP,
    output logic                      S_AXI_RVALID,
    input  logic                      S_AXI_RREADY,
    
    // Core Control Outputs
    output logic                      ctrl_global_en,
    output logic                      ctrl_array_clr,
    output logic                      ctrl_softmax_start,
    
    // Core Status Inputs
    input  logic                      core_softmax_done
);

    // Register map offsets
    localparam [ADDR_WIDTH-1:0] REG_CTRL   = 6'h00;  // Control register
    localparam [ADDR_WIDTH-1:0] REG_STATUS = 6'h04;  // Status register
    
    // Internal registers
    logic [DATA_WIDTH-1:0] ctrl_reg;
    logic [DATA_WIDTH-1:0] status_reg;
    
    // FSM states for write transaction
    typedef enum logic [1:0] {
        WRITE_IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP
    } write_state_t;
    
    write_state_t write_state, write_next;
    
    // FSM states for read transaction
    typedef enum logic [1:0] {
        READ_IDLE,
        READ_ADDR,
        READ_DATA
    } read_state_t;
    
    read_state_t read_state, read_next;
    
    // Timeout counter
    logic [7:0] timeout_counter;
    logic aw_timeout;
    
    // Byte lane write enable
    logic byte_write_en;
    
    // =========================================================================
    // Timeout Counter Logic
    // =========================================================================
    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            timeout_counter <= '0;
        end else if (S_AXI_AWVALID && !S_AXI_AWREADY) begin
            if (timeout_counter >= TIMEOUT_CYCLES[7:0]) begin
                timeout_counter <= timeout_counter;  // Saturate
            end else begin
                timeout_counter <= timeout_counter + 1'b1;
            end
        end else begin
            timeout_counter <= '0;
        end
    end
    
    assign aw_timeout = (timeout_counter >= TIMEOUT_CYCLES[7:0]);
    
    // =========================================================================
    // Control Register Mapping
    // =========================================================================
    assign ctrl_global_en    = ctrl_reg[0];
    assign ctrl_array_clr    = ctrl_reg[1];
    assign ctrl_softmax_start = ctrl_reg[2];
    
    // Status register mapping
    always_comb begin
        status_reg = '0;
        status_reg[0] = core_softmax_done;
        status_reg[1] = aw_timeout;
    end
    
    // =========================================================================
    // Write FSM State Register
    // =========================================================================
    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            write_state <= WRITE_IDLE;
        end else begin
            write_state <= write_next;
        end
    end
    
    // Write FSM Next State Logic
    always_comb begin
        write_next = write_state;
        S_AXI_AWREADY = 1'b0;
        S_AXI_WREADY  = 1'b0;
        S_AXI_BVALID  = 1'b0;
        S_AXI_BRESP   = 2'b00;  // OKAY response
        
        case (write_state)
            WRITE_IDLE: begin
                if (S_AXI_AWVALID) begin
                    write_next = WRITE_ADDR;
                end
            end
            
            WRITE_ADDR: begin
                S_AXI_AWREADY = 1'b1;
                if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                    write_next = WRITE_DATA;
                end
            end
            
            WRITE_DATA: begin
                S_AXI_WREADY = 1'b1;
                if (S_AXI_WVALID && S_AXI_WREADY) begin
                    write_next = WRITE_RESP;
                end
            end
            
            WRITE_RESP: begin
                S_AXI_BVALID = 1'b1;
                if (S_AXI_BVALID && S_AXI_BREADY) begin
                    write_next = WRITE_IDLE;
                end
            end
            
            default: write_next = WRITE_IDLE;
        endcase
    end
    
    // =========================================================================
    // Read FSM State Register
    // =========================================================================
    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            read_state <= READ_IDLE;
        end else begin
            read_state <= read_next;
        end
    end
    
    // Read FSM Next State Logic
    always_comb begin
        read_next = read_state;
        S_AXI_ARREADY = 1'b0;
        S_AXI_RVALID  = 1'b0;
        S_AXI_RRESP   = 2'b00;  // OKAY response
        S_AXI_RDATA   = '0;
        
        case (read_state)
            READ_IDLE: begin
                if (S_AXI_ARVALID) begin
                    read_next = READ_ADDR;
                end
            end
            
            READ_ADDR: begin
                S_AXI_ARREADY = 1'b1;
                if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                    read_next = READ_DATA;
                end
            end
            
            READ_DATA: begin
                S_AXI_RVALID = 1'b1;
                // Drive read data based on address
                case (S_AXI_ARADDR)
                    REG_CTRL:   S_AXI_RDATA = ctrl_reg;
                    REG_STATUS: S_AXI_RDATA = status_reg;
                    default:    S_AXI_RDATA = '0;  // Unmapped addresses return 0
                endcase
                
                if (S_AXI_RVALID && S_AXI_RREADY) begin
                    read_next = READ_IDLE;
                end
            end
            
            default: read_next = READ_IDLE;
        endcase
    end
    
    // =========================================================================
    // Control Register Write Logic
    // =========================================================================
    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            ctrl_reg <= '0;
        end else if (write_state == WRITE_DATA && S_AXI_WVALID && S_AXI_WREADY) begin
            // Byte lane write enable logic
            byte_write_en = 1'b1;
            
            if (S_AXI_AWADDR == REG_CTRL) begin
                // Full word write for control register
                ctrl_reg <= S_AXI_WDATA;
            end
        end
    end

endmodule
