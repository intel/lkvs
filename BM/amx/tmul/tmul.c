// SPDX-License-Identifier: GPL-2.0
/* Copyright(c) 2022 Intel Corporation. All rights reserved. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <stdlib.h>
#include <getopt.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <stdbool.h>
#include <linux/futex.h>
#include <sys/syscall.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include <math.h>
#include <immintrin.h>

#define MIN_THREAD_NUM 1
#define XFEATURE_XTILEDATA 18
#define ARCH_REQ_XCOMP_PERM 0x1023
#define ROW_NUM 16
#define COL_NUM 64
#define FUTEX_VAL 0x5E5E5E5E

#define DPBD(c, x, y, type1, type2)								\
	{														\
		c = (c +											\
		(uint32_t)((type1)(((uint8_t *)(x))[0])) * (uint32_t)((type2)(((uint8_t *)(y))[0])) +	\
		(uint32_t)((type1)(((uint8_t *)(x))[1])) * (uint32_t)((type2)(((uint8_t *)(y))[1])) +	\
		(uint32_t)((type1)(((uint8_t *)(x))[2])) * (uint32_t)((type2)(((uint8_t *)(y))[2])) +	\
		(uint32_t)((type1)(((uint8_t *)(x))[3])) * (uint32_t)((type2)(((uint8_t *)(y))[3])));	\
	}

#define load_tile_reg(tmm_num, tile, stride)						\
	{								\
		asm volatile("tileloadd\t(%0,%1,1), %%tmm" #tmm_num				\
			     : : "r" ((void *)(tile)->buf), "r" ((long)stride) : "memory");	\
	}

#define store_tile_reg(tmm_num, tile, stride)						\
	{								\
		asm volatile("tilestored\t%%tmm" #tmm_num ", (%0,%1,1)"				\
			     : : "r" ((void *)(tile)->buf), "r" ((long)stride) : "memory");	\
	}

enum {
	BREAK_BY_NOTHING = 0,
	BREAK_BY_YIELD = 1,
	BREAK_BY_SLEEP,
	BREAK_BY_TRAP,
	BREAK_BY_SIGNAL,
	BREAK_BY_FUTEX,
	BREAK_REASON_MAX = BREAK_BY_FUTEX
} BREAK_REASON;

enum {
	INS_TDPBF16PS = 0,
	INS_TDPBSSD,
	INS_TDPBSUD,
	INS_TDPBUSD,
	INS_TDPBUUD,
#ifdef FP16
	INS_TDPFP16PS,
	INS_MAX_NUM = INS_TDPFP16PS
#else
	INS_MAX_NUM = INS_TDPBUUD
#endif
} ENUM_INSTRUCTION_TYPE;

struct __tile_config {
	uint8_t palette_id;
	uint8_t start_row;
	uint8_t reserved_0[14];
	uint16_t colsb[8];
	uint16_t reserved_1[8];
	uint8_t rows[8];
	uint8_t reserved_2[8];
};

union __union_tile_config {
	struct __tile_config s;
	uint8_t a[64];
};

struct __tile {
	uint8_t buf[1024];
	int32_t rows;
	int32_t colsb;
};

static bool *thread_done;
static int32_t *futex_ptr;
struct __tile *buf_tile1, *buf_tile2, *buf_tile3, *buf_tile4;
static int32_t thread_num = MIN_THREAD_NUM;
static int32_t break_reason = BREAK_BY_NOTHING;
static uint32_t cycles = 1;
static int32_t ins_type = INS_TDPBSSD;

/*
 * convert_fp32_to_bf16() - Convert data format.
 * @fp32: A FP32 value.
 *
 * Covert FP32 to BF16.
 */
static uint16_t convert_fp32_to_bf16(float fp32)
{
	uint32_t u = *((uint32_t *)&fp32);

	u = (u >> 16) & 0xffff;

	return (uint16_t)u;
}

/*
 * convert_bf16_to_fp32() - Convert data format.
 * @bf16: A BF16 value.
 *
 * Covert BF16 to FP32.
 */
static float convert_bf16_to_fp32(uint16_t bf16)
{
	uint32_t u = (uint32_t)(bf16 << 16);

	return *((float *)&u);
}

#ifdef FP16
/*
 * convert_fp32_to_fp16() - Convert data format.
 * @fp32: A FP32 value.
 *
 * Covert FP32 to FP16.
 */
static uint16_t convert_fp32_to_fp16(float fp32)
{
	uint32_t u = *((uint32_t *)&fp32);
	uint16_t sign = (u >> 16) & 0x8000;
	uint16_t fraction = (u & 0x007fffff) >> 13;
	uint16_t exponent = (((u & 0x7f800000) >> 23) - 127 + 15) << 10;

	uint16_t fp16 = sign | exponent | fraction;

	return fp16;
}

/*
 * convert_fp16_to_fp32() - Convert data format.
 * @fp: A FP16 value.
 *
 * Covert FP16 to FP32.
 */
