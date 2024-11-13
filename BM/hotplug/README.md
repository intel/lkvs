# Release Notes

In the software solution, CPU hotplug and unplug refers to
CPU offline and online operations using the '/sys/devices/system/cpu' interface.

The python script utilizes the Avocade Test Framework, so it needs to be installed first

## The command to instlall the avocado from source code
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
./runtests.py -f hotplug -t hotplug/tests
```

### Running with avocado framework
```
avocado run cpu_off_on_stress.py
```
