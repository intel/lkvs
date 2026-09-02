// SPDX-License-Identifier: GPL-2.0
/*
 * test_llc_share.c — true cache-line-sharing microbenchmark for Perf1.
 *
 * Usage: test_llc_share [working_set_kib] [duration_secs]
 *   working_set_kib : shared buffer size in KiB (default 8192 = 8 MiB).
 *                     Caller should size this to ~fit one LLC.
 *   duration_secs   : run time; 0 or omitted means run until killed.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#ifndef NTHREADS
#define NTHREADS 28
#endif

#define CACHELINE 64

/*
 * One counter per cache line: guarantees each line is an independent unit of
 * true sharing (every thread touches it) with no unintended packing.
 */
struct line {
	_Atomic long v;
	char pad[CACHELINE - sizeof(long)];
};

static struct line *buf;
static long nr_lines;
static _Atomic int stop;

static void *worker(void *arg)
{
	long id = (long)arg;
	/*
	 * Start each thread at a different offset so at any instant the threads
	 * are sweeping different lines. This spreads the coherence traffic
	 * across the whole buffer (avoiding degenerate single-line lock-step
	 * serialization) while every line is still read-modify-written by every
	 * thread over each pass — i.e. fully shared.
	 */
	long idx = (id * 64) % nr_lines;

	while (!atomic_load(&stop)) {
		for (long n = 0; n < nr_lines; n++) {
			atomic_fetch_add(&buf[idx].v, 1);	/* read-modify-write shared line */
			if (++idx >= nr_lines)
				idx = 0;
		}
	}
	return NULL;
}

int main(int argc, char **argv)
{
	long ws_kib = (argc > 1) ? atol(argv[1]) : 8192;
	long duration = (argc > 2) ? atol(argv[2]) : 0;
	pthread_t threads[NTHREADS];

	if (ws_kib <= 0)
		ws_kib = 8192;

	nr_lines = (ws_kib * 1024L) / sizeof(struct line);
	if (nr_lines < 1)
		nr_lines = 1;

	buf = calloc(nr_lines, sizeof(struct line));
	if (!buf) {
		fprintf(stderr, "calloc of %ld lines (%ld KiB) failed\n",
			nr_lines, ws_kib);
		return 1;
	}

	printf("PID: %d\n", getpid());
	printf("shared working set: %ld KiB (%ld cache lines), %d threads%s\n",
	       ws_kib, nr_lines, NTHREADS,
	       duration > 0 ? "" : " (run until killed)");
	fflush(stdout);

	for (long i = 0; i < NTHREADS; i++)
		pthread_create(&threads[i], NULL, worker, (void *)i);

	if (duration > 0) {
		sleep(duration);
		atomic_store(&stop, 1);
		for (long i = 0; i < NTHREADS; i++)
			pthread_join(threads[i], NULL);
	} else {
		for (long i = 0; i < NTHREADS; i++)
			pthread_join(threads[i], NULL);
	}

	free(buf);
	return 0;
}
