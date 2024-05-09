// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2022 Intel Corporation.
 * Len Brown <len.brown@intel.com>
 */

#define _GNU_SOURCE
#include <stdio.h>		/* printf(3) */
#include <stdlib.h>		/* random(3) */
#include <sched.h>		/* CPU_SET */
#include "yogini.h"
#include <immintrin.h>
#include <stdint.h>
#include <err.h>

#pragma GCC target("avx2,fma")

#define BITS_PER_VECTOR		256
#define BYTES_PER_VECTOR	(BITS_PER_VECTOR / 8)
#define WORDS_PER_VECTOR	(BITS_PER_VECTOR / 16)
#define DWORD_PER_VECTOR	(BITS_PER_VECTOR / 32)

#pragma GCC optimize("unroll-loops")

struct thread_data {
	uint8_t *input_x;
	int8_t *input_y;
	int32_t *input_z;
	int16_t *input_ones;
	int32_t *output;
	int data_entries;
};

static void work(void *arg)
{
	int i;
	struct thread_data *dp = (struct thread_data *)arg;
	int entries = dp->data_entries;

	__m256i v_ones;

	v_ones = _mm256_loadu_si256((void *)dp->input_ones);

	for (i = 0; i < entries; ++i) {
		if (clfulsh) {
			clflush_range((void *)dp->input_x + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
			clflush_range((void *)dp->input_y + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
			clflush_range((void *)dp->input_z + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
		}

		__m256i vx, vy, vz, voutput;
		__m256i vtmp1, vtmp2;

		vx = _mm256_loadu_si256((void *)(dp->input_x + i * BYTES_PER_VECTOR));
		vy = _mm256_loadu_si256((void *)(dp->input_y + i * BYTES_PER_VECTOR));
		vz = _mm256_loadu_si256((void *)(dp->input_z + i * DWORD_PER_VECTOR));

		vtmp1 = _mm256_maddubs_epi16(vx, vy);	/* 8-bit mul, 16-bit add */
		vtmp2 = _mm256_madd_epi16(vtmp1, v_ones);	/* 32-bit convert */
		voutput = _mm256_add_epi32(vtmp2, vz);	/* 32-bit add */
		_mm256_storeu_si256((void *)(dp->output + i * DWORD_PER_VECTOR), voutput);
	}
}

#include "worker_init_dotprod.c"
#include "run_common.c"

static struct workload w = {
	"DOTPROD",
	init,
	cleanup,
	run,
};

struct workload *register_DOTPROD(void)
{
	return &w;
}
