# avx512vbmi (avx512 Vector Byte Manipulation Instructions)

avx512vbmi is a set of instructions for Intel Tiger Lake and subsequent
platforms. Here is the test of some vbmi instructions.

You can run the cases one by one, e.g. command

```
./vbmi_func.sh -n vbmi_test -p "1 ff b"
./vbmi_func.sh -n vbmi_test -p random
```

You also can run the cases together with runtests command, e.g.
```
cd ..
./runtests -f avx512vbmi/tests -o logfile

If the platform CPU you are testing does not support avx512vbmi, it will exit
immediately and remind you to check the /tmp/lkvs_dependence log.
```
