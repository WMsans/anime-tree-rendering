# Scalloped canopy silhouettes

## Intent
Make the leaf clumps in `demo/tree_demo.tscn` read like the hand-drawn foliage in
`docs/reference/`: the wavy, cauliflower-bump outline around every clump is the
signature of that look and the one thing the current smooth blobs lack.

## Goals
- Every leaf clump's silhouette is scalloped (round bumps), and the existing depth
  outline follows the scalloped edge.
- Bumps stay stuck to the clump as the camera moves (no swimming/crawling).
- Existing cel shading and outline passes keep working unchanged.

## Non-goals (this round)
- Inner lines between overlapping clumps. Explicitly unwanted.
- New fill/banding work. Cel shading already covers it.
- Depth haze / atmospheric perspective.
- Bark colour and streaks.

## Anti-goals
- Bumps that crawl, flicker or change count while orbiting the camera.
- Breaking the cel bands (lighting must stay the smooth blob lighting).

## Constraints
- Godot 4, Forward+, reverse-Z. Post passes read depth + opaque screen copy.
- Trees are Blender glTF exports from a generator on this machine; each leaf
  clump is its own node (`BranchLeaves_*`, `PineTier_*`), so `MODEL_MATRIX`
  origin is the clump centre. Materials: `Leaf_Green`, `Leaf_Light`.
- Meshes have POSITION + NORMAL only (no UVs). Approach A needs none.

## Approaches
- **A. Silhouette cut on existing blobs (picked).** Leaf material discards
  fragments near the silhouette (`dot(N, V)` small) where a scallop pattern says
  so. Pattern is indexed by screen-space angle around the projected clump centre.
  No model change, smooth shading kept, one small shader. Ceiling: scallop depth
  limited by the rim band width; no bumps inside a clump.
- B. Billboard leaf cards with painted cut-out texture + sphere normals. Closest to
  the drawings, but needs generator changes, UVs, a texture, and risks shading
  seams. Upgrade path if A's scallops look too shallow.
- C. Lumpier geometry from many small spheres. Real silhouettes, no shader trick,
  but heavy polycount and not what was asked ("shader tricks").

Picked A: shortest path to the look, fits the existing post-process pipeline.

## Decided
- Approach A.
- Trunk and branches are excluded: they keep their own `Tree_Trunk` /
  `Tree_Branch` materials; only `Leaf_Green` / `Leaf_Light` get the leaf shader.
- Tree models may be regenerated if needed (not needed for A).

## My calls (check these)
- **Pines get it too.** They share the leaf materials; costs nothing. Easy to
  exclude later with a separate material.
- **Fragment cut, not vertex displacement.** Discard writes no depth, so the depth
  outline traces the cut edge for free. The shadow pass discards too, so shadows
  get scalloped as well.
- **Pattern:** a primary bump `1 - |sin|`-style lobe at N bumps around the clump
  plus a smaller higher-frequency octave for the sub-bumps seen in the refs.
  Bump count is per clump (angle-based), so bigger clumps get bigger bumps.
- **Hook-up:** a `leaf.gdshader` with an albedo uniform, two `ShaderMaterial`
  `.tres` (green/light, colours copied from the glb), assigned via the glb import
  settings' material overrides, so regenerating trees keeps them.
- **Tunables (uniforms):** rim width, bump count, octave strength.

## Left to the builder
- Exact scallop function and default uniform values (tune by eye against refs 1, 2).
- Whether the projected-centre angle needs a fallback when the camera is inside a
  clump (it can just do nothing there).

## Revision (2026-11-19): screen-space grow replaces the silhouette cut
Approach A failed on the real meshes: leaf clumps are ~86-tri lumpy blobs with
normals radial from an off-origin centre, so no smooth "near the silhouette" value
exists and the cut gave radial spikes. Decided with the user:
- **Grow, not shrink, in screen space.** A post pass lets a non-leaf pixel take a
  nearby leaf pixel's colour and depth when it falls inside a round bump at that
  leaf's edge (shrinking can't work: what's behind a leaf is gone).
- **Leaf mask:** leaf shader writes `ROUGHNESS = 0.5` (no visual effect: Lambert,
  specular off); post passes read it from the normal/roughness buffer.
- **Bumps anchored to world position** of the leaf pixel (from depth), sized in
  metres, so they don't crawl and shrink with distance like the refs.
- **Grow only over farther surfaces** (sky, ground, trunk behind, farther clumps);
  a nearer trunk stays on top.
- Cel shading and outline both resolve each pixel through the same remap
  (shared `.gdshaderinc`), so grown pixels get cel bands and the depth outline
  traces the wavy edge.

## Revision 2 (2026-11-19): constant screen-size bumps, jump flood
User feedback: bumps crawled with the camera, too fine far away, too big/hairy up
close. Decided:
- **Bump size is constant in screen pixels** (`shader_globals/leaf_bump_px`).
- **Profile per clump:** leaf.gdshader computes a row of semicircles by on-screen
  angle around the clump origin (count from the clump's on-screen size, blended
  between whole counts so it morphs, not pops) and packs it into ROUGHNESS
  0.25..0.75. Bumps stay put under camera moves.
- **Jump flood** (`LeafSeedEffect`, CompositorEffect after opaque) gives each
  pixel its exact nearest leaf pixel via global `leaf_seed`; the shared include
  grows a pixel when it's within the bump height at that point.