static float convert_fp16_to_fp32(uint16_t fp16)
{
	int shift;
	uint32_t u;
	float fp32 = 0;
	uint32_t sign = (fp16 & 0x8000) << 16;
	uint32_t fraction = (fp16 & 0x3ff) << 13;
	uint32_t exponent = (fp16 & 0x7c00) >> 10;

	if (exponent == 0x1f && fraction == 0) {
		if (sign)
			fp32 = -INFINITY;
		else
			fp32 = INFINITY;
	} else if (exponent == 0x1f && fraction != 0) {
		fp32 = NAN;
	} else if (exponent == 0) {
		if (fraction == 0) {
			/* +0.0, -0.0 */
			u = sign;
			fp32 = *((float *)&u);
		} else {
			/* Convert subnormal into normal fp32 number */
			for (int i = 22; i >= 12; i--) {
				if (fraction & (1 << i)) {
					shift = (1 + 22 - i);
					fraction = (fraction << shift) & 0x7fffff;
					u = sign |
					    ((exponent - 15 - (shift - 1) + 127) << 23) |
					    fraction;
					fp32 = *((float *)&u);

					break;
				}
			}
		}
		//fp32 = *((float *)&u);
	} else {
		u = sign | ((exponent - 15 + 127) << 23) | fraction;
		fp32 = *((float *)&u);
	}

	return fp32;
}
#endif

/*
 * do_syscall() - Execute syscall instruction.
 * @nr: syscall number will be saved rax register.
 * @rdi: a parameter will be saved in rdi register and passed to Kernel.
 * @rsi: a parameter will be saved in rsi register and passed to Kernel.
 * @rdx: a parameter will be saved in rdx register and passed to Kernel.
 * @r10: a parameter will be saved in r10 register and passed to Kernel.
 * @r8: a parameter will be saved in r8 register and passed to Kernel.
 * @r9: a parameter will be saved in r9 register and passed to Kernel.
 *
 * Use inline asm to execute syscall instruction directly.
 */
static uint64_t do_syscall(uint64_t nr, uint64_t rdi, uint64_t rsi, uint64_t rdx,
			   uint64_t r10, uint64_t r8, uint64_t r9)
{
	uint64_t rtn;

	asm volatile("movq %0, %%rdi" : : "r"(rdi) : "%rdi");
	asm volatile("movq %0, %%rsi" : : "r"(rsi) : "%rsi");
	asm volatile("movq %0, %%rdx" : : "r"(rdx) : "%rdx");
	asm volatile("movq %0, %%r10" : : "r"(r10) : "%r10");
	asm volatile("movq %0, %%r8" : : "r"(r8) : "%r8");
	asm volatile("movq %0, %%r9" : : "r"(r9) : "%r9");
	asm volatile("syscall"
		     : "=a" (rtn)
		     : "a" (nr)
		     : "rcx", "r11", "memory", "cc");

	return rtn;
}

static uint32_t get_random(void)
{
	uint32_t random_val = 0;
	FILE *fp = fopen("/dev/random", "r");
	size_t num = 0;

	if (fp) {
		num = fread((void *)&random_val, sizeof(random_val), 1, fp);
		fclose(fp);
	}

	if (num >= 1)
		return random_val;
	else
		return 1;
}

/*
 * init_bf16_tile() - Init buffer.
 * @buf: The buffer for saving data.
 * @rows: Row number of the matrix.
 * @colsb: Column number of the matrix.
 *
 * Init buffer with chaotic float.
 */
static void init_bf16_tile(struct __tile *tile_ptr, uint8_t rows, uint8_t colsb)
{
	int32_t i, j;
	uint16_t *ptr = (uint16_t *)tile_ptr->buf;
	int32_t cols = colsb / 2;
	float f = 0;

	tile_ptr->rows = rows;
	tile_ptr->colsb = colsb;

	for (i = 0; i < rows; i++)
		for (j = 0; j < cols; j++) {
			f = 2.718f;
			ptr[i * cols + j] = convert_fp32_to_bf16(f);
		}
}

#ifdef FP16
/*
 * init_fp16_tile() - Init buffer.
 * @buf: The buffer for saving data.
 * @rows: Row number of the matrix.
 * @colsb: Column number of the matrix.
 *
 * Init buffer with chaotic float.
 */
static void init_fp16_tile(struct __tile *tile_ptr, uint8_t rows,
			   uint8_t colsb)
{
	int32_t i, j;
	uint16_t *ptr = (uint16_t *)tile_ptr->buf;
	int32_t cols = colsb / 2;
	float f = 0;

	tile_ptr->rows = rows;
	tile_ptr->colsb = colsb;

	for (i = 0; i < rows; i++)
		for (j = 0; j < cols; j++) {
			f = 2.718f;
			ptr[i * cols + j] = convert_fp32_to_fp16(f);
		}
}
#endif

/*
 * init_dword_tile() - Init buffer.
 * @buf: The buffer for saving data.
 * @rows: Row number of the matrix.
 * @colsb: Column number in byte of the matrix.
 *
 * Init buffer with chaotic integer.
 */
static void init_dword_tile(struct __tile *tile_ptr, uint8_t rows, uint8_t colsb)
{
	int32_t i, j;
	int32_t *ptr = (int32_t *)tile_ptr->buf;
	int32_t cols = colsb / 4;

	tile_ptr->rows = rows;
	tile_ptr->colsb = colsb;

	for (i = 0; i < rows; i++)
		for (j = 0; j < cols; j++)
			ptr[i * cols + j] = get_random() + i + j;
}

/*
 * init_tile_config() - Init the tile configuration structure.
 * @dst: The tile configuration structure.
 * @rows: Row number of the matrix.
 * @colsb: Column number in byte of the matrix.
 *
 * Init the tile configuration structure.
 * Fixedly using tile 0, 1 and 2.
 */
