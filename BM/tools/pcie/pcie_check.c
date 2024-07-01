// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * PCI/PCIe register check based on PCIe spec.
 *
 * Author: Xu, Pengfei <pengfei.xu@intel.com>
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <stdint.h>

#define MAX_BUS 256
#define MAX_DEV 32
#define MAX_FUN 8
#define PCI_CAP_START 0x34
#define PCI_EXPRESS 0x10
#define DVSEC_CAP 0x0023
#define CXL_VENDOR 0x1e98
#define CXL_1_1_VENDOR 0x8086
#define LEN_SIZE sizeof(unsigned long)
#define MAPS_LINE_LEN 128
/*
 * (4096 - 256)/32=120, PCIe caps in one PCIe should not more than 120
 */
#define PCIE_CAP_CHECK_MAX 120

#define EXP_CAP 4

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

static unsigned long BASE_ADDR;
static int check_list, is_pcie, is_cxl, spec_num, dev_id;
static u8 pci_offset;
static u32 sbus, sdev, sfunc, spec_offset[16], reg_value;
static u32 *reg_data, ptr_content = 0xffffffff;
static u32 check_value, err_num, enum_num;

int usage(void)
{
	printf("Usage: [n|a|s|i|e bus dev func]\n");
	printf("n    Show all PCI and PCIE important capability info\n");
	printf("a    Show all PCI and PCIE info\n");
	printf("c    Check cap register:c 23 8 4 means cap:0x23 offset:8bytes size:4bit\n");
	printf("s    Show all PCi and PCIE speed and bandwidth\n");
	printf("i    Show all or specific PCI info: i 10 c 4\n");
	printf("I    Show all or specific PCI and binary info\n");
	printf("e    Show all or specific PCIE info\n");
	printf("x    Only check CXL related registers:x 4 16 1e98\n");
	printf("X    Only check CXL related registers value included:X 4 16 8\n");
	printf("v    Verify PCIe register:v 23 4 16 1e98\n");
	printf("V    Verify PCIe register was included:V 23 4 16 8\n");
	printf("w    Write PCIe register if writeable:w 12 8 16 11\n");
	printf("bus  Specific bus number(HEX)\n");
	printf("dev  Specific device number(HEX)\n");
	printf("func Specific function number(HEX-optional)\n");
	printf("Write specific pcie 6b:00.0 reg sample:w 23 20 32 0002 6b 00 0\n");
	exit(2);
}

unsigned long find_base_from_dmesg(void)
{
	FILE *fp;
	unsigned long base_addr = 0;
	char result[256];
	const char *cmd = "dmesg | grep 'MMIO range' | grep 'Remove' | head -n 1";
	char *start;

	fp = popen(cmd, "r");
	if (!fp) {
		printf("Failed to run dmesg command by popen\n");
		return base_addr;
	}

	if (fgets(result, sizeof(result), fp)) {
		start = strstr(result, "[0x");
		if (start) {
			if (sscanf(start, "[0x%lx-", &base_addr) == 1)
				printf("MMIO BASE from dmesg:0x%lx\n", base_addr);
			else
				printf("No MMIO BASE from dmesg:0x%lx\n", base_addr);
		} else {
			printf("No MMIO range in dmesg:0x%lx\n", base_addr);
		}
	} else {
		printf("No useful MMIO info in dmesg.\n");
		if (pclose(fp) == -1) {
			perror("pclose failed");
			return base_addr;
		}
		return base_addr;
	}

	if (pclose(fp) == -1) {
		perror("pclose failed");
		return base_addr;
	}

	return base_addr;
}

unsigned long find_base_from_mcfg(void)
{
	FILE *fp;
	unsigned long base_addr = 0;
	// 16 chars actually and 64 is enough
	char result[64];
	const char *cmd = "b=$(ls /sys/firmware/acpi/tables/MCFG* | head -n 1);"
			"a=$(hexdump $b | grep 000030 | awk '{print $3 $2}');"
			"a+=$(hexdump $b | grep 000020 | awk '{print $9 $8}');"
			"echo $a";
	fp = popen(cmd, "r");
	if (!fp) {
		printf("Failed to run cmd command by popen\n");
		return base_addr;
	}

	if (fgets(result, sizeof(result), fp)) {
		if (sscanf(result, "%lx", &base_addr) == 1)
			printf("MMIO BASE from sysfs mcfg:0x%lx\n", base_addr);
		else
			printf("No MMIO BASE from sysfs mcfg:0x%lx\n", base_addr);
	} else {
		printf("Failed to read mcfg sysfs by fgets\n");
		if (pclose(fp) == -1) {
			perror("pclose failed");
			return base_addr;
		}
		return base_addr;
	}

	if (pclose(fp) == -1) {
		perror("pclose failed");
		return base_addr;
	}

	return base_addr;
}

