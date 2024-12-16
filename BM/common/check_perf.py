#!/usr/bin/env python3

import subprocess

def check_perf_installed():
    try:
        result = subprocess.run(['perf', '--version'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        if result.returncode == 0:
            print("Version:", result.stdout.decode().strip())
            return True
        else:
            print("Perf tool is not installed")
            return False
    except Exception as e:
        print("An error occurred:", str(e))
        return False

if __name__ == '__main__':
    check_perf_installed()
