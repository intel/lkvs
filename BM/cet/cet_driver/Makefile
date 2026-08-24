# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation.

# If called directly from the command line, invoke the kernel build system.
ifeq ($(KERNELRELEASE),)
PWD = $(shell pwd)
RPM_PKG := $(shell rpm -qa)
KERNEL_SOURCE = /lib/modules/$(shell uname -r)/build

BIN := cet_ioctl

all: $(BIN)

cet_ioctl:
	@if [ ! -d "$(KERNEL_SOURCE)" ]; then \
		echo "ERROR: kernel build dir $(KERNEL_SOURCE) not found."; \
		echo "       Install the matching kernel-devel/kernel-headers package"; \
		echo "       (e.g. 'dnf install kernel-devel-$(shell uname -r)' or"; \
		echo "       'apt install linux-headers-$(shell uname -r)') so the"; \
		echo "       cet_ioctl module can be built, then re-run make."; \
		exit 1; \
	fi
	$(MAKE) -C $(KERNEL_SOURCE) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNEL_SOURCE) M=$(PWD) clean
	${RM} -rf $(BIN)

# Otherwise KERNELRELEASE is defined; we've been invoked from the
# kernel build system and can use its language.
else
	# The IBT/SHSTK helper functions (cet_ibt1, cet_shstk1, ...) are file-local
	# but intentionally kept non-static so the compiler emits real stack frames
	# and indirect jumps needed to trigger #CP. Suppress the missing prototype/
	# declaration warnings so the module still builds on kernels configured with
	# -Werror for them.
	ccflags-y += -Wno-missing-prototypes -Wno-missing-declarations
	obj-m := cet_ioctl.o
endif