int find_bar(void)
{
#ifdef __x86_64__
	FILE *maps;
	unsigned long address;
	char line[MAPS_LINE_LEN], base_end[MAPS_LINE_LEN];
	char *mmio_bar = "MMCONFIG";

	maps = fopen("/proc/iomem", "r");
	if (!maps) {
		printf("[WARN]\tCould not open /proc/iomem\n");
		exit(1);
	}

	while (fgets(line, MAPS_LINE_LEN, maps)) {
		if (!strstr(line, mmio_bar))
			continue;

		if (sscanf(line, "%lx-%s", &address, base_end) != 2)
			continue;

		printf("start_addr:0x%lx, base_end:%s\n", address, base_end);
		if (!address) {
			printf("BAR(address) is NULL, did you use root to execute?\n");
			break;
		}
		printf("BAR(Base Address Register) for mmio MMCONFIG:0x%lx\n", address);
		BASE_ADDR = address;
		break;
	}
	fclose(maps);

	if (BASE_ADDR == 0) {
		//printf("Check kconfig CONFIG_IO_STRICT_DEVMEM or v6.9 or newer kernel!\n");
		BASE_ADDR = find_base_from_dmesg();
		if (BASE_ADDR == 0) {
			BASE_ADDR = find_base_from_mcfg();
			if (BASE_ADDR == 0) {
				printf("No MMIO in dmesg, /proc/iomem and mcfg, check acpidump.\n");
				exit(2);
			}
		}
	}
#endif
	return 0;
}

void typeshow(u8 data)
{
	printf("\tpcie type:%02x  - ", data);
	switch (data) {
	case 0x00:
		printf("PCI Express Endpoint device\n");
		break;
	case 0x01:
		printf("Legacy PCI Express Endpoint device\n");
		break;
	case 0x04:
		printf("RootPort of PCI Express Root Complex\n");
		break;
	case 0x05:
		printf("Upstream Port of PCI Express Switch\n");
		break;
	case 0x06:
		printf("Downstream Port of PCI Express Switch\n");
		break;
	case 0x07:
		printf("PCI Express-to-PCI/PCI-x Bridge\n");
		break;
	case 0x08:
		printf("PCI/PCI-xto PCi Express Bridge\n");
		break;
	case 0x09:
		printf("Root Complex Integrated Endpoint Device\n");
		break;
	case 0x0a:
		printf("Root Complex Event Collector\n");
		break;
	default:
		printf("reserved\n");
		break;
	}
}

void speed_show(u8 speed)
{
	printf(" %x - ", speed);
	switch (speed) {
	case 0x1:
		printf("2.5GT/S\n");
		break;
	case 0x2:
		printf("5GT/S\n");
		break;
	case 0x3:
		printf("8GT/S\n");
		break;
	case 0x4:
		printf("16GT/S\n");
		break;
	case 0x5:
		printf("32GT/s\n");
		break;
	case 0x6:
		printf("64GT/s\n");
		break;
	default:
		printf("reserved\n");
		break;
	}
}

void linkwidth(u8 width)
{
	printf("\tLink Capabilities Register(0x0c bit9:4) width:%02x - ", width);
	if (width > 0 && width < 17 && (width & (width - 1)) == 0)
		printf("x%d\n", width);
	else
		printf("reserved\n");
}

int check_pcie(u32 *ptrdata)
{
	u8 ver = 0;
	u32 next = 0x100, num = 0;
	u16 offset = 0, cap = 0;

	if (is_pcie == 1) {
		cap = (u16)(*(ptrdata + next / 4));
		offset = (u16)(*(ptrdata + next / 4) >> 20);
		ver = (u8)((*(ptrdata + next / 4) >> 16) & 0xf);
		// Compile will warning: warning: suggest parentheses around comparison...
		if (offset == 0 || offset == 0xfff) {
			printf("PCIE cap:%04x ver:%01x off:%03x|\n", cap, ver, offset);
			return 0;
		}
		printf("PCIE cap:%04x ver:%01x off:%03x|", cap, ver, offset);

		while (1) {
			num++;
			cap = (u16)(*(ptrdata + offset / 4));
			ver = (u8)((*(ptrdata + offset / 4) >> 16) & 0xf);
			offset = (u16)(*(ptrdata + offset / 4) >> 20);

			if (offset == 0) {
				printf("cap:%04x ver:%01x off:%03x|\n", cap, ver, offset);
				break;
			}
			printf("cap:%04x ver:%01x off:%03x|", cap, ver, offset);
			if (num > PCIE_CAP_CHECK_MAX) {
				printf("PCIE num is more than %d, return\n", PCIE_CAP_CHECK_MAX);
				break;
			}
		}
	} else {
		printf("\n");
	}
	return 0;
}

