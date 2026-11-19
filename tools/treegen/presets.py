"""Tree type presets. Starting values; tuned against docs/reference/*.png."""

_KEYS = ("height", "trunk_radius", "trunk_flare", "lean_deg", "twist_deg", "trunk_forks",
         "branch_levels", "branches_per_level", "branch_angle_deg", "branch_length_ratio",
         "crown_start", "clump_radius", "clumps_per_tip", "aerial_roots", "root_ground_fraction")


def _p(*values, segments_per_meter=1.5):
    d = dict(zip(_KEYS, values))
    d["segments_per_meter"] = segments_per_meter
    return d


PRESETS = {
    "banyan": _p(18, 1.4, 1.8, 0, 15, 3, 3, [6, 4, 3], 65, 0.7, 0.35, [2.0, 3.5], [1, 3], 40, 0.25),
    "jungle_tall": _p(28, 0.7, 1.5, 0, 5, 0, 3, [5, 3, 2], 50, 0.45, 0.7, [1.8, 3.0], [1, 2], 6, 0.0),
    "leaning": _p(14, 0.6, 1.3, 25, 60, 2, 3, [4, 3, 2], 45, 0.6, 0.45, [1.5, 2.5], [1, 2], 4, 0.0),
    "broadleaf": _p(6, 0.25, 1.2, 5, 20, 1, 2, [4, 3], 55, 0.6, 0.3, [1.0, 1.8], [1, 2], 0, 0.0,
                    segments_per_meter=2.5),
}
