// SPDX-License-Identifier: GPL-2.0-only
/*
 * work_AVX.c - offer the "AVX" workload to yogini
 *
 * Copyright (c) 2022 Intel Corporation.
 * Yi Sun <yi.sun@intel.com>
 * Dongcheng Yan <dongcheng.yan@intel.com>
 *
 */

#define _GNU_SOURCE
#include <stdio.h>		/* printf(3) */
#include <stdlib.h>		/* random(3) */
#include <sched.h>		/* CPU_SET */
#include <sched.h>
#include <xmmintrin.h>
#include <immintrin.h>
#include "yogini.h"
#include <err.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <unistd.h>

// #pragma GCC target("amx")
#define WORKLOAD_NAME "AMX"
#define XFEATURE_XTILEDATA 18
#define ARCH_REQ_XCOMP_PERM 0x1023
#define ROW_NUM 16
#define COL_NUM 64
#define BYTES_PER_VECTOR		1024
#define load_tile_reg(tmm_num, tile, stride)						\
do {											\
	asm volatile("tileloadd\t(%0,%1,1), %%tmm" #tmm_num				\
		     : : "r" ((void *)(tile)->buf), "r" ((long)stride) : "memory")	\
} while (0)

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

struct thread_data {
	int8_t *input_x;
	int8_t *input_y;
	int32_t *output;
	int data_entries;
};

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

	for (i = 0; i < 8; i++) {
		dst->s.colsb[i] = colsb;
		dst->s.rows[i] = rows;
	}

	_tile_loadconfig(dst->a);
}

/* Set_tiledata_use() - Invoke syscall to set ARCH_SET_STATE_USE */
static void set_tiledata_use(void)
{
	if (syscall(SYS_arch_prctl, ARCH_REQ_XCOMP_PERM, XFEATURE_XTILEDATA))
		printf("Fail to do XFEATURE_XTILEDATA\n");
}

static void work(void *arg)
{
	int i;
	struct thread_data *dp = (struct thread_data *)arg;
	int entries = dp->data_entries;

	set_tiledata_use();

	for (i = 0; i < entries; ++i) {
		_tile_loadd(2, dp->input_x + BYTES_PER_VECTOR * i, COL_NUM);
		_tile_loadd(3, dp->input_y + BYTES_PER_VECTOR * i, COL_NUM);
		_tile_loadd(1, dp->output + BYTES_PER_VECTOR / 4 * i, COL_NUM);
		_tile_dpbssd(1, 2, 3);
		_tile_stored(1, dp->output + BYTES_PER_VECTOR / 4 * i, COL_NUM);
	}
}

#include "worker_init_amx.c"
#include "run_common.c"

static struct workload w = {
	"AMX",
	init,
	cleanup,
	run,
};

struct workload *register_AMX(void)
{
	return &w;
}