int check_pci(u32 *ptrdata)
{
	u8 nextpoint = 0x34;
	u32 num = 0;
	u32 *ptrsearch;

	nextpoint = (u8)(*(ptrdata + nextpoint / 4));
	ptrsearch = ptrdata + nextpoint / 4;

	if (nextpoint == 0 || nextpoint == 0xff) {
		printf("off:0x34->%02x|\n", nextpoint);
		return 0;
	}
	printf("off:0x34->%02x cap:%02x|", nextpoint, (u8)(*ptrsearch));

	while (1) {
		if ((u8)((*ptrsearch) >> 8) == 0x00) {
			printf("off:%02x|", (u8)((*ptrsearch) >> 8));
			break;
		}
		if (num >= 16)
			break;

		printf("off:%02x ", (u8)(((*ptrsearch) >> 8) & 0x00ff));
		ptrsearch = ptrdata + ((u8)(((*ptrsearch) >> 8) & 0x00ff)) / 4;
		printf("cap:%02x|", (u8)(*ptrsearch));
		num++;
	}

	if (((check_list >> 3) & 0x1) == 1) {
		printf("\n");
		return 0;
	}
	check_pcie(ptrdata);

	return 0;
}

int pci_show(u32 bus, u32 dev, u32 fun)
{
	u32 *ptrdata = malloc(sizeof(unsigned long) * 4096);
	u64 addr = 0;
	int fd, offset;

	fd = open("/dev/mem", O_RDWR);
	if (fd < 0) {
		free(ptrdata);
		printf("open /dev/mem failed!\n");
		return -1;
	}

	if (BASE_ADDR == 0)
		find_bar();

	addr = BASE_ADDR | (bus << 20) | (dev << 15) | (fun << 12);
	ptrdata = mmap(NULL, LEN_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, addr);

	printf("Offset addr:%lx, *ptrdata:%x, LEN_SIZE:%lx\n", addr, *ptrdata, LEN_SIZE);
	if ((*ptrdata != ptr_content) && (*ptrdata != 0)) {
		printf("%02x:%02x.%01x:", bus, dev, fun);

		if (((check_list >> 1) & 0x1) == 1) {
			for (offset = 0; offset < 64; offset++) {
				if (offset % 4 == 0)
					printf("\n%02x: ", offset * 4);
				printf("%02x ", (u8)(*(ptrdata + offset) >> 0));
				printf("%02x ", (u8)(*(ptrdata + offset) >> 8));
				printf("%02x ", (u8)(*(ptrdata + offset) >> 16));
				printf("%02x ", (u8)(*(ptrdata + offset) >> 24));
			}
			if (is_pcie == 1) {
				for (offset = 64; offset < 1024; offset++) {
					if (offset % 4 == 0)
						printf("\n%02x: ", offset * 4);
					printf("%02x ", (u8)(*(ptrdata + offset) >> 0));
					printf("%02x ", (u8)(*(ptrdata + offset) >> 8));
					printf("%02x ", (u8)(*(ptrdata + offset) >> 16));
					printf("%02x ", (u8)(*(ptrdata + offset) >> 24));
				}
			}
			printf("\n");
		}
		if (is_pcie == 1)
			check_pcie(ptrdata);
		else
			check_pci(ptrdata);
	} else {
		printf("*ptrdata:%x, which is 0 or %x, ptrdata:%p, return\n",
		       *ptrdata, ptr_content, ptrdata);
	}
	munmap(ptrdata, LEN_SIZE);
	close(fd);
	return 0;
}

int recognize_pcie(u32 *ptrdata)
{
	int loop_num = 0;
	u8 nextpoint;
	u32 *ptrsearch;

	is_pcie = 0;
	/* 0x34/4 is capability pointer in PCI */
	nextpoint = (u8)(*(ptrdata + PCI_CAP_START / 4));

	if (nextpoint == 0)
		return 0;

	ptrsearch = ptrdata + nextpoint / 4;
	while (1) {
		/* 0x10 means PCIE capability */
		if ((u8)(*ptrsearch) == 0x10) {
			is_pcie = 1;
			break;
		}
		if ((u8)(*ptrsearch) == 0xff) {
			printf("*ptrsearch:%x offset is 0xff, ptrsearch:%p, ptrdata:%p\n",
			       *ptrsearch, ptrsearch, ptrdata);
			return 2;
		}

		/* no PCIE find */
		if ((u8)((*ptrsearch) >> 8) == 0x00)
			break;
		if (loop_num >= 16)
			break;
		/* next capability */
		ptrsearch = ptrdata + ((u8)(((*ptrsearch) >> 8)	& 0x00ff)) / 4;
		loop_num++;
	}
	return 0;
}

