/* SPDX-License-Identifier: GPL-2.0-only */
#include "tdx-compliance.h"

#define DEF_CPUID_TEST(_leaf, _subleaf)		\
{						\
	.name = "CPUID_" #_leaf "_" #_subleaf,	\
	.leaf = _leaf,				\
	.subleaf = _subleaf,			\
}

#define EXP_CPUID_BIT_CTL(_leaf, _subleaf, _reg, _bit_nr, _val, _vsn, _td_ctl, _pv_ctl) do {\
	struct test_cpuid *t;						\
	int bnr = _bit_nr;						\
	t = kzalloc_obj(struct test_cpuid, GFP_KERNEL);		\
	t->name = "CPUID(" #_leaf "," #_subleaf ")." #_reg "[" #_bit_nr "]";\
	t->version = (_vsn);						\
	t->leaf = (_leaf);						\
	t->subleaf = (_subleaf);					\
	t->regs._reg.mask = BIT(bnr);					\
	t->regs._reg.expect = BIT(bnr) * (_val);			\
	t->tdcs_td_ctl = (_td_ctl);					\
	t->tdcs_feature_pv_ctl = (_pv_ctl);				\
	list_add_tail(&t->list, &cpuid_list);				\
} while (0)

#define EXP_CPUID_BIT(_leaf, _subleaf, _reg, _bit_nr, _val, _vsn)	\
	EXP_CPUID_BIT_CTL(_leaf, _subleaf, _reg, _bit_nr, _val, _vsn, 0xbad, 0xbad)

#define EXP_CPUID_BYTE_CTL(_leaf, _subleaf, _reg, _val, _vsn, _td_ctl, _pv_ctl) do {\
	struct test_cpuid *t;						\
	t = kzalloc_obj(struct test_cpuid, GFP_KERNEL);		\
	t->name = "CPUID(" #_leaf "," #_subleaf ")." #_reg;		\
	t->version = (_vsn);						\
	t->leaf = (_leaf);						\
	t->subleaf = (_subleaf);					\
	t->regs._reg.mask = 0xffffffff;					\
	t->regs._reg.expect = (_val);					\
	t->tdcs_td_ctl = (_td_ctl);					\
	t->tdcs_feature_pv_ctl = (_pv_ctl);				\
	list_add_tail(&t->list, &cpuid_list);				\
} while (0)

#define EXP_CPUID_BYTE(_leaf, _subleaf, _reg, _val, _vsn)		\
	EXP_CPUID_BYTE_CTL(_leaf, _subleaf, _reg, _val, _vsn, 0xbad, 0xbad)
#define EXP_CPUID_RES_BITS_CTL(_leaf, _subleaf, _reg, _bit_s, _bit_e, _vsn, _td_ctl, _pv_ctl) do {\
	int i = 0;								\
	struct test_cpuid *t;							\
	t = kzalloc_obj(struct test_cpuid, GFP_KERNEL);			\
	t->name = "CPUID(" #_leaf "," #_subleaf ")." #_reg "[" #_bit_e ":" #_bit_s "]";\
	t->version = (_vsn);							\
	t->leaf = (_leaf);							\
	t->subleaf = (_subleaf);						\
	for (i = _bit_s; i <= (_bit_e); i++) {					\
		t->regs._reg.mask |= BIT(i);					\
	}									\
	t->tdcs_td_ctl = (_td_ctl);						\
	t->tdcs_feature_pv_ctl = (_pv_ctl);					\
	list_add_tail(&t->list, &cpuid_list);					\
} while (0)

#define EXP_CPUID_RES_BITS(_leaf, _subleaf, _reg, _bit_s, _bit_e, _vsn) \
	EXP_CPUID_RES_BITS_CTL(_leaf, _subleaf, _reg, _bit_s, _bit_e, _vsn, 0xbad, 0xbad)

