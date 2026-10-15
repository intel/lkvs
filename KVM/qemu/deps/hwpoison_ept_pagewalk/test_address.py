#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
"""Offline guardrails for calculating a hardware-poison injection address."""

import pathlib
import sys
import unittest


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))
from provider import ept_poison_utils as ept  # noqa: E402


GPA = 0x10EA8D000
SPTE_LINE = (
    "kvm: GPA 10ea8d000, spte[5] = 0x8000000118d1d907, "
    "spte[4] = 0x8000000118d21907, spte[3] = 0x80000001283d8907, "
    "spte[2] = 0x8000000124c7a907, spte[1] = 0x860000017f54eb77"
)


class PoisonAddressTests(unittest.TestCase):
    def test_real_ept_spte_and_injection_address(self):
        mapping = ept.parse_spte_line(SPTE_LINE, GPA)
        self.assertEqual(mapping["index"], 0x8D)
        self.assertEqual(mapping["pt_base"], 0x124C7A000)
        self.assertEqual(mapping["pte_hpa"], 0x124C7A468)
        self.assertEqual(mapping["poison_cl"], 0x124C7A440)

    def test_reject_large_leaf_or_wrong_gpa(self):
        with self.assertRaises(ValueError):
            ept.parse_spte_line(SPTE_LINE, GPA + 0x1000)
        large = SPTE_LINE.replace("spte[2] = 0x8000000124c7a907",
                                  "spte[2] = 0x8000000124c7a987")
        with self.assertRaises(ValueError):
            ept.parse_spte_line(large, GPA)

    def test_mce_requires_address_and_mcacod_in_one_event(self):
        correct = [
            "mce: CPU 0: Machine Check Exception: f Bank 1: bd800000001101a4",
            "mce: TSC 18a070cc061 ADDR 124c7a440 MISC 86",
        ]
        self.assertEqual(ept.find_mce(correct, 0x124C7A440, 0x1A4),
                         (1, 0xBD800000001101A4, 0x124C7A440))
        self.assertIsNone(ept.find_mce(correct, 0x124C7A440, 0x194))
        unrelated = [correct[0], "mce: Bank 2: bd80000000110194", correct[1]]
        self.assertIsNone(ept.find_mce(unrelated, 0x124C7A440, 0x1A4))


if __name__ == "__main__":
    unittest.main()
