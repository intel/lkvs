#define AUTOGEN_CPUID
void initial_cpuid(void) {
	EXP_CPUID_BYTE(0x0, 0x0, eax, 0x21, VER1_0);	//MaxIndex
	EXP_CPUID_BYTE(0x0, 0x0, eax, 0x23, VER1_5);	//MaxIndex
	EXP_CPUID_BYTE(0x0, 0x0, ebx, 0x756e6547, VER1_5);	//Genu
	EXP_CPUID_BYTE(0x0, 0x0, ecx, 0x6c65746e, VER1_5);	//ntel
	EXP_CPUID_BYTE(0x0, 0x0, edx, 0x49656e69, VER1_5);	//ineI

	// Leaf 0x0
	EXP_CPUID_RES_BITS(0x1, 0x0, eax, 14, 15, VER1_0 | VER1_5);	//Reserved_15_14
	EXP_CPUID_RES_BITS(0x1, 0x0, eax, 28, 31, VER1_0 | VER1_5);	//Reserved_31_28
	EXP_CPUID_RES_BITS(0x1, 0x0, ebx, 0, 7, VER1_5);	//Brand Index
	EXP_CPUID_RES_BITS(0x1, 0x0, ebx, 8, 15, VER1_0 | VER1_5);	//CLFLUSH Line Size
	EXP_CPUID_BIT(0x1, 0x0, ecx, 0, 0x1, VER1_5);	//SSE3
	EXP_CPUID_BIT(0x1, 0x0, ecx, 1, 0x1, VER1_5);	//PCLMULQDQ
	EXP_CPUID_BIT(0x1, 0x0, ecx, 2, 0x1, VER1_5);	//DTES64
	EXP_CPUID_BIT(0x1, 0x0, ecx, 4, 0x1, VER1_5);	//DS-CPL
	EXP_CPUID_BIT(0x1, 0x0, ecx, 5, 0x0, VER1_0 | VER1_5);	//VMX
	EXP_CPUID_BIT(0x1, 0x0, ecx, 6, 0x0, VER1_0 | VER1_5);	//SMX
	EXP_CPUID_BIT(0x1, 0x0, ecx, 9, 0x1, VER1_5);	//SSSE3
	EXP_CPUID_BIT(0x1, 0x0, ecx, 13, 0x1, VER1_0 | VER1_5);	//CMPXCHG16B
	EXP_CPUID_BIT(0x1, 0x0, ecx, 15, 0x1, VER1_0 | VER1_5);	//PDCM
	EXP_CPUID_BIT(0x1, 0x0, ecx, 16, 0x0, VER1_0 | VER1_5);	//Reserved_16
	EXP_CPUID_BIT(0x1, 0x0, ecx, 17, 0x1, VER1_5);	//PCID
	EXP_CPUID_BIT(0x1, 0x0, ecx, 19, 0x1, VER1_5);	//SSE4_1
	EXP_CPUID_BIT(0x1, 0x0, ecx, 20, 0x1, VER1_5);	//SSE4_2
	EXP_CPUID_BIT(0x1, 0x0, ecx, 21, 0x1, VER1_0 | VER1_5);	//x2APIC
	EXP_CPUID_BIT(0x1, 0x0, ecx, 22, 0x1, VER1_5);	//MOVBE
	EXP_CPUID_BIT(0x1, 0x0, ecx, 23, 0x1, VER1_5);	//POPCNT
	EXP_CPUID_BIT(0x1, 0x0, ecx, 25, 0x1, VER1_0 | VER1_5);	//AESNI
	EXP_CPUID_BIT(0x1, 0x0, ecx, 26, 0x1, VER1_0 | VER1_5);	//XSAVE
	EXP_CPUID_BIT(0x1, 0x0, ecx, 30, 0x1, VER1_0 | VER1_5);	//RDRAND
	EXP_CPUID_BIT(0x1, 0x0, ecx, 31, 0x1, VER1_0 | VER1_5);	//Reserved_31
	EXP_CPUID_BIT(0x1, 0x0, edx, 0, 0x1, VER1_5);	//FPU
	EXP_CPUID_BIT(0x1, 0x0, edx, 1, 0x1, VER1_5);	//VME
	EXP_CPUID_BIT(0x1, 0x0, edx, 2, 0x1, VER1_5);	//DE
	EXP_CPUID_BIT(0x1, 0x0, edx, 3, 0x1, VER1_5);	//PSE
	EXP_CPUID_BIT(0x1, 0x0, edx, 4, 0x1, VER1_5);	//TSC
	EXP_CPUID_BIT(0x1, 0x0, edx, 5, 0x1, VER1_0 | VER1_5);	//MSR
	EXP_CPUID_BIT(0x1, 0x0, edx, 6, 0x1, VER1_0 | VER1_5);	//PAE
	EXP_CPUID_BIT(0x1, 0x0, edx, 7, 0x1, VER1_0 | VER1_5);	//MCE
	EXP_CPUID_BIT(0x1, 0x0, edx, 8, 0x1, VER1_5);	//CX8
	EXP_CPUID_BIT(0x1, 0x0, edx, 9, 0x1, VER1_0 | VER1_5);	//APIC
	EXP_CPUID_BIT(0x1, 0x0, edx, 10, 0x0, VER1_0 | VER1_5);	//Reserved_10
	EXP_CPUID_BIT(0x1, 0x0, edx, 11, 0x1, VER1_5);	//SEP
	EXP_CPUID_BIT(0x1, 0x0, edx, 12, 0x1, VER1_0 | VER1_5);	//MTRR
	EXP_CPUID_BIT(0x1, 0x0, edx, 13, 0x1, VER1_5);	//PGE
	EXP_CPUID_BIT(0x1, 0x0, edx, 14, 0x1, VER1_0 | VER1_5);	//MCA
	EXP_CPUID_BIT(0x1, 0x0, edx, 15, 0x1, VER1_5);	//CMOV
	EXP_CPUID_BIT(0x1, 0x0, edx, 16, 0x1, VER1_5);	//PAT
	EXP_CPUID_BIT(0x1, 0x0, edx, 17, 0x0, VER1_5);	//PSE-36
	EXP_CPUID_BIT(0x1, 0x0, edx, 19, 0x1, VER1_0 | VER1_5);	//CLFSH
	EXP_CPUID_BIT(0x1, 0x0, edx, 20, 0x0, VER1_0 | VER1_5);	//Reserved_20
	EXP_CPUID_BIT(0x1, 0x0, edx, 21, 0x1, VER1_0 | VER1_5);	//DS
	EXP_CPUID_BIT(0x1, 0x0, edx, 23, 0x1, VER1_5);	//MMX
	EXP_CPUID_BIT(0x1, 0x0, edx, 24, 0x1, VER1_5);	//FXSR
	EXP_CPUID_BIT(0x1, 0x0, edx, 25, 0x1, VER1_5);	//SSE
	EXP_CPUID_BIT(0x1, 0x0, edx, 26, 0x1, VER1_5);	//SSE2
	EXP_CPUID_BIT(0x1, 0x0, edx, 30, 0x0, VER1_0 | VER1_5);	//Reserved_30

	// Leaf 0x1
	EXP_CPUID_BYTE(0x3, 0x0, eax, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x3, 0x0, ebx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x3, 0x0, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x3, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x3
	EXP_CPUID_RES_BITS(0x4, 0x0, eax, 10, 13, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x4, 0x0, ebx, 0, 11, VER1_5);	//L
	EXP_CPUID_BIT(0x4, 0x0, edx, 2, 0x0, VER1_5);	//Reserved

	// Leaf 0x4 / Sub-Leaf 0x0
	EXP_CPUID_RES_BITS(0x4, 0x1, eax, 10, 13, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x4, 0x1, ebx, 0, 11, VER1_5);	//L
	EXP_CPUID_BIT(0x4, 0x1, edx, 2, 0x0, VER1_5);	//Reserved

	// Leaf 0x4 / Sub-Leaf 0x1
	EXP_CPUID_RES_BITS(0x4, 0x2, eax, 10, 13, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x4, 0x2, ebx, 0, 11, VER1_5);	//L
	EXP_CPUID_BIT(0x4, 0x2, edx, 2, 0x0, VER1_5);	//Reserved

	// Leaf 0x4 / Sub-Leaf 0x2
	EXP_CPUID_RES_BITS(0x4, 0x3, eax, 10, 13, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x4, 0x3, ebx, 0, 11, VER1_5);	//L
	EXP_CPUID_RES_BITS(0x4, 0x3, edx, 3, 31, VER1_5);	//Reserved

	// Leaf 0x4 / Sub-Leaf 0x3
	EXP_CPUID_RES_BITS(0x4, 0x4, eax, 0, 4, VER1_0 | VER1_5);	//Type
	EXP_CPUID_RES_BITS(0x4, 0x4, eax, 5, 7, VER1_0 | VER1_5);	//Level
	EXP_CPUID_BIT(0x4, 0x4, eax, 8, 0x0, VER1_0 | VER1_5);	//Self Initializing
	EXP_CPUID_BIT(0x4, 0x4, eax, 9, 0x0, VER1_0 | VER1_5);	//Fully Associative
	EXP_CPUID_RES_BITS(0x4, 0x4, eax, 10, 13, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x4, 0x4, eax, 14, 25, VER1_0 | VER1_5);	//Addressable IDs Sharing this Cache
	EXP_CPUID_RES_BITS(0x4, 0x4, eax, 26, 31, VER1_0 | VER1_5);	//Addressable IDs for Cores in Package
	EXP_CPUID_RES_BITS(0x4, 0x4, ebx, 0, 11, VER1_0 | VER1_5);	//L
	EXP_CPUID_RES_BITS(0x4, 0x4, ebx, 12, 21, VER1_0 | VER1_5);	//P
	EXP_CPUID_RES_BITS(0x4, 0x4, ebx, 22, 31, VER1_0 | VER1_5);	//W
	EXP_CPUID_BYTE(0x4, 0x4, ecx, 0x0, VER1_0 | VER1_5);	//Number of Sets
	EXP_CPUID_BIT(0x4, 0x4, edx, 0, 0x0, VER1_0 | VER1_5);	//WBINVD
	EXP_CPUID_BIT(0x4, 0x4, edx, 1, 0x0, VER1_0 | VER1_5);	//Cache Inclusiveness
	EXP_CPUID_BIT(0x4, 0x4, edx, 2, 0x0, VER1_0 | VER1_5);	//Complex Cache Indexing
	EXP_CPUID_RES_BITS(0x4, 0x4, edx, 3, 31, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x4 / Sub-Leaf 0x4
	EXP_CPUID_BYTE(0x7, 0x0, eax, 0x1, VER1_0);	//Max Sub-Leaves
	EXP_CPUID_BYTE(0x7, 0x0, eax, 0x2, VER1_5);	//Max Sub-Leaves
	EXP_CPUID_BIT(0x7, 0x0, ebx, 0, 0x1, VER1_0 | VER1_5);	//FSGSBASE
	EXP_CPUID_BIT(0x7, 0x0, ebx, 1, 0x0, VER1_0 | VER1_5);	//IA32_TSC_ADJUST
	EXP_CPUID_BIT(0x7, 0x0, ebx, 2, 0x0, VER1_0 | VER1_5);	//SGX
	EXP_CPUID_BIT(0x7, 0x0, ebx, 6, 0x1, VER1_5);	//FDP_EXCPTN_ONLY
	EXP_CPUID_BIT(0x7, 0x0, ebx, 7, 0x1, VER1_5);	//SMEP
	EXP_CPUID_BIT(0x7, 0x0, ebx, 10, 0x1, VER1_5);	//INVPCID
	EXP_CPUID_BIT(0x7, 0x0, ebx, 13, 0x1, VER1_5);	//FCS/FDS Deprecation
	EXP_CPUID_BIT(0x7, 0x0, ebx, 14, 0x0, VER1_0 | VER1_5);	//MPX
	EXP_CPUID_BIT(0x7, 0x0, ebx, 18, 0x1, VER1_0 | VER1_5);	//RDSEED
	EXP_CPUID_BIT(0x7, 0x0, ebx, 20, 0x1, VER1_0 | VER1_5);	//SMAP/CLAC/STAC
	EXP_CPUID_BIT(0x7, 0x0, ebx, 22, 0x0, VER1_0 | VER1_5);	//PCOMMIT
	EXP_CPUID_BIT(0x7, 0x0, ebx, 23, 0x1, VER1_0 | VER1_5);	//CLFLUSHOPT
	EXP_CPUID_BIT(0x7, 0x0, ebx, 24, 0x1, VER1_0 | VER1_5);	//CLWB
	EXP_CPUID_BIT(0x7, 0x0, ebx, 29, 0x1, VER1_0 | VER1_5);	//SHA
	EXP_CPUID_BIT(0x7, 0x0, ecx, 15, 0x0, VER1_0 | VER1_5);	//FZM
	EXP_CPUID_RES_BITS(0x7, 0x0, ecx, 17, 21, VER1_0 | VER1_5);	//MAWAU for MPX
	EXP_CPUID_BIT(0x7, 0x0, ecx, 24, 0x1, VER1_0 | VER1_5);	//BUSLOCK
	EXP_CPUID_BIT(0x7, 0x0, ecx, 26, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x0, ecx, 27, 0x1, VER1_5);	//MOVDIRI
	EXP_CPUID_BIT(0x7, 0x0, ecx, 28, 0x1, VER1_0 | VER1_5);	//MOVDIR64B
	EXP_CPUID_BIT(0x7, 0x0, ecx, 29, 0x0, VER1_0 | VER1_5);	//ENQCMD
	EXP_CPUID_BIT(0x7, 0x0, ecx, 30, 0x0, VER1_0 | VER1_5);	//SGX_LC
	EXP_CPUID_BIT(0x7, 0x0, edx, 0, 0x0, VER1_0 | VER1_5);	//Reserved_0
	EXP_CPUID_BIT(0x7, 0x0, edx, 1, 0x0, VER1_0 | VER1_5);	//Reserved_1
	EXP_CPUID_BIT(0x7, 0x0, edx, 6, 0x0, VER1_0 | VER1_5);	//Reserved_6
	EXP_CPUID_BIT(0x7, 0x0, edx, 7, 0x0, VER1_0 | VER1_5);	//Reserved_7
	EXP_CPUID_BIT(0x7, 0x0, edx, 9, 0x0, VER1_0 | VER1_5);	//Reserved_9
	EXP_CPUID_BIT(0x7, 0x0, edx, 10, 0x1, VER1_5);	//MD_CLEAR supported
	EXP_CPUID_BIT(0x7, 0x0, edx, 11, 0x0, VER1_0 | VER1_5);	//Reserved_11
	EXP_CPUID_BIT(0x7, 0x0, edx, 12, 0x0, VER1_0 | VER1_5);	//Reserved_12
	EXP_CPUID_BIT(0x7, 0x0, edx, 13, 0x0, VER1_0 | VER1_5);	//Reserved_13
	EXP_CPUID_BIT(0x7, 0x0, edx, 15, 0x0, VER1_5);	//Hybrid Part
	EXP_CPUID_BIT(0x7, 0x0, edx, 17, 0x0, VER1_0 | VER1_5);	//Reserved_17
	EXP_CPUID_BIT(0x7, 0x0, edx, 21, 0x0, VER1_0 | VER1_5);	//Reserved_21
	EXP_CPUID_BIT(0x7, 0x0, edx, 26, 0x1, VER1_0 | VER1_5);	//IBRS (indirect branch restricted speculation)
	EXP_CPUID_BIT(0x7, 0x0, edx, 27, 0x1, VER1_5);	//STIBP (single thread indirect branch predictors)
	EXP_CPUID_BIT(0x7, 0x0, edx, 28, 0x1, VER1_5);	//L1D_FLUSH.  IA32_FLUSH_CMD support.
	EXP_CPUID_BIT(0x7, 0x0, edx, 29, 0x1, VER1_0 | VER1_5);	//IA32_ARCH_CAPABILITIES Support
	EXP_CPUID_BIT(0x7, 0x0, edx, 30, 0x1, VER1_0 | VER1_5);	//IA32_CORE_CAPABILITIES Present
	EXP_CPUID_BIT(0x7, 0x0, edx, 31, 0x1, VER1_0 | VER1_5);	//SSBD (Speculative Store Bypass Disable)

	// Leaf 0x7 / Sub-Leaf 0x0
	EXP_CPUID_BIT(0x7, 0x1, eax, 0, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, eax, 0, 2, VER1_0);	//Reserved_3_0
	EXP_CPUID_BIT(0x7, 0x1, eax, 1, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 2, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 3, 0x0, VER1_0 | VER1_5);	//Reserved_4
	EXP_CPUID_BIT(0x7, 0x1, eax, 6, 0x0, VER1_0);	//Reserved_6
	EXP_CPUID_BIT(0x7, 0x1, eax, 7, 0x0, VER1_0 | VER1_5);	//Reserved_7
	EXP_CPUID_BIT(0x7, 0x1, eax, 8, 0x0, VER1_0);	//Reserved_8
	EXP_CPUID_BIT(0x7, 0x1, eax, 9, 0x0, VER1_0 | VER1_5);	//Reserved_9
	EXP_CPUID_RES_BITS(0x7, 0x1, eax, 13, 16, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, eax, 13, 21, VER1_0);	//Reserved_21_13
	EXP_CPUID_BIT(0x7, 0x1, eax, 17, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 18, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 19, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 20, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 21, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, eax, 22, 0x0, VER1_0 | VER1_5);	//HRESET
	EXP_CPUID_BIT(0x7, 0x1, eax, 23, 0x0, VER1_0 | VER1_5);	//Reserved_23
	EXP_CPUID_BIT(0x7, 0x1, eax, 24, 0x0, VER1_0 | VER1_5);	//Reserved_24
	EXP_CPUID_BIT(0x7, 0x1, eax, 25, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, eax, 25, 31, VER1_0);	//Reserved_31_25
	EXP_CPUID_BIT(0x7, 0x1, eax, 27, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, eax, 28, 31, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, ebx, 0, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x7, 0x1, ebx, 0x0, VER1_0);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, ebx, 1, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, ebx, 2, 29, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, ebx, 30, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, ebx, 31, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x7, 0x1, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 0, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x7, 0x1, edx, 0x0, VER1_0);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 1, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 2, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 3, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 4, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 5, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, edx, 6, 7, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 8, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 9, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 10, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, edx, 11, 13, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 14, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, edx, 15, 16, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 17, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 18, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x1, edx, 19, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x1, edx, 20, 31, VER1_5);	//Reserved

	// Leaf 0x7 / Sub-Leaf 0x1
	EXP_CPUID_BYTE(0x7, 0x2, eax, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x7, 0x2, ebx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x7, 0x2, ecx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x7, 0x2, edx, 0, 0x1, VER1_5);	//PSFD
	EXP_CPUID_BIT(0x7, 0x2, edx, 1, 0x1, VER1_5);	//IPRED_CTRL
	EXP_CPUID_BIT(0x7, 0x2, edx, 2, 0x1, VER1_5);	//RRSBA_CTRL
	EXP_CPUID_BIT(0x7, 0x2, edx, 4, 0x1, VER1_5);	//BHI_CTRL
	EXP_CPUID_BIT(0x7, 0x2, edx, 6, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x7, 0x2, edx, 7, 31, VER1_5);	//Reserved

	// Leaf 0x7 / Sub-Leaf 0x2
	EXP_CPUID_BYTE(0x8, 0x0, eax, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x8, 0x0, ebx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x8, 0x0, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x8, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x8
	EXP_CPUID_BIT(0xa, 0x0, edx, 13, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0xa, 0x0, edx, 14, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0xa, 0x0, edx, 15, 0x1, VER1_5);	//AnyThread Deprecation
	EXP_CPUID_RES_BITS(0xa, 0x0, edx, 16, 31, VER1_5);	//Reserved

	// Leaf 0xa
	EXP_CPUID_BIT(0xd, 0x0, eax, 0, 0x1, VER1_0 | VER1_5);	//X87
	EXP_CPUID_BIT(0xd, 0x0, eax, 1, 0x1, VER1_0 | VER1_5);	//SSE
	EXP_CPUID_BIT(0xd, 0x0, eax, 3, 0x0, VER1_0 | VER1_5);	//PL_BNDREGS
	EXP_CPUID_BIT(0xd, 0x0, eax, 4, 0x0, VER1_0 | VER1_5);	//PL_BNDCFS
	EXP_CPUID_BIT(0xd, 0x0, eax, 8, 0x0, VER1_0 | VER1_5);	//Reserved_8
	EXP_CPUID_RES_BITS(0xd, 0x0, eax, 10, 16, VER1_0 | VER1_5);	//Reserved_16_10
	EXP_CPUID_RES_BITS(0xd, 0x0, eax, 19, 31, VER1_0 | VER1_5);	//Reserved_31_19
	EXP_CPUID_BYTE(0xd, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0xd / Sub-Leaf 0x0
	EXP_CPUID_BIT(0xd, 0x1, eax, 0, 0x1, VER1_0 | VER1_5);	//Supports XSAVEOPT
	EXP_CPUID_BIT(0xd, 0x1, eax, 1, 0x1, VER1_0 | VER1_5);	//Supports XSAVEC and compacted XRSTOR
	EXP_CPUID_BIT(0xd, 0x1, eax, 2, 0x1, VER1_5);	//Supports XGETBV with ECX = 1
	EXP_CPUID_BIT(0xd, 0x1, eax, 3, 0x1, VER1_0 | VER1_5);	//Supports XSAVES/XRSTORS and IA32_XSS
	EXP_CPUID_RES_BITS(0xd, 0x1, eax, 5, 31, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0xd, 0x1, ecx, 0, 7, VER1_0 | VER1_5);	//reserved_7_0
	EXP_CPUID_BIT(0xd, 0x1, ecx, 9, 0x0, VER1_0 | VER1_5);	//reserved_9
	EXP_CPUID_BIT(0xd, 0x1, ecx, 10, 0x0, VER1_0 | VER1_5);	//PASID
	EXP_CPUID_BIT(0xd, 0x1, ecx, 13, 0x0, VER1_0 | VER1_5);	//HDC
	EXP_CPUID_BIT(0xd, 0x1, ecx, 16, 0x0, VER1_0 | VER1_5);	//HWP Request
	EXP_CPUID_RES_BITS(0xd, 0x1, ecx, 17, 31, VER1_0 | VER1_5);	//Reserved_31_17
	EXP_CPUID_BYTE(0xd, 0x1, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0xd / Sub-Leaf 0x1
	EXP_CPUID_BYTE(0xd, 0x2, edx, 0x0, VER1_5);	//Reserved

	// Leaf 0xd / Sub-Leaves 0x2-0x12
	EXP_CPUID_BYTE(0xd, 0x3, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0x4, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0x5, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0x6, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0x7, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0x8, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0x9, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0xa, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0xb, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0xc, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0xd, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0xe, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0xf, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0x10, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0x11, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xd, 0x12, edx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xe, 0x0, eax, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xe, 0x0, ebx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xe, 0x0, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0xe, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0xe
	EXP_CPUID_BYTE(0x11, 0x0, eax, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x11, 0x0, ebx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x11, 0x0, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x11, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x11
	EXP_CPUID_BYTE(0x12, 0x0, eax, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x12, 0x0, ebx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x12, 0x0, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x12, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x12
	EXP_CPUID_BYTE(0x13, 0x0, eax, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x13, 0x0, ebx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x13, 0x0, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x13, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x13
	EXP_CPUID_RES_BITS(0x14, 0x0, ebx, 9, 31, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x14, 0x0, ecx, 4, 30, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x14, 0x0, edx, 0x0, VER1_5);	//Reserved

	// Leaf 0x14 / Sub-Leaf 0x0
	EXP_CPUID_RES_BITS(0x14, 0x1, eax, 3, 15, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x14, 0x1, ecx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x14, 0x1, edx, 0x0, VER1_5);	//Reserved

	// Leaf 0x14 / Sub-Leaf 0x1
	EXP_CPUID_BYTE(0x15, 0x0, eax, 0x1, VER1_0 | VER1_5);	//Denominator
	EXP_CPUID_BYTE(0x15, 0x0, ecx, 0x017D7840, VER1_0 | VER1_5);	//Nominal ART Frequency
	EXP_CPUID_BYTE(0x15, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x15
	EXP_CPUID_BIT(0x19, 0x0, eax, 3, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x19, 0x0, eax, 4, 31, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x19, 0x0, ebx, 1, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x19, 0x0, ebx, 3, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x19, 0x0, ebx, 4, 0x0, VER1_5);	//IW Key Backup Support
	EXP_CPUID_RES_BITS(0x19, 0x0, ebx, 5, 31, VER1_5);	//Reserved
	EXP_CPUID_BIT(0x19, 0x0, ecx, 0, 0x0, VER1_5);	//LOADIWKEY No Backup parameter Support
	EXP_CPUID_BIT(0x19, 0x0, ecx, 1, 0x0, VER1_0);	//Random IWKey Support
	EXP_CPUID_RES_BITS(0x19, 0x0, ecx, 2, 31, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x19, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x19
	EXP_CPUID_BYTE(0x1a, 0x0, ebx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x1a, 0x0, ecx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x1a, 0x0, edx, 0x0, VER1_5);	//Reserved

	// Leaf 0x1a
	EXP_CPUID_BYTE(0x20, 0x0, eax, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x20, 0x0, ebx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x20, 0x0, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x20, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x20
	EXP_CPUID_BYTE(0x21, 0x0, eax, 0x00000000, VER1_0 | VER1_5);	//Maximum sub-leaf
	EXP_CPUID_BYTE(0x21, 0x0, ebx, 0x65746E49, VER1_0 | VER1_5);	//“Inte”
	EXP_CPUID_BYTE(0x21, 0x0, ecx, 0x20202020, VER1_0 | VER1_5);	//“    “
	EXP_CPUID_BYTE(0x21, 0x0, edx, 0x5844546C, VER1_0 | VER1_5);	//“lTDX”

	// Leaf 0x21 / Sub-Leaf 0x0
	EXP_CPUID_BYTE(0x22, 0x0, eax, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x22, 0x0, ebx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x22, 0x0, ecx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x22, 0x0, edx, 0x0, VER1_5);	//Reserved

	// Leaf 0x22
	EXP_CPUID_RES_BITS(0x23, 0x0, eax, 4, 5, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x23, 0x0, eax, 6, 31, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x23, 0x0, ecx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x23, 0x0, edx, 0x0, VER1_5);	//Reserved

	// Leaf 0x23 / Sub-Leaf 0x0
	EXP_CPUID_BYTE(0x23, 0x1, ecx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x23, 0x1, edx, 0x0, VER1_5);	//Reserved

	// Leaf 0x23 / Sub-Leaf 0x1
	EXP_CPUID_BYTE(0x23, 0x2, eax, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x23, 0x2, ebx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x23, 0x2, ecx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x23, 0x2, edx, 0x0, VER1_5);	//Reserved

	// Leaf 0x23 / Sub-Leaf 0x2
	EXP_CPUID_BYTE(0x23, 0x3, ebx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x23, 0x3, ecx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x23, 0x3, edx, 0x0, VER1_5);	//Reserved

	// Leaf 0x23 / Sub-Leaf 0x3
	EXP_CPUID_BYTE(0x80000000, 0x0, eax, 0x80000008, VER1_5);	//MaxIndex
	EXP_CPUID_BYTE(0x80000000, 0x0, ebx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x80000000, 0x0, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x80000000, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x80000000
	EXP_CPUID_BYTE(0x80000001, 0x0, eax, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x80000001, 0x0, ebx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BIT(0x80000001, 0x0, ecx, 0, 0x1, VER1_5);	//LAHF/SAHF in 64-bit Mode
	EXP_CPUID_RES_BITS(0x80000001, 0x0, ecx, 1, 4, VER1_0 | VER1_5);	//Reserved_4_1
	EXP_CPUID_BIT(0x80000001, 0x0, ecx, 5, 0x1, VER1_5);	//LZCNT
	EXP_CPUID_RES_BITS(0x80000001, 0x0, ecx, 6, 7, VER1_0 | VER1_5);	//Reserved_7_6
	EXP_CPUID_BIT(0x80000001, 0x0, ecx, 8, 0x1, VER1_5);	//PREFETCHW
	EXP_CPUID_RES_BITS(0x80000001, 0x0, ecx, 9, 31, VER1_0 | VER1_5);	//Reserved_31_9
	EXP_CPUID_RES_BITS(0x80000001, 0x0, edx, 0, 10, VER1_0 | VER1_5);	//Reserved_10_0
	EXP_CPUID_RES_BITS(0x80000001, 0x0, edx, 12, 19, VER1_0 | VER1_5);	//Reserved_19_12
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 20, 0x1, VER1_0 | VER1_5);	//Execute Disable Bit
	EXP_CPUID_RES_BITS(0x80000001, 0x0, edx, 21, 25, VER1_0 | VER1_5);	//Reserved_25_21
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 26, 0x1, VER1_0 | VER1_5);	//1GB Pages
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 27, 0x1, VER1_0 | VER1_5);	//RDTSCP and IA32_TSC_AUX
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 28, 0x0, VER1_0 | VER1_5);	//Reserved_28
	EXP_CPUID_BIT(0x80000001, 0x0, edx, 29, 0x1, VER1_0 | VER1_5);	//Intel 64
	EXP_CPUID_RES_BITS(0x80000001, 0x0, edx, 30, 31, VER1_0 | VER1_5);	//Reserved_31_30

	// Leaf 0x80000001
	EXP_CPUID_BYTE(0x80000007, 0x0, eax, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x80000007, 0x0, ebx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x80000007, 0x0, ecx, 0x0, VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x80000007, 0x0, edx, 0, 7, VER1_5);	//Reserved_7_0
	EXP_CPUID_BIT(0x80000007, 0x0, edx, 8, 0x1, VER1_5);	//Invariant TSC
	EXP_CPUID_RES_BITS(0x80000007, 0x0, edx, 9, 31, VER1_5);	//Reserved_31_9

	// Leaf 0x80000007
	EXP_CPUID_RES_BITS(0x80000008, 0x0, eax, 0, 7, VER1_0 | VER1_5);	//Number of Physical Address Bits
	EXP_CPUID_RES_BITS(0x80000008, 0x0, eax, 16, 31, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_RES_BITS(0x80000008, 0x0, ebx, 0, 8, VER1_0 | VER1_5);	//Reserved_8_0
	EXP_CPUID_RES_BITS(0x80000008, 0x0, ebx, 10, 31, VER1_0 | VER1_5);	//Reserved_31_10
	EXP_CPUID_BYTE(0x80000008, 0x0, ecx, 0x0, VER1_0 | VER1_5);	//Reserved
	EXP_CPUID_BYTE(0x80000008, 0x0, edx, 0x0, VER1_0 | VER1_5);	//Reserved

	// Leaf 0x80000008
}
