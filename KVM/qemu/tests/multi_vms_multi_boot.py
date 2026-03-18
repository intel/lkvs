#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import logging
import random

from virttest import env_process
from virttest import error_context
from virttest import utils_misc
from provider import dmesg_router  # pylint: disable=unused-import

LOG = logging.getLogger("avocado.test")


def _calc_default_mem_series(params, vm_names):
    """
    Calculate a default memory series based on the generator type.

    Supported generators:
      - linear: increments by mem_step from start_mem to memory_limit
      - random_32g_window: random samples within sliding 32G windows
    """
    # Supported: "linear" (default fallback) or "random_32g_window" (used by current cfg)
    mem_generator = params.get("mem_generator", "linear")
    # Default 1024MB; override via cfg "start_mem = <value>"
    start_mem = int(params.get_numeric("start_mem", 1024))
    # Only used by linear generator; ignored by random_32g_window
    mem_step = int(params.get_numeric("mem_step", 128))
    # Optional cap on memory_limit; if not set in cfg, defaults to host free memory
    max_mem_raw = params.get("max_mem")
    divide_host_mem_limit_by_vm_count = (
        params.get("divide_host_mem_limit_by_vm_count", "yes") == "yes"
    )

    memory_limit = int(utils_misc.get_usable_memory_size())
    if divide_host_mem_limit_by_vm_count:
        memory_limit = memory_limit // max(1, len(vm_names))

    if max_mem_raw:
        memory_limit = min(memory_limit, int(max_mem_raw))

    if start_mem > memory_limit:
        LOG.warning("start_mem (%s) > memory_limit (%s), no iterations",
                    start_mem, memory_limit)
        return []

    if mem_generator == "random_32g_window":
        # All params below are read from cfg; values here are fallback defaults
        random_min = int(params.get_numeric("random_min", 0))
        random_max = int(params.get_numeric("random_max", 64))
        random_unit = int(params.get_numeric("random_unit", 511))
        samples_per_window = int(params.get_numeric("samples_per_window", 2))
        window_size = int(params.get_numeric("window_size", 32768))
        random_seed = params.get("random_seed")
        if random_seed is not None:
            random.seed(int(random_seed))

        series = []
        base = start_mem
        while base <= memory_limit:
            max_steps = (
                (min(base + window_size, memory_limit) - base) // random_unit
                if random_unit > 0 else 0
            )
            effective_max = min(random_max, max_steps)
            effective_min = min(random_min, effective_max)
            for _ in range(samples_per_window):
                if effective_min > effective_max:
                    series.append(base)
                else:
                    random_step = random.randint(effective_min, effective_max)
                    mem_value = base + random_step * random_unit
                    series.append(mem_value)
            base += window_size

        if start_mem not in series:
            series.insert(0, start_mem)
        if memory_limit not in series and memory_limit >= start_mem:
            series.append(memory_limit)

        return sorted(set(series))

    series = []
    current_mem = start_mem
    while current_mem <= memory_limit:
        series.append(current_mem)
        current_mem += mem_step
    return series


def _resolve_iteration_plan(params, vm_names):
    """
    Build a list of per-iteration memory overrides for each VM.

    Returns a list of dicts:
      [ {vm_name: {"mem": value}}, ... ]
    """
    vm_overrides = {vm_name: {} for vm_name in vm_names}

    default_mem_series = _calc_default_mem_series(params, vm_names)
    iteration_count = len(default_mem_series)
    for vm_name in vm_names:
        vm_overrides[vm_name]["mem"] = [
            str(value) for value in default_mem_series
        ]

    if iteration_count <= 0:
        return []

    plan = []
    for index in range(iteration_count):
        iteration_item = {}
        for vm_name in vm_names:
            iteration_item[vm_name] = {}
            for param_name, values in vm_overrides[vm_name].items():
                iteration_item[vm_name][param_name] = values[index]
        plan.append(iteration_item)
    return plan


@error_context.context_aware
def run(test, params, env):
    """
    Boot multiple VMs with per-iteration parameter overrides:
    1) Boot all VMs with current iteration parameters
    2) Verify all guests can login
    3) Destroy all VMs
    4) Repeat for all iterations

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    if params.get("boot_destroy_cycle", "no") == "yes":
        run_boot_destroy_cycle(test, params, env)
        return

    timeout = int(params.get_numeric("login_timeout", 240))

    vm_names = params.objects("vms")
    if not vm_names:
        test.cancel("No VMs configured for multi_vms_multi_boot")

    iteration_plan = _resolve_iteration_plan(params, vm_names)

    if not iteration_plan:
        test.cancel("No valid iterations resolved for multi_vms_multi_boot")

    test.log.info("Total iterations: %s, VMs per iteration: %s",
                  len(iteration_plan), len(vm_names))

    for iteration, vm_param_overrides in enumerate(iteration_plan, start=1):
        started_vms = []
        try:
            override_desc = ", ".join(
                "%s(mem=%s)" % (vm_name, vm_param_overrides.get(vm_name, {}).get("mem", "default"))
                for vm_name in vm_names
            )
            error_context.context(
                "Iteration %s/%s: %s"
                % (iteration, len(iteration_plan), override_desc),
                test.log.info,
            )

            for vm_name in vm_names:
                vm_params = params.object_params(vm_name)
                vm_params["start_vm"] = "yes"
                for key, value in vm_param_overrides.get(vm_name, {}).items():
                    vm_params[key] = value
                env_process.preprocess_vm(test, vm_params, env, vm_name)
                started_vms.append(env.get_vm(vm_name))

            for vm in started_vms:
                vm.verify_alive()
                session = vm.wait_for_login(timeout=timeout)
                session.close()
        finally:
            for vm in started_vms:
                vm.destroy(gracefully=False)


@error_context.context_aware
def run_boot_destroy_cycle(test, params, env):
    """
    Boot and destroy VM cycle repeated 20 times:
    1) Boot the VM
    2) Verify guest can login
    3) Destroy the VM
    4) Repeat 20 times

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    timeout = int(params.get_numeric("login_timeout", 240))
    cycle_count = int(params.get_numeric("boot_destroy_cycles", 20))

    vm_names = params.objects("vms")
    if not vm_names:
        test.cancel("No VMs configured for boot_destroy_cycle")

    vm_name = vm_names[0]  # Use the first VM
    test.log.info("Starting boot/destroy cycle test: %s cycles", cycle_count)

    for cycle in range(1, cycle_count + 1):
        started_vms = []
        try:
            error_context.context(
                "Boot/Destroy Cycle %s/%s" % (cycle, cycle_count),
                test.log.info,
            )

            vm_params = params.object_params(vm_name)
            vm_params["start_vm"] = "yes"
            env_process.preprocess_vm(test, vm_params, env, vm_name)
            vm = env.get_vm(vm_name)
            started_vms.append(vm)

            # Verify VM is alive and can login
            vm.verify_alive()
            session = vm.wait_for_login(timeout=timeout)
            session.close()
            test.log.info("Cycle %s/%s: VM login successful", cycle, cycle_count)

        finally:
            # Destroy the VM
            for vm in started_vms:
                vm.destroy(gracefully=False)
            test.log.info("Cycle %s/%s: VM destroyed", cycle, cycle_count)
