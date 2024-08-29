# Trust Platform Module

## Description
Trust Platform Module(TPM) is a physical or embedded security technology
(microcontroller) that resides on a computer's motherboard or in its processor.
TPMs use cryptography to help securely store essential and critical information
on PCs to enable platform authentication.

The Intel® PTT is an integrated TPM that adheres to the 2.0 specifications
and offers the same capabilities of a discrete TPM, only it resides in the
system’s firmware, thus removing the need for dedicated processing or memory
resources.

TPM2 smoke test: test_smoke.sh
```
# python3 -m unittest -v tpm2_tests.SmokeTest
test_read_partial_overwrite (tpm2_tests.SmokeTest) ... ok
test_read_partial_resp (tpm2_tests.SmokeTest) ... ok
test_seal_with_auth (tpm2_tests.SmokeTest) ... ok
test_seal_with_policy (tpm2_tests.SmokeTest) ... ok
test_seal_with_too_long_auth (tpm2_tests.SmokeTest) ... ok
test_send_two_cmds (tpm2_tests.SmokeTest) ... ok
test_too_short_cmd (tpm2_tests.SmokeTest) ... ok
test_unseal_with_wrong_auth (tpm2_tests.SmokeTest) ... ok
test_unseal_with_wrong_policy (tpm2_tests.SmokeTest) ... ok

----------------------------------------------------------------------
Ran 9 tests in 293.561s

OK
```

TPM2 space content test: test_space.sh
```
# python3 -m unittest -v tpm2_tests.SpaceTest
test_flush_context (tpm2_tests.SpaceTest) ... ok
test_get_handles (tpm2_tests.SpaceTest) ... ok
test_invalid_cc (tpm2_tests.SpaceTest) ... ok
test_make_two_spaces (tpm2_tests.SpaceTest) ... ok

----------------------------------------------------------------------
Ran 4 tests in 261.409s

OK
```


TPM2 sync test: test_async.sh
```
# python3 -m unittest -v tpm2_tests.AsyncTest
test_async (tpm2_tests.AsyncTest) ... ok
test_flush_invalid_context (tpm2_tests.AsyncTest) ... ok

----------------------------------------------------------------------
Ran 2 tests in 0.004s

OK
```

## Expected result
All test results should show pass, no fail.
