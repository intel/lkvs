// SPDX-License-Identifier: GPL-2.0-only
/*
 * generic worker code for re-use via inclusion
 *
 * Copyright (c) 2022 Intel Corporation.
 * Len Brown <len.brown@intel.com>
 */

#include <err.h>

#include <stdlib.h>
#include "yogini.h"

static double get_random_double(void)
{
	unsigned long long random_int64;

	random_int64 = (long long)random() | (((long long)random()) << 32);

	return (double)random_int64;
}

static int init(struct work_instance *wi)
{
	int i;
	struct thread_data *dp;
	int bytes_per_entry = sizeof(double) * 4;	/* a[], x[], y[], z[] */
	int entries;

	entries = wi->wi_bytes / bytes_per_entry;

	dp = (struct thread_data *)calloc(1, sizeof(struct thread_data));
	if (!dp)
		err(1, "thread_data");

	srand((int)time(0));

	dp->a = malloc(entries * sizeof(double));
	dp->x = malloc(entries * sizeof(double));
	dp->y = malloc(entries * sizeof(double));
	dp->z = malloc(entries * sizeof(double));
	dp->data_entries = entries;

	if (!dp->a || !dp->x || !dp->y || !dp->z)
		errx(-1, "malloc failed");

	for (i = 0; i < entries; ++i) {
		dp->a[i] = get_random_double();
		dp->x[i] = get_random_double();
		dp->y[i] = get_random_double();
		dp->z[i] = get_random_double();
	}
	wi->worker_data = dp;

	return 0;
}

static int cleanup(struct work_instance *wi)
{
	struct thread_data *dp = wi->worker_data;

	free(dp->a);
	free(dp->x);
	free(dp->y);
	free(dp->z);
	free(dp);
	wi->worker_data = NULL;

	return 0;
}
