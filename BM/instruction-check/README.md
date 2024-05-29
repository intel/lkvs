# Instruction Check

This README provides information about the `instruction-check` project, which focuses on the CPUID instruction in computer processors. The CPUID instruction allows software programs to query and retrieve detailed information about the processor, including the manufacturer, model, features, and other characteristics.

## CPUID Check Tool

In the `LKVS/tools` directory, you can find a pre-existing tool for checking CPUID information. This tool supports six parameters, for example: `cpuid_check 1 0 0 0 c 25`. The first four parameters represent the input values for the EAX, EBX, ECX, and EDX registers, while `c` indicates checking the output of the ECX register, and `25` represents checking the 25th bit.

## Preparation

### 1. Install the Avocado Test Framework
The Instruction Check project utilizes the Avocado Test Framework, so it needs to be installed first. You can install the Avocado test framework using either of the following methods:

1. Source code installation:
	```
	git clone git://github.com/avocado-framework/avocado.git
	cd avocado
	pip install .
	```
2. Installation via pip:
	```
	pip3 install --user avocado-framework
	```

### 2. Install the HTML plugin 
After installing the framework, you also need to install the HTML plugin for generating test results in HTML format. You can do this by running the following command:
``pip install avocado-framework-plugin-result-html``

## Usage 1

### 1. Compile the cpuid_check tool
Run the command:
``./setup.sh``

### 2. Execute instruction_check.py
Run the command:
``./instruction_check.py`` or ``python instruction_check.py``

## Usage 2
Usage 1 assembles each test into an Avocado job, so it can be executed directly by calling the Python interpreter. We also provide another method, which generates Avocado test classes based on the information in feature_list.py and writes them into the file cpuid_test.py.

### 1. Compile the cpuid_check tool
Run the command:
``./setup.sh``

### 2. Generate Avocado tests
Run the command:
``./auto_gen_test.py`` or ``python auto_gen_test.py``

### 3. Use Avocado to run tests
Run the command:
``avocado run cpuid_test.py``