int specific_pci_cap(u32 *ptrdata, u8 cap)
{
	u8 nextpoint = 0;
	u32 *ptrsearch;
	u8 num = 0, cap_value = 0;
	int ret_result = 0;

	nextpoint = (u8)(*(ptrdata + PCI_CAP_START / 4));

	if (nextpoint == 0 || nextpoint == 0xff)
		return 2;

	ptrsearch = ptrdata + nextpoint / 4;

	while (1) {
		cap_value = (u8)(*ptrsearch);
		if (cap_value == 0) {
			ret_result = 2;
			break;
		}

		if (cap_value == cap) {
			pci_offset = nextpoint;
			ret_result = 0;
			break;
		}
		nextpoint = (u8)(((*ptrsearch) >> 8) & 0xff);
		ptrsearch = ptrdata + ((u8)(((*ptrsearch) >> 8) & 0x00ff)) / 4;
		if (nextpoint == 0 || nextpoint == 0xff) {
			ret_result = 2;
			break;
		}
		num++;
		/* avoid offset is wrong and in infinite loop set the max loop 16 */
		if (num >= 16) {
			ret_result = 1;
			break;
		}
	}

	return ret_result;
}

int show_pci_info(u32 *ptrdata)
{
	u32 *ptr_search;
	int result = 0;

	result = specific_pci_cap(ptrdata, (u8)PCI_EXPRESS);

	if (!result) {
		ptr_search = ptrdata + pci_offset / 4;
		typeshow((u8)(((*ptr_search) >> 20) & 0x0f));
		printf("\tLink cap max link speed(offset:%x):",
		       pci_offset + 0xc);
		speed_show((u8)(*(ptrdata + (pci_offset + 0xc) / 4) & 0xf));
		printf("\tLink status current link speed(offset:%x):",
		       pci_offset + 0x12);
		speed_show((u8)(*(ptrdata + (pci_offset + 0x10) / 4) >> 16 & 0xf));
		linkwidth((u8)(((*(ptr_search + 0x0c / 4)) >> 4) & 0x3f));
	}

	return result;
}

int scan_pci(void)
{
	// Must be 64bit address for 64bit OS!
	u64 addr = 0;
	u32 bus, dev, fun;
	// Must 32bit for data check!
	u32 *ptrdata = malloc(sizeof(unsigned long) * 4096);
	int fd;

	fd = open("/dev/mem", O_RDWR);

	if (fd < 0) {
		printf("open /dev/mem failed!\n");
		free(ptrdata);
		return -1;
	}
	printf("fd=%d open /dev/mem successfully.\n", fd);

	ptrdata = &ptr_content;
	for (bus = 0; bus < MAX_BUS; ++bus) {
		for (dev = 0; dev < MAX_DEV; ++dev) {
			for (fun = 0; fun < MAX_FUN; ++fun) {
				addr = BASE_ADDR | (bus << 20) | (dev << 15) | (fun << 12);

				ptrdata = mmap(NULL, LEN_SIZE, PROT_READ | PROT_WRITE,
					       MAP_SHARED, fd, addr);

				if (ptrdata == MAP_FAILED) {
					munmap(ptrdata, LEN_SIZE);
					break;
				}

				if ((*ptrdata != ptr_content) && (*ptrdata != 0)) {
					if (recognize_pcie(ptrdata) == 2) {
						printf("%02x:%02x.%x debug:pcie_check a %x %x %x\n",
						       bus, dev, fun, bus, dev, fun);
						munmap(ptrdata, LEN_SIZE);
						close(fd);
						return 2;
					}

					if (is_pcie == 0)
						printf("PCI  %02x:%02x.%x: ", bus, dev, fun);
					else
						printf("PCIE %02x:%02x.%x: ", bus, dev, fun);

					printf("vendor:0x%04x dev:0x%04x ", (*ptrdata) & 0x0000ffff,
					       ((*ptrdata) >> 16) & 0x0000ffff);

					if (((check_list >> 2) & 0x1) == 1)
						check_pcie(ptrdata);
					else
						check_pci(ptrdata);

					if ((check_list & 0x1) == 1)
						show_pci_info(ptrdata);

					if (((check_list >> 1) & 0x1) == 1)
						pci_show(bus, dev, fun);
				}
				munmap(ptrdata, LEN_SIZE);
			}
		}
	}
	close(fd);
	return 0;
}

int specific_pcie_cap(u32 *ptrdata, u16 cap)
{
	u8 nextpoint = 0;
	u32 next = 0x100, num = 0;
	u16 offset = 0, cap_value = 0;
	int ret_result = 0;

	spec_num = 0;
	nextpoint = (u8)(*(ptrdata + PCI_CAP_START / 4));
	if (nextpoint == 0xff) {
		/* For debug
		 * printf("PCI cap offset:%x is 0xff, addr:%p ptrdata:%x, return 2\n",
		 *	PCI_CAP_START, ptrdata, *ptrdata);
		 */
		return 2;
	}

	cap_value = (u16)(*(ptrdata + next / 4));
	offset = (u16)(*(ptrdata + next / 4) >> 20);
	if (offset == 0 || offset == 0xfff)
		return 0;
	if (cap_value == cap) {
		spec_offset[spec_num] = next;
		spec_num++;
		ret_result = EXP_CAP;
	}

	while (1) {
		num++;
		cap_value = (u16)(*(ptrdata + offset / 4));
		if (cap_value == cap) {
			spec_offset[spec_num] = offset;
			spec_num++;
			ret_result = EXP_CAP;
		}
		offset = (u16)(*(ptrdata + offset / 4) >> 20);
		if (offset == 0)
			break;
		/* Same cap with cap_id should not more than 15 */
		if (spec_num > 15)
			break;
		/* avoid offset is wrong and in infinite loop set the max loop 30 */
		if (num > 30)
			break;
	}

	return ret_result;
}

