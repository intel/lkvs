# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

BIN := vbmi_test

all: $(BIN)

vbmi_test: vbmi_test.c
	$(CC) -o $@ $^

clean:
	rm -rf $(BIN) *.o
