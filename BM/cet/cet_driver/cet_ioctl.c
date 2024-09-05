// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2022 Intel Corporation.

/*
 * cet_ioctl.c
 *
 * Author: Pengfei Xu <pengfei.xu@intel.com>
 *
 * This file simulated stack changed by hack, CET should block hack func
 *      - For cet hack simulation driver
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/version.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/errno.h>
#include <linux/uaccess.h>

#include "cet_ioctl.h"

#define FIRST_MINOR 0
#define MINOR_CNT 1

static dev_t dev;
static struct cdev c_dev;
static struct class *cl;

static int my_open(struct inode *i, struct file *f)
{
	pr_info("Device opened\n");
	return 0;
}

static int my_close(struct inode *i, struct file *f)
{
	pr_info("Device closed\n");
	return 0;
}

void dump_buffer(unsigned char *buf, int size)
{
	int i, j;

	pr_info("xsave size = %d (%03xh)\n", size, size);

	for (i = 0; i < size; i += 16) {
		pr_info("%04x: ", i);

		for (j = i; ((j < i + 16) && (j < size)); j++)
			pr_info("%02x ", buf[j]);
		pr_info("\n");
	}
}

void do_hack(void)
{
	pr_info("Access hack function\n");
	pr_info("You see this line, which means kernel space shstk failed!\n");
}

void cet_shstk1(void)
{
	unsigned long *func_bp;

	asm("movq %%rbp,%0" : "=r"(func_bp));
	pr_info("access kernel space cet shstk function\n");
	pr_info("[INFO]\tReal shstk function rbp content:%lx for main rbp.\n",
		*func_bp);
	*(func_bp + 1) = (unsigned long)do_hack;
}

void cet_ibt1(void)
{
	pr_info("ibt1:jmp back with *%%rax\n");

	#ifdef __x86_64__
		asm volatile ("leaq 1f, %rax;"
			"jmp *%rax;"
			"1:nop"
		);
	#else
		asm volatile ("lea 1f, %eax;"
			"jmp *%eax;"
			"1:nop"
		);
	#endif
}

void cet_ibt_legal(void)
{
	pr_info("ibt with legal endbr64 flag:jmp back with *%%rax\n");

	#ifdef __x86_64__
		asm volatile ("leaq 1f, %rax;"
			"jmp *%rax;"
			"1:endbr64"
		);
	#else
		asm volatile ("lea 1f, %eax;"
			"jmp *%eax;"
			"1:endbr32"
		);
	#endif
}

static inline void cet_xsaves(uint32_t xstate_size)
{
	u32 ecx = MSR_IA32_PL3_SSP;
	u32 eax, ebx, edx;

	asm("rdmsr" : "=a" (eax), "=b" (ebx), "=d" (edx) : "c" (ecx));
	pr_info("rdmsr 0x6a7: eax:%x, ebx:%x, ecx:%x, edx:%x\n",
		eax, ebx, ecx, edx);
}

static long my_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
	u32 xstate_size;

	pr_info("cet ioctl in kernel space\n");
	switch (cmd) {
	case CET_SHSTK1:
		cet_shstk1();
		break;
	case CET_SHSTK_XSAVES:
		xstate_size = get_xstate_size();
		cet_xsaves(xstate_size);
		break;
	case CET_IBT1:
		cet_ibt1();
		break;
	case CET_IBT2:
		cet_ibt_legal();
		break;
	default:
		return -EINVAL;
	}

	return 0;
}

static const struct file_operations query_fops = {
	.owner = THIS_MODULE,
	.open = my_open,
	.release = my_close,
	.unlocked_ioctl = my_ioctl
};

static int __init cet_ioctl_init(void)
{
	int ret;
	struct device *dev_ret;
	char mod_name[] = "cet_ioctl";

	pr_info("Load cet_ioctl start\n");
	ret = alloc_chrdev_region(&dev, FIRST_MINOR, MINOR_CNT, mod_name);
	if (ret < 0) {
		pr_info("alloc_chrdev_region failed\n");
		return ret;
	}

	cdev_init(&c_dev, &query_fops);

	ret = cdev_add(&c_dev, dev, MINOR_CNT);
	if (ret < 0) {
		pr_info("cdev_add failed\n");
		return ret;
	}

	/*
	 * From v6.3-rc1: dcfbb67e48a2becfce7990386e985b9c45098ee5,
	 * there is no second parameter for class_create(const char *name).
	 * If the host kernel version is lower than v6.3-rc1, please change
	 * the code as follows:
	 * cl = class_create(THIS_MODULE, "char");
	 * mod_name is allocated from stack so released after this function.
	 * Othwise it will cause "BUG: unable to handle page fault for address:
	 * ffffc9000447fbd4" issue. So use string instead and it's "kernel" way:
	 * use plain string here.
	 */
	cl = class_create("cet_ioctl");
	if (IS_ERR(cl)) {
		cdev_del(&c_dev);
		unregister_chrdev_region(dev, MINOR_CNT);
		return PTR_ERR(cl);
	}

	dev_ret = device_create(cl, NULL, dev, NULL, "cet");
	if (IS_ERR(dev_ret)) {
		class_destroy(cl);
		cdev_del(&c_dev);
		unregister_chrdev_region(dev, MINOR_CNT);
		return PTR_ERR(dev_ret);
	}

	return 0;
}

static void __exit cet_ioctl_exit(void)
{
	pr_info("Will unload driver.\n");
	if (!cl)
		pr_err("Class pointer 'cl' is NULL\n");
	else
		pr_info("Class pointer 'cl' is valid: cl:%p\n", (void *)cl);

	if (!dev)
		pr_err("Device pointer 'dev' is NULL\n");
	else
		pr_info("Device pointer 'dev' is valid &dev:%p, dev:%d\n", &dev, dev);

	device_destroy(cl, dev);
	pr_info("Device destroyed\n");
	class_destroy(cl);
	cdev_del(&c_dev);
	unregister_chrdev_region(dev, MINOR_CNT);
	pr_info("Driver uninstall completed.\n");
}

module_init(cet_ioctl_init);
module_exit(cet_ioctl_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("XPF");
MODULE_DESCRIPTION("cet ioctl() Driver");
