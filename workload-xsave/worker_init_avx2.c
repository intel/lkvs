// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2022 Intel Corporation.
 * Len Brown <len.brown@intel.com>
 */

static int init(struct work_instance *wi)
{
	int i;
	struct thread_data *dp;
	int bytes_per_entry = BYTES_PER_VECTOR * 3;	/* x[], y[], output[] */
	int entries;

	entries = wi->wi_bytes / bytes_per_entry;

	dp = (struct thread_data *)calloc(1, sizeof(struct thread_data));
	if (!dp)
		err(1, "thread_data");

	dp->input_x = (uint8_t *)calloc(entries, BYTES_PER_VECTOR);
	if (!dp->input_x)
		err(1, "calloc input_x");

	dp->input_y = (int8_t *)calloc(entries, BYTES_PER_VECTOR);
	if (!dp->input_y)
		err(1, "calloc input_y");

	/* initialize input -- make every iteration the same for now */
	for (i = 0; i < entries; ++i) {
		int j;

		for (j = 0; j < BYTES_PER_VECTOR; j++) {
			int index = i * BYTES_PER_VECTOR + j;

			dp->input_x[index] = j;
			dp->input_y[index] = BYTES_PER_VECTOR + j;
		}
	}

	dp->output = (int16_t *) calloc(entries, BYTES_PER_VECTOR);
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
