#!/usr/bin/env python3
"""A zero-exit Godot missing-script/error must not count as a test pass."""
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import build_preview
class PreviewErrorTest(unittest.TestCase):
    def test_missing_script_and_engine_errors_are_fatal(self):
        for output in ["ERROR: Can't load script: res://tests/missing.gd\n", "SCRIPT ERROR: invalid test\n", "ADAPTIVE_FAIL_pressure\n"]:
            with self.subTest(output=output), patch.object(build_preview.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=output,stderr='')):
                with self.assertRaises(RuntimeError):build_preview.run(['godot'],{})
    def test_clean_output_is_preserved(self):
        with patch.object(build_preview.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout='ADAPTIVE_PASS_pressure\n',stderr='')):
            self.assertEqual(build_preview.run(['godot'],{}),'ADAPTIVE_PASS_pressure\n')
if __name__=='__main__':unittest.main()
