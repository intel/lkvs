// SPDX-License-Identifier: GPL-2.0-only
/*
 * generic worker code for re-use via inclusion
 *
 * Copyright (c) 2022 Intel Corporation.
 * Len Brown <len.brown@intel.com>
 * Yi Sun <yi.sun@intel.com>
 * Dongcheng Yan <dongcheng.yan@intel.com>
 *
 */

#include <time.h>
#include <stdint.h>
#include "yogini.h"

void thread_break(int32_t reason, uint32_t thread_idx);
/*
 * run()
 * complete work in chunks of "data_entries" operations
 * between each chunk, check the time
 * return when requested operations complete, or out of time
 *
 * return operationds completed
 */
static unsigned long long run(struct work_instance *wi)
{
	unsigned int count;
	unsigned int operations = wi->repeat;
	struct thread_data *dp = wi->worker_data;

	if (operations == 0)
		operations = (~0U);

	for (count = 0; count < operations; count++) {
		thread_break(wi->break_reason, wi->thread_number);
		/* each invocation of work() does "entries" operations */
		work(dp);
	}
	unsigned long long tsc_now = rdtsc();
	return tsc_now;
}
