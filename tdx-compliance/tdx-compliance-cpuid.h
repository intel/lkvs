/* SPDX-License-Identifier: GPL-2.0-only */
#include "tdx-compliance.h"

#define DEF_CPUID_TEST(_leaf, _subleaf)		\
{						\
	.name = "CPUID_" #_leaf "_" #_subleaf,	\
	.leaf = _leaf,				\
	.subleaf = _subleaf,			\
}

#define EXP_CPUID_BIT(_leaf, _subleaf, _reg, _bit_nr, _val) do {	\
	struct test_cpuid *t;						\
	int bnr = _bit_nr;						\
	t = kzalloc(sizeof(struct test_cpuid), GFP_KERNEL);		\
	t->name = "CPUID_" #_leaf "_" #_subleaf ,			\
	t->leaf = _leaf;						\
	t->subleaf = _subleaf;						\
	t->regs._reg.mask = BIT(bnr);					\
	t->regs._reg.expect = BIT(bnr) * (_val);			\
	list_add(&t->list, &cpuid_list);				\
} while (0)

#define EXP_CPUID_BYTE(_leaf, _subleaf, _reg, _val) do {		\
	struct test_cpuid *t;						\
	t = kzalloc(sizeof(struct test_cpuid), GFP_KERNEL);		\
	t->name = "CPUID_" #_leaf "_" #_subleaf,			\
	t->leaf = _leaf;						\
	t->subleaf = _subleaf;						\
	t->regs._reg.mask = 0xffffffff;				\
	t->regs._reg.expect = (_val);					\
	list_add(&t->list, &cpuid_list);				\
} while (0)

#define EXP_CPUID_RES_BITS(_leaf, _subleaf, _reg, _bit_s, _bit_e) do {	\
	int i = 0;							\
	struct test_cpuid *t;						\
	t = kzalloc(sizeof(struct test_cpuid), GFP_KERNEL);		\
	t->name = "CPUID_" #_leaf "_" #_subleaf,			\
	t->leaf = _leaf;						\
	t->subleaf = _subleaf;						\
	for (i = _bit_s; i <= (_bit_e); i++) {				\
		t->regs._reg.mask |= BIT(i);				\
	}								\
	list_add(&t->list, &cpuid_list);				\
} while (0)

