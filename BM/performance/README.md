# Release Notes

The performance covers the predefined benchmarks testing via perf tool
covers the CPU, Memory, I/O, Algorithm performance
If failures are detected, consider reading the debug logs, then
using perf top-down tool for additional analysis.

The python script utilizes the Avocade Test Framework, so it needs to be installed first

## The command to install the avocado from source code
```
git clone git://github.com/avocado-framework/avocado.git
cd avocado
pip install .
```

or

## Installing avocado vai pip:
```
pip3 install --user avocado-framework
```

## The command to run the case
### Running with 'runtest.py'
```
cd ..
./runtests.py -f performance -t performance/tests
```

