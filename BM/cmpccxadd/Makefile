# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation.

CC = gcc
CFLAGS = -g -Wall
TARGET = cmpccxadd

$(TARGET): cmpccxadd.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)