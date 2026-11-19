# Anime Tree Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reusable Godot 4.7 tool that generates cel-shaded, hand-drawn-looking trees (banyan, tall jungle, leaning/twisted, small broadleaf/bush) from a headless Blender script, renders them with camera-facing scalloped card clumps + screen-space ink outlines, switches through manual LODs, and draws far trees as relightable hemi-octahedral impostors in chunked forests.

**Architecture:** `tools/treegen/` (Python, run by Blender 5.3 headless) emits one `.glb` (trunk/roots LOD0+LOD1) plus a `.clumps.json` sidecar per tree variant. A Godot editor plugin (`addons/anime_trees/`) turns each import into a tree scene (LOD0, LOD1, Impostor), provides cel/foliage/impostor shaders, a compositor outline effect, a per-scene impostor baker, and a `Forest` node that scatters instances and renders them as per-cell MultiMeshes with visibility ranges.

**Tech Stack:** Godot 4.7.2 (Forward+, GDScript, Godot shaders, CompositorEffect + GLSL compute), Blender 5.3 `bpy` (Python 3.14), stdlib `unittest` (no pytest installed).

**Spec:** `docs/superpowers/specs/2026-11-18-anime-tree-rendering-design.md` (reference frames: `docs/reference/1.png` … `8.png`)

## Global Constraints

- Godot 4.7, Forward+. Blender at `/usr/bin/blender`, always run headless: `blender -b --python ... -- <args>`. User never opens Blender.
- No wind, collision, ground/grass, palm fronds, depth fade (fog does that), day/night.
- Lighting fixed per scene: one DirectionalLight + environment.
- Instances: yaw rotation (any angle) + uniform scale only; trees stay upright.
- Performance target: mid-range gaming PC, 60 fps at 1080p, ~2,000 trees visible in flyover, most of them impostors.
- Ink outline ≈ 2 px at 1080p, scaled with resolution; ink color = local scene color × darkening factor, never pure black.
- Godot automatic mesh LOD disabled on all tree meshes (`generate_lods = false` / import option off).
- Cel lighting = stepped ramp with 2–3 tones; same ramp function used by foliage, trunk and impostor shaders.
- Python tests: stdlib `unittest`, run inside Blender's Python. Godot tests: plain GDScript runner, no add-on frameworks.
- Coordinates: generator works in Blender Z-up meters; everything written to disk for Godot (glb, json) is Y-up: `(x, y, z)_blender → (x, z, -y)_godot`.

## Review Focus

1. **Axis conversion of the clump sidecar** — clumps must sit on the branch tips in Godot, not rotated 90° off the tree. Test: Task 2 `test_to_godot_axes`, Task 4 `test_imported_foliage_overlaps_trunk_top`.
2. **Re-running the pipeline** (reusable tool) — same preset+seed gives identical output; re-import and re-bake overwrite cleanly and keep references valid. Tests: Task 1 `test_deterministic`, Task 7 `test_rebake_overwrites`.
3. **Arbitrary instance yaw** (negative, >360°) — impostor shadow-channel selection wraps. Test: Task 7 `test_shadow_weights_wrap`.
4. **Camera directions outside the baked hemisphere** (looking up at a far tree from below) and straight down — frame lookup clamps to horizon / centre frame. Test: Task 7 `test_dir_to_uv_below_horizon_clamps`, `test_up_maps_to_center`.
5. **Forest edge cases** — empty forest, instances at negative coordinates, missing impostor set. Tests: Task 8 `test_chunk_negative_coords`, `test_chunk_empty`, `test_forest_without_impostor_set`.

---

## File Structure

```
tools/treegen/
  skeleton.py        pure Python: seeded branch/root/clump skeleton (no bpy)
  presets.py         PRESETS dict: banyan, jungle_tall, leaning, broadleaf
  meshing.py         bpy: sweep tubes, UVs, moss color attribute, LOD1 decimate
  export.py          bpy: build objects, write .glb + .clumps.json, axis conversion
  treegen.py         CLI entry
  batch.sh           generate N variants per preset into assets/trees/
  tests/run_tests.py unittest discovery inside Blender
  tests/test_skeleton.py, tests/test_meshing.py, tests/test_export.py
addons/anime_trees/
  plugin.cfg, plugin.gd                 EditorPlugin: post-import plugin, custom types
  import/tree_import_plugin.gd          EditorScenePostImportPlugin → tree scene
  tree/anime_tree.gd                    root script of a tree scene (LOD distances, impostor hookup)
  foliage/foliage_builder.gd            clumps → ArrayMesh of cards
  textures/make_textures.gd             @tool generator for scallop atlas + bark lines PNGs
  shaders/cel_ramp.gdshaderinc          shared stepped-ramp light helper
  shaders/foliage.gdshader, trunk.gdshader, impostor.gdshader
  outline/outline_effect.gd, outline/outline.glsl
  impostor/hemi_oct.gd, impostor/impostor_baker.gd, impostor/impostor_set.gd
  forest/forest_data.gd, forest/forest_chunker.gd, forest/forest.gd
tests/                       Godot tests (run_tests.gd, test_case.gd, test_*.gd, capture.gd)
demo/forest_demo.tscn, demo/camera_rig.gd
assets/trees/                generated .glb + .clumps.json (committed)
```