void initial_cpuid(void)
{
	/* CPUID(0x0) */
	EXP_CPUID_BYTE(0x0, 0, eax, 0x00000023);	//"MaxIndex"
	EXP_CPUID_BYTE(0x0, 0, ebx, 0x756e6547);	//"Genu"
	EXP_CPUID_BYTE(0x0, 0, ecx, 0x6c65746e);	//"ntel"
	EXP_CPUID_BYTE(0x0, 0, edx, 0x49656e69);	//"ineI"

	/* CPUID(0x1).EAX */
	EXP_CPUID_RES_BITS(0x1, 0, eax, 14, 15);	//Reserved_15_14
	EXP_CPUID_RES_BITS(0x1, 0, eax, 28, 31);	//Reserved_31_28

	/* CPUID(0x1).EBX */
	EXP_CPUID_RES_BITS(0x1, 0, ebx, 0, 8);		//Brand Index
	/* CLFLUSH Line Size */
	EXP_CPUID_BIT(0x1, 0, ebx, 8, 0);
	EXP_CPUID_BIT(0x1, 0, ebx, 9, 0);
	EXP_CPUID_BIT(0x1, 0, ebx, 10, 0);
	EXP_CPUID_BIT(0x1, 0, ebx, 11, 1);
	EXP_CPUID_BIT(0x1, 0, ebx, 12, 0);
	EXP_CPUID_BIT(0x1, 0, ebx, 13, 0);
	EXP_CPUID_BIT(0x1, 0, ebx, 14, 0);
	EXP_CPUID_BIT(0x1, 0, ebx, 15, 0);

	/* CPUID(0x1).ECX */
	EXP_CPUID_BIT(0x1, 0, ecx, 0, 1);		//SSE3
	EXP_CPUID_BIT(0x1, 0, ecx, 1, 1);		//PCLMULQDQ
	EXP_CPUID_BIT(0x1, 0, ecx, 2, 1);		//DTES64
	EXP_CPUID_BIT(0x1, 0, ecx, 4, 1);		//DS-CPL
	EXP_CPUID_BIT(0x1, 0, ecx, 5, 0);		//VMX
	EXP_CPUID_BIT(0x1, 0, ecx, 6, 0);		//SMX
	EXP_CPUID_BIT(0x1, 0, ecx, 9, 1);		//SSSE3
	EXP_CPUID_BIT(0x1, 0, ecx, 13, 1);		//CMPXCHG16B
	EXP_CPUID_BIT(0x1, 0, ecx, 15, 1);		//PDCM
	EXP_CPUID_BIT(0x1, 0, ecx, 16, 0);		//Reserved_16
	EXP_CPUID_BIT(0x1, 0, ecx, 17, 1);		//PCID
	EXP_CPUID_BIT(0x1, 0, ecx, 19, 1);		//SSE4_1
	EXP_CPUID_BIT(0x1, 0, ecx, 20, 1);		//SSE4_2
	EXP_CPUID_BIT(0x1, 0, ecx, 21, 1);		//x2APIC
	EXP_CPUID_BIT(0x1, 0, ecx, 22, 1);		//MOVBE
	EXP_CPUID_BIT(0x1, 0, ecx, 23, 1);		//POPCNT
	EXP_CPUID_BIT(0x1, 0, ecx, 25, 1);		//AESNI
	EXP_CPUID_BIT(0x1, 0, ecx, 26, 1);		//XSAVE
	EXP_CPUID_BIT(0x1, 0, ecx, 30, 1);		//RDRAND
	EXP_CPUID_BIT(0x1, 0, ecx, 31, 1);		//Reserved_31

	/* CPUID(0x1).EDX */
	EXP_CPUID_BIT(0x1, 0, edx, 0, 1);		//FPU
	EXP_CPUID_BIT(0x1, 0, edx, 1, 1);		//VME
	EXP_CPUID_BIT(0x1, 0, edx, 2, 1);		//DE
	EXP_CPUID_BIT(0x1, 0, edx, 3, 1);		//PSE
	EXP_CPUID_BIT(0x1, 0, edx, 4, 1);		//TSC
	EXP_CPUID_BIT(0x1, 0, edx, 5, 1);		//MSR
	EXP_CPUID_BIT(0x1, 0, edx, 6, 1);		//PAE
	EXP_CPUID_BIT(0x1, 0, edx, 7, 1);		//MCE
	EXP_CPUID_BIT(0x1, 0, edx, 8, 1);		//CX8
	EXP_CPUID_BIT(0x1, 0, edx, 9, 1);		//APIC
	EXP_CPUID_BIT(0x1, 0, edx, 10, 0);		//Reserved_10
	EXP_CPUID_BIT(0x1, 0, edx, 11, 1);		//SEP
	EXP_CPUID_BIT(0x1, 0, edx, 12, 1);		//MTRR
	EXP_CPUID_BIT(0x1, 0, edx, 13, 1);		//PGE
	EXP_CPUID_BIT(0x1, 0, edx, 14, 1);		//MCA
	EXP_CPUID_BIT(0x1, 0, edx, 15, 1);		//CMOV
	EXP_CPUID_BIT(0x1, 0, edx, 16, 1);		//PAT
	EXP_CPUID_BIT(0x1, 0, edx, 17, 0);		//PSE-36
	EXP_CPUID_BIT(0x1, 0, edx, 19, 1);		//CLFSH
	EXP_CPUID_BIT(0x1, 0, edx, 20, 0);		//Reserved_20
	EXP_CPUID_BIT(0x1, 0, edx, 21, 1);		//DS
	EXP_CPUID_BIT(0x1, 0, edx, 23, 1);		//MMX
	EXP_CPUID_BIT(0x1, 0, edx, 24, 1);		//FXSR
	EXP_CPUID_BIT(0x1, 0, edx, 25, 1);		//SSE
	EXP_CPUID_BIT(0x1, 0, edx, 26, 1);		//SSE2
	EXP_CPUID_BIT(0x1, 0, edx, 30, 0);		//Reserved_30

	/* CPUID(0x3) */
	EXP_CPUID_RES_BITS(0x3, 0, eax, 0, 31);		//Reserved_0_31
	EXP_CPUID_RES_BITS(0x3, 0, ebx, 0, 31);		//Reserved_0_31
	EXP_CPUID_RES_BITS(0x3, 0, ecx, 0, 31);		//Reserved_0_31
	EXP_CPUID_RES_BITS(0x3, 0, edx, 0, 31);		//Reserved_0_31

	/* CPUID(0x4, 0x0).EAX */
	EXP_CPUID_RES_BITS(0x4, 0, eax, 10, 13);	//Reserved_13_10

	/* CPUID(0x4, 0x0).EBX */
	/* L */
	EXP_CPUID_BIT(0x4, 0, ebx, 0, 1);
	EXP_CPUID_BIT(0x4, 0, ebx, 1, 1);
	EXP_CPUID_BIT(0x4, 0, ebx, 2, 1);
	EXP_CPUID_BIT(0x4, 0, ebx, 3, 1);
	EXP_CPUID_BIT(0x4, 0, ebx, 4, 1);
	EXP_CPUID_BIT(0x4, 0, ebx, 5, 1);
	EXP_CPUID_BIT(0x4, 0, ebx, 6, 0);
	EXP_CPUID_BIT(0x4, 0, ebx, 7, 0);
	EXP_CPUID_BIT(0x4, 0, ebx, 8, 0);
	EXP_CPUID_BIT(0x4, 0, ebx, 9, 0);
	EXP_CPUID_BIT(0x4, 0, ebx, 10, 0);
	EXP_CPUID_BIT(0x4, 0, ebx, 11, 0);

	/* CPUID(0x4, 0x0).EDX */
	EXP_CPUID_BIT(0x4, 0, edx, 2, 0);		//Reserved_2

	/* CPUID(0x4, 0x1).EAX */
	EXP_CPUID_RES_BITS(0x4, 1, eax, 10, 13);	//Reserved_13_10

	/* CPUID(0x4, 0x1).EBX */
	/* L */
	EXP_CPUID_BIT(0x4, 1, ebx, 0, 1);
	EXP_CPUID_BIT(0x4, 1, ebx, 1, 1);
	EXP_CPUID_BIT(0x4, 1, ebx, 2, 1);
	EXP_CPUID_BIT(0x4, 1, ebx, 3, 1);
	EXP_CPUID_BIT(0x4, 1, ebx, 4, 1);
	EXP_CPUID_BIT(0x4, 1, ebx, 5, 1);
	EXP_CPUID_BIT(0x4, 1, ebx, 6, 0);
	EXP_CPUID_BIT(0x4, 1, ebx, 7, 0);
	EXP_CPUID_BIT(0x4, 1, ebx, 8, 0);
	EXP_CPUID_BIT(0x4, 1, ebx, 9, 0);
	EXP_CPUID_BIT(0x4, 1, ebx, 10, 0);
	EXP_CPUID_BIT(0x4, 1, ebx, 11, 0);

	/* CPUID(0x4, 0x1).EDX */
	EXP_CPUID_BIT(0x4, 1, edx, 2, 0);		//Reserved_2

	/* CPUID(0x4, 0x2).EAX */
	EXP_CPUID_RES_BITS(0x4, 2, eax, 10, 13);	//Reserved_13_10

	/* CPUID(0x4, 0x2).EBX */
	/* L */
	EXP_CPUID_BIT(0x4, 2, ebx, 0, 1);
	EXP_CPUID_BIT(0x4, 2, ebx, 1, 1);
	EXP_CPUID_BIT(0x4, 2, ebx, 2, 1);
	EXP_CPUID_BIT(0x4, 2, ebx, 3, 1);
	EXP_CPUID_BIT(0x4, 2, ebx, 4, 1);
	EXP_CPUID_BIT(0x4, 2, ebx, 5, 1);
	EXP_CPUID_BIT(0x4, 2, ebx, 6, 0);
	EXP_CPUID_BIT(0x4, 2, ebx, 7, 0);
	EXP_CPUID_BIT(0x4, 2, ebx, 8, 0);
	EXP_CPUID_BIT(0x4, 2, ebx, 9, 0);
	EXP_CPUID_BIT(0x4, 2, ebx, 10, 0);
	EXP_CPUID_BIT(0x4, 2, ebx, 11, 0);

	/* CPUID(0x4, 0x2).EDX */
	EXP_CPUID_BIT(0x4, 2, edx, 2, 0);		//Reserved_2

	/* CPUID(0x4, 0x3).EAX */
	EXP_CPUID_RES_BITS(0x4, 3, eax, 10, 13);	//Reserved_13_10

	/* CPUID(0x4, 0x3).EBX */
	/* L */
	EXP_CPUID_BIT(0x4, 3, ebx, 0, 1);
	EXP_CPUID_BIT(0x4, 3, ebx, 1, 1);
	EXP_CPUID_BIT(0x4, 3, ebx, 2, 1);
	EXP_CPUID_BIT(0x4, 3, ebx, 3, 1);
	EXP_CPUID_BIT(0x4, 3, ebx, 4, 1);
	EXP_CPUID_BIT(0x4, 3, ebx, 5, 1);
	EXP_CPUID_BIT(0x4, 3, ebx, 6, 0);
	EXP_CPUID_BIT(0x4, 3, ebx, 7, 0);
	EXP_CPUID_BIT(0x4, 3, ebx, 8, 0);
	EXP_CPUID_BIT(0x4, 3, ebx, 9, 0);
	EXP_CPUID_BIT(0x4, 3, ebx, 10, 0);
	EXP_CPUID_BIT(0x4, 3, ebx, 11, 0);

	/* CPUID(0x4, 0x3).EDX */
	EXP_CPUID_RES_BITS(0x4, 3, edx, 3, 31);		//Reserved_31_3

	/* CPUID(0x4, 0x4).EAX */
	EXP_CPUID_RES_BITS(0x4, 4, eax, 0, 4);		//Type
	EXP_CPUID_RES_BITS(0x4, 4, eax, 5, 7);		//Level
	EXP_CPUID_BIT(0x4, 4, eax, 8, 0);		//Self Initializing
	EXP_CPUID_BIT(0x4, 4, eax, 9, 0);		//Fully Associative
	EXP_CPUID_RES_BITS(0x4, 4, eax, 10, 13);	//Reserved
	EXP_CPUID_RES_BITS(0x4, 4, eax, 14, 25);	//Addressable IDs Sharing this Cache
	EXP_CPUID_RES_BITS(0x4, 4, eax, 26, 31);	//Addressable IDs for Cores in Package

	/* CPUID(0x4, 0x4).EBX */
	EXP_CPUID_RES_BITS(0x4, 4, ebx, 0, 11);		//L
	EXP_CPUID_RES_BITS(0x4, 4, ebx, 12, 21);	//P
	EXP_CPUID_RES_BITS(0x4, 4, ebx, 22, 31);	//W

	/* CPUID(0x4, 0x4).ECX */
	EXP_CPUID_BYTE(0x4, 4, ecx, 0);			//Number of Sets

	/* CPUID(0x4, 0x4).EDX */
	EXP_CPUID_BIT(0x4, 4, edx, 0, 0);		//WBINVD
	EXP_CPUID_BIT(0x4, 4, edx, 1, 0);		//Cache Inclusiveness
	EXP_CPUID_BIT(0x4, 4, edx, 2, 0);		//Complex Cache Indexing
	EXP_CPUID_RES_BITS(0x4, 4, edx, 3, 31);		//Reserved

	/* CPUID(0x7, 0x0).EAX */
	EXP_CPUID_BYTE(0x7, 0, eax, 2);			//Max Sub-Leaves

	/* CPUID(0x7, 0x0).EBX */
	EXP_CPUID_BIT(0x7, 0x0, ebx, 0, 1);		//FSGSBASE
	EXP_CPUID_BIT(0x7, 0x0, ebx, 1, 0);		//IA32_TSC_ADJUST
	EXP_CPUID_BIT(0x7, 0x0, ebx, 2, 0);		//SGX
	EXP_CPUID_BIT(0x7, 0x0, ebx, 6, 1);		//FDP_EXCPTN_ONLY
	EXP_CPUID_BIT(0x7, 0x0, ebx, 7, 1);		//SMEP
	EXP_CPUID_BIT(0x7, 0x0, ebx, 10, 1);		//INVPCID
	EXP_CPUID_BIT(0x7, 0x0, ebx, 13, 1);		//FCS/FDS Deprecation
	EXP_CPUID_BIT(0x7, 0x0, ebx, 14, 0);		//MPX
	EXP_CPUID_BIT(0x7, 0x0, ebx, 18, 1);		//RDSEED
	EXP_CPUID_BIT(0x7, 0x0, ebx, 20, 1);		//SMAP/CLAC/STAC
	EXP_CPUID_BIT(0x7, 0x0, ebx, 22, 0);		//PCOMMIT
	EXP_CPUID_BIT(0x7, 0x0, ebx, 23, 1);		//CLFLUSHOPT
	EXP_CPUID_BIT(0x7, 0x0, ebx, 24, 1);		//CLWB
	EXP_CPUID_BIT(0x7, 0x0, ebx, 29, 1);		//SHA

	/* CPUID(0x7, 0x0).ECX */
	EXP_CPUID_BIT(0x7, 0x0, ecx, 15, 0);		//FZM
	EXP_CPUID_BIT(0x7, 0x0, ecx, 17, 0);		//MAWAU for MPX
	EXP_CPUID_BIT(0x7, 0x0, ecx, 18, 0);
	EXP_CPUID_BIT(0x7, 0x0, ecx, 19, 0);
	EXP_CPUID_BIT(0x7, 0x0, ecx, 20, 0);
	EXP_CPUID_BIT(0x7, 0x0, ecx, 21, 0);
	EXP_CPUID_BIT(0x7, 0x0, ecx, 24, 1);		//BUSLOCK
	EXP_CPUID_BIT(0x7, 0x0, ecx, 26, 0);		//Reserved
	EXP_CPUID_BIT(0x7, 0x0, ecx, 27, 1);		//MOVDIRI
	EXP_CPUID_BIT(0x7, 0x0, ecx, 28, 1);		//MOVDIR64B
	EXP_CPUID_BIT(0x7, 0x0, ecx, 29, 0);		//ENQCMD
	EXP_CPUID_BIT(0x7, 0x0, ecx, 30, 0);		//SGX_LC

	/* CPUID(0x7, 0x0).EDX */
	EXP_CPUID_RES_BITS(0x7, 0x0, edx, 0, 1);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x0, edx, 6, 7);	//Reserved
	EXP_CPUID_BIT(0x7, 0x0, edx, 9, 0);		//MCU_OPT supported
	EXP_CPUID_BIT(0x7, 0x0, edx, 10, 1);		//MD_CLEAR supported
	EXP_CPUID_RES_BITS(0x7, 0x0, edx, 11, 12);	//Reserved
	EXP_CPUID_BIT(0x7, 0x0, edx, 13, 0);		//RTM_FORCE_ABORT_SUPPORT
	EXP_CPUID_BIT(0x7, 0x0, edx, 17, 0);		//Reserved
	EXP_CPUID_BIT(0x7, 0x0, edx, 21, 0);		//Reserved
	EXP_CPUID_BIT(0x7, 0x0, edx, 26, 1);		//IBRS
	EXP_CPUID_BIT(0x7, 0x0, edx, 27, 1);		//STIBP
	EXP_CPUID_BIT(0x7, 0x0, edx, 29, 1);		//IA32_ARCH_CAPABILITIES Support
	EXP_CPUID_BIT(0x7, 0x0, edx, 30, 1);		//IA32_CORE_CAPABILITIES Present
	EXP_CPUID_BIT(0x7, 0x0, edx, 31, 1);		//SSBD(Speculative Store Bypass Disable)

	/* CPUID(0x7, 0x1).EAX */
	EXP_CPUID_RES_BITS(0x7, 0x1, eax, 0, 3);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 7, 0);		//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 9, 0);		//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, eax, 13, 21);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 22, 0);		//HRESET
	EXP_CPUID_RES_BITS(0x7, 0x1, eax, 23, 25);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, eax, 27, 31);	//Reserved

	/* CPUID(0x7, 0x1).EBX */
	EXP_CPUID_RES_BITS(0x7, 0x1, ebx, 0, 31);	//Reserved

	/* CPUID(0x7, 0x1).ECX */
	EXP_CPUID_RES_BITS(0x7, 0x1, ecx, 0, 31);	//Reserved

	/* CPUID(0x7, 0x1).EDX */
	EXP_CPUID_RES_BITS(0x7, 0x1, edx, 0, 31);	//Reserved

	/* CPUID(0x7, 0x2).EAX */
	EXP_CPUID_RES_BITS(0x7, 0x2, eax, 0, 31);	//Reserved

	/* CPUID(0x7, 0x2).EBX */
	EXP_CPUID_RES_BITS(0x7, 0x2, ebx, 0, 31);	//Reserved

	/* CPUID(0x7, 0x2).ECX */
	EXP_CPUID_RES_BITS(0x7, 0x2, ecx, 0, 31);	//Reserved

	/* CPUID(0x7, 0x2).EDX */
	EXP_CPUID_BIT(0x7, 0x2, edx, 0, 1);		//PSFD
	EXP_CPUID_BIT(0x7, 0x2, edx, 1, 1);		//IPRED_CTRL
	EXP_CPUID_BIT(0x7, 0x2, edx, 2, 1);		//RRSBA_CTRL
	EXP_CPUID_BIT(0x7, 0x2, edx, 4, 1);		//BHI_CTRL
	EXP_CPUID_RES_BITS(0x7, 0x2, edx, 6, 31);	//Reserved

	/* CPUID(0x8) */
	EXP_CPUID_RES_BITS(0x8, 0x0, eax, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x8, 0x0, ebx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x8, 0x0, ecx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x8, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0xa, 0x0).ECX */
	EXP_CPUID_RES_BITS(0xa, 0x0, ecx, 4, 31);	//Fixed Counter Support Bitmap [31:4]

	/* CPUID(0xa, 0x0).EDX */
	EXP_CPUID_RES_BITS(0xa, 0x0, edx, 13, 14);	//Reserved
	EXP_CPUID_BIT(0xa, 0x0, edx, 15, 1);		//AnyThread Deprecation
	EXP_CPUID_RES_BITS(0xa, 0x0, edx, 16, 31);	//Reserved

	/* CPUID(0xd, 0x0).EAX */
	EXP_CPUID_BIT(0xd, 0x0, eax, 0, 1);		//X87
	EXP_CPUID_BIT(0xd, 0x0, eax, 1, 1);		//SSE
	EXP_CPUID_BIT(0xd, 0x0, eax, 3, 0);		//PL_BNDREGS
	EXP_CPUID_BIT(0xd, 0x0, eax, 4, 0);		//PL_BNDCFS
	EXP_CPUID_BIT(0xd, 0x0, eax, 8, 0);		//Reserved
	EXP_CPUID_RES_BITS(0xd, 0x0, eax, 10, 16);	//Reserved
	EXP_CPUID_RES_BITS(0xd, 0x0, eax, 19, 31);	//Reserved

	/* CPUID(0xd, 0x0).EDX */
	EXP_CPUID_RES_BITS(0xd, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0xd, 0x1).EAX */
	EXP_CPUID_BIT(0xd, 0x1, eax, 0, 1);		//Supports XSAVEOPT
	EXP_CPUID_BIT(0xd, 0x1, eax, 1, 1);		//Supports XSAVEC and compacted XRSTOR
	EXP_CPUID_BIT(0xd, 0x1, eax, 2, 1);		//Supports XGETBV with ECX = 1
	EXP_CPUID_BIT(0xd, 0x1, eax, 3, 1);		//Supports XSAVES/XRSTORS and IA32_XSS
	EXP_CPUID_RES_BITS(0xd, 0x1, eax, 5, 31);	//Reserved

	/* CPUID(0xd, 0x1).ECX */
	EXP_CPUID_RES_BITS(0xd, 0x1, ecx, 0, 7);	//Reserved
	EXP_CPUID_BIT(0xd, 0x1, ecx, 9, 0);		//Reserved
	EXP_CPUID_BIT(0xd, 0x1, ecx, 10, 0);		//PASID
	EXP_CPUID_BIT(0xd, 0x1, ecx, 13, 0);		//HDC
	EXP_CPUID_BIT(0xd, 0x1, ecx, 16, 0);		//HDC
	EXP_CPUID_RES_BITS(0xd, 0x1, ecx, 17, 31);	//Reserved

	/* CPUID(0xd, 0x1).EDX */
	EXP_CPUID_RES_BITS(0xd, 0x1, edx, 0, 31);	//Reserved

	/* CPUID(0xd, 0x2-0x12).EDX */
	EXP_CPUID_RES_BITS(0xd, 0x2, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x3, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x4, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x5, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x6, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x7, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x8, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x9, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0xa, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0xb, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0xc, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0xd, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0xe, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0xf, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x10, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x11, edx, 0, 31);	//Reserved_0_31
	EXP_CPUID_RES_BITS(0xd, 0x12, edx, 0, 31);	//Reserved_0_31

	/* CPUID(0xe, 0x0) */
	EXP_CPUID_RES_BITS(0xe, 0x0, eax, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0xe, 0x0, ebx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0xe, 0x0, ecx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0xe, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x11, 0x0) */
	EXP_CPUID_RES_BITS(0x11, 0x0, eax, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x11, 0x0, ebx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x11, 0x0, ecx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x11, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x12, 0x0) */
	EXP_CPUID_RES_BITS(0x12, 0x0, eax, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x12, 0x0, ebx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x12, 0x0, ecx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x12, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x13, 0x0) */
	EXP_CPUID_RES_BITS(0x13, 0x0, eax, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x13, 0x0, ebx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x13, 0x0, ecx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x13, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x15, 0x0).EAX */
	EXP_CPUID_BYTE(0x15, 0x0, eax, 0x1);		//Denominator
	/* CPUID(0x15, 0x0).ECX */
	EXP_CPUID_BYTE(0x15, 0x0, ecx, 0x017d7840);	//Nominal ART Frequency
	/* CPUID(0x15, 0x0).EDX */
	EXP_CPUID_RES_BITS(0x15, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x19, 0x0).ECX */
	EXP_CPUID_BIT(0x19, 0x0, ecx, 1, 0);		//Random IWKey Support
	EXP_CPUID_RES_BITS(0x19, 0x0, ecx, 2, 31);	//Reserved
	/* CPUID(0x19, 0x0).EDX */
	EXP_CPUID_RES_BITS(0x19, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x20, 0x0) */
	EXP_CPUID_RES_BITS(0x20, 0x0, eax, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x20, 0x0, ebx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x20, 0x0, ecx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x20, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x21, 0x0).EAX */
	EXP_CPUID_BYTE(0x21, 0x0, eax, 0x0);		//Maximum sub-leaf
	/* CPUID(0x21, 0x0).EBX */
	EXP_CPUID_BYTE(0x21, 0x0, ebx, 0x65746E49);	//"Intel"
	/* CPUID(0x21, 0x0).ECX */
	EXP_CPUID_BYTE(0x21, 0x0, ecx, 0x20202020);	//"    "
	/* CPUID(0x21, 0x0).EDX */
	EXP_CPUID_BYTE(0x21, 0x0, edx, 0x5844546C);	//"lTDX"

	/* CPUID(0x22, 0x0) */
	EXP_CPUID_RES_BITS(0x22, 0x0, eax, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x22, 0x0, ebx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x22, 0x0, ecx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x22, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x23, 0x0).ECX */
	EXP_CPUID_RES_BITS(0x23, 0x0, ecx, 0, 31);	//Reserved
	/* CPUID(0x23, 0x0).EDX */
	EXP_CPUID_RES_BITS(0x23, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x23, 0x1).EBX */
	EXP_CPUID_RES_BITS(0x23, 0x1, ebx, 0, 3);	//Fixed counter bitmap
	EXP_CPUID_RES_BITS(0x23, 0x1, ebx, 4, 31);	//Fixed counter bitmap
	/* CPUID(0x23, 0x1).ECX */
	EXP_CPUID_RES_BITS(0x23, 0x1, ecx, 0, 31);	//Reserved
	/* CPUID(0x23, 0x1).EDX */
	EXP_CPUID_RES_BITS(0x23, 0x1, edx, 0, 31);	//Reserved

	/* CPUID(0x23, 0x2) */
	EXP_CPUID_RES_BITS(0x23, 0x2, eax, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x23, 0x2, ebx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x23, 0x2, ecx, 0, 31);	//Reserved
	EXP_CPUID_RES_BITS(0x23, 0x2, edx, 0, 31);	//Reserved

	/* CPUID(0x23, 0x3).EBX */
	EXP_CPUID_RES_BITS(0x23, 0x3, ebx, 0, 31);	//Reserved
	/* CPUID(0x23, 0x3).ECX */
	EXP_CPUID_RES_BITS(0x23, 0x3, ecx, 0, 31);	//Reserved
	/* CPUID(0x23, 0x3).EDX */
	EXP_CPUID_RES_BITS(0x23, 0x3, edx, 0, 31);	//Reserved

	/* CPUID(0x80000000).EAX */
	EXP_CPUID_BYTE(0x80000000, 0x0, eax, 0x80000008);	//MaxIndex
	/* CPUID(0x80000000).EBX */
	EXP_CPUID_RES_BITS(0x80000000, 0x0, ebx, 0, 31);	//Reserved
	/* CPUID(0x80000000).ECX */
	EXP_CPUID_RES_BITS(0x80000000, 0x0, ecx, 0, 31);	//Reserved
	/* CPUID(0x80000000).EDX */
	EXP_CPUID_RES_BITS(0x80000000, 0x0, edx, 0, 31);	//Reserved

	/* CPUID(0x80000001).EAX */
	EXP_CPUID_RES_BITS(0x80000001, 0x0, eax, 0, 31);	//Reserved
	/* CPUID(0x80000001).EBX */
	EXP_CPUID_RES_BITS(0x80000001, 0x0, ebx, 0, 31);	//Reserved
	/* CPUID(0x80000001).ECX */
	EXP_CPUID_BIT(0x80000001, 0x0, ecx, 0, 1);		//LAHF/SAHF in 64-bit Mode
	EXP_CPUID_RES_BITS(0x80000001, 0x0, ecx, 1, 4);		//Reserved
	EXP_CPUID_BIT(0x80000001, 0x0, ecx, 5, 1);		//LZCNT
	EXP_CPUID_RES_BITS(0x80000001, 0x0, ecx, 6, 7);		//Reserved
	EXP_CPUID_BIT(0x80000001, 0x0, ecx, 8, 1);		//PREFETCHW
	EXP_CPUID_RES_BITS(0x80000001, 0x0, ecx, 9, 31);	//Reserved

	/* CPUID(0x80000001).EDX */
	EXP_CPUID_RES_BITS(0x80000001, 0x0, edx, 0, 10);	//Reserved
	EXP_CPUID_RES_BITS(0x80000001, 0x0, edx, 12, 19);	//Reserved
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 20, 1);		//Execute Dis Bit
	EXP_CPUID_RES_BITS(0x80000001, 0x0, edx, 21, 25);	//Reserved
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 26, 1);		//1GB Pages
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 27, 1);		//RDTSCP
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 28, 0);		//Reserved
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 29, 1);		//Intel 64
	EXP_CPUID_RES_BITS(0x80000001, 0x0, edx, 30, 31);	//Reserved

	/* CPUID(0x80000007).EAX */
	EXP_CPUID_RES_BITS(0x80000007, 0x0, eax, 0, 31);	//Reserved
	/* CPUID(0x80000007).EBX */
	EXP_CPUID_RES_BITS(0x80000007, 0x0, ebx, 0, 31);	//Reserved
	/* CPUID(0x80000007).ECX */
	EXP_CPUID_RES_BITS(0x80000007, 0x0, ecx, 0, 31);	//Reserved
	/* CPUID(0x80000007).EDX */
	EXP_CPUID_RES_BITS(0x80000007, 0x0, edx, 0, 7);		//Reserved_7_0
	EXP_CPUID_BIT(0x80000007, 0x0, edx, 8, 1);		//Invariant TSC
	EXP_CPUID_RES_BITS(0x80000007, 0x0, edx, 9, 31);	//Reserved_31_9

	/* CPUID(0x80000008).EAX */
	/* CPUID.EAX[0:7] Number of Physical Address Bits */
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 0, 0);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 1, 0);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 2, 1);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 3, 0);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 4, 1);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 5, 1);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 6, 0);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 7, 0);
	/* CPUID.EAX[8:15] Number of Linear Address Bits */
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 8, 1);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 9, 0);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 10, 0);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 11, 1);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 12, 1);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 13, 1);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 14, 0);
	EXP_CPUID_BIT(0x80000008, 0x0, eax, 15, 0);
	EXP_CPUID_RES_BITS(0x80000008, 0x0, eax, 16, 31);	//Reserved

	/* CPUID(0x80000008).EBX */
	EXP_CPUID_RES_BITS(0x80000008, 0x0, ebx, 0, 8);		//Reserved
	EXP_CPUID_RES_BITS(0x80000008, 0x0, ebx, 10, 31);	//Reserved

	/* CPUID(0x80000008).ECX */
	EXP_CPUID_RES_BITS(0x80000008, 0x0, ecx, 0, 31);	//Reserved

	/* CPUID(0x80000008).EDX */
	EXP_CPUID_RES_BITS(0x80000008, 0x0, edx, 0, 31);	//Reserved
}
