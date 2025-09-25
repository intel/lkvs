# FRED(Flexible Return and Event Delivery) Test Cases

## Description
```
FRED architecture defines simple new transitions that change privilege level (ring transitions). It was designed with the following goals:

• Improve overall performance and response time by replacing event delivery through the interrupt descriptor table (IDT event delivery) and event return by the IRET instruction with lower latency transitions.

• Improve software robustness by ensuring that event delivery establishes the full supervisor context and that event return establishes the full user context.

```

## Usage
Before executing the case, make the BM folder
```
cd ../
make
```
Then run case as

```
./fred_test.sh -t <case name>
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f fred/tests -o logfile
```

## Expected result

All test results should show pass, no fail.
