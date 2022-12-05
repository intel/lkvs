// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

#ifndef _UTILS_H_
#define _UTILS_H_

#include <linux/perf_event.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <stdlib.h>
#include "intel-pt.h"

#define PAGESIZE 4096

#define USERMODE 1
#define KERNELMODE 2
int pt_pmu_type(void);
void init_evt_attribute(struct perf_event_attr *attr);
int seek_pck_w_lib(enum pt_packet_type pt_type, __u64 *buf_ev, long bufsize);
__u64 **create_map(int fde, long bufsize, int sn_fu_sm, int *fdi);
void del_map(__u64 **buf_ev, long bufsize, int sn_fu_sm, int fdi);
int sys_perf_event_open(struct perf_event_attr *attr, pid_t pid, int cpu,
			int group_fd, unsigned long flags);
#endif /* _UTILS_H_ */
