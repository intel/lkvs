# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

CETFLAGS := -O0 -fcf-protection=full -mshstk -fno-stack-check -fno-stack-protector -no-pie
SHSTKFLAGS := -O0 -mshstk -fcf-protection=return -fno-stack-check -fno-stack-protector -no-pie
NOCETFLAGS := -O0 -fcf-protection=none -mshstk -fno-stack-check -fno-stack-protector -no-pie

GCC_VER_MAJOR := $(shell gcc --version | grep gcc | cut -d . -f1 | awk '{print $$NF}')
GCC_GE_8 := $(shell [ $(GCC_VER_MAJOR) -ge 8 ] && echo true)

KER_SRC = /lib/modules/$(shell uname -r)/build
DRIVER_PATH = $(shell pwd)/cet_driver
IS_KER_SRC = $(shell  [ -d $(KER_SRC) ] && echo true)

ifeq ($(GCC_GE_8),true)
BIN := shstk_alloc test_shadow_stack quick_test wrss shstk_huge_page \
       shstk_unlock_test shstk_cp cet_app

$(info GCC major version: ${GCC_VER_MAJOR})
else
$(info [WARN]: GCC major version ${GCC_VER_MAJOR}, older than GCC 8)
$(info [WARN]: Could not handle CET related binary)
endif

ifeq ($(IS_KER_SRC),true)
BIN += cet_ioctl
else
$(info [WARN]:No $(KER_SRC) folder, please install $(shell uname -r) devel and header package!)
endif

all: $(BIN)

shstk_alloc: shstk_alloc.c
	gcc $(CETFLAGS) $^ -o $@

test_shadow_stack: test_shadow_stack.c
	gcc -pthread $(NOCETFLAGS) $^ -o $@

quick_test: quick_test.c
	gcc $(CETFLAGS) $^ -o $@

wrss: wrss.c
	gcc $(NOCETFLAGS) $^ -o $@

shstk_huge_page: shstk_huge_page.c
	gcc $(CETFLAGS) $^ -o $@

shstk_unlock_test: shstk_unlock_test.c
	gcc $(NOCETFLAGS) $^ -o $@

shstk_cp: shstk_cp.c
	gcc $(NOCETFLAGS) $^ -o $@

cet_app:
	gcc cet_driver/cet_app.c -I cet_driver -o $@

cet_ioctl:
	$(MAKE) -C $(KER_SRC) M=$(DRIVER_PATH) modules

clean:
	rm -rf $(BIN)
	$(MAKE) -C $(KER_SRC) M=$(DRIVER_PATH) clean
