// SPDX-License-Identifier: GPL-2.0-only
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>

static int __init test_tdx_hlt_init(void)
{
	pr_info("[TD guest test] Start to trigger hlt instr.\n");
	asm("cli");
	asm("hlt");
	return 0;
}

static void __exit test_tdx_hlt_exit(void)
{
	pr_info("[TD guest test] Complete of hlt instr. test, test module exit\n");
}

module_init(test_tdx_hlt_init);
module_exit(test_tdx_hlt_exit);
MODULE_INFO(intree, "Y");
MODULE_LICENSE("GPL");