static void init_tile_config(union __union_tile_config *dst, uint8_t rows, uint8_t colsb)
{
	int32_t i;

	dst->s.palette_id = 1;
	dst->s.start_row = 0;

	for (i = 0; i < 14; i++)
		dst->s.reserved_0[i] = 0;

	for (i = 0; i < 8; i++) {
		dst->s.reserved_1[i] = 0;
		dst->s.reserved_2[i] = 0;
	}

	dst->s.colsb[0] = colsb;
	dst->s.rows[0] = rows;

	dst->s.colsb[1] = colsb;
	dst->s.rows[1] = rows;

	dst->s.colsb[2] = colsb;
	dst->s.rows[2] = rows;

	dst->s.colsb[3] = colsb;
	dst->s.rows[3] = rows;

	dst->s.colsb[4] = colsb;
	dst->s.rows[4] = rows;

	dst->s.colsb[5] = colsb;
	dst->s.rows[5] = rows;

	dst->s.colsb[6] = colsb;
	dst->s.rows[6] = rows;

	dst->s.colsb[7] = colsb;
	dst->s.rows[7] = rows;

	asm volatile("ldtilecfg %0" : : "m" (dst->a));
}

/*
 * calc_matrix_tdpbf16ps() - Software algorithm for instruction TDPBF16PS.
 * @dst: The product of matrix multiplication.
 * @src1: The first multiplier.
 * @src2: The second multiplier.
 *
 * Compute dot-product of BF16 (16-bit) floating-point pairs in tiles a and b,
 * accumulating the intermediate single-precision (32-bit) floating-point
 * elements with elements in dst,
 * and store the 32-bit result back to tile dst.
 */
static void calc_matrix_tdpbf16ps(struct __tile *dst, struct __tile *src1, struct __tile *src2)
{
	uint16_t *src1_buf = (uint16_t *)src1->buf;
	uint16_t *src2_buf = (uint16_t *)src2->buf;
	float *dst_buf = (float *)dst->buf;

	int32_t M = src1->rows;
	int32_t K = src1->colsb / 4;
	int32_t N = src2->colsb / 4;
	int32_t m, k, n;

	for (m = 0; m < M; m++)
		for (k = 0; k < K; k++)
			for (n = 0; n < N; n++) {
				dst_buf[m * N + n] +=
					(convert_bf16_to_fp32(src1_buf[m * K * 2 + k * 2 + 0]) *
					 convert_bf16_to_fp32(src2_buf[k * N * 2 + n * 2 + 0])) +
					(convert_bf16_to_fp32(src1_buf[m * K * 2 + k * 2 + 1]) *
					 convert_bf16_to_fp32(src2_buf[k * N * 2 + n * 2 + 1]));
			}
}

#ifdef FP16
/*
 * calc_matrix_tdpfp16ps() - Software algorithm for instruction TDPBF16PS.
 * @dst: The product of matrix multiplication.
 * @src1: The first multiplier.
 * @src2: The second multiplier.
 *
 * Compute dot-product of FP16 (16-bit) floating-point pairs in tiles a and b,
 * accumulating the intermediate single-precision (32-bit) floating-point
 * elements with elements in dst,
 * and store the 32-bit result back to tile dst.
 */
static void calc_matrix_tdpfp16ps(struct __tile *dst, struct __tile *src1, struct __tile *src2)
{
	uint16_t *src1_buf = (uint16_t *)src1->buf;
	uint16_t *src2_buf = (uint16_t *)src2->buf;
	float *dst_buf = (float *)dst->buf;

	int32_t M = src1->rows;
	int32_t K = src1->colsb / 4;
	int32_t N = src2->colsb / 4;
	int32_t m, k, n;

	for (m = 0; m < M; m++)
		for (k = 0; k < K; k++)
			for (n = 0; n < N; n++) {
				dst_buf[m * N + n] +=
					(convert_fp16_to_fp32(src1_buf[m * K * 2 + k * 2 + 0]) *
					 convert_fp16_to_fp32(src2_buf[k * N * 2 + n * 2 + 0])) +
					(convert_fp16_to_fp32(src1_buf[m * K * 2 + k * 2 + 1]) *
					 convert_fp16_to_fp32(src2_buf[k * N * 2 + n * 2 + 1]));
		}
}
#endif

/*
 * calc_matrix_tdpbssd() - Software algorithm for instruction TDPBSSD.
 * @dst: The product of matrix multiplication.
 * @src1: The first multiplier.
 * @src2: The second multiplier.
 *
 * Compute dot-product of bytes in tiles with a source/destination accumulator.
 * Multiply groups of 4 adjacent pairs of signed 8-bit integers in a with
 * corresponding signed 8-bit integers in b,
 * producing 4 intermediate 32-bit results.
 * Sum these 4 results with the corresponding 32-bit integer in dst,
 * and store the 32-bit result back to tile dst.
 */
static void calc_matrix_tdpbssd(struct __tile *dst, struct __tile *src1, struct __tile *src2)
{
	uint32_t *src1_buf = (uint32_t *)src1->buf;
	uint32_t *src2_buf = (uint32_t *)src2->buf;
	uint32_t *dst_buf = (uint32_t *)dst->buf;

	int32_t M = src1->rows;
	int32_t K = src1->colsb / 4;
	int32_t N = src2->colsb / 4;
	int32_t m, k, n;

	for (m = 0; m < M; m++)
		for (k = 0; k < K; k++)
			for (n = 0; n < N; n++) {
				DPBD(dst_buf[m * N + n],
				     &src1_buf[m * K + k],
				     &src2_buf[k * N + n],
				     int8_t, int8_t);
			}
}

