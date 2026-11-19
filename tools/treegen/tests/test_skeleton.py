import math
import unittest

from presets import PRESETS
from skeleton import generate


def _dist(a, b):
    return math.dist(a, b)


class SkeletonTest(unittest.TestCase):
    def test_deterministic(self):
        self.assertEqual(generate(PRESETS["banyan"], 7), generate(PRESETS["banyan"], 7))

    def test_seeds_differ(self):
        a = generate(PRESETS["broadleaf"], 1)
        b = generate(PRESETS["broadleaf"], 2)
        self.assertNotEqual([c.center for c in a.clumps], [c.center for c in b.clumps])

    def test_trunk_base_at_origin(self):
        for name, p in PRESETS.items():
            t = generate(p, 1)
            self.assertEqual(t.branches[0].parent, -1, name)
            self.assertLess(_dist(t.branches[0].points[0], (0, 0, 0)), 1e-6, name)

    def test_height_in_range(self):
        for name, p in PRESETS.items():
            t = generate(p, 1)
            top = max([pt[2] for b in t.branches for pt in b.points]
                      + [c.center[2] + c.radius * c.scale[2] for c in t.clumps])
            self.assertGreater(top, p["height"] * 0.75, name)
            self.assertLess(top, p["height"] * 1.25, name)

    def test_radii_positive_and_taper(self):
        for name, p in PRESETS.items():
            t = generate(p, 1)
            for b in t.branches + t.roots:
                self.assertEqual(len(b.points), len(b.radii))
                self.assertTrue(all(r > 0 for r in b.radii), name)
            for b in t.branches[1:]:
                parent = t.branches[b.parent]
                i = min(range(len(parent.points)), key=lambda k: _dist(parent.points[k], b.points[0]))
                self.assertLessEqual(b.radii[0], parent.radii[i] + 1e-6, name)

    def test_clumps_near_branch_tips(self):
        for name, p in PRESETS.items():
            t = generate(p, 1)
            pts = [pt for b in t.branches if b.depth >= 1 for pt in b.points]
            for c in t.clumps:
                d = min(_dist(c.center, q) for q in pts)
                self.assertLess(d, c.radius * 1.5, name)

    def test_banyan_has_ground_roots(self):
        p = PRESETS["banyan"]
        t = generate(p, 1)
        self.assertEqual(len(t.roots), p["aerial_roots"])
        self.assertTrue(any(r.points[-1][2] < 0.1 for r in t.roots))

    def test_leaning_offsets_top(self):
        p = PRESETS["leaning"]
        t = generate(p, 1)
        top = t.branches[0].points[-1]
        self.assertGreater(math.hypot(top[0], top[1]), p["height"] * math.sin(math.radians(p["lean_deg"])) * 0.5)

    def test_all_presets_generate(self):
        for name, p in PRESETS.items():
            t = generate(p, 3)
            self.assertGreaterEqual(len(t.clumps), 3, name)
            for b in t.branches + t.roots:
                for pt in b.points:
                    self.assertFalse(any(math.isnan(v) for v in pt), name)
