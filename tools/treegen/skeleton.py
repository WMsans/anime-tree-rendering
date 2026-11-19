"""Seeded tree skeleton generator. Pure Python (no bpy). Blender Z-up, meters."""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

Vec3 = tuple[float, float, float]


@dataclass
class Branch:
    points: list[Vec3]
    radii: list[float]
    depth: int
    parent: int  # -1 for trunk


@dataclass
class Clump:
    center: Vec3
    radius: float
    scale: Vec3


@dataclass
class Tree:
    branches: list[Branch] = field(default_factory=list)
    roots: list[Branch] = field(default_factory=list)
    clumps: list[Clump] = field(default_factory=list)


# --- tiny vector helpers -------------------------------------------------------
def _add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def _mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def _cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def _dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _norm(a):
    n = math.sqrt(_dot(a, a)) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def _rotate(v, axis, ang):
    """Rodrigues rotation of v around unit axis."""
    c, s = math.cos(ang), math.sin(ang)
    return _add(_add(_mul(v, c), _mul(_cross(axis, v), s)), _mul(axis, _dot(axis, v) * (1 - c)))


def _perp(d):
    ref = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    return _norm(_cross(d, ref))


def _polyline(start, direction, length, step, rng, wiggle, upward=0.0):
    """Walk from start along a gently wiggling, optionally up-bending direction."""
    n = max(2, int(math.ceil(length / step)) + 1)
    seg = length / (n - 1)
    pts, d = [start], _norm(direction)
    for _ in range(n - 1):
        d = _norm(_add(d, (rng.uniform(-wiggle, wiggle), rng.uniform(-wiggle, wiggle),
                           rng.uniform(-wiggle, wiggle) + upward)))
        pts.append(_add(pts[-1], _mul(d, seg)))
    return pts


def _taper(n, r0, r1):
    return [r0 + (r1 - r0) * (i / (n - 1)) for i in range(n)]


# --- generator -----------------------------------------------------------------
def generate(preset: dict, seed: int) -> Tree:
    rng = random.Random(seed)
    p = preset
    step = 1.0 / p["segments_per_meter"]
    tree = Tree()

    # Trunk: leans from the base, lean azimuth twists along the trunk.
    trunk_len = p["height"] * (p["crown_start"] + (1 - p["crown_start"]) * 0.45)
    n = max(3, int(math.ceil(trunk_len / step)) + 1)
    az0 = rng.uniform(0, math.tau)
    lean, twist = math.radians(p["lean_deg"]), math.radians(p["twist_deg"])
    pts = [(0.0, 0.0, 0.0)]
    for i in range(1, n):
        t = i / (n - 1)
        az = az0 + twist * t
        tilt = lean * (1.0 - 0.35 * t * t) + rng.uniform(-0.04, 0.04)
        d = (math.sin(tilt) * math.cos(az), math.sin(tilt) * math.sin(az), math.cos(tilt))
        pts.append(_add(pts[-1], _mul(d, trunk_len / (n - 1))))
    r = p["trunk_radius"]
    radii = []
    for i in range(n):
        z = trunk_len * i / (n - 1)
        flare = 1.0 + (p["trunk_flare"] - 1.0) * math.exp(-z / 1.2)
        radii.append(r * flare * (1.0 - 0.6 * i / (n - 1)))
    tree.branches.append(Branch(pts, radii, 0, -1))

    # Forks: steep secondary stems from the upper trunk (multi-stem banyan, forked leaning tree).
    for k in range(p["trunk_forks"]):
        i = int((n - 1) * rng.uniform(0.55, 0.8))
        _spawn(tree, 0, i, rng, p, depth=1, angle=math.radians(rng.uniform(20, 35)),
               length=trunk_len * rng.uniform(0.45, 0.6), az=az0 + k * math.tau / max(1, p["trunk_forks"]),
               radius_mul=0.75, step=step)

    # Branch levels.
    level_parents = [0] + [i for i, b in enumerate(tree.branches) if b.depth == 1]
    for level in range(p["branch_levels"]):
        count = p["branches_per_level"][level]
        new_parents = []
        for pi in level_parents:
            parent = tree.branches[pi]
            pn = len(parent.points)
            start = p["crown_start"] if parent.depth == 0 else 0.3
            plen = _length(parent.points)
            for c in range(count):
                f = start + (0.95 - start) * (c + rng.uniform(0.2, 0.8)) / count
                i = min(pn - 2, max(1, int(round(f * (pn - 1)))))
                az = c * 2.39996 + rng.uniform(-0.4, 0.4)  # golden angle
                ang = math.radians(p["branch_angle_deg"] + rng.uniform(-12, 12))
                length = max(0.6, (plen if parent.depth else p["height"] * 0.55) * p["branch_length_ratio"]
                             * rng.uniform(0.75, 1.05) * (1.15 - 0.4 * f))
                new_parents.append(_spawn(tree, pi, i, rng, p, parent.depth + 1, ang, length, az, 0.6, step))
        level_parents = new_parents

    # Clumps at the tips of the outermost branches.
    tips = [b for b in tree.branches if b.depth >= max(1, p["branch_levels"])]
    if p["crown_start"] >= 0.6:  # tall trees also crown the trunk top
        tips += [b for b in tree.branches if b.depth == 1]
    for b in tips:
        for _ in range(rng.randint(*p["clumps_per_tip"])):
            rad = rng.uniform(*p["clump_radius"])
            off = (rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 1))
            c = _add(b.points[-1], _mul(_norm(off), rad * rng.uniform(0.0, 0.5)))
            tree.clumps.append(Clump(c, rad, (1.0, 1.0, rng.uniform(0.7, 0.85))))

    _normalize_height(tree, p["height"] * rng.uniform(0.92, 1.08))
    _add_aerial_roots(tree, rng, p, step)
    return tree


