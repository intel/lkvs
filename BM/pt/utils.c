// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

#include "utils.h"

#define BIT(nr)                 (1UL << (nr))
#define RTIT_CTL_DISRETC        BIT(11)
#define RTIT_CTL_TSC_EN         BIT(10)
#define PT_CTL_DISRETC RTIT_CTL_DISRETC
#ifndef PT_CTL_TSC_EN
#define PT_CTL_TSC_EN RTIT_CTL_TSC_EN
#define PT_CTL_DISRETC RTIT_CTL_DISRETC
#endif

#define PT_PMU_DIR "/sys/devices/intel_pt/"

int seek_pck_w_lib(enum pt_packet_type pt_type, __u64 *buf_ev, long bufsize)
{
	struct pt_packet_decoder *decoder;
	struct pt_config config;
	uint64_t offset;
	int r_val = -1;
	int errcode;
	struct pt_packet packet;

	memset(&config, 0, sizeof(config));
	pt_config_init(&config);
	config.begin = (uint8_t *)buf_ev;
	config.end = (uint8_t *)(buf_ev + bufsize);

	decoder = pt_pkt_alloc_decoder(&config);
	if (!decoder) {
		printf("pt_pkt_alloc_decoder is failed!\n");
		r_val = -1;
		return r_val;
	}
	errcode = pt_pkt_sync_set(decoder, 0ull);
	if (errcode < 0) {
		printf("sync error, %lld, errcode=%d", 0ull, errcode);
		r_val = -1;
		return r_val;
	}

	for (;;) {
		printf("offset = %ld\n", offset);
		errcode = pt_pkt_get_offset(decoder, &offset);
		if (errcode < 0) {
			printf("error getting offset %lu %d\r\n", offset, errcode);
				r_val = -1;
				return r_val;
		}
		errcode = pt_pkt_next(decoder, &packet, sizeof(packet));
		if (errcode < 0) {
			if (errcode == -pte_eos)
				break;
		}
		printf("packet.type = %d, pt_type=%d!\n", packet.type, pt_type);
		if (packet.type == pt_type) {
			printf("packet.type = %d, pt_type=%d!\n", packet.type, pt_type);
			printf("package is found!\n");
			r_val = 0;
			break;
		}
	}
	return r_val;
}

/*
 * Intel_pt pmu
 */
int pt_pmu_type(void)
{
	FILE *f = fopen(PT_PMU_DIR "type", "r");
	int type = -1;

	if (f) {
		if (fscanf(f, "%d", &type) != 1)
			type = -1;
		fclose(f);
	}

	if (type == -1)
		printf(f ? "PT pmu has a wtf type\n"
			: "PT pmu not found\n");

	return type;
}

/*
 * initialization event attribut
 */
void init_evt_attribute(struct perf_event_attr *attr)
{
	memset(attr, 0, sizeof(*attr));
	attr->type			= pt_pmu_type();
	attr->read_format		= PERF_FORMAT_ID | PERF_FORMAT_TOTAL_TIME_RUNNING
	 | PERF_FORMAT_TOTAL_TIME_ENABLED;
	attr->disabled			= 1;
	attr->config			= PT_CTL_TSC_EN | PT_CTL_DISRETC;
	attr->size			= sizeof(struct perf_event_attr);
	attr->exclude_kernel		= 0;
	attr->exclude_user		= 0;
	attr->mmap			= 1;
}

/*
 * mapping management
 */
__u64 **create_map(int fde, long bufsize, int sn_fu_sm, int *fdi)
{
	int pro_to;
	long p_buf_size;
	__u64 **buf_ev;
	struct perf_event_mmap_page *pc;

	buf_ev = malloc(2 * sizeof(__u64 *));
	if (!buf_ev)
		return NULL;

	/* Snapshot (0) Full (1) or Sample (2) */
	if (sn_fu_sm == 1)
		pro_to = PROT_READ | PROT_WRITE;
	else
		pro_to = PROT_READ;
	/* Perf buffer is 64 Kio -- max value */
	p_buf_size = 17 * 4096;// TBD -- 65536;
	/* sampling : itrace_sample_size should be less */
	if (sn_fu_sm == 2)
		p_buf_size = bufsize;
	buf_ev[0] = mmap(NULL, p_buf_size, PROT_READ | PROT_WRITE, MAP_SHARED, fde, 0);

	/* user page size */
	if (buf_ev[0] != MAP_FAILED && sn_fu_sm != 2) {
		pc = (struct perf_event_mmap_page *)buf_ev[0];
		pc->aux_offset = p_buf_size;
		pc->aux_size = bufsize;
		buf_ev[1] = mmap(NULL, bufsize, pro_to, MAP_SHARED, fde, p_buf_size);
	}
	return buf_ev;
}

void del_map(__u64 **buf_ev, long bufsize, int sn_fu_sm, int fdi)
{
	long p_buf_size;

	/* Perf buffer is 64 Kio -- max value */
	p_buf_size = 17 * 4096;// TBD -- 65536
	/* sampling : itrace_sample_size should be less */
	if (sn_fu_sm == 2)
		p_buf_size = bufsize;
	munmap(buf_ev[0], p_buf_size);
	if (sn_fu_sm != 2)
		munmap(buf_ev[1], bufsize);
	free(buf_ev);
}

/*
 * syscall perf event open
 */
int sys_perf_event_open(struct perf_event_attr *attr, pid_t pid, int cpu,
			int group_fd, unsigned long flags)
{
	int fd;

	fd = syscall(__NR_perf_event_open, attr, pid, cpu, group_fd, flags);
	return fd;
}
