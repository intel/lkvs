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

/* 3. Backward-Compatible -- when #VE reduction is not enabled: TD_CTLS.REDUCE_VE is 0. */
//	/* CPUID(0xc) Reserved */
	EXP_CPUID_BYTE_CTL(0xc, 0, eax, 0, VER1_5, 0, 0); //trigger #VE
}
#endif
