# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation.

BIN := apx_cpuid apx_xstate apx_egpr apx_instructions apx_ptrace apx_sigcontext apx_ctxsw

CFLAGS += -O2 -g -std=gnu99 -Wall -no-pie
NO_FPU_FLAG += -mno-sse -mno-mmx -mno-sse2 -mno-avx -mno-pku

# Check if GCC supports -mapxf
APX_FLAG := $(shell echo 'int main(){}' | gcc -mapxf -x c - -o /dev/null 2>/dev/null && echo -mapxf)

all: $(BIN)

apx_cpuid: apx_cpuid.c
	gcc $(CFLAGS) -o $@ $^

apx_xstate: apx_xstate.c apx_xstate_helpers.c
	gcc $(CFLAGS) $(NO_FPU_FLAG) $(APX_FLAG) -c -o apx_xstate_helpers.o apx_xstate_helpers.c
	gcc $(CFLAGS) -o $@ apx_xstate.c apx_xstate_helpers.o

apx_egpr: apx_egpr.c
	gcc $(CFLAGS) $(APX_FLAG) -o $@ $^

apx_instructions: apx_instructions.c
	gcc $(CFLAGS) $(APX_FLAG) -o $@ $^

apx_ptrace: apx_ptrace.c apx_xstate_helpers.c
	gcc $(CFLAGS) $(NO_FPU_FLAG) $(APX_FLAG) -c -o apx_xstate_helpers.o apx_xstate_helpers.c
	gcc $(CFLAGS) -o $@ apx_ptrace.c apx_xstate_helpers.o

apx_sigcontext: apx_sigcontext.c apx_xstate_helpers.c
	gcc $(CFLAGS) $(NO_FPU_FLAG) $(APX_FLAG) -c -o apx_xstate_helpers.o apx_xstate_helpers.c
	gcc $(CFLAGS) -o $@ apx_sigcontext.c apx_xstate_helpers.o

apx_ctxsw: apx_ctxsw.c apx_xstate_helpers.c
	gcc $(CFLAGS) $(NO_FPU_FLAG) $(APX_FLAG) -c -o apx_xstate_helpers.o apx_xstate_helpers.c
	gcc $(CFLAGS) -pthread -o $@ apx_ctxsw.c apx_xstate_helpers.o

clean:
	rm -rf $(BIN) *.o
