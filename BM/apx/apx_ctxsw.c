// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

/*
 * apx_ctxsw.c - Multi-threaded context switch test for APX EGPR state.
 *
 * Multiple threads are pinned to a single CPU, each loads random EGPR
 * values and verifies they survive context switches via mutex handoff.
 *
 * Tests:
 *   1. ctxsw_threads   - N threads with randomized EGPR, verify after switches
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdbool.h>
#include <pthread.h>
#include <sched.h>
#include <getopt.h>
#include <cpuid.h>
#include <time.h>

#include "apx_xstate_helpers.h"
#include "../common/kselftest.h"

#define CPUID_LEAF_XSTATE	0xD
#define NUM_THREADS		5
#define NUM_ITERATIONS		10

static u32 apx_xstate_offset;
static u32 apx_xstate_size;
static u32 total_xstate_size;

static void check_apx_cpuid(void)
{
	u32 eax, ebx, ecx, edx;

	__cpuid_count(7, 1, eax, ebx, ecx, edx);
	if (!(edx & (1U << 21)))
		ksft_exit_skip("CPU doesn't support APX (CPUID.7.1:EDX[21]).\n");

	__cpuid_count(1, 0, eax, ebx, ecx, edx);
	if (!(ecx & (1U << 26)))
		ksft_exit_skip("CPU doesn't support XSAVE.\n");
	if (!(ecx & (1U << 27)))
		ksft_exit_skip("OS hasn't enabled XSAVE (OSXSAVE=0).\n");

	__cpuid_count(CPUID_LEAF_XSTATE, XFEATURE_APX, eax, ebx, ecx, edx);
	apx_xstate_size = eax;
	apx_xstate_offset = ebx;

	if (apx_xstate_size == 0)
		ksft_exit_skip("APX XSAVE area size is 0 (not enabled by OS).\n");

	__cpuid_count(CPUID_LEAF_XSTATE, 0, eax, ebx, ecx, edx);
	total_xstate_size = ebx;
}

static void *alloc_xbuf(u32 size)
{
	void *buf = aligned_alloc(XSAVE_ALIGNMENT, size);

	if (!buf) {
		perror("aligned_alloc");
		return NULL;
	}
	memset(buf, 0, size);
	return buf;
}

static void fill_rand_apx(void *xbuf)
{
	struct apx_state *apx;
	u64 *header;
	int i;

	header = (u64 *)((char *)xbuf + XSAVE_HDR_OFFSET);
	*header |= XFEATURE_MASK_APX;

	apx = (struct apx_state *)((char *)xbuf + apx_xstate_offset);

	/* Use non-zero random data (ensures not init state) */
	for (i = 0; i < APX_NUM_REGS; i++)
		apx->egpr[i] = ((u64)rand() << 32 | rand()) | 1;
}

static bool compare_apx_state(void *buf1, void *buf2)
{
	struct apx_state *a1 = (struct apx_state *)((char *)buf1 + apx_xstate_offset);
	struct apx_state *a2 = (struct apx_state *)((char *)buf2 + apx_xstate_offset);
	int i;

	for (i = 0; i < APX_NUM_REGS; i++) {
		if (a1->egpr[i] != a2->egpr[i])
			return false;
	}
	return true;
}

struct thread_info {
	unsigned int iterations;
	struct thread_info *next;
	pthread_mutex_t mutex;
	pthread_t thread;
	bool valid;
	int nr;
};

