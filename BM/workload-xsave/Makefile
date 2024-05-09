# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2022 Intel Corporation.
# Len Brown <len.brown@intel.com>
# Yi Sun <yi.sun@intel.com>
# Dongcheng Yan <dongcheng.yan@intel.com>

CC		= $(CROSS_COMPILE)gcc
BUILD_OUTPUT	:= $(CURDIR)
PREFIX		?= /usr
DESTDIR		?=
DAY		:= $(shell date +%Y.%m.%d)
DATE_TIME	:= $(shell date +%Y%m%d_%H%M%S)

ifeq ("$(origin O)", "command line")
	BUILD_OUTPUT := $(O)
endif

PROGS= yogini
SRC= yogini.c work_AMX.c work_AVX.c work_AVX2.c work_AVX512.c work_VNNI512.c work_VNNI.c work_DOTPROD.c work_PAUSE.c work_TPAUSE.c work_UMWAIT.c work_RDTSC.c work_SSE.c work_MEM.c work_memcpy.c run_common.c worker_init4.c worker_init_dotprod.c worker_init_amx.c yogini.h
OBJS= yogini.o work_AMX.o work_AVX.o work_AVX2.o work_AVX512.o work_VNNI512.o $(GCC11_OBJS) work_DOTPROD.o work_PAUSE.o work_TPAUSE.o work_UMWAIT.o work_RDTSC.o work_SSE.o work_MEM.o work_memcpy.o
ASMS= work_AMX.S work_AVX.S work_AVX2.S work_AVX512.S work_VNNI512.S work_VNNI.S work_DOTPROD.S work_PAUSE.S work_TPAUSE.S work_UMWAIT.S work_RDTSC.S work_SSE.S work_MEM.S work_memcpy.S
GCC11_OBJS=work_VNNI.o

yogini : $(OBJS) $(ASMS)
ifeq ($(DEBUG), 1)
override CFLAGS +=      -march=sapphirerapids -g
else
override CFLAGS +=      -march=native
endif
override CFLAGS +=      -D_FORTIFY_SOURCE=2
override CFLAGS +=      -Wall
override CFLAGS +=      -O3
override CFLAGS +=      -mtune=skylake-avx512
#override CFLAGS +=     -mtune=alderlake
override CFLAGS +=      -mavx512bf16

LDFLAGS += -lm
LDFLAGS += -lpthread

%: %.c %.h
	@mkdir -p $(BUILD_OUTPUT)
	$(CC) $(CFLAGS) $(OBJS) -o $(BUILD_OUTPUT)/$@ $(LDFLAGS)

%.S: %.c
	@mkdir -p $(BUILD_OUTPUT)
	$(CC) $(CFLAGS) -S $^ -o $(BUILD_OUTPUT)/$@

.PHONY : clean
clean :
	@rm -f $(BUILD_OUTPUT)/yogini $(OBJS) $(ASMS)
