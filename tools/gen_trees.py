"""Regenerates demo/assets/trees/*.glb with the generate_tree_plugin Blender extension.

Run from the repo root:
    blender -b --factory-startup -P tools/gen_trees.py -- demo/assets/trees
Then reimport in Godot: godot --headless --path . --import
"""
import bpy, sys
import os
out = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
bpy.ops.preferences.addon_enable(module="bl_ext.user_default.generate_tree_plugin")
TREES = [("tree_a", 84, 'ICOSPHERE'), ("tree_b", 7, 'ICOSPHERE'), ("tree_c", 1234, 'ICOSPHERE'),
         ("pine_a", 84, 'PINE'), ("pine_b", 42, 'PINE')]
for name, seed, foliage in TREES:
    for c in list(bpy.data.collections): bpy.data.collections.remove(c)
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    s = bpy.context.scene.tree_generator_settings
    s.tree.seed = seed
    s.leaves.generate_leaves = True
    s.leaves.leaf_material_count = 1
    s.leaves.foliage_type = foliage
    s.leaves.spherical_leaf_normals = True
    s.leaves.spherical_normal_center = 'ISLAND'
    assert bpy.ops.treegen.generate() == {'FINISHED'}, name
    leaf = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == 'MESH' and o.data.materials and o.data.materials[0].name.startswith("Leaf_"))
    print("GEN", name, "leaf faces", leaf, sorted({m.name for o in bpy.data.objects if o.type == 'MESH' for m in o.data.materials}))
    bpy.ops.export_scene.gltf(filepath=f"{out}/{name}.glb", export_format='GLB', export_normals=True, export_apply=True)