/*
 * calc_matrix_tdpbsud() - Software algorithm for instruction TDPBSUD.
 * @dst: The product of matrix multiplication.
 * @src1: The first multiplier.
 * @src2: The second multiplier.
 *
 * Compute dot-product of bytes in tiles with a source/destination accumulator.
 * Multiply groups of 4 adjacent pairs of signed 8-bit integers in a with
 * corresponding unsigned 8-bit integers in b,
 * producing 4 intermediate 32-bit results.
 * Sum these 4 results with the corresponding 32-bit integer in dst,
 * and store the 32-bit result back to tile dst.
 */
static void calc_matrix_tdpbsud(struct __tile *dst, struct __tile *src1, struct __tile *src2)
{
	uint32_t *src1_buf = (uint32_t *)src1->buf;
	uint32_t *src2_buf = (uint32_t *)src2->buf;
	uint32_t *dst_buf = (uint32_t *)dst->buf;

	int32_t M = src1->rows;
	int32_t K = src1->colsb / 4;
	int32_t N = src2->colsb / 4;
	int32_t m, k, n;

	for (m = 0; m < M; m++)
		for (k = 0; k < K; k++)
			for (n = 0; n < N; n++) {
				DPBD(dst_buf[m * N + n],
				     &src1_buf[m * K + k],
				     &src2_buf[k * N + n],
				     int8_t, uint8_t);
			}
}

/*
 * calc_matrix_tdpbusd() - Software algorithm for instruction TDPBUSD.
 * @dst: The product of matrix multiplication.
 * @src1: The first multiplier.
 * @src2: The second multiplier.
 *
 * Compute dot-product of bytes in tiles with a source/destination accumulator.
 * Multiply groups of 4 adjacent pairs of unsigned 8-bit integers in a with
 * corresponding signed 8-bit integers in b,
 * producing 4 intermediate 32-bit results.
 * Sum these 4 results with the corresponding 32-bit integer in dst,
 * and store the 32-bit result back to tile dst.
 */
static void calc_matrix_tdpbusd(struct __tile *dst, struct __tile *src1, struct __tile *src2)
{
	uint32_t *src1_buf = (uint32_t *)src1->buf;
	uint32_t *src2_buf = (uint32_t *)src2->buf;
	uint32_t *dst_buf = (uint32_t *)dst->buf;

	int32_t M = src1->rows;
	int32_t K = src1->colsb / 4;
	int32_t N = src2->colsb / 4;
	int32_t m, k, n;

	for (m = 0; m < M; m++)
		for (k = 0; k < K; k++)
			for (n = 0; n < N; n++) {
				DPBD(dst_buf[m * N + n],
				     &src1_buf[m * K + k],
				     &src2_buf[k * N + n],
				     uint8_t, int8_t);
			}
}

/*
 * calc_matrix_tdpbuud() - Software algorithm for instruction TDPBUUD.
 * @dst: The product of matrix multiplication.
 * @src1: The first multiplier.
 * @src2: The second multiplier.
 *
 * Compute dot-product of bytes in tiles with a source/destination accumulator.
 * Multiply groups of 4 adjacent pairs of unsigned 8-bit integers in a with
 * corresponding unsigned 8-bit integers in b,
 * producing 4 intermediate 32-bit results.
 * Sum these 4 results with the corresponding 32-bit integer in dst,
 * and store the 32-bit result back to tile dst.
 */
static void calc_matrix_tdpbuud(struct __tile *dst, struct __tile *src1, struct __tile *src2)
{
	uint32_t *src1_buf = (uint32_t *)src1->buf;
	uint32_t *src2_buf = (uint32_t *)src2->buf;
	uint32_t *dst_buf = (uint32_t *)dst->buf;

	int32_t M = src1->rows;
	int32_t K = src1->colsb / 4;
	int32_t N = src2->colsb / 4;
	int32_t m, k, n;

	for (m = 0; m < M; m++)
		for (k = 0; k < K; k++)
			for (n = 0; n < N; n++) {
				DPBD(dst_buf[m * N + n],
				     &src1_buf[m * K + k],
				     &src2_buf[k * N + n],
				     uint8_t, uint8_t);
			}
}

static void tile_dpbf16ps(void)
{
	asm volatile("tdpbf16ps %tmm7, %tmm6, %tmm5");
	asm volatile("tdpbf16ps %tmm4, %tmm3, %tmm2");
	asm volatile("tdpbf16ps %tmm5, %tmm2, %tmm1");
	asm volatile("tdpbf16ps %tmm2, %tmm1, %tmm0");
}

#ifdef FP16
static void tile_dpfp16ps(void)
{
	asm volatile("tdpfp16ps %tmm7, %tmm6, %tmm5");
	asm volatile("tdpfp16ps %tmm4, %tmm3, %tmm2");
	asm volatile("tdpfp16ps %tmm5, %tmm2, %tmm1");
	asm volatile("tdpfp16ps %tmm2, %tmm1, %tmm0");
}
#endif

static void tile_dpbssd(void)
{
	asm volatile("tdpbssd %tmm7, %tmm6, %tmm5");
	asm volatile("tdpbssd %tmm4, %tmm3, %tmm2");
	asm volatile("tdpbssd %tmm5, %tmm2, %tmm1");
	asm volatile("tdpbssd %tmm2, %tmm1, %tmm0");
}