int show_pcie_spec_reg(u32 offset, u32 size, int show, int cap_id)
{
	u32 reg_offset = 0, get_size = 0xffffffff, left_off = 0;

	if (size != 32) {
		get_size = get_size >> size;
		get_size = get_size << size;
		get_size = ~get_size;
	}

	reg_offset = spec_offset[cap_id] + offset;
	reg_value = (u32)(*(reg_data + reg_offset / 4));
	left_off = reg_offset % 4;
	if (left_off != 0) {
		//printf("(left:%dbyte)", left_off);
		reg_value = reg_value >> (left_off * 8);
	}
	reg_value = reg_value & get_size;
	if (((check_list >> 7) & 0x1) == 1) {
		*(reg_data + reg_offset / 4) = check_value << (left_off * 8);
		printf(" Reg_offset:%x, size:%dbit, reg_value:%x->0x%x addr:%p",
		       reg_offset, size, reg_value,
		       (u32)(((*(reg_data + reg_offset / 4) >> (left_off * 8)) & get_size)),
		       reg_data + reg_offset / 4 + reg_offset % 4);
	} else if (show) {
		printf(" Reg_offset:%x, size:%dbit, reg_value:%x.",
		       reg_offset, size, reg_value);
	}

	return 0;
}

int verify_pcie_reg(u32 val)
{
	if (reg_value == val)
		return 1;
	else
		return 0;
}

int contain_pcie_reg(u32 val)
{
	u32 compare_value;

	compare_value = reg_value & val;
	if (compare_value == val)
		return 0;
	else
		return 1;
}

int check_pcie_register(u16 cap, u32 offset, u32 size)
{
	int i = 0, vendor = 0, dvsec_id = 0;

	for (i = 0; i < spec_num; i++) {
		if (i == 0)
			printf("Find cap %04x PCIe %02x:%02x.%x DEV:%04x base_offset:%03x.",
			       cap, sbus, sdev, sfunc, dev_id, spec_offset[i]);
		else
			printf("                                     base_offset:%x.",
			       spec_offset[i]);

		if (((check_list >> 4) & 0x1) == 1) {
			/* Check vendor ID offset 4bytes, size 16bit */
			show_pcie_spec_reg((u32)4, (u32)16, 0, i);
			if (verify_pcie_reg(CXL_VENDOR) || verify_pcie_reg(CXL_1_1_VENDOR)) {
				vendor = reg_value;
				/* Check DVSEC ID in offset 8 bytes with size 16bit */
				show_pcie_spec_reg((u32)8, (u32)16, 0, i);
				dvsec_id = reg_value;
				printf("DVSEC_vendor:%x. DVSEC_ID:%x.", vendor, dvsec_id);

				if (dvsec_id == 0) {
				/*
				 * CXL1.1/2.0: DVSEC ID0 upper 8bits CXL len should be 03, len:0x38
				 * CXL3.0: DVSEC ID0 byte offset 7 CXL len should be 03, len:0x3C
				 * CXL3.0 sample: 23 00 c1 3a 98 1e c2 03
				 */
					show_pcie_spec_reg((u32)7, (u32)8, 0, i);
					if (verify_pcie_reg(3)) {
						printf("<CXL PCI> ");
						is_cxl = 1;
					}
				}
			} else {
				printf("Not CXL vendor:0x%x, actual vendor:%x.",
				       CXL_VENDOR, vendor);
			}
		}
		enum_num++;
		show_pcie_spec_reg(offset, size, 1, i);
		if (((check_list >> 5) & 0x1) == 1) {
			if (verify_pcie_reg(check_value)) {
				printf("Match as expected.");
			} else {
				printf("reg_value:%x is not equal to check_value:%x.",
				       reg_value, check_value);
				if (((check_list >> 4) & 0x1) == 1) {
					if (is_cxl == 1)
						err_num++;
				} else {
					err_num++;
				}
			}
		}

		if (((check_list >> 6) & 0x1) == 1) {
			if (contain_pcie_reg(check_value)) {
				printf("reg_value:%x is not included by check_value:%x.",
				       reg_value, check_value);
				if (((check_list >> 4) & 0x1) == 1) {
					if (is_cxl == 1)
						err_num++;
				} else {
					err_num++;
				}
			} else {
				printf("Include as expected.");
			}
		}
		printf("\n");
	}

	return 0;
}

