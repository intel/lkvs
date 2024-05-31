# PREFETCHI (Code SW Prefetch)

## Description
PREFETCHI is a new set of instructions in the latest Intel platform Granite Rapids. This new instruction set moves code to memory (cache) closer to the processor depending on specific hints. The encodings stay NOPs in processors that do not enumerate these instructions.

This is a basic test to ensure PREFETCHIT0/1 is supported on your platform.

## Usage
```
make
./prefetchi
```
Test result will be printed out.
