Telemetry is collected and returned regardless of its type.  For example, telemetry will include counters, sampled data (such as voltages) and more complex data (such as histograms).
Collecting and reporting telemetry allows for a more detailed understanding of the operation of the system from which the telemetry is obtained. 

Current test cases are focusing on telemetry Aggregator 

Detailed cases:
#check if telemetry sysfs is generated
telemetry_tests.sh -t telem_sysfs
#check if telemetry device is generated
telemetry_tests.sh -t telem_dev
#check if detailed telemetry sysfs value is correct
telemetry_tests.sh -t telem_sysfs_common
#check if telemetry data is readable
telemetry_tests.sh -t telem_data
#check if pci drvier loaded
telemetry_tests.sh -t pci
#check load/unload telemetry drvier
telemetry_tests.sh -t telem_driver
#check load/unload telemetry pci drvier with 32bit binary
telemetry_tests.sh -t telem_data_32
#check load/unload telemetry pci drvier
telemetry_tests.sh -t pci_driver
