// SPDX-License-Identifier: GPL-2.0-only
/*
 * offer the "UMWAIT" workload to yogini
 *
 * Copyright (c) 2023 Intel Corporation.
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

#define WORKLOAD_NAME "UMWAIT"

#define DATA_ENTRIES 1

static void work(void *arg)
{
	char dummy;

	_umonitor(&dummy);
	_umwait(0, (unsigned long long)-1);
}

#include "run_common.c"

static struct workload w = {
	"UMWAIT",
	NULL,
	NULL,
	run,
};

struct workload *register_UMWAIT(void)
{
	if (cpuid.tpause)
		return &w;

	return NULL;
}
#else

#warning GCC < 9 can not build work_UMWAIT.c

#endif /* GCC < 9 */
