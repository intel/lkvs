# SPDX-License-Identifier: GPL-2.0
CETFLAGS := -O0 -fcf-protection=full -mshstk -fno-stack-check -fno-stack-protector -no-pie
SHSTKFLAGS := -O0 -mshstk -fcf-protection=return -fno-stack-check -fno-stack-protector -no-pie
NOCETFLAGS := -O0 -fcf-protection=none -mshstk -fno-stack-check -fno-stack-protector -no-pie

GCC_VER_MAJOR := $(shell gcc --version | grep gcc | cut -d . -f1 | awk '{print $$NF}')
GCC_GE_8 := $(shell [ $(GCC_VER_MAJOR) -ge 8 ] && echo true)

ifeq ($(GCC_GE_8),true)
BIN := shstk_alloc test_shadow_stack quick_test wrss shstk_huge_page

$(info GCC major version: ${GCC_VER_MAJOR})
else
$(info Warning: GCC major version ${GCC_VER_MAJOR}, older than GCC 8)
$(info Warning: Could not handle CET related binary)
endif

all: $(BIN)

shstk_alloc: shstk_alloc.c
	gcc $(CETFLAGS) $^ -o $@

test_shadow_stack: test_shadow_stack.c
	gcc $(NOCETFLAGS) $^ -o $@

quick_test: quick_test.c
	gcc $(CETFLAGS) $^ -o $@

wrss: wrss.c
	gcc $(SHSTKFLAGS) $^ -o $@

shstk_huge_page: shstk_huge_page.c
	gcc $(CETFLAGS) $^ -o $@

clean:
	rm -rf $(BIN)