# FRED(Flexible Return and Event Delivery) Test Cases

## Description
```
FRED architecture defines simple new transitions that change privilege level (ring transitions). It was designed with the following goals:

• Improve overall performance and response time by replacing event delivery through the interrupt descriptor table (IDT event delivery) and event return by the IRET instruction with lower latency transitions.

• Improve software robustness by ensuring that event delivery establishes the full supervisor context and that event return establishes the full user context.

At the moment, it includes two tests: 
1) Check FRED is enabled or not through checking cr4 32 bit. 1 represents enable.
2) Doubile fault trigger. It will trigger double fault intensively to see whether double fault will be detected. Its main logic is that changing RSP to 4096 which is a invalid RSP value before kernel handles a page fault, then a double fault will be triggered when kernel handles the first page fault.
```

## Usage
make
insmod fred_test_driver
echo "fred_enable" > /dev/fred_test_device This will trigger the FRED enable checking test.
echo "double_fault" > /dev/fred_test_device This will trigger double fault test and kernel will crash.
```
