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
	$(MAKE) -C $(KERNEL_SOURCE) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNEL_SOURCE) M=$(PWD) clean
	${RM} -rf $(BIN)

# Otherwise KERNELRELEASE is defined; we've been invoked from the
# kernel build system and can use its language.
else
	obj-m := cet_ioctl.o
endif
