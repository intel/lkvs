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
#include <err.h>

#if __GNUC__ >= 9

#pragma GCC target("avx512vnni")
#define WORKLOAD_NAME "VNNI512"
#define BITS_PER_VECTOR		512
#define BYTES_PER_VECTOR	(BITS_PER_VECTOR / 8)
#define WORDS_PER_VECTOR        (BITS_PER_VECTOR / 16)
#define DWORD_PER_VECTOR	(BITS_PER_VECTOR / 32)

#pragma GCC optimize("unroll-loops")

struct thread_data {
	u_int8_t *input_x;
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

	for (i = 0; i < entries; ++i) {
		if (clfulsh) {
			clflush_range((void *)dp->input_x + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
			clflush_range((void *)dp->input_y + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
			clflush_range((void *)dp->input_z + i * BYTES_PER_VECTOR, BYTES_PER_VECTOR);
		}
		__m512i vx, vy, vz, voutput;

		vx = _mm512_loadu_si512((void *)(dp->input_x + i * BYTES_PER_VECTOR));
		vy = _mm512_loadu_si512((void *)(dp->input_y + i * BYTES_PER_VECTOR));
		vz = _mm512_loadu_si512((void *)(dp->input_z + i * DWORD_PER_VECTOR));

		voutput = _mm512_dpbusds_epi32(vz, vx, vy);

		_mm512_storeu_si512((void *)(dp->output + i * DWORD_PER_VECTOR), voutput);
	}
}

#include "worker_init_dotprod.c"
#include "run_common.c"

static struct workload w = {
	"VNNI512",
	init,
	cleanup,
	run,
};

struct workload *register_VNNI512(void)
{
	if (cpuid.vnni512)
		return &w;

	return NULL;
}
#else

#warning GCC < 9 can not build work_VNNI512.c

#endif /* GCC < 9 */
