# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

BIN := sl_test

all: $(BIN)

sl_test: sl_test.c
	gcc $^ -o $@

clean:
	rm -rf $(BIN) *.o
