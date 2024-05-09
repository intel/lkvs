// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2022 Intel Corporation.
 * Yi Sun <yi.sun@intel.com>
 * Dongcheng Yan <dongcheng.yan@intel.com>
 *
 */
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#define YOGINI_MAIN
#include "yogini.h"

static void init_dword_tile(int8_t *ptr, uint8_t rows, uint8_t colsb, int entries)
{
	int32_t i, j, k;
	int32_t cols = colsb / 4;

	for (k = 0; k < entries; ++k) {
		for (i = 0; i < rows; i++)
			for (j = 0; j < cols; j++)
				ptr[k * rows * cols + i * cols + j] = random();
	}
}

static int init(struct work_instance *wi)
{
	struct thread_data *dp;
	/* int8_t x[], y[], int32_t output[] */
	int bytes_per_entry = BYTES_PER_VECTOR * 3;
	int entries;

	entries = wi->wi_bytes / bytes_per_entry;

	union __union_tile_config cfg;

	init_tile_config(&cfg, ROW_NUM, COL_NUM);

	dp = (struct thread_data *)calloc(1, sizeof(struct thread_data));
	if (!dp)
		err(1, "thread_data");

	dp->input_x = (int8_t *)calloc(entries, BYTES_PER_VECTOR);
	if (!dp->input_x)
		err(1, "calloc input_x");

	dp->input_y = (int8_t *)calloc(entries, BYTES_PER_VECTOR);
	if (!dp->input_y)
		err(1, "calloc input_y");

	/* initialize input -- make every iteration the same for now */
	init_dword_tile(dp->input_x, ROW_NUM, COL_NUM, entries);
	init_dword_tile(dp->input_y, ROW_NUM, COL_NUM, entries);

	dp->output = (int32_t *) calloc(entries, BYTES_PER_VECTOR);
	if (dp->output == NULL)
		err(1, "calloc output");

	dp->data_entries = entries;

	wi->worker_data = dp;

	return 0;
}

static int cleanup(struct work_instance *wi)
{
	struct thread_data *dp = wi->worker_data;

	free(dp->input_x);
	free(dp->input_y);
	free(dp->output);
	free(dp);
	wi->worker_data = NULL;

	return 0;
}
