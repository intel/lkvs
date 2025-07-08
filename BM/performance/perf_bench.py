#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

"""
This script performs the predefined benchmark testing via perf tool
Covers the CPU, Memory, I/O, Algorithm performance

Prerequisites:
Install the avocado framework and the required dependencies with below command:
    git clone git://github.com/avocado-framework/avocado.git
    cd avocado
    pip install .
"""

import subprocess
import re
import os
import argparse
import pty
import select
import sys

__author__ = "Wendy Wang"
__copyright__ = "GPL-2.0-only"
__license__ = "GPL version 2"

# Determine the directory of the current script
script_dir = os.path.dirname(os.path.abspath(__file__))

# Construct relative paths to the common.sh file
common_sh_path = os.path.join(script_dir, '../common/common.sh')


class ShellCommandRunnable():
    """Initialize the ShellCommandRunnable class."""

    def __init__(self, command):
        self.command = command
        self.stdout = ""
        self.stderr = ""

    def run(self):
        """Run the shell command in a pseudo-terminal(PTY) and capture its output.
        It handles both standard output and error, waits for the process to finish,
        and checks for any issues such as timeout or failures."""
        try:
            # Create a pseudo-terminal (PTY) pair
            master_fd, slave_fd = pty.openpty()

            # Define the environment to simulate a TTY for color support
            env = os.environ.copy()
            # Set TERM to a terminal that supports colors
            env['TERM'] = 'xterm-256color'

            # Run the perf command with the PTY (both stdout and stderr will be sent to the PTY)
            process = subprocess.Popen(
                self.command,
                shell=True,
                stdout=slave_fd,
                stderr=slave_fd,
                text=True,
                env=env,
                executable='/bin/bash'
            )

            # Read the output from the master end of the PTY
            output = ""
            try:
                while True:
                    rlist, _, _ = select.select([master_fd], [], [], 0.1)
                    if rlist:
                        part_output = os.read(master_fd, 1024).decode()
                        if not part_output:
                            break
                        output += part_output
                        print(part_output, end="")
                    else:
                        if process.poll() is not None:
                            break
            except Exception as e:
                print(f"Error reading output: {e}")
                sys.exit(1)

            # Close the slave_fd to stop output to the PTY
            os.close(slave_fd)

            # Wait for the process to finish with timeout
            try:
                process.wait(timeout=60)
            except subprocess.TimeoutExpired:
                print("Process tool too long to complete, terminating it.")
                os.killpg(os.getpgid(process.pid),
                          subprocess.signal.SIGTERM)
                process.wait()

            # Ensure process has terminated
            return_code = process.returncode
            if return_code != 0:
                print(f"Perf command failed with return code {return_code}")

            # Analyze output for color codes
            self.analyze_output(output)

            return return_code

        except (subprocess.CalledProcessError, OSError) as e:
            print(f"Error running perf bench: {e}")
            sys.exit(1)

        return 0

    def analyze_output(self, output):
        """Analyze the output of the perf command for any potential color codes or failures
        It check each line for the output for color codes and flags them if found."""
        # Check for any ANSI color codes in the output
        ansi_color_pattern = re.compile(r'\033\[[0-9;]*m')
        fail_lines = []

        if fail_lines:
            print(f"Raw output:\n{output}\n")

        for line in output.splitlines():
            # Skip empty lines
            if not line.strip():
                continue

            print(f"Checking line: {line}")
            # If the line contains ANSI color characters
            if ansi_color_pattern.search(line):
                print(f"Found color output(potential failure): {line}")
                fail_lines.append(line)
        if fail_lines:
            print("Failure detected in the following lines:")
            for line in fail_lines:
                print(line)
            sys.exit(1)


def check_dmesg_error():
    """Check the dmesg log for any failure or error messages."""
    result = ShellCommandRunnable(
        f"source {common_sh_path} && extract_case_dmesg")
    result.run()
    dmesg_log = result.stdout

    # Check any failure, error, bug in the dmesg log when stress is running
    if dmesg_log and any(keyword in dmesg_log for keyword in
                         ["fail", "error", "Call Trace", "Bug", "error"]):
        return dmesg_log
    return None


def run_perf_bench(bench_feature, feature_option):
    """Run perf stat check when running perf benchmarks testing."""
    try:
        # Define the perf command
        perf_command = (
            f"perf stat -e cycles,instructions,cache-references,cache-misses,"
            f"branch,branch-misses perf bench {bench_feature} {feature_option}"
        )
        # Run the perf command using ShellCommandRunnable
        result = ShellCommandRunnable(perf_command)
        exit_code = result.run()
        if exit_code != 0:
            print("Perf benchmark failed")
            sys.exit(1)

    except Exception as e:
        print(f"Error running perf bench: {e}")
        sys.exit(1)

    # Check dmesg log
    dmesg_log = check_dmesg_error()
    if dmesg_log:
        print(
            f"Kernel dmesg shows failure after perf bench testing: {dmesg_log}")
        sys.exit(1)

    print("Perf benchmark and dmesg check completed successfully")
    return 0


# Create an ArgumentParser object
parser = argparse.ArgumentParser(description="Running perf benchmark testing")

# Add the perf bench command arguments
parser.add_argument('--bench_feature', type=str,
                    default="mem", help="perf bench feature name")
parser.add_argument('--feature_option', type=str,
                    default="find_bit", help="perf bench feature option")

# Parse the command-line arguments
args = parser.parse_args()

# Run the perf bench command
if __name__ == '__main__':
    run_perf_bench(args.bench_feature, args.feature_option)
