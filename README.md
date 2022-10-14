# Linux Kernel Validation Suite

Linux Kernel Validation Suite (LKVS) is a test suite of Linux Kernel. It's a
developing project developed by Intel Core Linux Kernel Val Team. The gold is
to improve the quality of Linux Kernel code which is contributed by the Intel.

So far, the initial version covers test cases for feature AMX (Advanced Matrix
Extensions), Intel_TH (Trace Hub), CET (Control flow Enhancement Technology)
shadow stack, XSTATE and UMIP(User-Mode Instruction Prevention). More detail
and contribute rule please refer to the following.

## Features (To-do)

  * [AMX(Advanced Matrix Extensions)](amx/README.md)
  * [cet(Control flow Enhancement Technology)](cet/README.md)
  * [Intel_TH(Trace Hub)](th/README.md)
  * [UMIP(User-Mode Instruction Prevention)](umip/README.md)
  * [xsave](xsave/README.md)

# Compile from sources

## Compile the whole project

```
git clone https://github.com/intel/lkvs.git
cd lkvs
make
```

## Compile a single test case

```
cd lkvs/<test>
make
```

# Report a problem

Submit an [issue](https://github.com/intel/lkvs/issues) or initiate a discussion.

# Contribute rule

Any pull request are welcomed, the canonical patch format please refer to the Kernel [patches submitting](https://www.kernel.org/doc/html/latest/process/submitting-patches.html)

# License

See [LICENSE](https://github.com/intel/lkvs/blob/main/LICENSE) for details.

# TO-DO

    a, Fix compile warning.
    b, Make use of docker to compile project.
    c, Unify the output.
    d, Pre-checkin check.
    e, Post-checkin execution.
    f, Feature introduction
