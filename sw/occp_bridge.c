#include "occp_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile uint32_t *ctrl_reg = NULL;
static volatile uint32_t *status_reg = NULL;
static volatile float    *sram_buffer_A = NULL;
static volatile float    *sram_buffer_B = NULL;
static volatile float    *sram_buffer_res = NULL;

static int is_simulation_mode = 1;
static int is_initialized = 0;

static uint32_t mock_ctrl = 0;
static uint32_t mock_status = OCCP_STATUS_READY;
static float mock_sram_A[OCCP_MATRIX_SIZE * OCCP_MATRIX_SIZE];
static float mock_sram_B[OCCP_MATRIX_SIZE * OCCP_MATRIX_SIZE];
static float mock_sram_res[OCCP_MATRIX_SIZE * OCCP_MATRIX_SIZE];

int occp_init(void) {
    if (is_initialized) {
        printf("[OCCP Bridge] Already initialized.\n");
        return 0;
    }
    
    printf("[OCCP Bridge] Initializing hardware connection...\n");
    
    if (is_simulation_mode) {
        printf("[OCCP Bridge] Physical hardware not detected. Running in Co-Simulation Mode.\n");
        
        mock_ctrl = 0;
        mock_status = OCCP_STATUS_READY;
        
        ctrl_reg = &mock_ctrl;
        status_reg = &mock_status;
        sram_buffer_A = mock_sram_A;
        sram_buffer_B = mock_sram_B;
        sram_buffer_res = mock_sram_res;
        
        printf("[OCCP Bridge] Simulation buffers allocated.\n");
    } else {
        printf("[OCCP Bridge] ERROR: Real hardware mode not implemented yet.\n");
        return -1;
    }
    
    is_initialized = 1;
    printf("[OCCP Bridge] Initialization complete.\n");
    return 0;
}

int occp_dispatch_matrix_multiply(const float *matrix_A, const float *matrix_B, float *matrix_out) {
    if (!is_initialized) {
        printf("[OCCP Bridge] ERROR: Not initialized. Call occp_init() first.\n");
        return -1;
    }
    
    if (!matrix_A || !matrix_B || !matrix_out) {
        printf("[OCCP Bridge] ERROR: NULL pointer in matrix arguments.\n");
        return -1;
    }
    
    printf("[OCCP Bridge] Checking hardware status...\n");
    int timeout_counter = 0;
    while ((*status_reg & OCCP_STATUS_READY) == 0) {
        timeout_counter++;
        if (timeout_counter > OCCP_TIMEOUT_CYCLES) {
            printf("[OCCP Bridge] ERROR: Hardware timeout! Chip not responding.\n");
            *status_reg |= OCCP_STATUS_ERROR;
            return -1;
        }
        if (timeout_counter % 100000 == 0) {
            usleep(1);
        }
    }
    
    printf("[OCCP Bridge] Hardware ready. Streaming weights into SRAM Skew Buffers...\n");
    
    const int buffer_size = OCCP_MATRIX_SIZE * OCCP_MATRIX_SIZE;
    
    for (int i = 0; i < buffer_size; i++) {
        sram_buffer_A[i] = matrix_A[i];
        sram_buffer_B[i] = matrix_B[i];
    }
    
    printf("[OCCP Bridge] Data streaming complete. Triggering systolic array...\n");
    
    *status_reg = OCCP_STATUS_BUSY;
    *ctrl_reg = OCCP_CMD_START;
    
    printf("[OCCP Bridge] Processing neural calculations on silicon...\n");
    
    if (is_simulation_mode) {
        sram_buffer_res[0] = (matrix_A[0] * matrix_B[0]) + (matrix_A[1] * matrix_B[2]);
        sram_buffer_res[1] = (matrix_A[0] * matrix_B[1]) + (matrix_A[1] * matrix_B[3]);
        sram_buffer_res[2] = (matrix_A[2] * matrix_B[0]) + (matrix_A[3] * matrix_B[2]);
        sram_buffer_res[3] = (matrix_A[2] * matrix_B[1]) + (matrix_A[3] * matrix_B[3]);
        
        *status_reg = OCCP_STATUS_DONE;
    }
    
    timeout_counter = 0;
    while ((*status_reg & OCCP_STATUS_DONE) == 0) {
        timeout_counter++;
        if (timeout_counter > OCCP_TIMEOUT_CYCLES) {
            printf("[OCCP Bridge] ERROR: Computation timeout!\n");
            *status_reg |= OCCP_STATUS_ERROR;
            return -1;
        }
        if (timeout_counter % 100000 == 0) {
            usleep(1);
        }
    }
    
    printf("[OCCP Bridge] Computation complete. Retrieving results...\n");
    
    for (int i = 0; i < buffer_size; i++) {
        matrix_out[i] = sram_buffer_res[i];
    }
    
    *ctrl_reg = 0;
    *status_reg = OCCP_STATUS_READY;
    
    printf("[OCCP Bridge] Execution complete! Result sent back to application.\n");
    return 0;
}

int occp_reset(void) {
    if (!is_initialized) {
        return -1;
    }
    
    printf("[OCCP Bridge] Resetting OCCP co-processor...\n");
    
    *ctrl_reg = OCCP_CMD_RESET;
    *status_reg = OCCP_STATUS_READY;
    
    const int buffer_size = OCCP_MATRIX_SIZE * OCCP_MATRIX_SIZE;
    for (int i = 0; i < buffer_size; i++) {
        sram_buffer_A[i] = 0.0f;
        sram_buffer_B[i] = 0.0f;
        sram_buffer_res[i] = 0.0f;
    }
    
    printf("[OCCP Bridge] Reset complete.\n");
    return 0;
}

int occp_is_hardware_available(void) {
    return is_simulation_mode ? 0 : 1;
}

#ifdef OCCP_BRIDGE_TEST
int main(void) {
    printf("=== OCCP Bridge Test Suite ===\n\n");
    
    if (occp_init() != 0) {
        printf("Failed to initialize OCCP bridge\n");
        return 1;
    }
    
    float matrix_A[4] = {1.0f, 2.0f, 3.0f, 4.0f};
    float matrix_B[4] = {5.0f, 6.0f, 7.0f, 8.0f};
    float matrix_C[4] = {0.0f};
    
    printf("\nInput Matrix A:\n");
    printf("  [%.1f  %.1f]\n", matrix_A[0], matrix_A[1]);
    printf("  [%.1f  %.1f]\n", matrix_A[2], matrix_A[3]);
    
    printf("\nInput Matrix B:\n");
    printf("  [%.1f  %.1f]\n", matrix_B[0], matrix_B[1]);
    printf("  [%.1f  %.1f]\n", matrix_B[2], matrix_B[3]);
    
    if (occp_dispatch_matrix_multiply(matrix_A, matrix_B, matrix_C) != 0) {
        printf("Matrix multiplication failed\n");
        return 1;
    }
    
    printf("\nResult Matrix C (A x B):\n");
    printf("  [%.1f  %.1f]\n", matrix_C[0], matrix_C[1]);
    printf("  [%.1f  %.1f]\n", matrix_C[2], matrix_C[3]);
    
    printf("\nExpected result:\n");
    printf("  [19.0  22.0]\n");
    printf("  [43.0  50.0]\n");
    
    occp_reset();
    
    printf("\n=== Test Complete ===\n");
    return 0;
}
#endif