---

### Task 1: Tree skeleton generator + presets (pure Python)

**Files:**
- Create: `tools/treegen/skeleton.py`, `tools/treegen/presets.py`, `tools/treegen/tests/run_tests.py`, `tools/treegen/tests/test_skeleton.py`

**Interfaces:**
- Produces:
  ```python
  Vec3 = tuple[float, float, float]            # Blender Z-up, meters
  @dataclass class Branch: points: list[Vec3]; radii: list[float]; depth: int; parent: int  # parent=-1 for trunk
  @dataclass class Clump:  center: Vec3; radius: float; scale: Vec3                          # ellipsoid = radius*scale
  @dataclass class Tree:   branches: list[Branch]; roots: list[Branch]; clumps: list[Clump]
  def generate(preset: dict, seed: int) -> Tree
  PRESETS: dict[str, dict]   # keys: "banyan", "jungle_tall", "leaning", "broadleaf"
  ```
- Preset keys (all presets define all keys): `height`(m), `trunk_radius`, `trunk_flare` (base radius multiplier), `lean_deg`, `twist_deg` (total twist over trunk), `trunk_forks` (0–3), `branch_levels`, `branches_per_level` (list[int]), `branch_angle_deg`, `branch_length_ratio`, `crown_start` (0–1 of height), `clump_radius` ([min,max] m), `clumps_per_tip` ([min,max]), `aerial_roots` (count), `root_ground_fraction` (0–1), `segments_per_meter`.
- Starting values (tune in Task 9 against reference frames):
  - banyan: height 18, trunk_radius 1.4, flare 1.8, lean 0, twist 15, forks 3, levels 3, branches [6,4,3], angle 65, length_ratio 0.7, crown_start 0.35, clump_radius [2.0,3.5], clumps_per_tip [1,3], aerial_roots 40, root_ground_fraction 0.25
  - jungle_tall: 28, 0.7, 1.5, 0, 5, 0, 3, [5,3,2], 50, 0.45, 0.7, [1.8,3.0], [1,2], 6, 0.0
  - leaning: 14, 0.6, 1.3, 25, 60, 2, 3, [4,3,2], 45, 0.6, 0.45, [1.5,2.5], [1,2], 4, 0.0
  - broadleaf: 6, 0.25, 1.2, 5, 20, 1, 2, [4,3], 55, 0.6, 0.3, [1.0,1.8], [1,2], 0, 0.0
