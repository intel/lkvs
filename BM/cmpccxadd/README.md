# CMPccXADD

## Description
CMPccXADD is a new set of instructions in the latest Intel platform
Sierra Forest. This new instruction set includes a semaphore operation
that can compare and add the operands if condition is met, which can
improve database performance.

This test suite provides basic functional check to ensure CMPccXADD works properly.

## Usage
```
make
# To run a specific case
(for example) ./cmpbexadd_above
# To run all cases at once
./runtest_all.sh
```
Test results (PASS or FAIL) will be printed out. 
