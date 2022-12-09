# Contributing

### License

Linux Kernel Validation Suite (LKVS) is licensed under the terms in [GPL-2.0](https://github.com/intel/lkvs/blob/main/LICENSE). By contributing to the project, you agree to the license and copyright terms therein and release your contribution under these terms.

### Sign your work

Please use the sign-off line at the end of the patch. Your signature certifies that you wrote the patch or otherwise have the right to pass it on as an open-source patch. The rules are pretty simple: if you can certify
the below (from [developercertificate.org](http://developercertificate.org/)):

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.
660 York Street, Suite 102,
San Francisco, CA 94110 USA

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

Then you just add a line to every git commit message:

    Signed-off-by: Joe Smith <joe.smith@email.com>

Use your real name (sorry, no pseudonyms or anonymous contributions.)

If you set your `user.name` and `user.email` git configs, you can sign your
commit automatically with `git commit -s`.

### Coding rules 
Here are some key points to remember when developing for the LKVS:

Use a consistent coding style, and follow the Linux kernel coding style
guidelines. This will make the code easier to read and maintain.

Use meaningful and descriptive names for variables, functions, and macros.
Avoid abbreviations, and use CamelCase for multi-word names.

By following these guidelines, developers can ensure that their contributions
are of high quality and provide a stable and reliable applications.


### Check patch
We encourage developers to use Shellcheck and checkpatch.pl to check their
patches before submission. For ERRORs and WARNINGs, fixes are required.
For CHECKs, fixes are not required but highly recommended.

Shellcheck is a tool that checks for common errors and best practices in shell
scripts. It can help to identify and fix problems before they become issues in
the code.

checkpatch.pl is a script that checks for conformance to the Linux kernel coding
style guidelines. It can help to ensure that patches are consistent with the
rest of the kernel and are easy to read and maintain.

By using these tools, developers can improve the quality of their patches and
reduce the time and effort required to review and merge them. This will help to
keep the LKVS codebase clean and maintainable, and ensure that it continues to
evolve and improve.

### file 'tests'
We encourage developers to add a 'tests' file in each feature directory. Each
line in the file would represent the command line of a sigle test, e.g.:
```
powermgr_cstate_tests.sh -t verify_server_all_cores_cstate6
powermgr_cstate_tests.sh -t verify_server_core_cstate6_residency
... ...
```
But it is not mandatory.

Having a 'tests' file in each feature directory would provide a convenient way
to organize and run tests for that feature. Each test case would be specified
on a separate line, with the name of the case and the command line to run it.

Although this is not a mandatory requirement, we believe that it would be a
useful addition to the development process. It would allow developers to easily
run a set of tests for a specific feature, and ensure that it is working
correctly.

### Information format
Regarding the print information, the unified format is:
```
[Key word] case_name: informations ....
```

Using a consistent format for printing information will help to make the output
more readable and easier to understand. The format should include a key word
that indicates the type of information being printed, such as`PASS` `FAIL`
`INFO` and `SKIP`.

For example, if we are printing a debug message for a test case called
"test_foo", the output might look like this:
[PASS] test_foo: Variable x has value 42.
