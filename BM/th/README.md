TH is for Intel Trace Hub. Intel Trace Hub functional blocks include the Software Trace Hub
(STH) block, the On-Die Logic Analyzer (ODLA)/VIS Event Recognition (VER) block, the
System-on-Chip Performance Counters (SoCHAP) block, the Visualization of Internal Signals
(VIS) Controller block, and the Global Trace Hub (GTH) block. 

This test will check policy set/get with ioctl for Intel trace hub.

Precondition:
Enable "0-sth.test" policy for TH.

Cmds: 
th_test 1 : for policy set test 
th_test 2 : for policy get test
	
