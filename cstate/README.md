# Release Notes for CPU Core Cstate cases

The CPU Core C-state cases are designed for Intel® Architecture-based platforms.
Considering Intel® Server and Client platforms have different Core C-states behavior.
So created two tests files to distinguish the cases running on different test units:

tests-client file collects the cases for Intel® client platforms
You can run the cases one by one, e.g. command

```
./powermgr_cstate_tests.sh -t verify_cstate_name
```
You also can run the cases together with runtests command, e.g.

```
cd ../lkvs
./runtests -f cstate/tests-client -o logfile
```

tests-server file collects the cases for Intel® server platforms.

These are the basic cases for CPU Core C-states, If you have good idea to 
improve cstate cases, you are welcomed to send us the patches, thanks!
