# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

BIN := umip_exceptions_64
SUPPORT_GCC_32BIT = $(shell gcc -no-pie -c umip_utils.c -m32 -o umip_utils_32.o 2>/dev/null || echo false)

ifeq ($(SUPPORT_GCC_32BIT),false)
$(info Skip 32-bit compilation or clean due to lack of GCC support for 32-bit architecture.)
else
BIN += umip_exceptions_32
endif

all: $(BIN)

umip_exceptions_64: umip_exceptions.c
	$(CC) -no-pie -c umip_utils.c -o umip_utils_64.o
	$(CC) -o $@ umip_utils_64.o $^

umip_exceptions_32: umip_exceptions.c
	$(CC) -no-pie -c umip_utils.c -m32 -o umip_utils_32.o
	$(CC) -m32 -o $@ umip_utils_32.o $^

clean:
	rm -rf $(BIN) *.o
