# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation.

CC = gcc
CFLAGS = -g -Wall 
TARGET = prefetchi

$(TARGET): prefetchi.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)
