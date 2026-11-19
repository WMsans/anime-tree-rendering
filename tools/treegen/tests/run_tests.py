"""Run treegen tests inside Blender: blender -b --python tools/treegen/tests/run_tests.py"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # tools/treegen
sys.path.insert(0, HERE)

pattern = os.environ.get("TREEGEN_TEST_PATTERN", "test_*.py")
suite = unittest.defaultTestLoader.discover(HERE, pattern=pattern)
result = unittest.TextTestRunner(verbosity=1).run(suite)
sys.exit(0 if result.wasSuccessful() else 1)