def _length(pts):
    return sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def _spawn(tree, pi, i, rng, p, depth, angle, length, az, radius_mul, step):
    parent = tree.branches[pi]
    pts = parent.points
    d = _norm(_add(pts[min(i + 1, len(pts) - 1)], _mul(pts[max(i - 1, 0)], -1)))
    side = _rotate(_perp(d), d, az)
    direction = _rotate(d, _norm(_cross(d, side)), angle)
    bpts = _polyline(pts[i], direction, length, step, rng, wiggle=0.12, upward=0.05)
    r0 = parent.radii[i] * radius_mul
    tree.branches.append(Branch(bpts, _taper(len(bpts), r0, max(0.02, r0 * 0.25)), depth, pi))
    return len(tree.branches) - 1


def _normalize_height(tree, target):
    top = max([pt[2] for b in tree.branches for pt in b.points]
              + [c.center[2] + c.radius * c.scale[2] for c in tree.clumps])
    s = target / top
    for b in tree.branches:
        b.points = [_mul(pt, s) for pt in b.points]
        b.radii = [r * s for r in b.radii]
    for c in tree.clumps:
        c.center, c.radius = _mul(c.center, s), c.radius * s


def _add_aerial_roots(tree, rng, p, step):
    hosts = [(bi, k) for bi, b in enumerate(tree.branches) if b.depth in (1, 2)
             for k in range(len(b.points)) if b.points[k][2] > 3.0]
    if not hosts:
        return
    for j in range(p["aerial_roots"]):
        bi, k = rng.choice(hosts)
        top = tree.branches[bi].points[k]
        grounded = j == 0 and p["root_ground_fraction"] > 0 or rng.random() < p["root_ground_fraction"]
        length = top[2] if grounded else top[2] * rng.uniform(0.2, 0.7)
        pts = _polyline(top, (0, 0, -1), length, step, rng, wiggle=0.03)
        if grounded:  # stretch z from [bottom, top] to [0, top] so it lands on the ground
            zb = pts[-1][2]
            pts = [(x, y, (z - zb) * top[2] / max(1e-6, top[2] - zb)) for x, y, z in pts]
            radii = _taper(len(pts), rng.uniform(0.15, 0.25), rng.uniform(0.2, 0.32))
        else:
            radii = _taper(len(pts), rng.uniform(0.03, 0.06), 0.02)
        tree.roots.append(Branch(pts, radii, 1, bi))
