# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation.

CC = gcc
CFLAGS = -O2 -W -Wall -pthread

BIN = test_llc_agg test_fork test_churn test_llc_share

all: $(BIN)

test_llc_agg: test_llc_agg.c
	$(CC) $(CFLAGS) -o $@ $<

test_fork: test_fork.c
	$(CC) $(CFLAGS) -o $@ $<

test_churn: test_churn.c
	$(CC) $(CFLAGS) -o $@ $<

test_llc_share: test_llc_share.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	-rm -f $(BIN)

.PHONY: all clean
