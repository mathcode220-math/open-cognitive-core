#ifndef OCCP_BRIDGE_H
#define OCCP_BRIDGE_H

#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE

#include <stdint.h>
#include <stddef.h>
#include <unistd.h>

#define OCCP_BASE_ADDR      0x40000000UL
#define OCCP_CTRL_REG       (OCCP_BASE_ADDR + 0x00)
#define OCCP_STATUS_REG     (OCCP_BASE_ADDR + 0x04)
#define OCCP_SRAM_SKEW_A    (OCCP_BASE_ADDR + 0x10)
#define OCCP_SRAM_SKEW_B    (OCCP_BASE_ADDR + 0x20)
#define OCCP_SRAM_RESULT    (OCCP_BASE_ADDR + 0x30)

#define OCCP_CMD_START      0x01
#define OCCP_CMD_RESET      0x02

#define OCCP_STATUS_READY   0x01
#define OCCP_STATUS_BUSY    0x02
#define OCCP_STATUS_DONE    0x04
#define OCCP_STATUS_ERROR   0x08

#define OCCP_TIMEOUT_CYCLES 10000000
#define OCCP_MATRIX_SIZE    2

int occp_init(void);
int occp_dispatch_matrix_multiply(const float *matrix_A, const float *matrix_B, float *matrix_out);
int occp_reset(void);
int occp_is_hardware_available(void);

#endif
