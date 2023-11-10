// SPDX-License-Identifier: GPL-2.0-only
/*
 * offer the "TPAUSE" workload to yogini
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

#if __GNUC__ >= 9

#pragma GCC target("waitpkg")

#define WORKLOAD_NAME "TPAUSE"
#define TPAUSE_TSC_CYCLES	((unsigned long long)(1000 * 1000))

#define DATA_ENTRIES 1

static void work(void *arg)
{
	unsigned int ctrl;
	unsigned long long tsc;

	ctrl = 0;
	tsc = _rdtsc();
	tsc += TPAUSE_TSC_CYCLES;

	_tpause(ctrl, tsc);
}

#include "run_common.c"

static struct workload w = {
	"TPAUSE",
	NULL,
	NULL,
	run,
};

struct workload *register_TPAUSE(void)
{
	if (cpuid.tpause)
		return &w;

	return NULL;
}
#else

#warning GCC < 9 can not build work_TPAUSE.c

#endif /* GCC < 9 */
