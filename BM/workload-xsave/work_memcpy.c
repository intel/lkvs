// SPDX-License-Identifier: GPL-2.0-only
/*
 * offer the "memcpy" workload to yogini
 *
 * see yogini.8
 *
 * Initial implementation is specific to Intel hardware.
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
#include "string.h"
#include <err.h>
#include <stdint.h>
void thread_break(int32_t reason, uint32_t thread_idx);
#define MEM_BYTES_PER_ITERATION (4 * 1024)

struct thread_data {
	char *buf1;
	char *buf2;
};

static int init(struct work_instance *wi)
{
	struct thread_data *dp;

	dp = (struct thread_data *)calloc(1, sizeof(struct thread_data));
	if (!dp)
		err(1, "thread_data");

	/*
	 * set default working set to equal l3 cache
	 */

	if (wi->wi_bytes == 0)
		wi->wi_bytes = SIZE_1GB * 1024;	/* small calibration buffer for high score */

	if (wi->wi_bytes % (2 * MEM_BYTES_PER_ITERATION)) {
		warnx("memcpy: %d bytes is invalid working set size.\n", wi->wi_bytes);
		errx(-1, "memcpy: requires multiple of %d KB.\n",
		     (2 * MEM_BYTES_PER_ITERATION) / 1024);
	}

	dp->buf1 = malloc(wi->wi_bytes / 2);
	dp->buf2 = malloc(wi->wi_bytes / 2);

	if (!dp->buf1 || !dp->buf2) {
		perror("malloc");
		exit(-1);
	}

	wi->worker_data = dp;

	return 0;
}

static int cleanup(struct work_instance *wi)
{
	struct thread_data *dp = wi->worker_data;

	free(dp->buf1);
	free(dp->buf2);
	free(dp);

	wi->worker_data = NULL;

	return 0;
}

/*
 * run()
 * MEM bytes_to_copy, or until tsc_end
 * return bytes copied
 * use buf1 and buf2, in alternate directions
 */
static unsigned long long run(struct work_instance *wi)
{
	char *src, *dst;
	unsigned long long bytes_done;
	unsigned long long bytes_to_copy = wi->repeat * MEM_BYTES_PER_ITERATION;
	struct thread_data *dp = wi->worker_data;

	src = dp->buf1;
	dst = dp->buf2;

	for (bytes_done = 0;;) {
		int kb;

		for (kb = 0; kb < wi->wi_bytes / 1024 / 2; kb += 4) {
			/* MEM 4KB */
			memcpy(dst + kb * 1024, src + kb * 1024, MEM_BYTES_PER_ITERATION);

			bytes_done += MEM_BYTES_PER_ITERATION;

			thread_break(wi->break_reason, wi->thread_number);
			if (bytes_to_copy && bytes_done >= bytes_to_copy)
				goto done;
		}
	}
done:
	return rdtsc();
}

static struct workload memcpy_workload = {
	"memcpy",
	init,
	cleanup,
	run,
};

struct workload *register_memcpy(void)
{
	return &memcpy_workload;
}