static void *check_xstate_thread(void *arg)
{
	struct thread_info *ti = (struct thread_info *)arg;
	void *xbuf_expected, *xbuf_check;
	int i;

	xbuf_expected = alloc_xbuf(total_xstate_size);
	xbuf_check = alloc_xbuf(total_xstate_size);
	if (!xbuf_expected || !xbuf_check) {
		ti->valid = false;
		return ti;
	}

	/* Load random EGPR state */
	fill_rand_apx(xbuf_expected);
	xrstor_apx(xbuf_expected, XFEATURE_MASK_APX);
	ti->valid = true;

	for (i = 0; i < (int)ti->iterations; i++) {
		pthread_mutex_lock(&ti->mutex);

		if (ti->valid) {
			/* Save current state and compare with expected */
			memset(xbuf_check, 0, total_xstate_size);
			xsave_apx(xbuf_check, XFEATURE_MASK_APX);

			ti->valid = compare_apx_state(xbuf_expected, xbuf_check);

			/* Reload new random data for next iteration */
			fill_rand_apx(xbuf_expected);
			xrstor_apx(xbuf_expected, XFEATURE_MASK_APX);
		}

		/* Wake up next thread in chain */
		pthread_mutex_unlock(&ti->next->mutex);
	}

	free(xbuf_expected);
	free(xbuf_check);
	return ti;
}

static void test_ctxsw_threads(void)
{
	struct thread_info *tinfo;
	bool all_valid = true;
	cpu_set_t cpuset;
	int i;

	/* Pin to CPU 0 to force context switches between threads */
	CPU_ZERO(&cpuset);
	CPU_SET(0, &cpuset);
	if (sched_setaffinity(0, sizeof(cpuset), &cpuset) != 0)
		ksft_exit_fail_msg("sched_setaffinity to CPU 0 failed\n");

	srand(time(NULL));

	tinfo = calloc(NUM_THREADS, sizeof(*tinfo));
	if (!tinfo)
		ksft_exit_fail_msg("calloc failed\n");

	/* Create threads with chained mutex handoff */
	for (i = 0; i < NUM_THREADS; i++) {
		int next = (i + 1) % NUM_THREADS;

		tinfo[i].nr = i;
		tinfo[i].iterations = NUM_ITERATIONS;
		tinfo[i].next = &tinfo[next];

		pthread_mutex_init(&tinfo[i].mutex, NULL);
		pthread_mutex_lock(&tinfo[i].mutex);

		if (pthread_create(&tinfo[i].thread, NULL,
				   check_xstate_thread, &tinfo[i]))
			ksft_exit_fail_msg("pthread_create failed for thread %d\n", i);
	}

	/* Kick off thread 0 */
	pthread_mutex_unlock(&tinfo[0].mutex);

	/* Wait for all threads to finish */
	for (i = 0; i < NUM_THREADS; i++) {
		void *retval;

		if (pthread_join(tinfo[i].thread, &retval))
			ksft_exit_fail_msg("pthread_join failed for thread %d\n", i);

		if (!tinfo[i].valid) {
			ksft_print_msg("[FAIL] Thread %d detected EGPR corruption\n", i);
			all_valid = false;
		}
	}

	if (all_valid)
		ksft_test_result_pass("Multi-threaded context switch: %d threads x %d iterations\n",
				      NUM_THREADS, NUM_ITERATIONS);
	else
		ksft_test_result_fail("Multi-threaded context switch: EGPR corruption detected\n");

	free(tinfo);
}

static void usage(const char *prog)
{
	fprintf(stderr, "Usage: %s -t <test>\n", prog);
	fprintf(stderr, "Tests:\n");
	fprintf(stderr, "  ctxsw_threads - Multi-threaded EGPR context switch\n");
}

int main(int argc, char *argv[])
{
	const char *test_name = NULL;
	int opt;

	while ((opt = getopt(argc, argv, "t:")) != -1) {
		switch (opt) {
		case 't':
			test_name = optarg;
			break;
		default:
			usage(argv[0]);
			return 1;
		}
	}

	if (!test_name) {
		usage(argv[0]);
		return 1;
	}

	ksft_print_header();
	ksft_set_plan(1);

	check_apx_cpuid();

	if (strcmp(test_name, "ctxsw_threads") == 0)
		test_ctxsw_threads();
	else
		ksft_exit_fail_msg("Unknown test: %s\n", test_name);

	ksft_finished();
	return 0;
}
