// SPDX-License-Identifier: GPL-2.0-only
/*
 * offer the "AVX512" workload to yogini
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
#include <err.h>

#if __GNUC__ >= 11

#pragma GCC target("avx512bf16")
#define WORKLOAD_NAME "AVX512"
#define BITS_PER_VECTOR		512
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

		__m512 vx, vy, vz, voutput;

		vx = _mm512_loadu_ps((float *)(dp->input_x + i * BYTES_PER_VECTOR));
		vy = _mm512_loadu_ps((float *)(dp->input_y + i * BYTES_PER_VECTOR));
		vz = _mm512_loadu_ps((float *)(dp->input_z + i * DWORD_PER_VECTOR));
		__m512bh bvx = _mm512_cvtne2ps_pbh(vx, _mm512_setzero_ps());
		__m512bh bvy = _mm512_cvtne2ps_pbh(vy, _mm512_setzero_ps());

		voutput = _mm512_dpbf16_ps(vz, bvx, bvy);
		_mm512_storeu_si512((__m512i *)(dp->output + i * BYTES_PER_VECTOR), _mm512_castps_si512(voutput));
	}
}

#include "worker_init_dotprod.c"
#include "run_common.c"

static struct workload w = {
	"AVX512",
	init,
	cleanup,
	run,
};

struct workload *register_AVX512(void)
{
	if (cpuid.avx512f)
		return &w;

	return NULL;
}
#else

#warning GCC < 11 can not build work_AVX512.c

#endif /* GCC < 11 */
