# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

BIN := umip_exceptions_64 umip_exceptions_32

all: $(BIN)

umip_exceptions_64: umip_exceptions.c
	$(CC) -no-pie -c umip_utils.c -o umip_utils_64.o
	$(CC) -o $@ umip_utils_64.o $^

umip_exceptions_32: umip_exceptions.c
	$(CC) -no-pie -c umip_utils.c -m32 -o umip_utils_32.o
	$(CC) -m32 -o $@ umip_utils_32.o $^

clean:
	rm -rf $(BIN) *.o
