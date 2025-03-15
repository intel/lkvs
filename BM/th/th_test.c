// SPDX-License-Identifier: GPL-2.0-only

/**
 *   Copyright © Intel, 2018
 *
 *   This file is part of Intel TH tests.
 *
 *   It is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Lesser General Public License as
 *   published by the Free Software Foundation, either version 3 of the
 *   License, or (at your option) any later version.
 *
 *   It is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Lesser General Public License for more details.
 *
 *   You should have received a copy of the GNU Lesser General Public
 *   License along with it.  If not, see <http://www.gnu.org/licenses/>.
 *
 *
 * File:         th_test.c
 *
 * Description:  ioctl test for intel th
 *
 * Author(s):    Ammy Yi <ammy.yi@intel.com>
 *
 * Date:         12/11/2018
 */

#include <stdlib.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <fcntl.h>	// for open
#include <unistd.h>	// for close
#include <sys/mman.h>
#include <string.h>
#include <stdint.h>

#include "linux/stm.h"

struct intel_th_channel {
	uint64_t	Dn;
	uint64_t	DnM;
	uint64_t	DnTS;
	uint64_t	DnMTS;
	uint64_t	USER;
	uint64_t	USER_TS;
	uint32_t	FLAG;
	uint32_t	FLAG_TS;
	uint32_t	MERR;
	uint32_t	__unused;
} __packed;

static int set_policy(int fd, const char *policy)
{
	struct stp_policy_id *id;
	size_t size = sizeof(*id) + strlen(policy) + 1;
	int ret = 0;

	id = calloc(1, size);
	if (!id) {
		fprintf(stderr, "Case is failed for open device failed %m!\n");
		return 1;
	}
	id->size = size;
	id->width = 64;
	memcpy(id->id, policy, size);
	fprintf(stdout, "start to ioctl with STP_POLICY_ID_SET\n");
	ret = ioctl(fd, STP_POLICY_ID_SET, id);
	fprintf(stderr, "ioctl result : %d\n", ret);
	free(id);
	return ret;
}


static int get_policy(int fd, const char *policy)
{
	struct stp_policy_id *id;
	size_t size = sizeof(*id) + strlen(policy) + 1;
	int ret = 0;

	id = calloc(1, size);
	if (!id) {
		fprintf(stderr, "Case is failed for open device failed %m!\n");
		return 1;
	}
	id->size = size;
	id->width = 64;
	memcpy(id->id, policy, size);
	fprintf(stdout, "start to ioctl with STP_POLICY_ID_SET\n");
	ret = ioctl(fd, STP_POLICY_ID_GET, id);
	fprintf(stderr, "ioctl result : %d\n", ret);
	free(id);
	return ret;
}

int set_policy_test(void)
{
	char *dev = "/dev/0-sth";
	char *policy_name = "th_test";
	int fd = -1, ret;

	fprintf(stdout, "start to open device %s\n", dev);
	fd = open(dev, O_RDWR | O_SYNC);
	if (fd < 0) {
		fprintf(stderr, "Case is failed for open device failed %m!\n");
		return 1;
	}
	fprintf(stdout, "start to set_policy %s\n", policy_name);
	ret = set_policy(fd, policy_name);
	close(fd);
	return ret;
}

int get_policy_test(void)
{
	char *dev = "/dev/0-sth";
	char *policy_name = "th_test";
	int fd = -1, ret;

	fprintf(stdout, "start to open device %s\n", dev);
	fd = open(dev, O_RDWR | O_SYNC);
	if (fd < 0) {
		fprintf(stderr, "Case is failed for open device failed %m!\n");
		return 1;
	}
	fprintf(stdout, "start to set_policy %s\n", policy_name);
	ret = get_policy(fd, policy_name);
	close(fd);
	return ret;
}

int mmap_test(void)
{
	char *dev = "/dev/0-sth";
	char *str = "vvvvvvvvvv";
	struct intel_th_channel *base, *c;
	int fd = -1, ret, temp;
	char *policy_name = "th_test";

	fprintf(stdout, "start to open device %s\n", dev);
	fd = open(dev, O_RDWR | O_SYNC);
	if (fd < 0) {
		fprintf(stderr, "Case is failed for open code failed %m.\n");
		return 1;
	}
	ret = set_policy(fd, policy_name);
	if (ret < 0) {
		fprintf(stderr, "Case is failed for open code failed %m.\n");
		close(fd);
		return 1;
	}
	base = mmap(NULL, 4096, PROT_WRITE, MAP_SHARED, fd, 0);
	if (base == MAP_FAILED) {
		fprintf(stderr, "Case is failed for mmap failed %m.\n");
		close(fd);
		return 1;
	}
	c = base;
	for (temp = 0; temp < strlen(str); temp++)
		*(uint8_t *)&c[0].Dn = str[temp];
	munmap(base, 4096);
	close(fd);
	return 0;
}

/**
 * will set policy/get policy/trace into memory
 *
 */
int main(int argc, char *argv[])
{
	int result = 2;
	int cmd = 0;

	if (argc == 2)
		cmd = atoi(argv[1]);
	switch (cmd) {
	case 1:
		result = set_policy_test();
		break;
	case 2:
		result = get_policy_test();
		break;
	case 3:
		result = mmap_test();
		break;
	default:
		printf("Command is not correct!\n");
		break;
	}
	printf("CASE result = %d\n", result);
	return result;
}