static void tile_dpbsud(void)
{
	asm volatile("tdpbsud %tmm7, %tmm6, %tmm5");
	asm volatile("tdpbsud %tmm4, %tmm3, %tmm2");
	asm volatile("tdpbsud %tmm5, %tmm2, %tmm1");
	asm volatile("tdpbsud %tmm2, %tmm1, %tmm0");
}

static void tile_dpbusd(void)
{
	asm volatile("tdpbusd %tmm7, %tmm6, %tmm5");
	asm volatile("tdpbusd %tmm4, %tmm3, %tmm2");
	asm volatile("tdpbusd %tmm5, %tmm2, %tmm1");
	asm volatile("tdpbusd %tmm2, %tmm1, %tmm0");
}

static void tile_dpbuud(void)
{
	asm volatile("tdpbuud %tmm7, %tmm6, %tmm5");
	asm volatile("tdpbuud %tmm4, %tmm3, %tmm2");
	asm volatile("tdpbuud %tmm5, %tmm2, %tmm1");
	asm volatile("tdpbuud %tmm2, %tmm1, %tmm0");
}

/*
 * check_tile_bf16_register() - check calculation result.
 * @ref: The result calculated by AMX/TMUL.
 * @target: The result calculated by software.
 *
 * Check if the difference of the 2 results is small enough.
 *
 * Return:
 * true - OK
 * false - Abnormal
 */
static bool check_tile_bf16_register(struct __tile *ref, struct __tile *target)
{
	/*
	 * Tile register should be stored from tmm to
	 * memory and compare with emulation results.
	 */
	int32_t rows = target->rows;
	int32_t colsb = target->colsb / 4;
	uint8_t *rbuf = ref->buf;
	uint8_t *tbuf = target->buf;
	int32_t i, j, idx;

	for (i = 0; i < rows; i++)
		for (j = 0; j < colsb; j++) {
			idx = i * colsb + j;
			if ((((float *)rbuf)[idx] - ((float *)tbuf)[idx]) > (0.5) ||
			    (((float *)rbuf)[idx] - ((float *)tbuf)[idx]) < (-0.5)) {
				printf("Mismatch: idx=%d, ref=%f, target=%f\n", idx,
				       ((float *)rbuf)[idx],
				       ((float *)tbuf)[idx]);
				return false;
			}
		}

	return true;
}

#ifdef FP16
/*
 * check_tile_fp16_register() - check calculation result.
 * @ref: The result calculated by AMX/TMUL.
 * @target: The result calculated by software.
 *
 * Check if the difference of the 2 results is small enough.
 *
 * Return:
 * true - OK
 * false - Abnormal
 */
static bool check_tile_fp16_register(struct __tile *ref, struct __tile *target)
{
	/*
	 * Tile register should be stored from tmm to
	 * memory and compare with emulation results.
	 */
	int32_t rows = target->rows;
	int32_t colsb = target->colsb / 4;
	uint8_t *rbuf = ref->buf;
	uint8_t *tbuf = target->buf;
	int32_t i, j, idx;

	for (i = 0; i < rows; i++)
		for (j = 0; j < colsb; j++) {
			idx = i * colsb + j;
			if ((((float *)rbuf)[idx] - ((float *)tbuf)[idx]) > (0.5) ||
			    (((float *)rbuf)[idx] - ((float *)tbuf)[idx]) < (-0.5)) {
				printf("Mismatch: idx=%d, ref=%f, target=%f\n", idx,
				       ((float *)rbuf)[idx],
				       ((float *)tbuf)[idx]);
				return false;
			}
		}

	return true;
}
#endif

/*
 * check_tile_dword_register() - check calculation result.
 * @ref: The result calculated by AMX/TMUL.
 * @target: The result calculated by software.
 *
 * Check if the 2 results are identical.
 *
 * Return:
 * true - OK
 * false - Abnormal
 */
static bool check_tile_dword_register(struct __tile *ref, struct __tile *target)
{
	int32_t i, j, idx;

	int32_t rows = target->rows;
	int32_t colsb = target->colsb / 4;
	uint8_t *rbuf = ref->buf;
	uint8_t *tbuf = target->buf;

	for (i = 0; i < rows; i++)
		for (j = 0; j < colsb; j++) {
			idx = i * colsb + j;
			if (((uint32_t *)rbuf)[idx] != ((uint32_t *)tbuf)[idx]) {
				printf("Mismatch: ref=0x%X, target=0x%X\n",
				       ((uint32_t *)rbuf)[idx],
				       ((uint32_t *)tbuf)[idx]);
				return false;
			}
		}

	return true;
}

/*
 * set_tiledata_use() - Invoke syscall to set ARCH_SET_STATE_USE.
 *
 * It's necessary to be invoked when using a AMX/TMUL fully supported kernel.
 *
 * Return:
 * true - OK
 * false - Abnormal
 */
static bool set_tiledata_use(void)
{
	bool rtn = true;

	if (syscall(SYS_arch_prctl, ARCH_REQ_XCOMP_PERM, XFEATURE_XTILEDATA)) {
		printf("Fail to do XFEATURE_XTILEDATA\n");
		rtn = false;
	}

	return rtn;
}

/*
 * signal_handler() - Handle SIGTRAP and SIGUSR1 signal.
 * @signum: Signal number.
 */
static void signal_handler(int32_t signum)
{
	int32_t current_cpu = sched_getcpu();

	if (signum == SIGTRAP)
		printf("Break by trap, current_cpu=%d\n", current_cpu);

	if (signum == SIGUSR1)
		printf("Break by signal, current_cpu=%d\n", current_cpu);
}

