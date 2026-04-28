// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Intel Corporation

#include <stdio.h>
#include <stdlib.h>

#include "bus_lock_common.h"

int main(void)
{
	unsigned char *buffer;
	int *int_ptr;
	int cache_line_size;

	cache_line_size = get_cache_line_size_cpuid();
	printf("The cache line size is %d bytes.\n", cache_line_size);

	buffer = (unsigned char *)aligned_alloc(cache_line_size,
			 2 * cache_line_size);
	int_ptr = (int *)(buffer + cache_line_size - 1);
	locked_add_1(int_ptr);

	return 0;
}
