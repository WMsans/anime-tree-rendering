# Scalloped Canopy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Leaf clumps get scalloped (cauliflower-bump) silhouettes via a fragment-discard leaf shader; trunk/branches untouched.

**Architecture:** One spatial shader `shaders/leaf.gdshader` lit like the current StandardMaterial (Lambert, no specular), discarding fragments near the silhouette according to a bump profile indexed by the screen-space angle around the clump's origin. Two `ShaderMaterial`s replace the glb's `Leaf_Green` / `Leaf_Light` via each `.glb.import`'s material overrides. The existing depth outline traces the cut edge for free.

**Tech Stack:** Godot 4.7 (Forward+, reverse-Z), GDScript, Godot shading language. `godot` binary at `/usr/bin/godot`.

**Spec:** `docs/superpowers/specs/2026-11-19-scalloped-canopy-design.md`

## Global Constraints

- No changes to `cel_shading.gdshader`, `outline.gdshader`, their scripts, or the `.glb` files.
- Only `Leaf_Green` / `Leaf_Light` get the leaf shader; `Tree_Trunk` / `Tree_Branch` keep their glb materials.
- Leaf lighting must stay view-independent: `diffuse_lambert`, `specular_disabled` (cel ramp depends on it).
- Leaf colours (sRGB, converted from glb linear base colours): green `Color(0.41, 0.65, 0.2934)`, light `Color(0.5838, 0.7858, 0.3492)`.
- Tunables are shader uniforms: `rim_width`, `bump_count`, `octave_strength`.

## Review Focus

1. Camera orbit/strafe: bumps must stay attached to the clump, not crawl — Task 2 two-shot check.
2. Camera very near or inside a clump (clump origin behind/at camera): no NaN, no full-clump vanish — Task 2 guard + step.
3. Cel bands on leaves look the same as before the change (same lighting model) — Task 1 baseline vs after screenshot.
4. Regenerated trees keep the override (keyed by material name, not mesh) — Task 1 import test.
5. Shadows: scalloped shadow edge without new acne/holes — Task 2 screenshot step.

---

### Task 1: Leaf material hook-up (no scallops yet)

**Files:**
- Create: `shaders/leaf.gdshader`
- Create: `demo/assets/trees/leaf_green.tres`, `demo/assets/trees/leaf_light.tres` (ShaderMaterial)
- Modify: `demo/assets/trees/{tree_a,tree_b,tree_c,pine_a,pine_b}.glb.import` (`_subresources`)
- Create: `tests/check_leaf_materials.gd`, `tests/screenshot.gd`

