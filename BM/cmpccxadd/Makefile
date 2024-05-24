# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation.
# Jiaan Lu <jiaan.lu@intel.com>

CFLAGS = -g

src = $(filter-out cmpxadd.c, $(wildcard *.c))
target = $(patsubst %.c, %, ${src})

.PHONY: all clean

%:%.c
	$(CC) ${CFLAGS} $^ -o $@

all: ${target}

clean:
	rm -f ${target}