- Algorithm (builder's choice, spec §1): recursive branching along the trunk curve. Aerial roots hang from level-1/2 branches straight down; the `root_ground_fraction` share reaches z=0 and gets radius ≥ 0.15 m (pillar roots).

- [ ] **Step 1: Write `run_tests.py`** — `unittest` discovery over `tools/treegen/tests`, `sys.exit(1)` on failure. Run: `blender -b --python tools/treegen/tests/run_tests.py`
- [ ] **Step 2: Write failing tests in `test_skeleton.py`**
  ```python
  def test_deterministic(self):         # same preset+seed → equal Tree (dataclass ==)
  def test_seeds_differ(self):          # seed 1 vs 2 → different clump centers
  def test_trunk_base_at_origin(self):  # branches[0].points[0] == approx (0,0,0)
  def test_height_in_range(self):       # max z over branches+clumps within preset height ±25 %
  def test_radii_positive_and_taper(self):  # all radii>0; each child's radii[0] <= parent radius at attach point
  def test_clumps_near_branch_tips(self):   # every clump center within clump.radius*1.5 of some branch point with depth>=1
  def test_banyan_has_ground_roots(self):   # ≥1 root ends with z < 0.1; count(roots) == preset aerial_roots
  def test_leaning_offsets_top(self):       # trunk top xy distance > height*sin(lean)*0.5
  def test_all_presets_generate(self):      # each PRESETS key → ≥3 clumps, no NaN
  ```
- [ ] **Step 3: Run tests → FAIL** (import error).
- [ ] **Step 4: Implement `skeleton.py` and `presets.py`.** Use `random.Random(seed)` only (no global RNG).
- [ ] **Step 5: Run tests → all PASS.**
- [ ] **Step 6: Commit** `feat(treegen): seeded skeleton generator and four presets`

---

### Task 2: Meshing, LOD1, export, CLI

**Files:**
- Create: `tools/treegen/meshing.py`, `tools/treegen/export.py`, `tools/treegen/treegen.py`, `tools/treegen/batch.sh`, `tools/treegen/tests/test_meshing.py`, `tools/treegen/tests/test_export.py`

**Interfaces:**
- Consumes: `generate`, `PRESETS`, `Tree` (Task 1).
- Produces:
  ```python
  def sweep_branches(branches: list[Branch], name: str) -> bpy.types.Object  # tube mesh; UV: U around, V = length along branch (meters / 2.0); color attribute "moss" (point, float, 0..1)
  def make_lod1(obj, ratio: float = 0.3) -> bpy.types.Object                  # decimated copy, name suffix "_LOD1"
  def to_godot_axes(v: Vec3) -> Vec3                                          # (x, y, z) -> (x, z, -y)
  def export_tree(tree: Tree, out_dir: str, name: str, preset: str, seed: int) -> tuple[str, str]  # (glb_path, json_path)
  ```
- glb objects (exact names, Godot reads them): `Trunk_LOD0`, `Trunk_LOD1`, `Roots_LOD0`, `Roots_LOD1` (roots omitted when tree has none). LOD1 roots: only roots with radius ≥ 0.15 m (pillars).
- Sidecar `<name>.clumps.json`, Y-up:
  `{"preset": str, "seed": int, "clumps": [{"center": [x,y,z], "radius": r, "scale": [sx,sy,sz]}]}` (scale also axis-converted, without sign).
- Moss: `max(0, normal_z) * noise` (Blender `mathutils.noise`), so upward faces get moss.
- CLI: `blender -b --python tools/treegen/treegen.py -- --preset banyan --seed 3 --out assets/trees` → writes `assets/trees/banyan_003.glb` and `banyan_003.clumps.json`. Names are `<preset>_<seed:03d>`.
- Triangle budgets (assert in tests): Trunk_LOD0 ≤ 15,000 tris for banyan, ≤ 6,000 others; LOD1 ≤ 35 % of LOD0.
- `batch.sh`: `batch.sh <count>` → seeds 1..count for each of the four presets.

- [ ] **Step 1: Write failing tests**
  ```python
  def test_to_godot_axes(self):        # to_godot_axes((1,2,3)) == (1,3,-2)
  def test_sweep_has_uv_and_moss(self):# mesh has a UV layer and color attribute "moss" with values in [0,1]
  def test_lod1_ratio(self):           # tris(LOD1) <= 0.35*tris(LOD0) and > 0
  def test_budgets(self):              # per preset, seed 1: within budgets above
  def test_export_files(self):         # export_tree to tempdir → both files exist; json clump count == len(tree.clumps); first center == to_godot_axes(tree.clumps[0].center)
  def test_export_deterministic(self): # export twice same seed → identical json bytes
  ```
- [ ] **Step 2: Run** `blender -b --python tools/treegen/tests/run_tests.py` → new tests FAIL.
- [ ] **Step 3: Implement** meshing (bmesh ring sweep, ~8 sides trunk / 5 sides thin branches & roots, flare at base), decimate modifier for LOD1, glTF export (`bpy.ops.export_scene.gltf`, `export_format='GLB'`, `export_yup=True`, attributes exported so "moss" arrives as `COLOR_0`).
- [ ] **Step 4: Run tests → PASS.**
- [ ] **Step 5: Generate assets:** `tools/treegen/batch.sh 3` → 12 glb + 12 json in `assets/trees/`.
- [ ] **Step 6: Commit** `feat(treegen): tube meshing, LOD1, glb + clump sidecar export`

---

### Task 3: Godot test harness, foliage card mesh, textures

**Files:**
- Create: `tests/test_case.gd`, `tests/run_tests.gd`, `tests/test_foliage_builder.gd`, `addons/anime_trees/foliage/foliage_builder.gd`, `addons/anime_trees/textures/make_textures.gd`, `addons/anime_trees/textures/scallop_atlas.png`, `addons/anime_trees/textures/bark_lines.png`
- Modify: `.gitignore` (add `tests/out/`)

**Interfaces:**
- Test harness: `test_case.gd` (`class_name TestCase extends RefCounted`, `func check(cond: bool, msg: String)` records failures). `run_tests.gd` extends `SceneTree`, loads every `res://tests/test_*.gd`, calls each `test_*` method, prints failures, `quit(failure_count)`. Run: `godot --headless --path . --import && godot --headless --path . -s tests/run_tests.gd`.
- Produces:
  ```gdscript
  class_name FoliageBuilder
  static func load_clumps(json_path: String) -> Array[Dictionary]   # {center: Vector3, radius: float, scale: Vector3}
  static func build(clumps: Array[Dictionary], cards_per_clump: int, card_size_mul: float, seed: int) -> ArrayMesh
  ```
- Mesh layout (shader contract, Task 5): one surface, 4 verts per card, `PRIMITIVE_TRIANGLES`.
  - `VERTEX` = card center (object space). `UV` = corner (0..1). `UV2.x` = atlas cell index (0–3), `UV2.y` = random 0..1.
  - `CUSTOM0` (RGBA_FLOAT) = clump center xyz + clump radius. `CUSTOM1` (RGBA_FLOAT) = clump scale xyz + card half-size.
  - Card centers: uniformly inside ellipsoid at 0.55–0.95 of radius (biased outward). Card half-size = `radius * 0.45 * card_size_mul`.
  - Mesh `custom_aabb` grown by max card half-size (verts move in shader).
- LOD settings: LOD0 = `build(clumps, 20, 1.0, seed)`, LOD1 = `build(clumps, 6, 1.6, seed)`.
- Textures (generated once by `make_textures.gd`, run with `godot --headless --path . -s addons/anime_trees/textures/make_textures.gd`, PNG committed):
  - `scallop_atlas.png` 1024×1024, 2×2 cells, white mask on transparent. Each blob = union of a base circle plus 2 recursive rings of smaller circles on its boundary (ring radius ratio ~0.35, 9–14 circles per ring, jittered). This gives the fractal scallop edge of reference frames 1, 2 and 8.
  - `bark_lines.png` 512×512 tileable, R channel = thin wavy vertical lines (bark), used along V.

- [ ] **Step 1: Write harness + failing tests**
  ```gdscript
  func test_card_count():      # 3 clumps, 20 cards → 240 verts, 360 indices
  func test_custom0_is_center():  # every vertex CUSTOM0.xyz equals its clump center
  func test_cards_inside_ellipsoid():  # VERTEX within clump ellipsoid (radius*scale)
  func test_deterministic():   # same seed → identical vertex arrays
  func test_load_clumps(): # parses assets/trees/broadleaf_001.clumps.json, count matches JSON
  ```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement `foliage_builder.gd` and `make_textures.gd`; generate PNGs.** View `scallop_atlas.png` (Read tool) and compare edge character to `docs/reference/2.png`; iterate until scallops read as fractal, not round bumps.
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(anime_trees): test harness, foliage card mesh builder, scallop/bark textures`

---

### Task 4: Import plugin → tree scene with manual LOD

**Files:**
- Create: `addons/anime_trees/plugin.cfg`, `addons/anime_trees/plugin.gd`, `addons/anime_trees/import/tree_import_plugin.gd`, `addons/anime_trees/tree/anime_tree.gd`, `tests/test_tree_import.gd`
- Modify: `project.godot` (enable plugin; add `[shader_globals] anime_tree_bake_mode={"type":"int","value":0}`)

**Interfaces:**
- Consumes: `FoliageBuilder` (Task 3), glb node names + sidecar (Task 2).
- `tree_import_plugin.gd` extends `EditorScenePostImportPlugin`, acts only when `<source>.clumps.json` exists next to the glb. It disables mesh LOD generation (`_get_import_options`/`_pre_process` option `meshes/generate_lods = false`) and in `_post_process` rebuilds the scene as:
  ```
  AnimeTree (Node3D, script anime_tree.gd)
    LOD0 (MeshInstance3D)   mesh surfaces: Trunk_LOD0 [trunk mat], Roots_LOD0 [trunk mat], foliage LOD0 [foliage mat]
    LOD1 (MeshInstance3D)   Trunk_LOD1, Roots_LOD1, foliage LOD1
    Impostor (MeshInstance3D)  QuadMesh sized to tree AABB, material assigned from impostor_set (Task 7); hidden if none
  ```
  Shadows: LOD0 casts shadows; LOD1 and Impostor `cast_shadow = OFF`.
  Each LOD is one merged ArrayMesh (one surface per material) so the Forest (Task 8) can MultiMesh it.
- Produces:
  ```gdscript
  class_name AnimeTree extends Node3D
  @export var lod0_end := 30.0
  @export var lod1_end := 120.0
  @export var impostor_end := 2000.0
  @export var fade_margin := 8.0
  @export var impostor_set: ImpostorSet   # Task 7; may be null
  @export var variant_id: String           # "<preset>_<seed:03d>"
  func apply_lod() -> void   # sets visibility_range_begin/end/margins, fade mode = VISIBILITY_RANGE_FADE_SELF
  ```
  Per-preset LOD distance multiplier written at import: banyan ×1.5, jungle_tall ×1.3, leaning ×1.0, broadleaf ×0.6.

- [ ] **Step 1: Write failing tests** (load `res://assets/trees/banyan_001.glb` as PackedScene)
  ```gdscript
  func test_scene_structure():   # root is AnimeTree; children LOD0, LOD1, Impostor exist
  func test_visibility_ranges():  # LOD0.end == lod0_end; LOD1.begin == lod0_end; Impostor.begin == lod1_end; fade mode SELF
  func test_lod1_cheaper():       # triangle count LOD1 < 0.5 * LOD0
  func test_no_auto_lods():       # every surface of LOD0 mesh: get_surface_lod_count... == 0 (ArrayMesh has no lods)
  func test_imported_foliage_overlaps_trunk_top():  # foliage surface AABB center.y > 0.4 * trunk AABB size.y and AABBs intersect
  ```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement plugin, import plugin, `anime_tree.gd`.** Materials temporarily `StandardMaterial3D` until Task 5.
- [ ] **Step 4: Re-import + run → PASS.**
- [ ] **Step 5: Commit** `feat(anime_trees): import plugin builds AnimeTree scenes with manual LOD`

---

### Task 5: Cel shaders — foliage and trunk

**Files:**
- Create: `addons/anime_trees/shaders/cel_ramp.gdshaderinc`, `foliage.gdshader`, `trunk.gdshader`, `addons/anime_trees/materials/foliage.tres`, `trunk.tres`, `tests/capture.gd`, `demo/tree_closeup.tscn`
- Modify: `tree_import_plugin.gd` (assign the two materials)

**Interfaces:**
- `cel_ramp.gdshaderinc`: `vec3 cel_ramp(float ndotl, float shadow, vec3 lit, vec3 mid, vec3 dark)`. Bands: `ndotl*shadow > 0.55 → lit`, `> 0.15 → mid`, else `dark`. No smoothing beyond 1 px AA (`fwidth`).
- Material uniforms (both shaders): `lit_color`, `mid_color`, `dark_color`, `blotch_color`, `blotch_scale`, `blotch_threshold`. Foliage defaults sampled from `docs/reference/1.png` (lit ≈ #5FA02A, mid ≈ #3F8424, dark ≈ #2C6A1E). Trunk defaults from the same frame (≈ #6B6A2E / #575327 / #3F3D1E, moss ≈ #7C8A34).
- **Foliage shader (key decision, refines spec §3/§5):** in `fragment()`, ray-cast the clump ellipsoid (CUSTOM0/1 passed as varyings). Write `NORMAL` = ellipsoid normal at the hit and `DEPTH` = hit depth. On a miss (scallop fringe outside the ellipsoid), use the closest-approach point. This makes normal *and* depth continuous across all cards of one clump, so the outline (Task 6) only draws at clump silhouettes and creases between clumps. Discard by `scallop_atlas` alpha (`ALPHA_SCISSOR`-style `discard`, threshold 0.5).
- Vertex: expand card to face camera (`INV_VIEW_MATRIX` basis), rotate per-card by `UV2.y * TAU`. Near-camera handling: cards within 1.5 m of camera shrink to 0 by 0.5 m.
- Shadow pass: cards face the light (builder: detect via the projection being orthographic).
- Blotches: 3D value noise in clump-local space (`VERTEX` world hit − clump center), threshold → `blotch_color`, never screen-space.
- `light()`: `DIFFUSE_LIGHT += cel_ramp(...)` using `ATTENUATION` as shadow; `AMBIENT_LIGHT` handled via ramp (unshaded fallback not used).
- `anime_tree_bake_mode` (global uniform) behaviour, used by Task 7: 0 normal; 1 = output unlit base tone (`lit_color`/bark/moss/blotch) via `ALBEDO`, no lighting; 2 = output object-space normal octa-encoded in RG + linear depth (0..1 across object AABB along view axis) in B; 3 = output `ATTENUATION` only (white lit / black shadowed). Trunk shader honours the same modes.
- Trunk: `bark_lines.png` along UV (V repeats per 2 m), lines multiply to `dark_color`; moss from `COLOR.r` (glTF COLOR_0) mixed with noise → `moss_color` flat.
- `tests/capture.gd` (run **without** `--headless`): `godot --path . -s tests/capture.gd -- <scene> <out.png> [camera_node]` waits 30 frames, saves viewport PNG to `tests/out/`.

- [ ] **Step 1: Build `demo/tree_closeup.tscn`**: one banyan + one broadleaf, DirectionalLight (shadows on), WorldEnvironment (flat green ambient), Camera3D nodes `CamClose` (2 m under canopy looking up), `CamMid` (40 m side view).
- [ ] **Step 2: Implement shaders + materials, assign in import plugin, re-import.**
- [ ] **Step 3: Capture** both cameras → `tests/out/close.png`, `tests/out/mid.png`. View them next to `docs/reference/1.png`, `4.png`, `8.png`. Pass criteria: clumps read as one mass with 2–3 flat bands; no visible card edges inside clumps; scallops on clump perimeter; blotches stay put while camera moves (capture again after moving camera 1 m; blotch pattern on the same clump is unchanged).
- [ ] **Step 4: Run Godot tests** → still PASS.
- [ ] **Step 5: Commit** `feat(anime_trees): cel foliage (ellipsoid normal+depth) and trunk shaders`

---

### Task 6: Screen-space ink outline

**Files:**
- Create: `addons/anime_trees/outline/outline_effect.gd`, `addons/anime_trees/outline/outline.glsl`
- Modify: `demo/tree_closeup.tscn` (Compositor on cameras), `plugin.gd` (register `OutlineEffect` type)

**Interfaces:**
- `class_name OutlineEffect extends CompositorEffect`, `effect_callback_type = POST_TRANSPARENT`, `needs_normal_roughness = true`. Exports: `line_width_px := 2.0` (at 1080p; scale by `size.y / 1080.0`), `depth_threshold := 0.08` (relative, `|Δd|/d`), `normal_threshold := 0.5` (`1 - dot`), `darken := 0.35`.
- Compute: sample depth + normal at ±width in 4 directions; edge if relative depth jump > threshold or normal jump > threshold; color = center color × `darken` (take the color of the *nearer* side so ink belongs to the front object). Sky pixels (depth at far plane) never draw lines on themselves.
- **No-outline flag:** pixels whose roughness in the normal-roughness buffer > 0.99 are skipped (impostors set `ROUGHNESS = 1.0`; trees use 0.5). This keeps impostors (which carry baked ink, Task 7) from getting double lines.

- [ ] **Step 1: Implement effect + shader, add Compositor with OutlineEffect to both demo cameras.**
- [ ] **Step 2: Capture** `close.png`, `mid.png`. Pass criteria vs `docs/reference/1.png`, `5.png`: lines around clump silhouettes and between overlapping clumps; **no** lines inside a clump; trunk outlines dark brown, leaf outlines dark green; ~2 px at 1080p.
- [ ] **Step 3: Tune thresholds**; record final defaults in the script.
- [ ] **Step 4: Commit** `feat(anime_trees): compositor ink outline with no-outline flag`

---

### Task 7: Relightable hemi-octahedral impostors + per-scene baker

**Files:**
- Create: `addons/anime_trees/impostor/hemi_oct.gd`, `impostor_set.gd`, `impostor_baker.gd`, `addons/anime_trees/shaders/impostor.gdshader`, `tests/test_hemi_oct.gd`, `tests/test_impostor_bake.gd`
- Modify: `anime_tree.gd` (assign impostor material from `impostor_set`), `plugin.gd` (register `ImpostorBaker`, inspector "Bake" button)

**Interfaces:**
- Consumes: AnimeTree scenes (Task 4), bake modes (Task 5), OutlineEffect (Task 6).
- Produces:
  ```gdscript
  class_name HemiOct
  const FRAMES := 8                                    # 8×8 frames
  static func dir_to_uv(d: Vector3) -> Vector2         # Y-up; y<0 clamped to horizon; returns 0..1
  static func uv_to_dir(uv: Vector2) -> Vector3
  static func frame_dir(ix: int, iy: int) -> Vector3   # center direction of frame
  static func shadow_weights(rel_azimuth_rad: float) -> Vector3  # (k0, k1, t): blend channel k0→k1 by t, K = 8 azimuths, wraps

  class_name ImpostorSet extends Resource
  @export var entries: Dictionary   # variant_id -> ShaderMaterial (impostor.gdshader with 4 atlases)

  class_name ImpostorBaker extends Node   (@tool)
  @export var variants: Array[PackedScene]
  @export var sun: DirectionalLight3D
  @export var output_dir := "res://impostors/<scene_name>/"
  @export var frame_px := 256
  func bake() -> ImpostorSet    # writes PNGs + impostor_set.tres into output_dir, overwriting
  ```
- Atlases per variant (2048² at 256 px/frame), file names `<variant>_albedo.png`, `_normal_depth.png`, `_shadow_a.png`, `_shadow_b.png`:
  - **albedo**: RGB = bake mode 1 render *with* outline; A = coverage. Ink flag = pixels where the outline-on and outline-off renders differ by luminance > 0.1, stored in `normal_depth.a`.
  - **normal_depth**: RG octa-encoded object normal, B linear depth, A ink flag (bake mode 2).
  - **shadow_a / shadow_b**: bake mode 3, sun at the scene sun's elevation, relative azimuths k·45°, k = 0..3 → shadow_a.RGBA, k = 4..7 → shadow_b.RGBA.
- Bake rig: SubViewport with own World3D, transparent bg, orthographic Camera3D fit to tree AABB, Compositor with OutlineEffect, sets `anime_tree_bake_mode` via `RenderingServer.global_shader_parameter_set`, restores 0 afterwards.
- Impostor shader: billboard quad facing camera. Frame from `HemiOct.dir_to_uv` of the view direction **in object space** (so yaw is handled), blend the 3 nearest frames. Relight in `light()`: normal from atlas → world via `MODEL_MATRIX`; self-shadow = `mix(chan(k0), chan(k1), t)` from `shadow_weights(sun azimuth in object space)`; same `cel_ramp`; ink pixels output the albedo ink color unlit. `DEPTH` from the depth channel (pixel depth offset). `ROUGHNESS = 1.0` (no-outline flag). GLSL copies of `dir_to_uv`/`shadow_weights` must match `hemi_oct.gd` (comment both).

- [ ] **Step 1: Write failing tests (`test_hemi_oct.gd`)**
  ```gdscript
  func test_up_maps_to_center():   # dir_to_uv(UP) ≈ (0.5, 0.5)
  func test_round_trip():          # for 50 random upper-hemisphere dirs: uv_to_dir(dir_to_uv(d)) ≈ d (1e-4)
  func test_dir_to_uv_below_horizon_clamps():  # dir_to_uv((1,-0.5,0).normalized()) == dir_to_uv((1,0,0))
  func test_frame_dir_corners_horizon():  # frame_dir(0,0).y < 0.2
  func test_shadow_weights_wrap():  # shadow_weights(-PI/8) == shadow_weights(15*PI/8); shadow_weights(2*PI+0.1) ≈ shadow_weights(0.1); k1 == (k0+1)%8
  ```
- [ ] **Step 2: Run → FAIL; implement `hemi_oct.gd`; run → PASS.**
- [ ] **Step 3: Write failing bake test (`test_impostor_bake.gd`, needs a GPU — run without `--headless`):** `godot --path . -s tests/run_tests.gd -- --gpu`
  ```gdscript
  func test_bake_writes_atlases():   # bake 1 variant → 4 PNGs of 2048² exist; impostor_set.tres has entry for variant_id
  func test_rebake_overwrites():     # bake twice → same file paths, entry still loads, no extra files in output_dir
  ```
- [ ] **Step 4: Implement baker, set, impostor shader; hook `AnimeTree` impostor material.**
- [ ] **Step 5: Run → PASS.**
- [ ] **Step 6: Visual check:** add `CamFar` (150 m) to `tree_closeup.tscn`, rotate one tree to yaw 0°, 100°, 230° and capture each from LOD1 range edge and impostor range start. Pass criteria: lit side matches the 3D tree for every yaw (no lighting jump at swap); outline weight similar across swap; looks right from top-down (camera at 89° pitch).
- [ ] **Step 7: Commit** `feat(anime_trees): relightable hemi-octahedral impostors with yaw-indexed self-shadow`

---

### Task 8: Forest placement and chunked rendering

**Files:**
- Create: `addons/anime_trees/forest/forest_data.gd`, `forest_chunker.gd`, `forest.gd`, `tests/test_forest.gd`
- Modify: `plugin.gd` (register `Forest`, inspector "Scatter" / "Rebuild" buttons)

**Interfaces:**
- Consumes: AnimeTree scenes (LOD0/LOD1/Impostor meshes + distances), `ImpostorSet`.
- Produces:
  ```gdscript
  class_name ForestData extends Resource
  @export var variant_scenes: Array[PackedScene]
  @export var instances: PackedFloat32Array   # stride 5: variant_index, x, y, z, yaw  (+ scale below)
  @export var scales: PackedFloat32Array      # one per instance
  func add(variant: int, pos: Vector3, yaw: float, scale: float) -> void
  func count() -> int

  class_name ForestChunker
  static func cell_of(pos: Vector3, cell_size: float) -> Vector2i   # floor on x,z
  static func chunk(data: ForestData, cell_size: float) -> Dictionary  # Vector2i -> {variant_index: Array[Transform3D]}

  class_name Forest extends Node3D (@tool)
  @export var data: ForestData
  @export var impostor_set: ImpostorSet
  @export var ground: MeshInstance3D
  @export var cell_size := 64.0
  @export var scatter_rect := Rect2(-200, -200, 400, 400)
  @export var density_per_ha := 120.0
  @export var variant_weights: PackedFloat32Array
  @export var seed := 1
  func scatter() -> void     # deterministic: Poisson-ish jittered grid in scatter_rect, y from ray against ground.mesh.generate_triangle_mesh(); yaw random 0..TAU; scale 0.85..1.2
  func rebuild() -> void     # clears generated children; per cell, per variant, per LOD: MultiMeshInstance3D with that LOD mesh + visibility range copied from the variant's AnimeTree (distances measured from cell AABB)
  ```
- Generated children are not saved into the scene (`owner` left null); `rebuild()` runs in `_ready()`.
- Missing `impostor_set` or missing entry: skip impostor MultiMeshes, `push_warning` once per variant, no crash.
- Painting by brush: **skipped** (scatter + data edit only); add when designers ask.

- [ ] **Step 1: Write failing tests**
  ```gdscript
  func test_chunk_negative_coords():   # cell_of(Vector3(-0.5,0,-64.5), 64) == Vector2i(-1,-2)
  func test_chunk_empty():             # chunk(empty data) == {}
  func test_chunk_counts():            # 100 instances → sum of transforms over all cells == 100
  func test_transform_has_yaw_scale(): # instance yaw 1.0, scale 1.2 → basis == Basis(UP,1.0).scaled(1.2*ONE)
  func test_scatter_deterministic():   # scatter twice same seed → identical instances
  func test_scatter_on_ground():       # with tilted plane ground, every instance y within 0.05 of plane height
  func test_forest_without_impostor_set():  # rebuild() with impostor_set null → no error, LOD0/LOD1 multimeshes exist
  ```
- [ ] **Step 2: Run → FAIL; implement; run → PASS.**
- [ ] **Step 3: Commit** `feat(anime_trees): Forest node with deterministic scatter and per-cell LOD multimeshes`

---

### Task 9: Demo, performance check, look tuning

**Files:**
- Create: `demo/forest_demo.tscn`, `demo/camera_rig.gd`, `tests/perf.gd`
- Modify: preset values (`presets.py`), material defaults, regenerated `assets/trees/`

**Interfaces:**
- `forest_demo.tscn`: ground plane (2 km), DirectionalLight (shadows, fixed angle), WorldEnvironment with fog, `ImpostorBaker` (all 12 variants), `Forest` (density so ~2,000 trees are visible from flyover), 3 hero `AnimeTree` banyans near spawn.
- `camera_rig.gd`: keys `1` walk under canopy (eye height 1.7 m, WASD+mouse), `2` orbit at 60 m, `3` flyover at 150 m altitude; nodes `CamWalk`, `CamOrbit`, `CamFly` for capture.
- `tests/perf.gd` (GPU): loads demo, uses `CamFly`, averages 300 frames; prints `frame_ms`, `draw_calls` (`RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)`), visible tree count. Exit code 1 if `frame_ms > 16.6` or `draw_calls > 1500`.

- [ ] **Step 1: Build demo + rig; bake impostors; scatter.**
- [ ] **Step 2: Run perf:** `godot --path . -s tests/perf.gd` → exit 0. If it fails, raise `cell_size`, lower LOD distances, or lower LOD0 card count, then rerun.
- [ ] **Step 3: Capture all three cameras** and compare to references: walk vs `3.png`/`5.png`/`6.png`, orbit vs `1.png`/`7.png`/`8.png`, flyover vs `2.png`. Tune preset values, clump sizes, colors, outline thresholds; regenerate assets (`batch.sh 3`), re-import, re-bake, recapture until each type is recognisable as its reference (banyan: spreading crown + hanging roots; jungle_tall: tall clear trunk; leaning: leaning twisted trunk; broadleaf fills gaps).
- [ ] **Step 4: Run all tests** (Python, Godot headless, Godot GPU) → PASS.
- [ ] **Step 5: Commit** `feat: forest demo, perf check, tuned presets`
