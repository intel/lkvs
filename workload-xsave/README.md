# Intel SIMD Instruction Microbenchmark Suite

The Intel SIMD Instruction Microbenchmark Suite is a collection of microbenchmarks designed to evaluate and debug various Intel SIMD instructions. The suite includes a total of 15 benchmarks covering instructions such as AMX, AVX, AVX2, AVX512, VNNI, VNNI512, SSE, RDTSC, PAUSE, and more. These benchmarks are primarily used for debugging xsave/xrestor related issues.

## Features
* Provides a comprehensive set of microbenchmarks for Intel SIMD instructions.
* Covers a range of instruction sets, including AMX, AVX, AVX2, AVX512, VNNI, VNNI512, SSE, RDTSC, PAUSE, and more.
* Assists in debugging xsave/xrestor related problems.
* Lightweight and easy to use.
* Open-source and freely available.

## Getting Started
These instructions will help you get a copy of the Intel SIMD Instruction Microbenchmark Suite up and running on your local machine for development and testing purposes.

### Prerequisites
* C/C++ compiler with support for the desired SIMD instruction sets.
* CMake and make installed.

### Installation
Clone the repository to your local machine:
```
git clone https://github.com/intel-sandbox/workload-xsave.git
```
Enter the project directory:
```
cd workload-xsave
```
#### CMake(Recommended)
The CMakeLists.txt is capable of selecting the appropriate source files for compilation based on the instruction sets supported by the target CPU.
Build the benchmarks using CMake:
```
mkdir build
cd build
cmake ..
make
```

#### Make(Alternative)
Build the benchmarks using Make:
```
make
```
Or, if your platform is not support all SIMD feature, you can try
```
DEBUG=1 make
```
Run the benchmarks:
```
usage: ./yogini [OPTIONS]

./yogini runs some simple micro workloads
  -w, --workload [AVX,AVX2,AVX512,AMX,MEM,memcpy,SSE,VNNI,VNNI512,UMWAIT,TPAUSE,PAUSE,RDTSC]
  -r, --repeat, each instance needs to be run
  -b, --break_reason, [yield/sleep/trap/signal/futex]Available workloads:  AMX memcpy MEM SSE RDTSC PAUSE DOTPROD VNNI512 AVX512_BF16 AVX2 AVX

```

## Contributing
Contributions are welcome and encouraged! If you would like to contribute to the Intel SIMD Instruction Microbenchmark Suite, please follow these steps:

* License
This project is licensed under the GPL2.0.
* Architecture/Workflow
![2023-07-07_15-03](https://github.com/intel-sandbox/workload-xsave/assets/1448148/1485edf4-91f5-4f46-ab34-a4eed9ff77f5)

## Acknowledgments
Mention any contributors or references you have used for this project.
Contact
For any questions or suggestions regarding the Intel SIMD Instruction Microbenchmark Suite, please contact [Yi Sun <yi.sun@intel.com>].

Replace [your-email-address] with an appropriate contact email or remove this section if not necessary.
