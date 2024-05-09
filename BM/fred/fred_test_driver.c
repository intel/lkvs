// SPDX-License-Identifier: GPL-2.0-only
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/kdev_t.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/ioctl.h>
#include <linux/err.h>

MODULE_AUTHOR("Shan Kang <shan.kang@intel.com>");
MODULE_VERSION("1.0");

dev_t dev;
static struct class *dev_class;
static struct cdev fred_test_cdev;
static char our_buf[256];

/* Function Prototypes */
static int      __init fred_test_driver_init(void);
static void     __exit fred_test_driver_exit(void);
static int      fred_test_open(struct inode *inode, struct file *file);
static int      fred_test_release(struct inode *inode, struct file *file);
static ssize_t  fred_test_read(struct file *filp, char __user *buf, size_t count, loff_t *off);
static ssize_t  fred_test_write(struct file *filp, const char *buf, size_t count, loff_t *off);
static long     fred_test_ioctl(struct file *file, unsigned int cmd, unsigned long arg);

/*
 * File operation structure
 */
static const struct file_operations fops = {
	.owner = THIS_MODULE,
	.read = fred_test_read,
	.write = fred_test_write,
	.open = fred_test_open,
	.unlocked_ioctl = fred_test_ioctl,
	.release = fred_test_release,
};

static int fred_enable(void)
{
	u64 cr4;
	u64 fred_bit;

	asm volatile("mov %%cr4,%0\n\t" : "=r" (cr4) : __FORCE_ORDER);

	pr_info("cr4 value = %llx\n", cr4);

	fred_bit = cr4 >> 32 & 1;

	return fred_bit;
}

static void invoke_double_fault(void)
{
	long rsp;
	int *pi = 0x0;

	/* Close irq and preemption */
	local_irq_disable();
	preempt_disable();

	asm volatile ("movq %%rsp, %0" : "=rm" (rsp));
	//set_orig_rsp(rsp);
	/* Set rsp to 4096 */
	/* it will invoke a second page fault when entering into the page fault handler */
	asm volatile ("movq %0, %%rsp" : : "r" (4096L));

	/* It will invoke the first page fault */
	*pi = 100;

	/* Open irq and preemption */
	preempt_enable();
	local_irq_enable();
}

/* This function will be called when we open the Device file */
static int fred_test_open(struct inode *inode, struct file *file)
{
	pr_info("Device File Opened...!!!\n");
	return 0;
}

/* This function will be called when we close the Device file */
static int fred_test_release(struct inode *inode, struct file *file)
{
	pr_info("Device File Closed...!!!\n");
	return 0;
}

static ssize_t fred_test_read(struct file *filp, char __user *buf, size_t count, loff_t *off)
{
	int len;
	/* For example - when content of our_buf is "100" - */
	/* when user executes command "cat /dev/fred_test_device" */
	/* he will see content of our_buf(in our example "100" */
	len = snprintf(buf, count, "%s", our_buf);
	return len;
}

static ssize_t fred_test_write(struct file *filp, const char *buf, size_t count, loff_t *off)
{
	long opt;
	u64 fred_bit;
	int ret;
	/* If count is bigger than 255, */
	/* data which user wants to write is too big to fit in our_buf. */
	/* We don't want any buffer overflows, so we read only 255 bytes */
	if (count > 255)
		count = 255;
	/* Here we read from buf to our_buf */
	if (copy_from_user(our_buf, buf, count))
		pr_err("Data Write : Err!\n");

	/* we write NULL to end the string */
	our_buf[count] = '\0';

	if (strncmp(our_buf, "fred_enable ", strlen("fred_enable ")) == 0) {
		ret = kstrtol(our_buf + strlen("fred_enable "), 10, &opt);
		if (!ret) {
			pr_err("kstrtol failed\n");
			return 0;
		}
		//opt = simple_strtol(our_buf + strlen("fred_enable "), NULL, 10);
		pr_info("fred_enable expected %ld\n", opt);
		fred_bit = fred_enable();
		if (fred_bit == (u64)opt)
			pr_info("fred_enable test PASS\n");
		else
			pr_info("fred_enable test FAIL\n");

	} else if (strncmp(our_buf, "double_fault", strlen("double_fault")) == 0) {
		pr_info("double_fault test begin\n");
		invoke_double_fault();
	} else {
		pr_info("Not supported case\n");
	}

	return count;
}

/* This function will be called when we write IOCTL on the Device file */
static long fred_test_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	return 0;
}

/* Module Init function */
static int __init fred_test_driver_init(void)
{
	/* Allocating Major number */
	if ((alloc_chrdev_region(&dev, 0, 1, "fred_test_Dev")) < 0) {
		pr_err("Cannot allocate major number\n");
		return -1;
	}
	pr_info("Major = %d Minor = %d\n", MAJOR(dev), MINOR(dev));
	/* Creating cdev structure */
	cdev_init(&fred_test_cdev, &fops);
	/* Adding character device to the system */
	if ((cdev_add(&fred_test_cdev, dev, 1)) < 0) {
		pr_err("Cannot add the device to the system\n");
		goto r_class;
	}
	/* Creating struct class */
	dev_class = class_create(THIS_MODULE, "fred_test_class");
	if (IS_ERR(dev_class)) {
		pr_err("Cannot create the struct class\n");
		goto r_class;
	}
	/* Creating device */
	if (IS_ERR(device_create(dev_class, NULL, dev, NULL, "fred_test_device"))) {
		pr_err("Cannot create the Device 1\n");
		goto r_device;
	}
	pr_info("Device Driver Insert...Done!!!\n");
	return 0;

r_device:
	class_destroy(dev_class);
r_class:
	unregister_chrdev_region(dev, 1);
	return -1;
}

/* Module exit function */
static void __exit fred_test_driver_exit(void)
{
	device_destroy(dev_class, dev);
	class_destroy(dev_class);
	cdev_del(&fred_test_cdev);
	unregister_chrdev_region(dev, 1);
	pr_info("Device Driver Remove...Done!!!\n");
}

module_init(fred_test_driver_init);
module_exit(fred_test_driver_exit);

MODULE_LICENSE("GPL");
