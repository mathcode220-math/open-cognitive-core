// =============================================================================
// Project: Open Cognitive Core Project (OCCP)
// File: tb_axi4_lite_core_ctrl.sv
// Description: Comprehensive testbench verifying the AXI4-Lite control interface.
//              Simulates CPU register reads/writes, pulse triggers, and timeout.
// License: CERN Open Hardware Licence v2 - Weakly Reciprocal (CERN-OHL-W)
// =============================================================================

`timescale 1ns/1ps

module tb_axi4_lite_core_ctrl;

    // Simulation Parameters
    parameter ADDR_WIDTH     = 6;
    parameter DATA_WIDTH     = 32;
    parameter TIMEOUT_CYCLES = 5; // Low threshold configured to trigger timeout verification easily

    // Interconnect Wire Signals
    logic                      S_AXI_ACLK;
    logic                      S_AXI_ARESETN;

    logic [ADDR_WIDTH-1:0]     S_AXI_AWADDR;
    logic                      S_AXI_AWVALID;
    logic                      S_AXI_AWREADY;

    logic [DATA_WIDTH-1:0]     S_AXI_WDATA;
    logic [3:0]                S_AXI_WSTRB;
    logic                      S_AXI_WVALID;
    logic                      S_AXI_WREADY;

    logic [1:0]                S_AXI_BRESP;
    logic                      S_AXI_BVALID;
    input logic                S_AXI_BREADY;

    logic [ADDR_WIDTH-1:0]     S_AXI_ARADDR;
    logic                      S_AXI_ARVALID;
    logic                      S_AXI_ARREADY;

    logic [DATA_WIDTH-1:0]     S_AXI_RDATA;
    logic [1:0]                S_AXI_RRESP;
    logic                      S_AXI_RVALID;
    logic                      S_AXI_RREADY;

    logic                      ctrl_global_en;
    logic                      ctrl_array_clr;
    logic                      ctrl_softmax_start;
    logic                      core_softmax_done;

    // Instantiate Design Under Test (DUT)
    axi4_lite_core_ctrl #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) dut (.*); // Connects all matching pin declarations automatically

    // 100MHz System Clock Generation
    always #5 S_AXI_ACLK = ~S_AXI_ACLK;

    // Custom Tasks simulating clean standard CPU Bus Transactions
    task automatic axi_write(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data, input logic [3:0] strb);
        @(posedge S_AXI_ACLK);
        S_AXI_AWADDR  = addr;
        S_AXI_AWVALID = 1'b1;
        S_AXI_WDATA   = data;
        S_AXI_WSTRB   = strb;
        S_AXI_WVALID  = 1'b1;
        S_AXI_BREADY  = 1'b1;

        // Wait until both addresses and data lines capture handshakes
        fork
            begin while (!S_AXI_AWREADY) @(posedge S_AXI_ACLK); S_AXI_AWVALID = 1'b0; end
            begin while (!S_AXI_WREADY)  @(posedge S_AXI_ACLK); S_AXI_WVALID  = 1'b0; end
        join

        // Wait for the explicit AXI slave write confirmation channel response
        while (!S_AXI_BVALID) @(posedge S_AXI_ACLK);
        @(posedge S_AXI_ACLK);
        S_AXI_BREADY = 1'b0;
    endtask

    task automatic axi_read(input logic [ADDR_WIDTH-1:0] addr);
        @(posedge S_AXI_ACLK);
        S_AXI_ARADDR  = addr;
        S_AXI_ARVALID = 1'b1;
        S_AXI_RREADY  = 1'b1;

        while (!S_AXI_ARREADY) @(posedge S_AXI_ACLK);
        S_AXI_ARVALID = 1'b0;

        while (!S_AXI_RVALID) @(posedge S_AXI_ACLK);
        $display("[CPU BUS READ] Address: 6'h%h -> Captured Register Value: 32'h%h | Protocol Code: %b", addr, S_AXI_RDATA, S_AXI_RRESP);
        @(posedge S_AXI_ACLK);
        S_AXI_RREADY = 1'b0;
    endtask

    initial begin
        // 1. Structural Initialization & System Reset
        S_AXI_ACLK    = 0;
        S_AXI_ARESETN = 0;
        S_AXI_AWADDR  = '0; S_AXI_AWVALID = 0;
        S_AXI_WDATA   = '0; S_AXI_WSTRB   = 0; S_AXI_WVALID = 0;
        S_AXI_BREADY  = 0;
        S_AXI_ARADDR  = '0; S_AXI_ARVALID = 0;
        S_AXI_RREADY  = 0;
        core_softmax_done = 0;

        #20;
        S_AXI_ARESETN = 1; // Release Reset State
        #10;

        $display("\n==========================================================================");
        $display("   [OCCP SIMULATION REPORT - AXI4-LITE BUS CONTROL ENGINE VERIFICATION]   ");
        $display("==========================================================================");

        // 2. Transaction 1: Enable Core globally and trigger Array Clear Pulse commands
        // Offset 0x00 (Control Register) -> Write Payload: 32'h0000_0003 (Bit 0 = Global En, Bit 1 = Array Clr)
        $display("\n[STEP 1] Writing to Control Register (Offset 0x00) with Global Enable + Array Clear...");
        axi_write(6'h00, 32'h0000_0003, 4'hF);
        
        // Monitor intermediate execution states before the next transaction
        #1;
        $display("[CORE HARDWARE STATE] global_en flag: %b | array_clr pulse status: %b", ctrl_global_en, ctrl_array_clr);

        // 3. Transaction 2: Read back Control Register state to verify persistent data retention
        $display("\n[STEP 2] Verifying control register retention state via Bus Reading...");
        axi_read(6'h00);

        // 4. Transaction 3: Emulate Softmax Acceleration Engine Completion State Flags
        $display("\n[STEP 3] External AI sub-system asserts 'core_softmax_done'. Reading status register...");
        core_softmax_done = 1'b1;
        repeat(2) @(posedge S_AXI_ACLK); // Allow propagation through clock synchronizers
        axi_read(6'h04); // Offset 0x04 reads status register

        // 5. Transaction 4: Aborted Transaction Timeout Safety Verification Engine
        $display("\n[STEP 4] Initiating a corrupted partial bus transaction (Stuck Address Without Data)...");
        @(posedge S_AXI_ACLK);
        S_AXI_AWADDR  = 6'h00;
        S_AXI_AWVALID = 1'b1; // Send address validation only, keep data lines dead
        
        // Wait to monitor if the engine recovers automatically without locking the system
        repeat (TIMEOUT_CYCLES + 2) @(posedge S_AXI_ACLK);
        S_AXI_AWVALID = 1'b0;
        
        if (dut.aw_timeout) begin
            $display(">> SUCCESS: Hardware Timeout Engine detected bus stall and aborted transaction cleanly!");
        end else begin
            $display(">> ERROR: Timeout protection failed to trigger.");
        end

        // 6. Transaction 5: Bad Address Space Request Handling Verification
        $display("\n[STEP 5] Requesting data mapping configurations from an invalid memory address pointer...");
        axi_read(6'h3C); // Offset 0x3C is unmapped fallback zone

        $display("==========================================================================\n");
        #20;
        $finish;
    end

endmodule
