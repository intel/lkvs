#!/usr/bin/python
import os
from feature_list import cpuid_info

# Template string, used to generate code for each test class
class_template = """
class {class_name}(Test):
    def test(self):
        cmd = os.path.join(source_dir, file_name + ' ' + ' '.join({args}))
        cmd_result = process.run(cmd, ignore_status=True)
        self.assertEqual(cmd_result.exit_status, expected_result)
"""

def generate_cpuid_tests():
    with open('cpuid_test.py', 'w') as f:
        script_dir = os.path.dirname(__file__)
        parent_dir = os.path.dirname(script_dir)
        grandparent_dir = os.path.dirname(parent_dir)
        source_dir = f"{grandparent_dir}/tools/cpuid_check"
        # Write the necessary imports and variable definitions
        f.write(f'''#!/usr/bin/python

import os
from avocado import Test
from avocado.utils import process

source_dir = "{source_dir}"
file_name = "cpuid_check"
expected_result = 0
''')
        # For each feature in feature_list.py generates a test class
        for feature, args in cpuid_info.items():
            class_code = class_template.format(class_name=feature, args=args)
            f.write(class_code)

generate_cpuid_tests()