# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation.

CC = gcc
CFLAGS = -D_GNU_SOURCE -lpthread -m64 -O2
TARGET = lam

$(TARGET): lam.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)
