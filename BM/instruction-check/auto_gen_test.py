#!/usr/bin/python
import os
from feature_list import feature_list
from feature_list import get_platform

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
        feature_name_list = feature_list.keys()
        platform = get_platform()
        for feature_name in feature_name_list:
            if platform in feature_list[feature_name]["platforms"]:
                args = feature_list[feature_name]["cpuid"]
                class_code =  class_template.format(class_name=feature_name, args=args)
                f.write(class_code)
            else:
                continue

generate_cpuid_tests()