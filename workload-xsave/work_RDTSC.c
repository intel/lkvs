// SPDX-License-Identifier: GPL-2.0-only
/*
 * offer the "RDTSC" workload to yogini
 *
 * Copyright (c) 2022 Intel Corporation.
 * Len Brown <len.brown@intel.com>
 */

#define _GNU_SOURCE
#include <stdio.h>		/* printf(3) */
#include <stdlib.h>		/* random(3) */
#include <sched.h>		/* CPU_SET */
#include "yogini.h"

/*
 * This "workload" runs the worker infrastructure without any inner work.
 * As a result, it spends all of its time using RDTSC to end promptly.
 */
static inline void work(void *arg)
{
}

#define DATA_ENTRIES 1

#include "run_common.c"

static struct workload w = {
	"RDTSC",
	NULL,
	NULL,
	run,
};

struct workload *register_RDTSC(void)
{
	return &w;
}
