// ============================================================================
// hdc_distance_core_v3.sv
// Pipelined Hamming Distance Core for Hyperdimensional Computing
//
// Architecture:
//   Stage 0 -> XOR + Input Register
//   Stage 1 -> Parallel Popcount (16 x 64-bit chunks)
//   Stage 2 -> Adder Tree + Output Register
//
// Interface: AXI-Stream (valid/ready handshake)
// Latency:   3 clock cycles
// ============================================================================

module hdc_distance_core_v3 #(
    parameter VECTOR_SIZE = 1024,
    parameter STAGE_WIDTH = 64
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // ---- AXI-Stream Slave (Input) ----
    input  logic                          s_valid,
    output logic                          s_ready,
    input  logic [VECTOR_SIZE-1:0]        vector_a,
    input  logic [VECTOR_SIZE-1:0]        vector_b,

    // ---- AXI-Stream Master (Output) ----
    output logic                          m_valid,
    input  logic                          m_ready,
    output logic [$clog2(VECTOR_SIZE):0]  hamming_distance
);

    // ========================================================================
    // Local Parameters
    // ========================================================================
    localparam NUM_CHUNKS  = VECTOR_SIZE / STAGE_WIDTH;          // 16
    localparam CHUNK_CNT_W = $clog2(STAGE_WIDTH) + 1;            // 7  (0..64)
    localparam OUT_W       = $clog2(VECTOR_SIZE) + 1;            // 11 (0..1024)

    // ========================================================================
    // Pipeline Control
    // ========================================================================
    // Advance pipeline when output register is free or downstream accepts
    wire pipe_en = !m_valid || m_ready;

    // Accept new input only when the pipeline can advance
    assign s_ready = pipe_en;

    // ========================================================================
    // Stage 0: XOR + Input Register
    // ========================================================================
    logic [VECTOR_SIZE-1:0] xor_reg;
    logic                   v0;           // valid bit for stage 0

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xor_reg <= '0;
            v0      <= 1'b0;
        end else if (pipe_en) begin
            xor_reg <= vector_a ^ vector_b;
            v0      <= s_valid & s_ready;
        end
    end

    // ========================================================================
    // Stage 1: Parallel Popcount (each chunk processed independently)
    // ========================================================================
    logic [CHUNK_CNT_W-1:0] partial_cnt [NUM_CHUNKS];
    logic                   v1;           // valid bit for stage 1

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_CHUNKS; i++)
                partial_cnt[i] <= '0;
            v1 <= 1'b0;
        end else if (pipe_en) begin
            for (int i = 0; i < NUM_CHUNKS; i++)
                partial_cnt[i] <= $countones(xor_reg[i*STAGE_WIDTH +: STAGE_WIDTH]);
            v1 <= v0;
        end
    end

    // ========================================================================
    // Stage 2: Adder Tree + Output Register
    // ========================================================================

    // Combinational adder tree: sum all partial counts
    logic [OUT_W-1:0] sum_comb;

    always_comb begin
        sum_comb = '0;
        for (int i = 0; i < NUM_CHUNKS; i++)
            sum_comb = sum_comb + {{(OUT_W - CHUNK_CNT_W){1'b0}}, partial_cnt[i]};
    end

    // Output register with valid flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hamming_distance <= '0;
            m_valid          <= 1'b0;
        end else if (pipe_en) begin
            hamming_distance <= sum_comb;
            m_valid          <= v1;
        end
    end

    // ========================================================================
    // Simulation-only Assertions (ignored during synthesis)
    // ========================================================================
    // synthesis translate_off

    initial begin
        assert (VECTOR_SIZE % STAGE_WIDTH == 0)
            else $fatal(1, "VECTOR_SIZE must be divisible by STAGE_WIDTH");
        assert (STAGE_WIDTH == 32 || STAGE_WIDTH == 64 || STAGE_WIDTH == 128)
            else $warning("Unusual STAGE_WIDTH: %0d", STAGE_WIDTH);
    end

    // m_valid must remain asserted until handshake completes
    assert property (@(posedge clk) disable iff (!rst_n)
        (m_valid && !m_ready) |=> m_valid
    ) else $error("m_valid dropped without handshake!");

    // Output data must remain stable during backpressure
    assert property (@(posedge clk) disable iff (!rst_n)
        (m_valid && !m_ready) |=> $stable(hamming_distance)
    ) else $error("Output changed during backpressure!");

    // synthesis translate_on

endmodule
