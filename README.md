# Linux Kernel Validation Suite

The Linux Kernel Validation Suite (LKVS) is a Linux Kernel test suite. It is a working project created by the Intel Core Linux Kernel Val Team.
The purpose is to improve the quality of Intel-contributed Linux Kernel code. Furthermore, it shows the customer how to use or validate the features.

More details please refer to following.

## Features

  * [AMX(Advanced Matrix Extensions)](amx/README.md)
  * [cet(Control flow Enhancement Technology)](cet/README.md)
  * [cstate](cstate/README.md)
  * [Intel_TH(Trace Hub)](th/README.md)
  * [Intel_PT](pt/README.md)
  * [UMIP(User-Mode Instruction Prevention)](umip/README.md)
  * [xsave](xsave/README.md)

# Compile from sources

## Compile the whole project

```
git clone https://github.com/intel/lkvs.git
cd lkvs
make
```

## Alternativly compile the whole project with Docker

```
make docker_image
make docker_make
```

## Compile a single test case

```
cd lkvs/<test>
make
```

# Run tests

There're two ways to run the tests.

## Binary/Shell directly

Normally, there're one or more executable binaries or scirpts in a sub-project, once it is compiled successfully. The easiest way is to run them directly.

## Case runner

**runtests** is a straightforward test runner that can execute a single or a set of test cases and redirect the log.

There are 2 ways to pass test to **runtests**:
  1. `-c`: Pass test cmdline.
  2. `-f <component/tests*>`: the `tests*` file under each component folder records the detailed test cmd lines.

Output of tests can be saved in a file using `-o` option.

Examples:

```
$ ./runtests -f <cmdfile>
$ ./runtests -f <cmdfile> -o <logfile>
$ ./runtests -c <cmdline>
$ ./runtests -c <cmdline> -o <logfile>
```

# Report a problem

Submit an [issue](https://github.com/intel/lkvs/issues) or initiate a discussion.

# Contribute rule

Any pull request are welcomed, the canonical patch format please refer to the Kernel [patches submitting](https://www.kernel.org/doc/html/latest/process/submitting-patches.html)

# License

See [LICENSE](https://github.com/intel/lkvs/blob/main/LICENSE) for details.
