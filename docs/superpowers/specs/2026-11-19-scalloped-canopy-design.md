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
