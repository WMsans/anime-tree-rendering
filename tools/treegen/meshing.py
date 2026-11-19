"""bpy: sweep skeleton branches into tube meshes (UVs + moss color attribute)."""
import math

import bmesh
import bpy
from mathutils import Vector, noise

V_METERS = 2.0  # one bark-texture repeat per 2 m along the branch


def _frames(pts):
    """Parallel-transport normals along a polyline."""
    tangents = []
    for i in range(len(pts)):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        tangents.append((b - a).normalized())
    ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
    n = tangents[0].cross(ref).normalized()
    normals = [n]
    for i in range(1, len(pts)):
        n = (n - tangents[i] * n.dot(tangents[i])).normalized()
        normals.append(n)
    return tangents, normals


def sweep_branches(branches, name):
    """One tube per branch. U wraps around (seam duplicated), V = length / 2 m."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for br in branches:
        pts = [Vector(p) for p in br.points]
        sides = 8 if br.radii[0] > 0.3 else (5 if br.radii[0] > 0.06 else 4)
        tangents, normals = _frames(pts)
        rings, v_coord, dist = [], [], 0.0
        for i, (p, t, n, r) in enumerate(zip(pts, tangents, normals, br.radii)):
            if i:
                dist += (pts[i] - pts[i - 1]).length
            b = t.cross(n)
            ring = [bm.verts.new(p + (n * math.cos(a) + b * math.sin(a)) * r)
                    for a in (math.tau * s / sides for s in range(sides))]
            rings.append(ring)
            v_coord.append(dist / V_METERS)
        for i in range(len(rings) - 1):
            for s in range(sides):
                s2 = (s + 1) % sides
                f = bm.faces.new((rings[i][s], rings[i][s2], rings[i + 1][s2], rings[i + 1][s]))
                us = (s / sides, (s + 1) / sides)
                for loop, uv in zip(f.loops, ((us[0], v_coord[i]), (us[1], v_coord[i]),
                                              (us[1], v_coord[i + 1]), (us[0], v_coord[i + 1]))):
                    loop[uv_layer].uv = uv
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    _write_moss(mesh)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _write_moss(mesh):
    """Moss patches: noise-driven, biased to upward faces (spec §4)."""
    attr = mesh.color_attributes.new("moss", "FLOAT_COLOR", "POINT")
    for v, c in zip(mesh.vertices, attr.data):
        n = noise.noise(v.co * 0.6) * 0.5 + 0.5  # 0..1
        m = max(0.0, min(1.0, (n - 0.55) * 4.0 + max(0.0, v.normal.z) * 0.6))
        c.color = (m, m, m, 1.0)
    mesh.color_attributes.active_color = attr


def make_lod1(obj, ratio=0.3):
    lod = obj.copy()
    lod.data = obj.data.copy()
    lod.name = obj.name.replace("_LOD0", "") + "_LOD1"
    lod.data.name = lod.name
    bpy.context.scene.collection.objects.link(lod)
    mod = lod.modifiers.new("decimate", "DECIMATE")
    mod.ratio = ratio
    with bpy.context.temp_override(object=lod, active_object=lod, selected_objects=[lod]):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return lod
