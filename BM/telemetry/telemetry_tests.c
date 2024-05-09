// SPDX-License-Identifier: GPL-2.0-or-later

/*
 * Author: Ammy Yi (ammy.yi@intel.com)
 */

/*
 * This test will check if telemetry is working.
 */

#include <stdlib.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>

#define SAMPLE_SIZE 8

void print_bin(uint8_t n)
{
	uint8_t l = sizeof(n) * 8;
	int i;

	for (i = l - 1; i >= 0; i--)
		printf("%d", (n & (1 << i))  != 0);
}

int telem_test(char *telem_dev, int size, int idx)
{
	int offset = idx * getpagesize();
	char *ptr;
	int fd;
	int i = 0;

	fd = open(telem_dev, O_RDONLY);
	if (fd == -1) {
		printf("open telem device failure with %s!\n", telem_dev);
		return -1;
	}
	ptr = (char *)malloc(SAMPLE_SIZE * size * sizeof(char));
	read(fd, ptr, SAMPLE_SIZE * size);
	for (i = size; i >= 0; i--) {
		printf("telem value 0x%x= ", i);
		print_bin(ptr[i]);
		printf("\n");
	}
	free(ptr);
	close(fd);
	return 0;
}

int main(int argc, char *argv[])
{
	int result = 2;
	int cmd;
	char *dev;
	int size, idx;

	if (argc == 5) {
		cmd = atoi(argv[1]);
		dev = argv[2];
		size = atoi(argv[3]);
		idx = atoi(argv[4]);
		printf("cmd = %d, dev = %s, size = %d, idx = %d\n", cmd, dev, size, idx);
	}
	switch (cmd) {
	case 1:
		result = telem_test(dev, size, idx);
		break;
	default:
		printf("Command is not correct!\n");
		break;
	}
	printf("CASE result = %d\n", result);
	return result;
}
