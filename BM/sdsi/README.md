# Release Notes for Intel® on Demand feature test cases

The cases are designed for Intel® on Demand(former name is:
Software Defined Silicon, aka SoftSKU) driver on
Intel® Architecture-based server platforms.

The prerequisites to run Intel® on Demand cases:
- intel_sdsi tool, which can be built from
upstream kernel: tools/arch/x86/intel_sdsi/intel_sdsi.c

The cases do not cover AKC and CAP provisioning considering
each unique processor has dedicated CAP file.
AKC: Authentication Key Certificate
CAP: Capability Activation Payload

You can run the cases one by one, e.g. command

```
./intel_sdsi.sh -t sdsi_unbind_bind
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f sdsi/tests -o logfile
```

These are the basic cases for Intel® on Demand driver, If you have good idea to
improve sdsi cases, you are welcomed to send us the patches, thanks!