/*
 * thread_break() - Break the thread execution.
 * @reason: Several kinds of reason to break the thread execution.
 * @thread_idx: The index of sub-thread.
 */
static void thread_break(int32_t reason, uint32_t thread_idx)
{
	struct timespec req;

	switch (reason) {
	case BREAK_BY_YIELD:
		/*
		 * Schedule out current thread by executing syscall
		 * instruction with syscall number SYS_sched_yield
		 */
		do_syscall(SYS_sched_yield, 0, 0, 0, 0, 0, 0);
		break;
	case BREAK_BY_SLEEP:
		/*
		 * Schedule out current thread by executing syscall
		 * instruction with syscall number SYS_nanosleep
		 */
		req.tv_sec = 1;
		req.tv_nsec = 0;
		do_syscall(SYS_nanosleep, (uint64_t)&req, 0, 0, 0, 0, 0);
		break;
	case BREAK_BY_TRAP:
		/*
		 * Trap is handled by the thread generated the trap,
		 * Schedule out current thread by trap handling
		 */
		asm volatile("int3;");
		break;
	case BREAK_BY_SIGNAL:
		/*
		 * Do nothing, main thread send SIGUSR1 to sub thread periodically
		 * Schedule out current thread by signal handling
		 */
		break;
	case BREAK_BY_FUTEX:
		/* Schedule out current thread by waiting futex */
		do_syscall(SYS_futex, (uint64_t)&futex_ptr[thread_idx],
			   FUTEX_WAIT, FUTEX_VAL, 0, 0, 0);
		break;
	}
}

/*
 * worker_thread() - The sub-thread entrance.
 * @arg: The index of sub-thread.
 *       Index from 0 to the total number of threads - 1.
 *
 * Two results are generated by AMX/TMUL calculation procedure,
 * one is calculated by software, the other is calculated by TMUL.
 * Interrupt the AMX/TMUL calculation procedure by different reasons.
 * These reasons may cause context-switch by Kernel.
 * Check if the thread context is saved and restored correctly
 * by comparing the two results.
 */