#ifdef AUTOGEN_CPUID
void initial_cpuid(void);
#else
void initial_cpuid(void)
{
/********* The following test cases are defined for #VE reduction. *********/

/*
 * There are 3 configurations in total:
 * 1. By default -- when #VE Reduction is enabled: TDCS.TD_CTRL.REDUCE_VE ==1 ,
 * TDCS.FEATURE_PARAVIRT_CTLS is all-0.
 * 2. TD_CTLS.REDUCE_VE == 1, FEATURE_PARAVIRT_CTLS == 1
 * 3. Backward-Compatible -- when #VE reduction is not enabled: TD_CTLS.REDUCE_VE is 0.
 */

/* 2. TD_CTLS.REDUCE_VE == 1, FEATURE_PARAVIRT_CTLS == 1 */
//	/* CPUID(0x1) */
//	/* EST(est) */
//	EXP_CPUID_BIT_CTL(0x1, 0, ecx, 7, 0x0, VER1_5, 8, BIT(2)); //not supported by VMM
//	/* TSC_DEADLINE(tsc-deadline) */
	EXP_CPUID_BIT_CTL(0x1, 0, ecx, 24, 0x1, VER1_5, 8, BIT(11)); //enable it by qemu
//	EXP_CPUID_BIT_CTL(0x1, 0, ecx, 24, 0x0, VER1_5, 8, BIT(11)); //disable it by qemu
//	/* MCA(mce) */
	EXP_CPUID_BIT_CTL(0x1, 0, edx, 7, 0x1, VER1_5, 8, BIT(3)); //enable it by qemu
//	EXP_CPUID_BIT_CTL(0x1, 0, edx, 7, 0x0, VER1_5, 8, BIT(3)); //disable it by qemu
//	/* MTRR(mtrr) */
	EXP_CPUID_BIT_CTL(0x1, 0, edx, 12, 0x1, VER1_5, 8, BIT(4)); //enable it by qemu
//	EXP_CPUID_BIT_CTL(0x1, 0, edx, 12, 0x0, VER1_5, 8, BIT(4)); //disable it by qemu
//	/* MCA(mca) */
	EXP_CPUID_BIT_CTL(0x1, 0, edx, 14, 0x1, VER1_5, 8, BIT(3)); //enable it by qemu
//	EXP_CPUID_BIT_CTL(0x1, 0, edx, 14, 0x0, VER1_5, 8, BIT(3)); //disable it by qemu
//	/* TM(acpi) */
//	EXP_CPUID_BIT_CTL(0x1, 0, edx, 22, 0x0, VER1_5, 8, BIT(8)); //not supported by VMM
//
//	/* CPUID(0x2) */
	EXP_CPUID_BYTE_CTL(0x2, 0, eax, 0x00feff01, VER1_5, 4, 0);
	EXP_CPUID_BYTE_CTL(0x5, 0, ebx, 0, VER1_5, 4, 0);
	EXP_CPUID_BYTE_CTL(0x2, 0, ecx, 0, VER1_5, 4, 0);
	EXP_CPUID_BYTE_CTL(0x2, 0, edx, 0, VER1_5, 4, 0);
//	/* CPUID(0x7) */
//	/* CORE_CAPABILITIES(core-capability) */
	EXP_CPUID_BIT_CTL(0x7, 0, edx, 30, 0x1, VER1_5, 8, BIT(0)); //enable it by qemu
//	EXP_CPUID_BIT_CTL(0x7, 0, edx, 30, 0x0, VER1_5, 8, BIT(0)); //disable it by qemu
//	/* RDT_M(pqm) */
//	EXP_CPUID_BIT_CTL(0x7, 0, ebx, 12, 0x0, VER1_5, 8, BIT(7)); //not supported by qemu
//	/* RDT_A(rdta) */
//	EXP_CPUID_BIT_CTL(0x7, 0, ebx, 15, 0x0, VER1_5, 8, BIT(6)); //not supported by qemu
//	/* PCONFIG(pconfig) */
//	EXP_CPUID_BIT_CTL(0x7, 0, edx, 18, 0x0, VER1_5, 8, BIT(5)); //not supported by qemu
//	/* TME(tme) */
//	EXP_CPUID_BIT_CTL(0x7, 0, ecx, 13, 0x0, VER1_5, 8, BIT(10)); //not supported by qemu
//
//	/* CPUID(0x9), enumerated by virtual CPUID(1).ECX[18] */
//	/* DCA(dca) */
//	EXP_CPUID_BIT_CTL(0x1, 0, ecx, 18, 0x0, VER1_5, 8, BIT(1)); //not supported by VMM
//	EXP_CPUID_BYTE_CTL(0x9, 0, eax, 0x0, VER1_5, 8, BIT(1)); //virtual CPUID(1).ECX[18] == 0
//	EXP_CPUID_BYTE_CTL(0x9, 0, ebx, 0x0, VER1_5, 8, BIT(1)); //virtual CPUID(1).ECX[18] == 0
//	EXP_CPUID_BYTE_CTL(0x9, 0, ecx, 0x0, VER1_5, 8, BIT(1)); //virtual CPUID(1).ECX[18] == 0
//	EXP_CPUID_BYTE_CTL(0x9, 0, edx, 0x0, VER1_5, 8, BIT(1)); //virtual CPUID(1).ECX[18] == 0

}
#endif
