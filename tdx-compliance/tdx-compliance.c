// SPDX-License-Identifier: GPL-2.0-only
#include <linux/debugfs.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/list.h>

#include "asm/trapnr.h"

#include "tdx-compliance.h"
#include "tdx-compliance-cpuid.h"
#include "tdx-compliance-cr.h"
#include "tdx-compliance-msr.h"

MODULE_AUTHOR("Yi Sun");

/*
 * Global Variables Summary:
 * - stat_total: Count the total number of cases of TDX compliance tests.
 *
 * - stat_pass: Count the number of cases in TDX compliance tests that
 *              passed the test according to the TDX Architecture
 *              Specification.
 *
 * - stat_fail: Count the number of cases in TDX compliance tests that
 *              failed to pass the test according to the TDX Architecture
 *              Specification.
 *
 * - cnt_log: Count the length of logs.
 *
 */
int stat_total, stat_pass, stat_fail, cnt_log;
int operation;
int spec_version;
char case_name[256];
char version_name[32];
char *buf_ret;
static struct dentry *f_tdx_tests, *d_tdx;
LIST_HEAD(cpuid_list);

#define SIZE_BUF		(PAGE_SIZE << 3)
#define pr_buf(fmt, ...)				\
	(cnt_log += sprintf(buf_ret + cnt_log, fmt, ##__VA_ARGS__))\

#define pr_tdx_tests(fmt, ...)				\
	pr_info("%s: " pr_fmt(fmt),			\
		module_name(THIS_MODULE), ##__VA_ARGS__)\

#define CR_ERR_INFO					\
	"Error: CR compliance test failed,"

#define MSR_ERR_INFO			\
	"Error: MSR compliance test failed,"

#define MSR_MULTIBYTE_ERR_INFO		\
	"Error: MSR multiple bytes difference,"

#define PROCFS_NAME		"tdx-tests"
#define OPMASK_CPUID		1
#define OPMASK_CR		2
#define OPMASK_MSR		4
#define OPMASK_DUMP			0x800
#define OPMASK_SINGLE		0x8000

#define CPUID_DUMP_PATTERN	\
	"eax(%08x) ebx(%08x) ecx(%08x) edx(%08x)\n"

static char *result_str(int ret)
{
	switch (ret) {
	case 1:
		return "PASS";
	case 0:
		return "NRUN";
	case -1:
		return "FAIL";
	}

	return "UNKNOWN";
}

void parse_version(void) 
{
	if (strstr(version_name, "1.0"))
		spec_version = VER1_0;
	else if (strstr(version_name, "1.5"))
		spec_version = VER1_5;
	else
		spec_version = (VER1_0 | VER1_5);
}

static char* case_version(int ret) {
	switch (ret) {
	case VER1_0:
		return "1.0";
	case VER1_5:
		return "1.5";
	}

	return "";
}

void parse_input(char* s) 
{
	memset(case_name, 0, sizeof(case_name));
	memset(version_name, 0, sizeof(version_name));
	char *space = strchr(s, ' ');
	if (space != NULL) {
		size_t length_case = space - s;
		strncpy(case_name, s, length_case);
		case_name[length_case] = '\0';

		size_t length_ver = strlen(space+1);
		strncpy(version_name, space+1, length_ver);
	} else {
		strcpy(case_name, s);
		strcpy(version_name, "generic");
	}

	parse_version();
}

static int check_results_msr(struct test_msr *t)
{
		if (t->excp.expect == t->excp.val)
			return 1;

		pr_buf(MSR_ERR_INFO "exception %d, but expect_exception %d\n",
		       t->excp.val, t->excp.expect);
		return -1;
}

static int run_cpuid(struct test_cpuid *t)
{
	t->regs.eax.val = t->leaf;
	t->regs.ecx.val = t->subleaf;
	__cpuid(&t->regs.eax.val, &t->regs.ebx.val, &t->regs.ecx.val, &t->regs.edx.val);

	return 0;
}

static int _native_read_msr(unsigned int msr, u64 *val)
{
	int err;
	u32 low = 0, high = 0;

	asm volatile("1: rdmsr ; xor %[err],%[err]\n"
		     "2:\n\t"
		     _ASM_EXTABLE_TYPE_REG(1b, 2b, EX_TYPE_FAULT, %[err])
		     : [err] "=r" (err), "=a" (low), "=d" (high)
		     : "c" (msr));

	*val = ((low) | (u64)(high) << 32);
	if (err)
		err = (int)low;
	return err;
}

static int _native_write_msr(unsigned int msr, u64 *val)
{
	int err;
	u32 low = (u32)(*val), high = (u32)((*val) >> 32);

	asm volatile("1: wrmsr ; xor %[err],%[err]\n"
		     "2:\n\t"
		     _ASM_EXTABLE_TYPE_REG(1b, 2b, EX_TYPE_FAULT, %[err])
		     : [err] "=a" (err)
		     : "c" (msr), "0" (low), "d" (high)
		     : "memory");

	return err;
}

static int read_msr_native(struct test_msr *c)
{
	int i, err, tmp;

	err = _native_read_msr((u32)(c->msr.msr_num), &c->msr.val.q);

	for (i = 1; i < c->size; i++) {
		tmp = _native_read_msr((u32)(c->msr.msr_num) + i, &c->msr.val.q);

		if (err != tmp) {
			pr_buf(MSR_MULTIBYTE_ERR_INFO
			       "MSR(%x): %d(byte0) and %d(byte%d)\n",
			       c->msr.msr_num, err, tmp, i);
			return -1;
		}
	}
	return err;
}

static int write_msr_native(struct test_msr *c)
{
	int i, err, tmp;

	err = _native_write_msr((u32)(c->msr.msr_num), &c->msr.val.q);

	for (i = 1; i < c->size; i++) {
		tmp = _native_write_msr((u32)(c->msr.msr_num) + i, &c->msr.val.q);

		if (err != tmp) {
			pr_buf(MSR_MULTIBYTE_ERR_INFO
			       "MSR(%x): %d(byte0) and %d(byte%d)\n",
			       c->msr.msr_num, err, tmp, i);
			return -1;
		}
	}
	return err;
}

static int run_all_msr(void)
{
	struct test_msr *t = msr_cases;
	int i = 0;

	pr_tdx_tests("Testing MSR...\n");

	for (i = 0; i < ARRAY_SIZE(msr_cases); i++, t++) {
		if (operation & 0x8000 && strcmp(case_name, t->name) != 0)
			continue;

		if (!(spec_version & t->version)) continue;

		if (operation & 0x800) {
			pr_buf("%s %s\n", t->name, case_version(t->version));
			continue;
		}

		if (t->pre_condition)
			t->pre_condition(t);
		if (t->run_msr_rw)
			t->excp.val = t->run_msr_rw(t);

		t->ret = check_results_msr(t);
		t->ret == 1 ? stat_pass++ : stat_fail++;

		pr_buf("%d: %s_%s:\t %s\n", ++stat_total, t->name, version_name,
		       result_str(t->ret));
	}
	return 0;
}

static int check_results_cpuid(struct test_cpuid *t)
{
	if (t->regs.eax.mask == 0 && t->regs.ebx.mask == 0 &&
	    t->regs.ecx.mask == 0 && t->regs.edx.mask == 0)
		return 0;

	if (t->regs.eax.expect == (t->regs.eax.val & t->regs.eax.mask) &&
	    t->regs.ebx.expect == (t->regs.ebx.val & t->regs.ebx.mask) &&
	    t->regs.ecx.expect == (t->regs.ecx.val & t->regs.ecx.mask) &&
	    t->regs.edx.expect == (t->regs.edx.val & t->regs.edx.mask))
		return 1;

	/*
	 * Show the detail that resutls in the failure,
	 * CPUID here focus on the fixed bit, not actual cpuid val.
	 */
	pr_buf("CPUID: %s_%s\n", t->name, version_name);
	pr_buf("CPUID	 :" CPUID_DUMP_PATTERN,
	       (t->regs.eax.val & t->regs.eax.mask), (t->regs.ebx.val & t->regs.ebx.mask),
	       (t->regs.ecx.val & t->regs.ecx.mask), (t->regs.edx.val & t->regs.edx.mask));

	pr_buf("CPUID exp:" CPUID_DUMP_PATTERN,
	       t->regs.eax.expect, t->regs.ebx.expect,
	       t->regs.ecx.expect, t->regs.edx.expect);

	pr_buf("CPUID msk:" CPUID_DUMP_PATTERN,
	       t->regs.eax.mask, t->regs.ebx.mask,
	       t->regs.ecx.mask, t->regs.edx.mask);
	return -1;
}

int check_results_cr(struct test_cr *t)
{
	t->reg.val &= t->reg.mask;
	if (t->reg.val == (t->reg.mask * t->reg.expect) &&
	    t->excp.expect == t->excp.val)
		return 1;

	pr_buf(CR_ERR_INFO "output/exception %llx/%d, but expect %llx/%d\n",
	       t->reg.val, t->excp.val, t->reg.expect, t->excp.expect);
	return -1;
}

static int run_all_cpuid(void)
{
	struct test_cpuid *t;

	pr_tdx_tests("Testing CPUID...\n");
	list_for_each_entry(t, &cpuid_list, list) {

		if (operation & 0x8000 && strcmp(case_name, t->name) != 0)
			continue;

		if (!(spec_version & t->version)) continue;

		if (operation & 0x800) {
			pr_buf("%s %s\n", t->name, case_version(t->version));
			continue;
		}

		run_cpuid(t);

		t->ret = check_results_cpuid(t);
		if (t->ret == 1)
			stat_pass++;
		else if (t->ret == -1)
			stat_fail++;

		pr_buf("%d: %s_%s:\t %s\n", ++stat_total, t->name, version_name, result_str(t->ret));
	}
	return 0;
}

static u64 get_cr0(void)
{
	u64 cr0;

	asm volatile("mov %%cr0,%0\n\t" : "=r" (cr0) : __FORCE_ORDER);

	return cr0;
}

static u64 get_cr4(void)
{
	u64 cr4;

	asm volatile("mov %%cr4,%0\n\t" : "=r" (cr4) : __FORCE_ORDER);

	return cr4;
}

int __no_profile _native_write_cr0(u64 val)
{
	int err;

	asm volatile("1: mov %1,%%cr0; xor %[err],%[err]\n"
		     "2:\n\t"
		     _ASM_EXTABLE_TYPE_REG(1b, 2b, EX_TYPE_FAULT, %[err])
		     : [err] "=a" (err)
		     : "r" (val)
		     : "memory");
	return err;
}

int __no_profile _native_write_cr4(u64 val)
{
	int err;

	asm volatile("1: mov %1,%%cr4; xor %[err],%[err]\n"
		     "2:\n\t"
		     _ASM_EXTABLE_TYPE_REG(1b, 2b, EX_TYPE_FAULT, %[err])
		     : [err] "=a" (err)
		     : "r" (val)
		     : "memory");
	return err;
}

static int run_all_cr(void)
{
	struct test_cr *t;
	int i = 0;

	t = cr_list;
	pr_tdx_tests("Testing Control Register...\n");

	for (i = 0; i < ARRAY_SIZE(cr_list); i++, t++) {
		if (operation & 0x8000 && strcmp(case_name, t->name) != 0)
			continue;

		if (!(spec_version & t->version)) continue;

		if (operation & 0x800) {
			pr_buf("%s %s\n", t->name, case_version(t->version));
			continue;
		}

		if (t->run_cr_get)
			t->reg.val = t->run_cr_get();

		if (t->run_cr_set) {
			if (t->pre_condition) {
				if (t->pre_condition(t) != 0) {
					pr_buf("%d: %s:\t %s\n",
					       ++stat_total, t->name, "SKIP");
					continue;
				}
			}

			t->excp.val = t->run_cr_set(t->reg.mask);
		}

		t->ret = check_results_cr(t);
		t->ret == 1 ? stat_pass++ : stat_fail++;

		pr_buf("%d: %s_%s:\t %s\n", ++stat_total, t->name, version_name,
		       result_str(t->ret));
	}
	return 0;
}

static ssize_t
tdx_tests_proc_read(struct file *file, char __user *buffer,
		    size_t count, loff_t *ppos)
{
	return simple_read_from_buffer(buffer, count, ppos, buf_ret, cnt_log);
}

static ssize_t
tdx_tests_proc_write(struct file *file,
		     const char __user *buffer,
		     size_t count, loff_t *f_pos)
{
	char *str_input;
	str_input = kzalloc((count + 1), GFP_KERNEL);

	if (!str_input)
		return -ENOMEM;

	if (copy_from_user(str_input, buffer, count)) {
		kfree(str_input);
		return -EFAULT;
	}

	if (*(str_input + strlen(str_input) - 1) == '\n')
		*(str_input + strlen(str_input) - 1) = '\0';

	parse_input(str_input);

	if (strstr(case_name, "cpuid"))
		operation |= OPMASK_CPUID;
	else if (strstr(case_name, "cr"))
		operation |= OPMASK_CR;
	else if (strstr(case_name, "msr"))
		operation |= OPMASK_MSR;
	else if (strstr(case_name, "all"))
		operation |= OPMASK_CPUID | OPMASK_CR | OPMASK_MSR;
	else if (strstr(case_name, "list"))
		operation |= OPMASK_DUMP | OPMASK_CPUID | OPMASK_CR | OPMASK_MSR;
	else
		operation |= OPMASK_SINGLE | OPMASK_CPUID | OPMASK_CR | OPMASK_MSR;

	cnt_log = 0;
	stat_total = 0;
	stat_pass = 0;
	stat_fail = 0;

	memset(buf_ret, 0, SIZE_BUF);

	if (operation & OPMASK_CPUID)
		run_all_cpuid();
	if (operation & OPMASK_CR)
		run_all_cr();
	if (operation & OPMASK_MSR)
		run_all_msr();

	if (!(operation & OPMASK_DUMP))
		pr_buf("Total:%d, PASS:%d, FAIL:%d, SKIP:%d\n",
			   stat_total, stat_pass, stat_fail,
			   stat_total - stat_pass - stat_fail);

	kfree(str_input);
	operation = 0;
	return count;
}

const struct file_operations data_file_fops = {
	.owner = THIS_MODULE,
	.write = tdx_tests_proc_write,
	.read = tdx_tests_proc_read,
};

static int __init tdx_tests_init(void)
{
	d_tdx = debugfs_create_dir("tdx", NULL);
	if (!d_tdx)
		return -ENOENT;

	f_tdx_tests = debugfs_create_file(PROCFS_NAME, 0644, d_tdx, NULL,
					  &data_file_fops);

	if (!f_tdx_tests) {
		debugfs_remove_recursive(d_tdx);
		return -ENOENT;
	}

	buf_ret = kzalloc(SIZE_BUF, GFP_KERNEL);
	if (!buf_ret)
		return -ENOMEM;

	initial_cpuid();

	cur_cr0 = get_cr0();
	cur_cr4 = get_cr4();
	pr_buf("cur_cr0: %016llx, cur_cr4: %016llx\n", cur_cr0, cur_cr4);

	return 0;
}

static void __exit tdx_tests_exit(void)
{
	struct test_cpuid *t, *tmp;

	list_for_each_entry_safe(t, tmp, &cpuid_list, list) {
		list_del(&t->list);
		kfree(t);
	}
	kfree(buf_ret);
	debugfs_remove_recursive(d_tdx);
}

module_init(tdx_tests_init);
module_exit(tdx_tests_exit);
MODULE_LICENSE("GPL");
