# If called directly from the command line, invoke the kernel build system.
ifeq ($(KERNELRELEASE),)

	KERNEL_SOURCE := /usr/src/kernels/$(shell uname -r)
	PWD := $(shell pwd)
default: module cet_app

module:
	$(MAKE) -C $(KERNEL_SOURCE) SUBDIRS=$(PWD) modules

cet_app:
	$(CC) -mshstk -o $@ cet_app.c

clean:
	$(MAKE) -C $(KERNEL_SOURCE) SUBDIRS=$(PWD) clean
	${RM} -rf cet_app

# Otherwise KERNELRELEASE is defined; we've been invoked from the
# kernel build system and can use its language.
else

	obj-m := cet_ioctl.o

endif
