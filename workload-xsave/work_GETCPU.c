// SPDX-License-Identifier: GPL-2.0-only
/*
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

extern unsigned int tsc_to_msec_from_start(unsigned long long tsc);

/*
 * GETCPU_run()
 * Run the GETCPU spin loop either "loops" times, or until tsc_end
 * return loops completed
 */
static unsigned long long GETCPU_run(struct work_instance *wi,
				     unsigned long long loops, unsigned long long tsc_end)
{
	unsigned long long count;

	if (loops == 0)
		loops = (unsigned int)-1;

	if (tsc_end == 0)
		tsc_end = (unsigned long long)-1;

	for (count = 0; count < loops; count++) {
		unsigned long long tsc_now = rdtsc();
		int cpu;

		if (tsc_now >= tsc_end)
			break;

		cpu = record_cpu_residency(wi, tsc_to_msec_from_start(tsc_now));
		record_wi_duration(wi, tsc_now);
		record_cpu_work(wi, cpu, 1);
	}

	return (count);
}

static struct workload w = {
	"GETCPU",
	NULL,
	NULL,
	GETCPU_run,
};

struct workload *register_GETCPU(void)
{
	return &w;
}
