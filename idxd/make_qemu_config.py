#!/usr/bin/python3

import sys, getopt
import json

# helper function
def usage():
	print(
	'''usage:
	-t vm type
	-c number of cpu
	-m memory size in MB
	-d pcie device list(e.g 0000:6a:01.0-0000:7a:01.0-0000:8a:01.0)
	-i path of initrd image
	-k path of kernel image
	-r path of rootfs(guest os) image
	-h HELP info'''
	)


# Parse the parameters
try:
    opts, args = getopt.getopt(sys.argv[1:],"t:c:m:d:i:k:r:h",["type=","cpus=","memory=","devices=","initrd=","kernel=","rootfs="])
except getopt.GetoptError:
    sys.exit(2)
for opt, arg in opts:
    if opt in ("-t", "--type"):
        vm_type = arg
    elif opt in ("-c", "--cpus"):
        cpus_num = arg
    elif opt in ("-m", "--memory"):
        memory_size = arg
    elif opt in ("-d", "--devices"):
        device_list = arg.split('-')
        device_count = len(device_list)
    elif opt in ("-i", "--initrd"):
        initrd = arg
    elif opt in ("-k", "--kernel"):
        kernel = arg
    elif opt in ("-r", "--rootfs"):
        rootfs = arg

# Generate json
qemu_config = {}
config_data = json.loads(json.dumps(qemu_config))

config_data['common'] = {}
config_data['common']['vm_type'] = vm_type

index = 0
config_data['vm'] = {}
config_data['vm']['cfg_' + str(index)] = '-cpu host -machine q35 -enable-kvm -global kvm-apic.vapic=false '
if 'cpus_num' in globals():
	index += 1
	config_data['vm']['cfg_' + str(index)] = '-smp ' + cpus_num + ' '
if 'memory_size' in globals():
	index += 1
	config_data['vm']['cfg_' + str(index)] = '-m ' + memory_size + ' '
if 'rootfs' in globals():
	index += 1
	config_data['vm']['cfg_' + str(index)] = '-drive format=raw,file=' + rootfs + ' '
if 'kernel' in globals():
	index += 1
	config_data['vm']['cfg_' + str(index)] = '-kernel ' + kernel + ' '
if 'initrd' in globals():
	index += 1
	config_data['vm']['cfg_' + str(index)] = '-initrd ' + initrd + ' '
index += 1
config_data['vm']['cfg_' + str(index)] = '-bios /usr/share/qemu/OVMF.fd '
index += 1
config_data['vm']['cfg_' + str(index)] = '-nic user,hostfwd=tcp::$PORT-:22 '
index += 1
config_data['vm']['cfg_' + str(index)] = '-nographic '
index += 1
config_data['vm']['cfg_' + str(index)] = '-object iommufd,id=iommufd0 '
index += 1
config_data['vm']['cfg_' + str(index)] = '-device intel-iommu,caching-mode=on,dma-drain=on,x-scalable-mode=modern,x-pasid-mode=true,device-iotlb=on,iommufd=iommufd0 '
if 'device_list' in globals():
	index += 1
	for device_num in range(0, device_count):
		config_data['vm']['cfg_dev_' + str(device_num)] = '-device vfio-pci,host=' + device_list[device_num] + ',iommufd=iommufd0,bypass-iommu=false'

format_data = json.dumps(config_data, sort_keys=True, indent=4, separators=(',', ': '))
print(format_data)

file = open('qemu.config.json','w')
file.write(format_data)
file.close()