int find_pcie_reg(u16 cap, u32 offset, u32 size)
{
	u64 addr = 0;
	u32 *ptrdata = malloc(sizeof(unsigned long) * 4096);
	u32 bus, dev, func;
	int fd, result = 0;

	printf("PCIe specific register-> cap:0x%04x, offset:0x%x, size:%dbit:\n",
	       cap, offset, size);

	fd = open("/dev/mem", O_RDWR);
	if (fd < 0) {
		free(ptrdata);
		printf("open /dev/mem failed!\n");
		return -1;
	}

	ptrdata = &ptr_content;
	for (bus = 0; bus < MAX_BUS; ++bus) {
		for (dev = 0; dev < MAX_DEV; ++dev) {
			for (func = 0; func < MAX_FUN; ++func) {
				addr = BASE_ADDR | (bus << 20) | (dev << 15) | (func << 12);
				ptrdata = mmap(NULL, LEN_SIZE, PROT_READ | PROT_WRITE,
					       MAP_SHARED, fd, addr);
				/* If this bus:fun.dev is all FF will break and check next */
				if (ptrdata == (void *)-1) {
					munmap(ptrdata, LEN_SIZE);
					break;
				}

				if ((*ptrdata != ptr_content) && (*ptrdata != 0)) {
					result = specific_pcie_cap(ptrdata, cap);
					if (result == 4) {
						sbus = bus;
						sdev = dev;
						sfunc = func;
						reg_data = ptrdata;
						dev_id = *(ptrdata) >> 16;
						is_cxl = 0;
						check_pcie_register(cap, offset, size);
					} else if (result == 2) {
						/* This PCIe ended with unknown CAP ff, mark it */
						printf("%02x:%02x.%x debug:pcie_check a %x %x %x\n",
						       bus, dev, func, bus, dev, func);
						munmap(ptrdata, LEN_SIZE);
						close(fd);
						return 2;
					}
				}
				munmap(ptrdata, LEN_SIZE);
			}
		}
	}
	close(fd);
	return 0;
}

int specific_pcie_check(u16 cap, u32 offset, u32 size)
{
	u64 addr = 0;
	u32 *ptrdata = malloc(sizeof(unsigned long) * 4096);
	int fd, result = 0;

	is_cxl = 0;
	printf("PCIe %x:%x.%x: cap:0x%04x, offset:0x%x, size:%dbit:\n",
	       sbus, sdev, sfunc, cap, offset, size);

	fd = open("/dev/mem", O_RDWR);
	if (fd < 0) {
		printf("open /dev/mem failed!\n");
		free(ptrdata);
		return -1;
	}

	ptrdata = &ptr_content;
	addr = BASE_ADDR | (sbus << 20) | (sdev << 15) | (sfunc << 12);
	ptrdata = mmap(NULL, LEN_SIZE, PROT_READ | PROT_WRITE,
		       MAP_SHARED, fd, addr);
	if (ptrdata == (void *)-1) {
		printf("mmap failed\n");
		munmap(ptrdata, LEN_SIZE);
		close(fd);
		return 2;
	}

	if ((*ptrdata != ptr_content) && (*ptrdata != 0)) {
		result = specific_pcie_cap(ptrdata, cap);
		if (result == 4) {
			reg_data = ptrdata;
			check_pcie_register(cap, offset, size);
		} else {
			printf("Could not find cap:%x for %x:%x.%x\n",
			       cap, sbus, sdev, sfunc);
			munmap(ptrdata, LEN_SIZE);
			close(fd);
			return 1;
		}
	}
	munmap(ptrdata, LEN_SIZE);

	close(fd);
	return 0;
}

int show_pci_spec_reg(u8 offset, u32 size, int show)
{
	u32 reg_offset = 0, get_size = 0xffffffff, left_off = 0;

	if (size != 32) {
		get_size = get_size >> size;
		get_size = get_size << size;
		get_size = ~get_size;
	}

	reg_offset = pci_offset + offset;
	reg_value = (u32)(*(reg_data + reg_offset / 4));
	left_off = reg_offset % 4;
	if (left_off != 0) {
		/*
		 * Debug
		 * printf("(left:%dbyte)", left_off);
		 */
		reg_value = reg_value >> (left_off * 8);
	}
	reg_value = reg_value & get_size;
	if (((check_list >> 7) & 0x1) == 1) {
		*(reg_data + reg_offset / 4) = check_value << (left_off * 8);
		printf(" Reg_offset:%x, size:%dbit, reg_value:%x->0x%x addr:%p",
		       reg_offset, size, reg_value,
		       (u32)(((*(reg_data + reg_offset / 4) >> (left_off * 8))
		       & get_size)),
		       reg_data + reg_offset / 4 + reg_offset % 4);
	} else if (show)
		printf(" Reg_offset:%x, size:%dbit, reg_value:%x.",
		       reg_offset, size, reg_value);

	return 0;
}

