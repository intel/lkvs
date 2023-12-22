// SPDX-License-Identifier: GPL-2.0-only
/*
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
#include <err.h>

#if __GNUC__ >= 11

#pragma GCC target("avxvnni")
#define WORKLOAD_NAME "VNNI"
#define BITS_PER_VECTOR		256
#define BYTES_PER_VECTOR	(BITS_PER_VECTOR / 8)
#define WORDS_PER_VECTOR        (BITS_PER_VECTOR / 16)
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
	int entries = dp->data_entries / sizeof(double);

	for (i = 0; i < entries; ++i) {
		if (clfulsh) {
			clflush_range((void *)dp->input_x + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
			clflush_range((void *)dp->input_y + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
			clflush_range((void *)dp->input_z + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
		}
		__m256i vx, vy, vz, voutput;

		vx = _mm256_loadu_si256((void *)(dp->input_x + i * BYTES_PER_VECTOR));
		vy = _mm256_loadu_si256((void *)(dp->input_y + i * BYTES_PER_VECTOR));
		vz = _mm256_loadu_si256((void *)(dp->input_z + i * DWORD_PER_VECTOR));

		voutput = _mm256_dpbusds_epi32(vz, vx, vy);

		_mm256_storeu_si256((void *)(dp->output + i * DWORD_PER_VECTOR), voutput);
	}
}

#include "worker_init_dotprod.c"
#include "run_common.c"

static struct workload w = {
	"VNNI",
	init,
	cleanup,
	run,
};

struct workload *register_VNNI(void)
{
	if (cpuid.avx2vnni)
		return &w;

	return NULL;
}
#else

#warning GCC < 11 can not build work_VNNI.c

#endif /* GCC < 11 */