static void *worker_thread(void *arg)
{
	union __union_tile_config cfg;
	struct __tile *ptr_tile1, *ptr_tile2, *ptr_tile3, *ptr_tile4;
	cpu_set_t mask;

	bool rtn = true;
	uint32_t i = 0;
	uint32_t thread_idx = *((uint32_t *)arg);

	/* All sub threads are attached on CPU 1 */
	CPU_ZERO(&mask);
	CPU_SET(1, &mask);
	pthread_setaffinity_np(pthread_self(), sizeof(mask), &mask);

	ptr_tile1 = &buf_tile1[thread_idx];
	ptr_tile2 = &buf_tile2[thread_idx];
	ptr_tile3 = &buf_tile3[thread_idx];
	ptr_tile4 = &buf_tile4[thread_idx];

	/* Init the test data in memory */
	if (ins_type == INS_TDPBF16PS)
		init_bf16_tile(ptr_tile1, ROW_NUM, COL_NUM);
#ifdef FP16
	else if (ins_type == INS_TDPFP16PS)
		init_fp16_tile(ptr_tile1, ROW_NUM, COL_NUM);
#endif
	else
		init_dword_tile(ptr_tile1, ROW_NUM, COL_NUM);

	memcpy(ptr_tile2, ptr_tile1, sizeof(struct __tile));
	memcpy(ptr_tile3, ptr_tile1, sizeof(struct __tile));
	memcpy(ptr_tile4, ptr_tile1, sizeof(struct __tile));

	/* Calculate a result by software and store it in memory */
	if (ins_type == INS_TDPBF16PS) {
		calc_matrix_tdpbf16ps(ptr_tile4, ptr_tile3, ptr_tile2);
		calc_matrix_tdpbf16ps(ptr_tile3, ptr_tile4, ptr_tile4);
		calc_matrix_tdpbf16ps(ptr_tile2, ptr_tile3, ptr_tile4);
#ifdef FP16
	} else if (ins_type == INS_TDPFP16PS) {
		calc_matrix_tdpfp16ps(ptr_tile4, ptr_tile3, ptr_tile2);
		calc_matrix_tdpfp16ps(ptr_tile3, ptr_tile4, ptr_tile4);
		calc_matrix_tdpfp16ps(ptr_tile2, ptr_tile3, ptr_tile4);
#endif
	} else if (ins_type == INS_TDPBSSD) {
		calc_matrix_tdpbssd(ptr_tile4, ptr_tile3, ptr_tile2);
		calc_matrix_tdpbssd(ptr_tile3, ptr_tile4, ptr_tile4);
		calc_matrix_tdpbssd(ptr_tile2, ptr_tile3, ptr_tile4);
	} else if (ins_type == INS_TDPBSUD) {
		calc_matrix_tdpbsud(ptr_tile4, ptr_tile3, ptr_tile2);
		calc_matrix_tdpbsud(ptr_tile3, ptr_tile4, ptr_tile4);
		calc_matrix_tdpbsud(ptr_tile2, ptr_tile3, ptr_tile4);
	} else if (ins_type == INS_TDPBUSD) {
		calc_matrix_tdpbusd(ptr_tile4, ptr_tile3, ptr_tile2);
		calc_matrix_tdpbusd(ptr_tile3, ptr_tile4, ptr_tile4);
		calc_matrix_tdpbusd(ptr_tile2, ptr_tile3, ptr_tile4);
	} else if (ins_type == INS_TDPBUUD) {
		calc_matrix_tdpbuud(ptr_tile4, ptr_tile3, ptr_tile2);
		calc_matrix_tdpbuud(ptr_tile3, ptr_tile4, ptr_tile4);
		calc_matrix_tdpbuud(ptr_tile2, ptr_tile3, ptr_tile4);
	}

	/* Program the tile config to TILECFG register */
	init_tile_config(&cfg, ROW_NUM, COL_NUM);

	for (i = 0; i < cycles; i++) {
		/* Step1: Program the test data to TMM register */
		load_tile_reg(0, ptr_tile1, COL_NUM);
		load_tile_reg(1, ptr_tile1, COL_NUM);
		load_tile_reg(2, ptr_tile1, COL_NUM);
		load_tile_reg(3, ptr_tile1, COL_NUM);
		asm volatile("mfence" : : : "memory");

		/* Step2: Interrupt this thread by a reason */
		thread_break(break_reason, thread_idx);

		load_tile_reg(4, ptr_tile1, COL_NUM);
		load_tile_reg(5, ptr_tile1, COL_NUM);
		load_tile_reg(6, ptr_tile1, COL_NUM);
		load_tile_reg(7, ptr_tile1, COL_NUM);
		asm volatile("mfence" : : : "memory");

		/* Step3: Interrupt this thread by a reason */
		thread_break(break_reason, thread_idx);

		/* Step4: Calculate a result by TMUL and store it in TMM0 register */
		if (ins_type == INS_TDPBF16PS)
			tile_dpbf16ps();
#ifdef FP16
		else if (ins_type == INS_TDPFP16PS)
			tile_dpfp16ps();
#endif
		else if (ins_type == INS_TDPBSSD)
			tile_dpbssd();
		else if (ins_type == INS_TDPBSUD)
			tile_dpbsud();
		else if (ins_type == INS_TDPBUSD)
			tile_dpbusd();
		else if (ins_type == INS_TDPBUUD)
			tile_dpbuud();
		asm volatile("mfence" : : : "memory");

		/* Step5: Interrupt this thread by a reason */
		thread_break(break_reason, thread_idx);

		/* Step6: Store the result from TMM0 to memory */
		store_tile_reg(0, ptr_tile3, COL_NUM);
		asm volatile("mfence" : : : "memory");

		/* Step7: Check if the 2 results are identical */
		if (ins_type == INS_TDPBF16PS) {
			if (!check_tile_bf16_register(ptr_tile3, ptr_tile2)) {
				printf("Instruction %d test in Thread %d Cycle %d: failed\n",
				       ins_type, thread_idx, i);
				rtn = false;
			}
#ifdef FP16
		} else if (ins_type == INS_TDPFP16PS) {
			if (!check_tile_fp16_register(ptr_tile3, ptr_tile2)) {
				printf("Instruction %d test in Thread %d Cycle %d: failed\n",
				       ins_type, thread_idx, i);
				rtn = false;
			}
#endif
		} else {
			if (!check_tile_dword_register(ptr_tile3, ptr_tile2)) {
				printf("Instruction %d test in Thread %d Cycle %d: failed\n",
				       ins_type, thread_idx, i);
				rtn = false;
			}
		}
	}

	/* After every sub-thread is done, the main thread can exit */
	thread_done[thread_idx] = true;

	if (rtn)
		pthread_exit((void *)0);
	else
		pthread_exit((void *)1);
}

static struct option long_options[] = {
	{"break-reason", required_argument, 0, 'b'},
	{"thread-count", required_argument, 0, 't'},
	{"cycle-number", required_argument, 0, 'c'},
	{"instruction-type", required_argument, 0, 'i'},
	{"help", no_argument, 0, 'h'},
	{0, 0, 0, 0}
};

static const char *option_string = "b:t:c:i:h::";

static char *progname;

static void help(void)
{
	fprintf(stderr,
		"Usage: %s [OPTIONS]\n"
		"%s runs amx_tmul test\n"
		"  -b, --break-reason [%d - %d]\n"
		"      0: break by nothing\n"
		"      1: break by yield\n"
		"      2: break by sleep\n"
		"      3: break by trap\n"
		"      4: break by signal\n"
		"      5: break by futex\n"
		"  -t, --thread-count [Should not be less than %d]\n"
		"  -c, --cycle-number [Should not be less than 1]\n"
#ifdef FP16
		"  -i, --instruction-type [0:TDPBF16PS 1:TDPBSSD 2:TDPBSUD 3:TDPBUSD 4:TDPBUUD 5:TDPFP16PS]\n"
#else
		"  -i, --instruction-type [0:TDPBF16PS 1:TDPBSSD 2:TDPBSUD 3:TDPBUSD 4:TDPBUUD]\n"
#endif
		, progname, progname, BREAK_BY_YIELD, BREAK_REASON_MAX, MIN_THREAD_NUM);
}

/*
 * parse_options() - The main process entrance.
 * @ac: The total number of arguments.
 * @av: Pointer array.
 *
 * Parse arguments of main()
 *
 * Return:
 * true - The subsequential test should be done.
 * false - The subsequential test should not be done.
 */
