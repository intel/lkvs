# SPDX-License-Identifier: GPL-2.0
CFLAG = -O2 -W -Wall -g -fno-strict-aliasing
LIBS = -lpthread
CC = gcc
BIN_AMX = tmul
CFILES_AMX = tmul.c

# Auto-enable the FP16 (TDPFP16PS, -i 5) cases when the toolchain can assemble
# tdpfp16ps. Older toolchains (binutils < 2.38 / gcc < 13.3, some distros
# backport to 12.3) build tmul without FP16 so the remaining AMX cases still
# compile.
FP16_SUPPORTED := $(shell echo 'int main(void){asm volatile("tdpfp16ps %tmm7, %tmm6, %tmm5");return 0;}' | $(CC) -x c - -o /dev/null 2>/dev/null && echo yes)
ifeq ($(FP16_SUPPORTED),yes)
CFLAG += -DFP16
else
$(info NOTE: toolchain cannot assemble tdpfp16ps; building tmul without FP16 (-i 5 cases will fail).)
endif

all:
	$(CC) $(CFLAG) $(CFILES_AMX) -o $(BIN_AMX) $(LIBS)

# Kept as an alias for backward compatibility; FP16 auto-enables when supported.
fp16: all

clean:
	-rm $(BIN_AMX)

.PHONY: clean

