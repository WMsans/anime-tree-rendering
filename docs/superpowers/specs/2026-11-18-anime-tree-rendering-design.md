# Anime Tree Rendering — Design

Date: 2026-11-18
Engine: Godot 4.7 (Forward+), Blender 5.3 (headless, CLI)

## Intent

Build 3D trees whose look matches a set of reference frames from a 2D Chinese
cartoon (8 screenshots, stored as `docs/reference/1.png` … `8.png`; the screenshot
numbers used throughout this doc refer to these files). The trees must be cheap to render, use hand-authored LOD
levels (not Godot's automatic mesh LOD), and be cel-shaded. The user cannot
model trees, so tree geometry is generated procedurally.

The player experiences the trees in three ways, all of which must hold up:
1. **Walking under the canopy** — clumps seen from below, at arm's length.
2. **Looking at trees from a distance** — mid-range, side-on.
3. **Flying over the forest** — hundreds to thousands of crowns seen from above.

## The look (what "matches the screenshots" means)

- **Leaf clumps**: cauliflower-like masses with scalloped/fractal edges. Each
  clump has a dark ink outline on its *outer silhouette only*; no lines between
  the leaves inside a clump. Interior is flat: 2–3 tones of green plus darker
  irregular blotches.
- **Ink color is not black**: it is a dark version of the local color (dark
  green on leaves, dark olive-brown on trunks).
- **Trunks/branches**: olive-brown, cel-shaded, with hand-drawn bark lines
  following the trunk length and moss/lighter patches.
- **Banyan aerial roots / vines**: thin dark lines hanging straight down from
  branches; some fuse into pillar-like secondary trunks.
- Lighting reads as flat bands, not smooth gradients.

## Goals

- Four tree types, each a preset of one generator with a random seed:
  1. **Banyan** — huge spreading crown, flared multi-stem trunk, hanging
     aerial roots, some rooted pillar roots (screenshots 1, 4, 5).
  2. **Tall jungle** — tall straight trunk, high crown, few low branches
     (screenshots 3, 7).
  3. **Leaning/twisted** — trunk that leans and twists, multiple forks
     (screenshot 8).
  4. **Small broadleaf / bush** — fills gaps and understory (all screenshots).
- Close/mid foliage via camera-facing card clusters with spherified normals
  (approach A, below).
- Silhouette-only ink outlines via a screen-space post-process.
- Manually authored LOD levels with explicit switch distances.
- Far LOD = pre-rendered camera-facing impostors that work from the side
  *and* from above.
- **A reusable tool, not a one-off demo** (user decision): level designers
  generate tree variants, place forests in any scene, and bake impostors per
  scene, repeatedly, across many levels.
- **Placed trees can be freely rotated around their vertical axis and
  uniformly scaled** (user decision: free rotation preferred).
- Demo scene(s) covering the three viewing modes, for visual comparison and
  performance measurement.

## Non-goals

- **Depth fade / atmospheric color shift** — handled by fog, out of scope.
- **Day/night cycle or moving sun** — lighting is fixed per scene.
- **Wind animation** — *my call*: screenshots are static; not requested.
- **Collision / gameplay interaction** — *my call*: not requested.
- **Ground, grass, buildings, characters.** Palm-like fronds seen in
  screenshot 8 are out of scope (*my call*).

## Anti-goals (fails even if it technically works)

- Looks like generic low-poly 3D trees or "clay blobs" instead of drawn clumps.
- Ink lines appear between cards inside a clump.
- Scallops or outlines that crawl/shimmer as the camera moves.
- LOD swaps that visibly pop (color, outline weight, or silhouette jump).
- Impostors that look wrong when seen from above during flyover.

## Constraints

- Godot 4.7 Forward+, empty project at start.
- Blender 5.3 available at `/usr/bin/blender`; all generation runs headless
  (`blender -b --python ...`). The user never opens Blender.
- Performance target — *my call, user didn't specify*: mid-range gaming PC,
  60 fps at 1080p, ~2,000 trees in view during flyover, the majority of them
  impostors.
- Fixed lighting per scene (one DirectionalLight + environment). Different
  scenes may use different lighting.

## Approaches considered (for leaf clumps)

| | Approach | Trade-off |
|---|---|---|
| **A (chosen)** | Clusters of camera-facing alpha-scissor cards with a scalloped blob texture; normals spherified from clump center; screen-space outline | Proven stylized-tree technique; reads as one drawn mass from every angle incl. from below/above; cheap. Costs some overdraw; cards may visibly overlap/slide at arm's length (mitigated by near-camera fade). Outline thresholds need tuning. |
| B | Solid lumpy 3D blobs + inverted-hull outline | Stable up close, no post-process; but real scallops need lots of polygons and the result reads as clay, not drawing. |
| C | Smooth blobs, scallops cut in screen space | Cheapest geometry; scallops are screen-locked and crawl with camera motion. Ruled out. |

The user picked **A**.

For the tree geometry source, the user decided: trunks/branches come from
Blender, generated by a plugin or a custom script. **My call: a custom
Python generator script**, not Sapling Tree Gen, because it must also
emit clump anchor points, multiple LOD trunk meshes, aerial roots, and moss
masks in one consistent export — Sapling does none of these and would need
a wrapper anyway.

For far LOD, the user decided: **camera-facing cards from pre-rendered images**.

## Design

### 1. Blender generator (`tools/treegen/`)

- Entry: `blender -b --python tools/treegen/treegen.py -- --preset <name> --seed <n> --out <dir>`.
  A batch wrapper (shell or Python) generates a set of variants per preset.
- Presets are data (e.g. JSON or Python dicts) controlling: height, trunk
  radius & flare, lean, twist, branching depth/angles/counts, crown shape,
  clump size range & density, aerial-root count and probability of rooting.
- Branch skeleton → swept tube meshes with UVs running along branch length
  (U around, V along) so a bark-line texture follows the wood.
- Banyan: hanging aerial roots as thin tubes from branches to/toward the
  ground; a fraction reach the ground and thicken into pillar roots.
- Moss mask written to a vertex color channel (upward-facing + noise).
- Clump anchors: positions + radius (optionally ellipsoid scale) placed at
  branch tips / along outer branches, recorded so they survive glTF export
  (empties with custom properties, or a JSON sidecar — builder's choice).
- Export: one `.glb` per tree variant containing trunk LOD0 and LOD1
  (decimated) meshes, root meshes, and clump anchors.
- Hidden branches that sit fully inside clumps can be culled to save triangles.

### 2. Godot import (`addons/anime_trees/` or `tools/`)

- An `EditorScenePostImport` script (or an editor tool) turns each `.glb`
  into a tree scene (`.tscn`):
  - trunk MeshInstance3D per LOD,
  - foliage mesh per LOD built from clump anchors (see §3),
  - roots mesh,
  - impostor MeshInstance3D (see §6).
- Godot's automatic mesh LOD generation is **disabled** on these meshes.

### 3. Foliage clumps (approach A)

- Each clump = N quads scattered inside the clump ellipsoid (LOD0 ≈ 15–30,
  LOD1 ≈ 5–8 larger quads). All clumps of a tree are **merged into one
  ArrayMesh per LOD** → one foliage draw call per tree per LOD.
- Per-vertex data: card center, corner offset, clump center, random value
  (via CUSTOM channels / UV2).
- Vertex shader expands each card to face the camera.
- Shading normal = direction from clump center to card position (spherified),
  so light bands wrap the whole clump as one mass.
- Lighting: custom `light()` with a stepped ramp (2–3 tones) so the scene's
  DirectionalLight and its shadows produce flat bands and dappled shadow
  shapes (screenshot 6). Tone colors exposed as material uniforms per preset.
- Blotches: clump-space 3D noise (stable relative to clump, never screen-space)
  thresholded to darken patches.
- Card texture: a small atlas of scalloped blob masks (alpha scissor). Masks
  are authored procedurally or by hand — builder's choice — but the edge must
  read as the fractal scallop in screenshots 1, 2, 8.
- Near-camera handling: cards closer than a threshold shrink/dither out so the
  camera never sits inside a flat card.

### 4. Trunks, branches, roots

- Cel shader with the same stepped `light()` ramp.
- Bark lines: tileable hand-drawn-style line texture along V.
- Moss patches from vertex color mask + noise, flat lighter/greener tone.
- Aerial roots: tubes at LOD0, camera-facing ribbons or dropped at LOD1,
  baked into impostor at LOD2.

### 5. Outline (screen-space post-process)

- Godot 4.7 `CompositorEffect` (compute shader) on the main camera's
  `Compositor`.
- Edges detected from depth discontinuity + normal discontinuity
  (normal-roughness buffer). Spherified normals make cards inside a clump
  continuous, so lines only appear at clump silhouettes, between clumps,
  and on trunk edges.
- Ink color = scene color at the edge multiplied by a darkening factor
  (dark green on leaves, dark brown on trunks), not black.
- Line width in pixels, scaled with resolution (≈2 px at 1080p — *my call*).
- Thresholds exposed for tuning; ground/sky edges must not double-line.

### 6. LOD system

- Use Godot's **`visibility_range_begin/end` with fade** on each
  GeometryInstance3D — native, manual, per-node distances with hysteresis.
- Levels (distances set per preset, editable on the tree scene):
  - **LOD0** — full trunk + roots + full card clusters + shadows on.
  - **LOD1** — decimated trunk, fewer bigger cards, simplified/no roots,
    shadows optional.
  - **LOD2** — impostor card.
- Visibility-range fade (or dithered cross-fade) hides the swap.

### 7. Impostors (far LOD)

Research basis: the standard way to support rotated/relit impostors is to
bake albedo, normal and depth per frame and relight in the shader
([Octahedral imposters write-up](https://smailikhappy.github.io/posts/Octahedral_imposters/),
[three.js forest of octahedral impostors](https://discourse.threejs.org/t/a-forest-of-octahedral-impostors/85735)).
Fortnite uses upper-hemisphere impostors for all its trees
([Epic, VSM in Fortnite](https://www.unrealengine.com/en-US/tech-blog/virtual-shadow-maps-in-fortnite-battle-royale-chapter-4)).
The known weakness is lost self-shadowing; Unreal's Impostor Baker only
partially recovers it with a scatter mask
([UE Impostor Baker](https://dev.epicgames.com/documentation/en-us/unreal-engine/impostor-baker-plugin-in-unreal-engine)).

Design:
- **Hemi-octahedral impostors** (upper hemisphere only): each tree variant
  captured from a grid of directions (e.g. 8×8 frames at 256 px → 2048²
  atlas — builder tunes), correct from side and from above.
- **Relightable bake, not lit-color bake** — required by free rotation:
  - *Albedo* atlas: the cel base tone per pixel (unlit), with baked ink
    outlines and a flag (e.g. alpha bit / separate channel) marking ink pixels
    so relighting leaves them dark.
  - *Normal* atlas: the **spherified clump normals** for foliage and real
    normals for wood (the same normals the 3D cel shader uses), so the runtime
    stepped ramp produces identical bands to LOD1.
  - *Depth* atlas: for pixel depth offset (correct intersection with ground and
    neighbours) and to make impostors cast/receive shadow sensibly.
- **Self-shadowing with free rotation — my proposal, not found in the
  sources:** because lighting is fixed per scene, the sun's *elevation* is
  fixed; rotating an instance only changes the sun's *azimuth relative to the
  tree*. Self-shadowing is therefore a 1-D function of instance yaw. Bake a
  self-shadow mask for K relative sun azimuths (e.g. K = 8, packed into two
  RGBA8 atlases), and at runtime blend the two channels nearest to the
  instance's yaw. Cost: +2 bytes/texel per 8 azimuths, far cheaper than baking
  lit color per rotation. Rebake is needed when the scene's sun elevation
  changes (part of the per-scene bake anyway).
- Instance rotation is restricted to **yaw + uniform scale**; trees stay
  upright (tilt would need a full-sphere impostor).
- Baked **inside Godot**, using the real LOD0 tree, its cel shaders and
  outline effect, so the impostor matches the 3D tree at the swap. Runtime
  outline post-process must not re-outline impostors on top of baked lines
  (builder: e.g. exclude via normal/depth trick or a render layer).
- Bake is an **editor action per scene** reading that scene's
  DirectionalLight, writing atlases to a per-scene folder. Rebake when
  lighting or tree variants change. Bakes must be deterministic and
  re-runnable (reusable-tool requirement).
- Runtime shader picks frames from view direction (in the instance's local
  space, so yaw is handled) and blends neighbouring frames to avoid popping.
- Existing Godot 4 addon "Octahedral Impostor LOD"
  ([asset library](https://godotengine.org/asset-library/asset/5528); custom
  free license with credit) and the MIT Godot 3 plugin
  ([wojtekpil](https://relatedrepos.com/gh/wojtekpil/Godot-Octahedral-Impostors))
  can be used as references; builder decides whether to reuse code given the
  custom channels needed (shadow masks, ink flag, spherified normals).

### 7b. Forest placement (reusable tool)

- A placement tool (editor node, e.g. `Forest`) that scatters or paints tree
  instances on scene geometry and stores per instance: variant id, position,
  yaw, uniform scale — as a resource, so designers can re-scatter, edit, and
  rebake.
- Rendering is **chunked** (*my call*): the forest is split into grid cells;
  each cell holds one `MultiMeshInstance3D` per variant per LOD, with
  visibility ranges applied per cell. Reason: `MultiMesh` has no per-instance
  visibility range, and per-tree nodes won't reach ~2,000 visible trees.
  LOD therefore switches per cell with fade; cell size is a tuning knob.
- Individual hand-placed tree scenes (§2) must also work for hero trees.

### 8. Demo & verification

- Demo scene with a scattered forest using all four types, with three camera
  setups: ground walk under canopy, mid-distance orbit, flyover.
- Reference screenshots stored in repo; capture comparable views for
  side-by-side review.
- Measure frame time & draw calls in the flyover view against the target.

## Left to the builder

- Branching algorithm (recursive, space colonization, etc.) and mesh
  sweeping details.
- How clump anchors are carried through glTF (custom props vs sidecar).
- Exact card counts, atlas sizes, LOD distances, outline thresholds — tune
  against reference frames and the performance target.
- How scallop masks and bark-line textures are produced.
- File/folder layout beyond what's named above.
