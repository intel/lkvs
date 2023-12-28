// SPDX-License-Identifier: GPL-2.0-only
/*
 * offer the "AVX2" workload to yogini
 *
 * Copyright (c) 2022 Intel Corporation.
 * Len Brown <len.brown@intel.com>
 * Yi Sun <yi.sun@intel.com>
 * Dongcheng Yan <dongcheng.yan@intel.com>
 *
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
#define WORKLOAD_NAME "AVX2"
#define BITS_PER_VECTOR		256
#define BYTES_PER_VECTOR	(BITS_PER_VECTOR / 8)
#define WORDS_PER_VECTOR        (BITS_PER_VECTOR / 16)
#define DWORD_PER_VECTOR	(BITS_PER_VECTOR / 32)

#pragma GCC optimize("unroll-loops")

struct thread_data {
	uint8_t *input_x;
	int8_t *input_y;
	int16_t *output;
	int data_entries;
};

static void work(void *arg)
{
	int i;
	struct thread_data *dp = (struct thread_data *)arg;
	int entries = dp->data_entries / sizeof(double);

	for (i = 0; i < entries; ++i) {
		if (clfulsh) {
			clflush_range((void *)dp->input_x + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
			clflush_range((void *)dp->input_y + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
		}
		__m256i vx, vy, voutput;

		vx = _mm256_loadu_si256((__m256i *)(dp->input_x + i * BYTES_PER_VECTOR));
		vy = _mm256_loadu_si256((__m256i *)(dp->input_y + i * BYTES_PER_VECTOR));
		voutput = _mm256_maddubs_epi16(vx, vy);
		_mm256_storeu_si256((__m256i *)(dp->output + i * WORDS_PER_VECTOR), voutput);
	}
}

#include "worker_init_avx2.c"
#include "run_common.c"

static struct workload w = {
	"AVX2",
	init,
	cleanup,
	run,
};

struct workload *register_AVX2(void)
{
	return &w;
}
