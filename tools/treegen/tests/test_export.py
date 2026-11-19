import json
import os
import tempfile
import unittest

import bpy

from export import export_tree, to_godot_axes
from presets import PRESETS
from skeleton import generate


class ExportTest(unittest.TestCase):
    def setUp(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)

    def test_to_godot_axes(self):
        self.assertEqual(to_godot_axes((1, 2, 3)), (1, 3, -2))

    def test_export_files(self):
        tree = generate(PRESETS["banyan"], 1)
        with tempfile.TemporaryDirectory() as d:
            glb, js = export_tree(tree, d, "banyan_001", "banyan", 1)
            self.assertTrue(os.path.isfile(glb))
            data = json.load(open(js))
            self.assertEqual(data["preset"], "banyan")
            self.assertEqual(data["seed"], 1)
            self.assertEqual(len(data["clumps"]), len(tree.clumps))
            for got, want in zip(data["clumps"][0]["center"], to_godot_axes(tree.clumps[0].center)):
                self.assertAlmostEqual(got, want, places=5)

    def test_export_deterministic(self):
        with tempfile.TemporaryDirectory() as d:
            _, js1 = export_tree(generate(PRESETS["broadleaf"], 4), d, "a", "broadleaf", 4)
            bpy.ops.wm.read_factory_settings(use_empty=True)
            _, js2 = export_tree(generate(PRESETS["broadleaf"], 4), d, "b", "broadleaf", 4)
            self.assertEqual(open(js1, "rb").read(), open(js2, "rb").read())
