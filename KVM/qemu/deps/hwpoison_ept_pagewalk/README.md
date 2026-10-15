# Hardware-poisoned EPT pagewalk test

`hwpoison_ept_pagewalk.cfg` is an Avocado VT test of the DMR KVM EPT poison
recovery path. It requires a dedicated host with the recovery kernel and the
`print_sptes` / forced EPT TLB flush debug patches, platform EINJ support,
root on host and guest, and guest `gcc`.

## Kernel debugfs SPTE contract

The following known-good reference implementation was authored by Qiuxu Zhuo
<qiuxu.zhuo@intel.com> on 2025-07-28. It is included to preserve the original
control flow when the relevant KVM internals change; it is not a stable kernel
ABI and may need adaptation for a newer kernel.

```c
/* Source: arch/x86/kvm/debugfs.c */
static int dbgfs_print_sptes(void *data, u64 val)
{
	struct kvm *kvm = (struct kvm *)data;
	gpa_t gpa = (gpa_t)val;
	struct kvm_vcpu *vcpu;

	if (!gpa) {
		pr_err("Invalid GPA.\n");
		return -EINVAL;
	}

	if (!kvm) {
		pr_err("No KVM instance.\n");
		return -ENOENT;
	}

	vcpu = kvm_get_vcpu(kvm, 0);

	kvm_mmu_print_sptes(vcpu, gpa, "GPA");
	kvm_flush_remote_tlbs(kvm);

	return 0;
}
DEFINE_SIMPLE_ATTRIBUTE(fops_print_sptes, NULL, dbgfs_print_sptes, "%llu\n");

void kvm_arch_create_vm_debugfs(struct kvm *kvm)
{
	debugfs_create_file("mmu_rmaps_stat", 0644, kvm->debugfs_dentry, kvm,
			    &mmu_rmaps_stat_fops);
	debugfs_create_file("print_sptes", 0666, kvm->debugfs_dentry, kvm,
			    &fops_print_sptes);
}
```

The kernel implementation may change, but the testcase depends on this
externally observable contract:

1. A writable per-VM `print_sptes` node exists. By default the testcase looks
	under `/sys/kernel/debug/kvm/<qemu-pid>-*/print_sptes`; `spte_debugfs` can
	override the path. The testcase runs as root and does not require a
	particular file mode.
2. Writing one GPA, including `0x`-prefixed input, emits a new kernel log
	record for that exact GPA. The record contains a complete, contiguous
	four- or five-level chain in this form:

	```text
	kvm: GPA 10ea8d000, spte[5] = 0x..., ..., spte[2] = 0x..., spte[1] = 0x...
	```

3. `spte[2]` points to the level-1 EPT page-table page. For a 4 KB mapping,
	bits GPA[20:12] select the eight-byte PTE within that page. The testcase
	poisons the 64-byte cache line containing that PTE; it does not poison the
	guest-data HPA in `spte[1]`.
4. All non-leaf entries are present and are not large-page leaves. The
	testcase rejects an incomplete chain or a large-page leaf above level 1.
5. The remote EPT TLB flush completes before the debugfs write returns. The
	testcase pauses the VM, writes the GPA, waits for the SPTE record, and only
	then performs EINJ. This ordering ensures that the later guest access must
	walk the EPT after its PTE cache line has been poisoned.

The sample in the reference patch ends at a large-page `spte[2]`. That output
is useful for inspecting non-leaf EPT pages, but it is not sufficient for this
testcase. The guest victim executes its target page and the host enables
`nx_huge_pages=force` so KVM creates a 4 KB mapping with `spte[1]`. If a newer
kernel still reports a large-page leaf, the testcase cancels rather than
injecting into an ambiguous address.

When rebasing or replacing the kernel patch, preserve the semantic contract
above instead of the current `debugfs.c` location, internal helper signatures,
or `0666` reference file mode. Validate the replacement in two stages:

1. Run with `perform_injection=no`. Confirm that the logged GPA matches the
	guest GPA, the chain includes `spte[1]`, and the reported PT, PTE HPA, and
	cache-line HPA agree with the offline parser check below.
2. Run once with `perform_injection=yes` on the dedicated test host. Confirm
	that no matching MCE is consumed during SPTE capture, EINJ, or VM resume,
	and that the explicit guest load produces the target address and MCACOD,
	terminates QEMU, and leaves the host running.

The test **does not stop unrelated VMs**. It refuses to reload KVM while
another process owns `/dev/kvm`. Stop those VMs before starting the test.
The default `prepare_host=yes` disables THP and reloads `kvm` with
`nx_huge_pages=force` and `kvm_intel` with `ept=1`. It restores the original
THP setting at normal test exit; it does not revert loaded module parameters.
Set `prepare_host=no` to use an already prepared host; all settings are still
checked before launching the VM.

Run once with `perform_injection=no` to record the GPA, SPTE chain, PTE HPA and
64-byte injection HPA without poisoning memory. Then set
`perform_injection=yes` and run **once** on the test hardware. The test
defaults to `einj_mask=0xffffffffffffffff`, matching the reported manual
experiment; configure this value if the firmware requires another mask.

The guest program executes the chosen page before announcing `READY`, then
blocks on a FIFO. After the VM is paused, its SPTE is inspected and its EPT
PTE cache line is poisoned. The VM is resumed, and the FIFO releases one
`volatile` data load. A PASS requires the host MCA record to contain the
target cache-line address and MCACOD `0x1a4`, QEMU to exit, and the host test
process to survive for `host_survival_seconds` with the same boot ID.

The full kernel records collected during the test are saved in the Avocado
per-test result directory alongside `debug.log` as `ept_poison_host_kmsg.log`.
If the host reboots or panics, an external job controller or serial console
must record that outcome; a
rebooted in-host test process cannot report its own failure. If injection
starts but the VM survives, the test leaves that VM in place for inspection:
avoid an automatic retry while its EPT PT page may still be poisoned.

Offline address and MCE parser check:

```sh
python3 KVM/qemu/deps/hwpoison_ept_pagewalk/test_address.py
```
