# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation.

CC = gcc
TARGET = rdpmc_user_disable_test pebs_mrt_workload

$(TARGET): rdpmc_user_disable_test.c pebs_mrt_workload.c

rdpmc_user_disable_test: rdpmc_user_disable_test.c
	$(CC) -o $@ $<

pebs_mrt_workload: pebs_mrt_workload.c
	$(CC) -O2 -pthread -o $@ $<

clean:
	rm -f rdpmc_user_disable_test pebs_mrt_workload
