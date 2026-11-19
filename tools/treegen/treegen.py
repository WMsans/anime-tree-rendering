"""CLI: blender -b --python tools/treegen/treegen.py -- --preset banyan --seed 3 --out assets/trees"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from export import export_tree  # noqa: E402
from presets import PRESETS  # noqa: E402
from skeleton import generate  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--preset", required=True, choices=sorted(PRESETS))
ap.add_argument("--seed", type=int, required=True)
ap.add_argument("--out", required=True)
a = ap.parse_args(argv)
name = f"{a.preset}_{a.seed:03d}"
glb, js = export_tree(generate(PRESETS[a.preset], a.seed), a.out, name, a.preset, a.seed)
print("wrote", glb, js)
