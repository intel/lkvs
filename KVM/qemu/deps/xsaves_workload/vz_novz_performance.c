// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Intel Corporation
/*
 * XSAVES workload payload: tight SSE loop with an optional leading
 * vzeroupper. Build twice from the same source, once with -DVZ and once
 * without, so the test harness can compare wall-clock time between the
 * two variants under KVM.
 */

int main(void)
{
	unsigned long long i;

#ifdef VZ
	asm("vzeroupper");
#endif
	for (i = 0; i < 0xc0000000; i++) {
		asm("movups (%rsp), %xmm2");
		asm("addps %xmm1, %xmm2");
	}
	return 0;
}
