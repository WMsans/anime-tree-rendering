"""bpy: build tree objects and write <name>.glb + <name>.clumps.json (Y-up for Godot)."""
import json
import os

import bpy

from meshing import make_lod1, sweep_branches

PILLAR_RADIUS = 0.15


def to_godot_axes(v):
    """Blender Z-up -> glTF/Godot Y-up: (x, y, z) -> (x, z, -y)."""
    return (v[0], v[2], -v[1])


def _r(v):
    return [round(float(x), 5) for x in v]


def export_tree(tree, out_dir, name, preset, seed):
    os.makedirs(out_dir, exist_ok=True)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    make_lod1(sweep_branches(tree.branches, "Trunk_LOD0"))
    if tree.roots:
        sweep_branches(tree.roots, "Roots_LOD0")
        pillars = [r for r in tree.roots if r.radii[0] >= PILLAR_RADIUS]
        if pillars:
            make_lod1(sweep_branches(pillars, "Roots_LOD0_tmp")).name = "Roots_LOD1"
            bpy.data.objects.remove(bpy.data.objects["Roots_LOD0_tmp"])

    glb = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True,
                              export_vertex_color="ACTIVE", export_apply=True)
    js = os.path.join(out_dir, name + ".clumps.json")
    data = {"preset": preset, "seed": seed, "clumps": [
        {"center": _r(to_godot_axes(c.center)), "radius": round(c.radius, 5),
         "scale": _r(abs(x) for x in to_godot_axes(c.scale))} for c in tree.clumps]}
    with open(js, "w") as f:
        json.dump(data, f, indent=1)
    return glb, js
