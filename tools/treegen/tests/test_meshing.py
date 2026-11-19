import unittest

import bpy

from meshing import make_lod1, sweep_branches
from presets import PRESETS
from skeleton import generate

BUDGET = {"banyan": 15000}


def tris(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


class MeshingTest(unittest.TestCase):
    def setUp(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)

    def test_sweep_has_uv_and_moss(self):
        obj = sweep_branches(generate(PRESETS["broadleaf"], 1).branches, "Trunk_LOD0")
        self.assertEqual(len(obj.data.uv_layers), 1)
        moss = obj.data.color_attributes.get("moss")
        self.assertIsNotNone(moss)
        vals = [c.color[0] for c in moss.data]
        self.assertTrue(all(0.0 <= v <= 1.0 for v in vals))
        self.assertGreater(max(vals), 0.0)

    def test_lod1_ratio(self):
        lod0 = sweep_branches(generate(PRESETS["leaning"], 1).branches, "Trunk_LOD0")
        lod1 = make_lod1(lod0)
        self.assertEqual(lod1.name, "Trunk_LOD1")
        self.assertGreater(tris(lod1), 0)
        self.assertLessEqual(tris(lod1), 0.35 * tris(lod0))

    def test_budgets(self):
        for name, p in PRESETS.items():
            obj = sweep_branches(generate(p, 1).branches, "Trunk_LOD0")
            self.assertLessEqual(tris(obj), BUDGET.get(name, 6000), name)
