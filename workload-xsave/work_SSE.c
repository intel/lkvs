// SPDX-License-Identifier: GPL-2.0-only
/*
 * offer the "SSE" workload to yogini
 *
 * Copyright (c) 2022 Intel Corporation.
 * Len Brown <len.brown@intel.com>
 */
#define _GNU_SOURCE
#include <stdio.h>		/* printf(3) */
#include <stdlib.h>		/* random(3) */
#include <sched.h>		/* CPU_SET */
#include <sched.h>
#include "yogini.h"
#include <emmintrin.h>
#include <err.h>

#pragma GCC target("sse4.2")
#pragma GCC optimize("unroll-loops")
#define WORKLOAD_NAME "SSE"
#define BITS_PER_VECTOR		128
#define BYTES_PER_VECTOR	(BITS_PER_VECTOR / 8)
#define WORDS_PER_VECTOR        (BITS_PER_VECTOR / 16)
#define DWORD_PER_VECTOR	(BITS_PER_VECTOR / 32)

struct thread_data {
	int32_t *input_x;
	int32_t *input_y;
	int32_t *output;
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
		__m128i vx, vy, voutput;

		vx = _mm_loadu_si128((__m128i *)dp->input_x);
		vy = _mm_loadu_si128((__m128i *)dp->input_y);

		voutput = _mm_add_epi32(vx, vy);
		_mm_storeu_si128((__m128i *)dp->output, voutput);
	}
}

#include "run_common.c"
#include "worker_init_sse.c"

static struct workload w = {
	"SSE",
	init,
	cleanup,
	run,
};

struct workload *register_SSE(void)
{
	return &w;
}
