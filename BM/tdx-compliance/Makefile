# SPDX-License-Identifier: GPL-2.0-only

MODULES = tdx-compliance.ko

obj-m += tdx-compliance.o

# Add other source files if needed
tdx-compliance-objs := tdx-compliance-main.o # tdcall.o tdxcall.o

ifeq ($(KERNEL_SRC),)
KDIR ?= /lib/modules/$(shell uname -r)/build
else
KDIR ?= $(abspath $(KERNEL_SRC))
endif

all:
	make -C $(KDIR) M=$(PWD) modules

clean:
	@make -C $(KDIR) M=$(PWD) clean


