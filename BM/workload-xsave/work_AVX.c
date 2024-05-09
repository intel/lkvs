// SPDX-License-Identifier: GPL-2.0-only
/*
 * offer the "AVX" workload to yogini
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
#include <sched.h>
#include "yogini.h"
#include <immintrin.h>
#include <err.h>

#pragma GCC target("avx")
#pragma GCC optimize("unroll-loops")
#define WORKLOAD_NAME "AVX"
#define BITS_PER_VECTOR		256
#define BYTES_PER_VECTOR	(BITS_PER_VECTOR / 8)
#define WORDS_PER_VECTOR        (BITS_PER_VECTOR / 16)
#define DWORD_PER_VECTOR	(BITS_PER_VECTOR / 32)
struct thread_data {
	float *input_x;
	float *input_y;
	float *output;
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
		__m256 vx, vy, voutput;

		vx = _mm256_loadu_ps(dp->input_x + i * DWORD_PER_VECTOR);
		vy = _mm256_loadu_ps(dp->input_y + i * DWORD_PER_VECTOR);
		voutput = _mm256_add_ps(vx, vy);
		_mm256_storeu_ps(dp->output + i * DWORD_PER_VECTOR, voutput);
	}
}

#include "run_common.c"
#include "worker_init_avx.c"

static struct workload w = {
	"AVX",
	init,
	cleanup,
	run,
};

struct workload *register_AVX(void)
{
	return &w;
}
