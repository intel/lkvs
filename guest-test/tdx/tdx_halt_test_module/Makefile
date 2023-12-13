# SPDX-License-Identifier: GPL-2.0-only

MODULES = halt_test.ko

obj-m += halt_test.o

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	make -C $(KDIR) M=$(PWD) modules
clean:
	make -C $(KDIR) M=$(PWD) clean