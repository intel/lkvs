# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation.

CC = gcc
TARGET = rdpmc_user_disable_test

$(TARGET): rdpmc_user_disable_test.c
	$(CC) -o $@ $<

clean:
	rm -f $(TARGET)
