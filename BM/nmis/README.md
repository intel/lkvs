# FRED(Flexible Return and Event Delivery) Test Cases

## Description
```
Different event sources can generate a non maskable (NMI) interrupt to exception vector 2. Traditionally, the software NMI handler must query all the possible NMI sources to decide which NMI software handler to call. NMI source allows the software NMI exception handler to identify the source of the NMI reliably and efficiently without checking all sources.
Normal interrupts carry a vector which identifies the exception vector the interrupt is delivered on. The vector is programmed at the source. NMIs carry the same vector, but it was ignored. With NMI source the NMI vector is repurposed to identify the originator (source) of the NMI. Software is responsible to program unique values into the NMI vector at the originating site.
When the NMI is delivered the NMI source vector is reported as a bitmask in the exception event data field code pushed on the stack for a FRED exception. NMI source is only delivered when CR4.FRED is enabled.
When multiple NMIs are pending they are all collapsed into single exception delivered on vector 2.
```

## Usage
Before executing the case, make the BM folder
```
cd ../
make
```
Then run case as

```
./nmis_test.sh -t <case name>
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f nmis/tests -o logfile
```

## Expected result

All test results should show pass, no fail.