**Interfaces:**
- Produces: `shaders/leaf.gdshader` with `uniform vec4 albedo : source_color;`, `render_mode diffuse_lambert, specular_disabled, cull_back;` (cull_back so the cut never reveals the clump's inside).
- Produces: `tests/screenshot.gd` — `extends SceneTree`; args after `--`: `<out_prefix>`; loads `res://demo/tree_demo.tscn`, waits 10 frames, saves `<out_prefix>_0.png`, moves `Camera3D` +1.0 m on x, waits 10 frames, saves `<out_prefix>_1.png`, quits. Free camera's mouse capture is irrelevant here.

- [ ] **Step 1: Baseline screenshots** (before any change)

Run: `godot --path . --script tests/screenshot.gd -- /tmp/claude-1000/-home-jeremy-Development-Godot-AllKindsOfRendering-anime-tree-rendering/cce6da36-f91d-4515-9e7c-6992f94226d7/scratchpad/before` (write `screenshot.gd` first)
Expected: two PNGs of the current scene.

- [ ] **Step 2: Write the failing import test `tests/check_leaf_materials.gd`**

`extends SceneTree`. For each of the 5 tree scenes: instantiate, walk all `MeshInstance3D`, for every surface `m = mesh.surface_get_material(i)`:
- if `m.resource_path` is `leaf_green.tres` or `leaf_light.tres` path → `leaf += 1`, assert `m is ShaderMaterial`;
- else assert `not (m is ShaderMaterial)` and `m.resource_name in ["Tree_Trunk", "Tree_Branch"]`.
Assert `leaf > 0` per tree. Print `PASS`/`FAIL: <scene> <detail>`, `quit(0|1)`.

- [ ] **Step 3: Run, expect FAIL**

Run: `godot --headless --path . --import && godot --headless --path . --script tests/check_leaf_materials.gd`
Expected: `FAIL: ... Leaf_Green` (leaf surfaces still StandardMaterial), exit 1.

- [ ] **Step 4: Implement**

`leaf.gdshader`: `ALBEDO = albedo.rgb; ROUGHNESS = 1.0;`. Two `.tres` with the Global Constraints colours. In each `.glb.import`:
```
_subresources={"materials": {"Leaf_Green": {"use_external/enabled": true, "use_external/path": "res://demo/assets/trees/leaf_green.tres"}, "Leaf_Light": {"use_external/enabled": true, "use_external/path": "res://demo/assets/trees/leaf_light.tres"}}}
```

- [ ] **Step 5: Run test, expect PASS**

Same command as Step 3. Expected: `PASS`, exit 0.

- [ ] **Step 6: After screenshots, compare to baseline**

Run: `godot --path . --script tests/screenshot.gd -- /tmp/claude-1000/-home-jeremy-Development-Godot-AllKindsOfRendering-anime-tree-rendering/cce6da36-f91d-4515-9e7c-6992f94226d7/scratchpad/after1`
Expected: leaves look the same as `before_*` (same colours and cel bands); trunk unchanged.

- [ ] **Step 7: Commit**

```bash
git add shaders/leaf.gdshader demo/assets/trees/*.tres demo/assets/trees/*.glb.import tests/
git commit -m "feat: leaf shader material hook-up"
```

---

### Task 2: Scallop cut

**Files:**
- Modify: `shaders/leaf.gdshader`

**Interfaces:**
- Consumes: Task 1 shader, materials, `tests/screenshot.gd`.
- Produces: uniforms `rim_width = 0.35`, `bump_count = 9.0`, `octave_strength = 0.35` (starting values; tune by eye against `docs/reference/1.png`, `2.png`, update defaults).

- [ ] **Step 1: Implement the cut in `fragment()`**

The algorithm (the part the spec leaves open):
```glsl
vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz; // clump centre, view space
if (c.z < -0.1 && VERTEX.z < -0.1) {           // guard: centre in front of camera
    vec2 d = VERTEX.xy / -VERTEX.z - c.xy / -c.z; // perspective-divided offset
    float phase = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453) * TAU;
    float a = atan(d.y, d.x) + phase;
    float profile = sqrt(abs(sin(a * bump_count * 0.5)));                       // round lobes, sharp cusps
    profile = mix(profile, profile * sqrt(abs(sin(a * bump_count * 1.5))), octave_strength); // sub-bumps
    float rim = 1.0 - abs(dot(NORMAL, VIEW));
    if (rim > 1.0 - rim_width * (1.0 - profile)) discard;
}
```

- [ ] **Step 2: Shader compiles**

Run: `godot --path . --script tests/screenshot.gd -- /tmp/claude-1000/-home-jeremy-Development-Godot-AllKindsOfRendering-anime-tree-rendering/cce6da36-f91d-4515-9e7c-6992f94226d7/scratchpad/after2 2>&1 | grep -i -E "error|shader"`
Expected: no output.

- [ ] **Step 3: Visual check**

Open `after2_0.png` / `after2_1.png`. Expected: every leaf clump and pine tier has a bumpy edge traced by the outline; trunk smooth; shadows on the ground scalloped with no new speckle; bump positions on the same clump match between `_0` and `_1` (no crawl). Tune the three defaults until clumps resemble refs 1/2; rerun.

- [ ] **Step 4: Near-camera check**

Temporarily put `Camera3D` inside `TreeA`'s canopy (or fly there in the editor): no clump vanishes, no flicker. Revert scene changes.

- [ ] **Step 5: Regression test still passes**

Run: `godot --headless --path . --script tests/check_leaf_materials.gd`
Expected: `PASS`.

- [ ] **Step 6: Commit**

```bash
git add shaders/leaf.gdshader
git commit -m "feat: scalloped canopy silhouettes"
```
