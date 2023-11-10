// SPDX-License-Identifier: GPL-2.0-only
/*
 * offer the "PAUSE" workload to yogini
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
#include <x86intrin.h>

#define DATA_ENTRIES 1024

static void work(void *arg)
{
	int i;

	for (i = 0; i < DATA_ENTRIES; ++i)
		asm volatile ("pause");
}

#include "run_common.c"

static struct workload w = {
	"PAUSE",
	NULL,
	NULL,
	run,
};

struct workload *register_PAUSE(void)
{
	return &w;
}
