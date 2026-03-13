#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import logging
import random

from virttest import env_process
from virttest import error_context
from provider import dmesg_router  # pylint: disable=unused-import

LOG = logging.getLogger("avocado.test")


def _host_available_mem_mb():
    """Return host available memory in MB from /proc/meminfo."""
    with open("/proc/meminfo", "r", encoding="utf-8") as meminfo:
        for line in meminfo:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) // 1024
    raise RuntimeError("Cannot read host available memory from /proc/meminfo")


def _parse_series(raw_value):
    """Parse a whitespace-separated string into a list of strings."""
    if raw_value is None or str(raw_value).strip() == "":
        return []
    return [item for item in str(raw_value).split() if item]


def _parse_int_series(raw_value, key_name):
    """Parse a whitespace-separated string into a list of integers."""
    values = _parse_series(raw_value)
    parsed = []
    for value in values:
        try:
            parsed.append(int(value))
        except ValueError as exc:
            raise ValueError(
                "Invalid integer value '%s' in %s" % (value, key_name)
            ) from exc
    return parsed


def _calc_default_mem_series(params, vm_names):
    """
    Calculate a default memory series based on the generator type.

    Supported generators:
      - linear: increments by mem_step from start_mem to memory_limit
      - random_32g_window: random samples within sliding 32G windows
    """
    mem_generator = params.get("mem_generator", "linear")
    start_mem = int(params.get_numeric("start_mem", 1024))
    # Default 1024MB; override via cfg "start_mem = <value>"
    mem_step = int(params.get_numeric("mem_step", 128))
    max_mem_raw = params.get("max_mem")
    divide_host_mem_limit_by_vm_count = (
        params.get("divide_host_mem_limit_by_vm_count", "yes") == "yes"
    )

    host_available_mem = _host_available_mem_mb()
    memory_limit = host_available_mem
    if divide_host_mem_limit_by_vm_count:
        memory_limit = host_available_mem // max(1, len(vm_names))

    if max_mem_raw:
        memory_limit = min(memory_limit, int(max_mem_raw))

    if start_mem > memory_limit:
        LOG.warning("start_mem (%s) > memory_limit (%s), no iterations",
                    start_mem, memory_limit)
        return []

    if mem_generator == "random_32g_window":
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
            window_end = min(base + window_size, memory_limit)
            max_steps = (window_end - base) // random_unit if random_unit > 0 else 0
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

        # Always include boundary values
        if start_mem not in series:
            series.insert(0, start_mem)
        if memory_limit not in series and memory_limit >= start_mem:
            series.append(memory_limit)

        series = sorted(set(series))
        return series

    # Default: linear generator
    series = []
    current_mem = start_mem
    while current_mem <= memory_limit:
        series.append(current_mem)
        current_mem += mem_step
    return series


def _resolve_iteration_plan(params, vm_names):
    """
    Build a list of per-iteration parameter overrides for each VM.

    Returns a list of dicts:
      [ {vm_name: {param_name: value, ...}, ...}, ... ]
    """
    loop_params = _parse_series(params.get("loop_params", "mem"))
    vm_overrides = {vm_name: {} for vm_name in vm_names}
    iteration_count = int(params.get_numeric("multi_boot_iterations", 0))

    for param_name in loop_params:
        global_key = "%s_series" % param_name
        global_series = _parse_series(params.get(global_key))
        if global_series:
            iteration_count = max(iteration_count, len(global_series))

        for vm_name in vm_names:
            vm_key = "%s_series_%s" % (param_name, vm_name)
            vm_series = _parse_series(params.get(vm_key))
            if vm_series:
                iteration_count = max(iteration_count, len(vm_series))

    if iteration_count == 0:
        mem_series = _parse_int_series(params.get("mem_series"), "mem_series")
        if mem_series:
            iteration_count = len(mem_series)
            for vm_name in vm_names:
                vm_overrides[vm_name]["mem"] = [
                    str(value) for value in mem_series
                ]
        else:
            default_mem_series = _calc_default_mem_series(params, vm_names)
            iteration_count = len(default_mem_series)
            for vm_name in vm_names:
                vm_overrides[vm_name]["mem"] = [
                    str(value) for value in default_mem_series
                ]
    else:
        for param_name in loop_params:
            global_key = "%s_series" % param_name
            global_series = _parse_series(params.get(global_key))
            if global_series and len(global_series) not in (
                1,
                iteration_count,
            ):
                raise ValueError(
                    "%s length (%s) must be 1 or iterations (%s)"
                    % (global_key, len(global_series), iteration_count)
                )

            for vm_name in vm_names:
                vm_key = "%s_series_%s" % (param_name, vm_name)
                vm_series = _parse_series(params.get(vm_key))
                active_series = vm_series if vm_series else global_series
                if not active_series:
                    continue
                if len(active_series) not in (1, iteration_count):
                    raise ValueError(
                        "%s length (%s) must be 1 or iterations (%s)"
                        % (
                            vm_key if vm_series else global_key,
                            len(active_series),
                            iteration_count,
                        )
                    )
                if len(active_series) == 1:
                    active_series = active_series * iteration_count
                vm_overrides[vm_name][param_name] = [
                    str(value) for value in active_series
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

    timeout = int(params.get_numeric("login_timeout", 240))
    serial_login = params.get("serial_login", "no") == "yes"

    vm_names = params.objects("vms")
    if not vm_names:
        test.cancel("No VMs configured for multi_vms_multi_boot")

    try:
        iteration_plan = _resolve_iteration_plan(params, vm_names)
    except ValueError as error:
        test.cancel(str(error))

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
                for key, value in vm_param_overrides.get(
                    vm_name, {}
                ).items():
                    vm_params[key] = value
                env_process.preprocess_vm(test, vm_params, env, vm_name)
                started_vms.append(env.get_vm(vm_name))

            for vm in started_vms:
                vm.verify_alive()
                if serial_login:
                    session = vm.wait_for_serial_login(timeout=timeout)
                else:
                    session = vm.wait_for_login(timeout=timeout)
                session.close()
        finally:
            for vm in started_vms:
                vm.destroy(gracefully=False)
