# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation.

BIN := cpuid_check

all: $(BIN)

cpuid_check: cpuid_check.c
	gcc $^ -o $@

clean:
	rm -rf $(BIN)
