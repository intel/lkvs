# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

BINS := xstate_64 xsave_list xsave_test

CFLAGS += -O2 -g -std=gnu99 -pthread -Wall -no-pie
NO_FPU_FLAG +=  -mno-sse -mno-mmx -mno-sse2 -mno-avx -mno-pku

all: $(BINS)

xstate_64: xstate.c
	gcc $(CFLAGS) $(NO_FPU_FLAG) -c -o xstate_helpers.o xstate_helpers.c
	gcc -m64 -o $@ -O2 $(CFLAGS) -DCAN_BUILD_32 -DCAN_BUILD_64 $^ xstate_helpers.o -lrt -ldl

xsave_list: xsave_list.c
	gcc -o $@ $^

xsave_test: xsave_test.c
	gcc -o $@ $^

clean:
	rm -rf $(BINS) *.o