int check_pci_register(u8 cap, u8 offset, u32 size)
{
	printf("Find cap 0x%02x PCI %02x:%02x.%x DEV:%04x pci_offset:%02x.",
	       cap, sbus, sdev, sfunc, dev_id, pci_offset);

	show_pci_spec_reg(offset, size, 1);
	if (((check_list >> 5) & 0x1) == 1) {
		if (verify_pcie_reg(check_value)) {
			printf("Match as expected.");
		} else {
			printf("reg_value:%x is not equal to check_value:%x.",
			       reg_value, check_value);
			err_num++;
		}
	}
	if (((check_list >> 6) & 0x1) == 1) {
		if (contain_pcie_reg(check_value)) {
			printf("reg_value:%x is not included by check_value:%x.",
			       reg_value, check_value);
			err_num++;
		} else {
			printf("Include as expected.");
		}
	}
	printf("\n");

	return 0;
}

int find_pci_reg(u16 cap, u32 offset, u32 size)
{
	u64 addr = 0;
	u32 *ptrdata = malloc(sizeof(unsigned long) * 4096);
	u32 bus, dev, func;
	int fd, result = 0;

	printf("PCI specific register-> cap:0x%04x, offset:0x%x, size:%dbit:\n",
	       cap, offset, size);

	fd = open("/dev/mem", O_RDWR);
	if (fd < 0) {
		free(ptrdata);
		printf("open /dev/mem failed!\n");
		return -1;
	}

	ptrdata = &ptr_content;
	for (bus = 0; bus < MAX_BUS; ++bus) {
		for (dev = 0; dev < MAX_DEV; ++dev) {
			for (func = 0; func < MAX_FUN; ++func) {
				addr = BASE_ADDR | (bus << 20) | (dev << 15) | (func << 12);
				ptrdata = mmap(NULL, LEN_SIZE, PROT_READ | PROT_WRITE,
					       MAP_SHARED, fd, addr);
				/* If this bus:fun.dev is all FF will break and check next */
				if (ptrdata == (void *)-1) {
					munmap(ptrdata, LEN_SIZE);
					break;
				}

				if ((*ptrdata != ptr_content) && (*ptrdata != 0)) {
					result = specific_pci_cap(ptrdata, (u8)cap);
					/*
					 * Debug
					 * printf("BDF:%02x:%02x.%x: result: %d\n",
					 *        bus, dev, func, result);
					 */
					if (result == 0) {
						sbus = bus;
						sdev = dev;
						sfunc = func;
						reg_data = ptrdata;
						dev_id = *(ptrdata) >> 16;
						is_cxl = 0;
						enum_num++;
						check_pci_register((u8)cap, (u8)offset, size);
					} else if (result == 1) {
						/* This PCI ended with unknown CAP ff so mark it */
						printf("%02x:%02x.%x debug:pcie_check a %x %x %x\n",
						       bus, dev, func, bus, dev, func);
						munmap(ptrdata, LEN_SIZE);
						close(fd);
						return 2;
					}
				}
				munmap(ptrdata, LEN_SIZE);
			}
		}
	}
	close(fd);
	return 0;
}

