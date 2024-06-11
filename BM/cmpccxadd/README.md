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
./cmpccxadd -t <testcase_id>
(for example, cmpbexadd_above) ./cmpccxadd -t 1
```
Test results (PASS or FAIL) will be printed out. 

## Testcase ID
| Case ID | Case Name |
| ------ | ---------------------------- |
| 1      | cmpbexadd_above |
| 2      | cmpbexadd_below |
| 3      | cmpbexadd_equal |
| 4      | cmpbxadd_above |
| 5      | cmpbxadd_below |
| 6      | cmpbxadd_equal |
| 7      | cmplexadd_equal |
| 8      | cmplexadd_less |
| 9      | cmplexadd_more |
| 10      | cmplxadd_equal |
| 11      | cmplxadd_less |
| 12      | cmplxadd_more |
| 13      | cmpnbexadd_above |
| 14      | cmpnbexadd_below |
| 15      | cmpnbexadd_equal |
| 16      | cmpnbxadd_above |
| 17      | cmpnbxadd_below |
| 18      | cmpnbxadd_equal |
| 19      | cmpnlexadd_equal |
| 20      | cmpnlexadd_less |
| 21      | cmpnlexadd_more |
| 22      | cmpnlxadd_equal |
| 23      | cmpnlxadd_less |
| 24      | cmpnlxadd_more |
| 25      | cmpnoxadd_not_overflow |
| 26      | cmpnoxadd_overflow |
| 27      | cmpnpxadd_even |
| 28      | cmpnpxadd_odd |
| 29      | cmpnsxadd_negative |
| 30      | cmpnsxadd_positive |
| 31      | cmpnzxadd_not_zero |
| 32      | cmpnzxadd_zero |
| 33      | cmpoxadd_not_overflow |
| 34      | cmpoxadd_overflow |
| 35      | cmppxadd_even |
| 36      | cmppxadd_odd |
| 37      | cmpsxadd_negative |
| 38      | cmpsxadd_positive |
| 39      | cmpzxadd_not_zero |
| 40      | cmpzxadd_zero |