static bool parse_options(int32_t ac, char **av)
{
	int32_t c;
	bool do_nothing = false;

	progname = av[0];

	while (1) {
		int32_t option_index = 0;

		c = getopt_long(ac, av, option_string,
				long_options, &option_index);
		if (c == -1)
			break;
		switch (c) {
		case 'b':
			break_reason = atoi(optarg);
			if (break_reason < BREAK_BY_NOTHING || break_reason > BREAK_REASON_MAX) {
				help();
				do_nothing = true;
			}
			break;
		case 't':
			thread_num = atoi(optarg);
			if (thread_num < MIN_THREAD_NUM) {
				help();
				do_nothing = true;
			}
			break;
		case 'c':
			cycles = atoi(optarg);
			if (cycles < 1) {
				help();
				do_nothing = true;
			}
			break;
		case 'i':
			ins_type = atoi(optarg);
			if (ins_type < INS_TDPBF16PS || ins_type > INS_MAX_NUM) {
				help();
				do_nothing = true;
			}
			break;
		case 'h':
			help();
			do_nothing = true;
			break;
		default:
			break;
		}
	}

	return do_nothing;
}

/*
 * main() - The main process entrance.
 * @argc: The total number of arguments.
 * @argv: Pointer array.
 *
 * Return:
 * 0 - OK
 * -1 - Abnormal
 */
int32_t main(int32_t argc, char **argv)
{
	int32_t i;
	cpu_set_t mask;
	struct sigaction sigact;
	bool all_thread_done = false;

	if (parse_options(argc, argv))
		exit(-1);

	/* Main thread is attached on CPU 0 */
	CPU_ZERO(&mask);
	CPU_SET(0, &mask);
	pthread_setaffinity_np(pthread_self(), sizeof(mask), &mask);

	if (!set_tiledata_use())
		exit(-1);

	if (break_reason == BREAK_BY_TRAP) {
		sigact.sa_handler = signal_handler;
		sigemptyset(&sigact.sa_mask);
		sigact.sa_flags = 0;
		sigaction(SIGTRAP, &sigact, NULL);
	}

	if (break_reason == BREAK_BY_SIGNAL) {
		sigact.sa_handler = signal_handler;
		sigemptyset(&sigact.sa_mask);
		sigact.sa_flags = 0;
		sigaction(SIGUSR1, &sigact, NULL);
	}

	futex_ptr = (int32_t *)malloc(sizeof(int32_t) * thread_num);
	thread_done = (bool *)malloc(sizeof(bool) * thread_num);
	buf_tile1 = (struct __tile *)malloc(sizeof(struct __tile) * thread_num);
	buf_tile2 = (struct __tile *)malloc(sizeof(struct __tile) * thread_num);
	buf_tile3 = (struct __tile *)malloc(sizeof(struct __tile) * thread_num);
	buf_tile4 = (struct __tile *)malloc(sizeof(struct __tile) * thread_num);
	pthread_t *tid_ptr = (pthread_t *)malloc(sizeof(pthread_t) * thread_num);
	uint32_t *pthread_idx_ptr = (uint32_t *)malloc(sizeof(int32_t) * thread_num);
	int32_t **thread_result = (int32_t **)malloc(sizeof(int32_t *) * thread_num);

	if (!futex_ptr || !thread_done || !tid_ptr || !pthread_idx_ptr || !thread_result ||
	    !buf_tile1 || !buf_tile2 || !buf_tile3 || !buf_tile4) {
		printf("Fail to malloc memory\n");
		exit(1);
	}

	for (i = 0; i < thread_num; i++) {
		futex_ptr[i] = FUTEX_VAL;
		thread_done[i] = false;
		pthread_idx_ptr[i] = i;
		pthread_create(&tid_ptr[i], NULL, worker_thread, &pthread_idx_ptr[i]);
	}

	/* wait 1 second to ensure sub-thread has been attached on CPU 1*/
	sleep(1);

	/* Send SIGUSR1 to each sub-thread */
	if (break_reason == BREAK_BY_SIGNAL) {
		while (!all_thread_done) {
			all_thread_done = true;
			for (i = 0; i < thread_num; i++) {
				if (!thread_done[i]) {
					pthread_kill(tid_ptr[i], SIGUSR1);
					all_thread_done = false;
					printf("pthread_kill thread %d\n", i);
					/*
					 * wait 0.5 second to prevent from
					 * sending signal too frequently
					 */
					usleep(500000);
				}
			}
		}
	}

	/* Wake up the sub-thread waiting on a futex */
	if (break_reason == BREAK_BY_FUTEX) {
		while (!all_thread_done) {
			all_thread_done = true;
			for (i = 0; i < thread_num; i++) {
				if (!thread_done[i]) {
					syscall(SYS_futex, &futex_ptr[i], FUTEX_WAKE, 1, 0, 0, 0);
					all_thread_done = false;
					printf("FUTEX_WAKE thread %d\n", i);
					/* wait 0.5 second to prevent from printing too much */
					usleep(500000);
				}
			}
		}
	}

	for (i = 0; i < thread_num; i++)
		pthread_join(tid_ptr[i], (void **)(&thread_result[i]));

	free(futex_ptr);
	free(thread_done);
	free(tid_ptr);
	free(pthread_idx_ptr);
	free(buf_tile1);
	free(buf_tile2);
	free(buf_tile3);
	free(buf_tile4);

	for (i = 0; i < thread_num; i++) {
		if (thread_result[i]) {
			printf("TMUL test failed\n");
			exit(1);
		}
	}

	printf("TMUL test passed\n");
	exit(0);
}