int main(int argc, char *argv[])
{
	char param;
	u32 bus, dev, func, offset, size;
	u16 cap;

	printf("Remove CONFIG_IO_STRICT_DEVMEM in kconfig when all result 0.\n");
	if (argc == 2) {
		if (sscanf(argv[1], "%c", &param) != 1) {
			printf("Invalid param:%c\n", param);
			usage();
		}
		printf("1 parameters: param=%c\n", param);
		find_bar();

		switch (param) {
		case 'a':
			check_list = (check_list | 0x7);
			break;
		case 's': // speed
			check_list = (check_list | 0x1);
			break;
		case 'x': // pci binary
			check_list = (check_list | 0x2);
			break;
		case 'i': // only check pci capability
			check_list = (check_list | 0x8);
			break;
		case 'e': // only check pcie capability
			check_list = (check_list | 0x4);
			break;
		case 'n':
			check_list = 0;
			break;
		case 'h':
			usage();
			break;
		default:
			usage();
			break;
		}
		scan_pci();
	}  else if ((argc == 4) | (argc == 5) | (argc == 6) | (argc == 9)) {
		if (sscanf(argv[1], "%c", &param) != 1) {
			printf("Invalid param:%c\n", param);
			usage();
		}
		find_bar();
		switch (param) {
		case 'i':
			is_pcie = 0;
			check_list = (check_list | 0x8);
			break;
		case 'I':
			is_pcie = 0;
			check_list = (check_list | 0x2);
			break;
		case 'e':
			is_pcie = 1;
			break;
		case 'a':
			check_list = (check_list | 0x7);
			is_pcie = 1;
			break;
		case 'c':
			is_pcie = 1;
			check_list = (check_list | 0x8);
			break;
		case 'x':
			is_pcie = 1;
			check_list = (check_list | 0x10); // only for CXL PCIe check
			break;
		case 'X':
			is_pcie = 1;
			check_list = (check_list | 0x10);
			check_list = (check_list | 0x40); // contain matched bit
			break;
		case 'v':
			is_pcie = 1;
			check_list = (check_list | 0x8);
			check_list = (check_list | 0x20);  // specific register should same
			break;
		case 'V':
			is_pcie = 1;
			check_list = (check_list | 0x8);
			check_list = (check_list | 0x40);
			break;
		case 'w':
			is_pcie = 1;
			check_list = (check_list | 0x8);
			check_list = (check_list | 0x80);
			break;
		default:
			usage();
			break;
		}

		if (((check_list >> 3) & 0x1) == 1) {
			if (argc == 4)
				usage();
			if (sscanf(argv[2], "%hx", &cap) != 1) {
				printf("Invalid cap:%x", cap);
				usage();
			}
			if (sscanf(argv[3], "%x", &offset) != 1) {
				printf("Invalid offset:%x", offset);
				usage();
			}
			if (sscanf(argv[4], "%d", &size) != 1) {
				printf("Invalid size:%d", size);
				usage();
			}
			if (argc == 5 && param != 'i') {
				find_pcie_reg(cap, offset, size);
				if (enum_num == 0) {
					printf("No cap:0x%x PCI/PCIe found\n", cap);
					err_num = 1;
				}
				return err_num;
			} else if (argc == 5 && param == 'i') {
				find_pci_reg(cap, offset, size);
				if (enum_num == 0) {
					printf("No cap:0x%x PCI found\n", cap);
					err_num = 1;
				}
				return err_num;
			} else if (argc == 6) {
				if (sscanf(argv[5], "%x", &check_value) != 1) {
					printf("Invalid check_value:%x", check_value);
					usage();
				}
				printf("Value:%x\n", check_value);
				find_pcie_reg(cap, offset, size);
				if (enum_num == 0) {
					printf("No cap:0x%x PCI/PCIe found\n", cap);
					err_num = 1;
				}
				return err_num;
			} else if (argc == 9) {
				if (sscanf(argv[5], "%x", &check_value) != 1) {
					printf("Invalid check_value:%x", check_value);
					usage();
				}
				printf("Value:%x\n", check_value);
				if (sscanf(argv[6], "%x", &sbus) != 1) {
					printf("Invalid check_value:%x", sbus);
					usage();
				}
				if (sscanf(argv[7], "%x", &sdev) != 1) {
					printf("Invalid check_value:%x", sdev);
					usage();
				}
				if (sscanf(argv[8], "%x", &sfunc) != 1) {
					printf("Invalid check_value:%x", sfunc);
					usage();
				}
				return specific_pcie_check(cap, offset, size);
			}
			usage();
		}

		if (((check_list >> 4) & 0x1) == 1) {
			if (sscanf(argv[2], "%x", &offset) != 1) {
				printf("Invalid offset:%x", offset);
				usage();
			}
			if (sscanf(argv[3], "%d", &size) != 1) {
				printf("Invalid size:%d", size);
				usage();
			}
			if (argc == 4) {
				find_pcie_reg(DVSEC_CAP, offset, size);
				return 0;
			} else if (argc == 5) {
				if (sscanf(argv[4], "%x", &check_value) != 1) {
					printf("Invalid check_value:%x", check_value);
					usage();
				}
				printf("check_value:%x\n", check_value);
				if (((check_list >> 6) & 1) == 0)
					check_list = (check_list | 0x20);

				find_pcie_reg(DVSEC_CAP, offset, size);
				if (enum_num == 0) {
					printf("No CXL with cap:0x%x PCI/PCIe found\n", DVSEC_CAP);
					err_num = 1;
				}
				return err_num;
			}
			usage();
		}

		if (sscanf(argv[2], "%x", &bus) != 1) {
			printf("Invalid bus:%x", bus);
			usage();
		}

		if (sscanf(argv[3], "%x", &dev) != 1) {
			printf("Invalid dev:%x", dev);
			usage();
		}
		if (argc == 5) {
			if (sscanf(argv[4], "%x", &func) != 1) {
				printf("Invalid func:%x", func);
				usage();
			}
		} else {
			printf("No useful input func, will scan all func\n");
			for (func = 0; func < MAX_FUN; ++func)
				pci_show(bus, dev, func);
			return 0;
		}
		printf("param:%c bus:dev.func: %02x:%02x.%x\n", param, bus, dev, func);

		pci_show(bus, dev, func);
	} else {
		find_bar();
		usage();
	}

	return 0;
}
