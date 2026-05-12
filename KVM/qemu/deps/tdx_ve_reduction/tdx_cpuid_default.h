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

/* 1. By default, TDCS.TD_CTRL.REDUCE_VE is set, TDCS.FEATURE_PARAVIRT_CTLS is all-0 */

	/* CPUID(0x1) */
	/* EST(est) */
	EXP_CPUID_BIT(0x1, 0, ecx, 7, 0x0, VER1_5);
	/* TSC_DEADLINE(tsc-deadline) */
	EXP_CPUID_BIT(0x1, 0, ecx, 24, 0x0, VER1_5);
	/* MCA(mce) */
	EXP_CPUID_BIT(0x1, 0, edx, 7, 0x0, VER1_5);
	/* MTRR(mtrr) */
	EXP_CPUID_BIT(0x1, 0, edx, 12, 0x0, VER1_5);
	/* MCA(mca) */
	EXP_CPUID_BIT(0x1, 0, edx, 14, 0x0, VER1_5);
	/* TM(acpi) */
	EXP_CPUID_BIT(0x1, 0, edx, 22, 0x0, VER1_5);

	/* CPUID(0x2) */
	EXP_CPUID_BYTE(0x2, 0, eax, 0x00feff01, VER1_5);
	EXP_CPUID_BYTE(0x2, 0, ebx, 0, VER1_5);
	EXP_CPUID_BYTE(0x2, 0, ecx, 0, VER1_5);
	EXP_CPUID_BYTE(0x2, 0, edx, 0, VER1_5);

	/* CPUID(0x6) */
	EXP_CPUID_BIT(0x6, 0, eax, 2, 0x1, VER1_5);
	EXP_CPUID_RES_BITS(0x6, 0, eax, 0, 1, VER1_5);
	EXP_CPUID_RES_BITS(0x6, 0, eax, 3, 31,  VER1_5);
	EXP_CPUID_BYTE(0x6, 0, ebx, 0x0, VER1_5);
	EXP_CPUID_BYTE(0x6, 0, ecx, 0x0, VER1_5);
	EXP_CPUID_BYTE(0x6, 0, edx, 0x0, VER1_5);


	/* CPUID(0x7) */
	/* CORE_CAPABILITIES(core-capability) */
	EXP_CPUID_BIT(0x7, 0, edx, 30, 0x0, VER1_5);
	/* RDT_M(pqm) */
	EXP_CPUID_BIT(0x7, 0, ebx, 12, 0x0, VER1_5);
	/* RDT_A(rdta) */
	EXP_CPUID_BIT(0x7, 0, ebx, 15, 0x0, VER1_5);
	/* PCONFIG(pconfig) */
	EXP_CPUID_BIT(0x7, 0, edx, 18, 0x0, VER1_5);
	/* TME(tme) */
	EXP_CPUID_BIT(0x7, 0, ecx, 13, 0x0, VER1_5);

	/* CPUID(0x9), enumerated by virtual CPUID(1).ECX[18] */
	EXP_CPUID_BIT(0x1, 0, ecx, 18, 0x0, VER1_5);
	EXP_CPUID_BYTE(0x9, 0, eax, 0x0, VER1_5);

	/* CPUID(0xc), reserved */
	EXP_CPUID_BYTE(0xc, 0, eax, 0x0, VER1_5);
	EXP_CPUID_BYTE(0xc, 0, ebx, 0x0, VER1_5);
	EXP_CPUID_BYTE(0xc, 0, ecx, 0x0, VER1_5);
	EXP_CPUID_BYTE(0xc, 0, edx, 0x0, VER1_5);

}
#endif
