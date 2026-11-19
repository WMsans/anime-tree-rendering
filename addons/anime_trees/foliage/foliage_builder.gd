@tool
class_name FoliageBuilder
extends RefCounted
## Builds the leaf-clump card mesh. Shader contract (foliage.gdshader):
##   VERTEX  = card center (object space), expanded to a camera-facing quad in the shader
##   UV      = card corner 0..1
##   UV2     = (atlas cell 0..3 + 4 * outline blob index, random 0..1)
## Cards of a clump are emitted bottom -> top: they share one depth in the shader, so the later
## (higher) card is drawn on top.
##   CUSTOM0 = clump center xyz, clump radius
##   CUSTOM1 = clump ellipsoid scale xyz, card half-size

const CORNERS := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
## Average clumps per outline blob: the outline pass inks blob silhouettes only (refs 1, 8).
const CLUMPS_PER_BLOB := 6


static func load_clumps(json_path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if data == null:
		push_error("FoliageBuilder: cannot parse %s" % json_path)
		return out
	for c in data.clumps:
		out.append({
			center = Vector3(c.center[0], c.center[1], c.center[2]),
			radius = float(c.radius),
			scale = Vector3(c.scale[0], c.scale[1], c.scale[2]),
		})
	return out


static func build(clumps: Array[Dictionary], cards_per_clump: int, card_size_mul: float, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	var aabb := AABB()
	var max_half := 0.0
	var groups := blob_groups(clumps, maxi(1, roundi(clumps.size() / float(CLUMPS_PER_BLOB))))
	for ci in clumps.size():
		var clump := clumps[ci]
		var center: Vector3 = clump.center
		var radius: float = clump.radius
		var scl: Vector3 = clump.scale
		var half := radius * 0.45 * card_size_mul
		max_half = maxf(max_half, half)
		var cards := []
		for i in cards_per_clump:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			while dir.length_squared() > 1.0 or dir.length_squared() < 1e-4:
				dir = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			var p := center + dir.normalized() * radius * rng.randf_range(0.55, 0.95) * scl
			cards.append([p, float(rng.randi_range(0, 3)) + 4.0 * groups[ci], rng.randf()])
		cards.sort_custom(func(a, b): return a[0].y < b[0].y)
		for card in cards:
			var p: Vector3 = card[0]
			var cell: float = card[1]
			var rnd: float = card[2]
			var base := verts.size()
			for k in 4:
				verts.append(p)
				uvs.append(CORNERS[k])
				uv2s.append(Vector2(cell, rnd))
				c0.append_array([center.x, center.y, center.z, radius])
				c1.append_array([scl.x, scl.y, scl.z, half])
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
			aabb = AABB(p, Vector3.ZERO) if verts.size() == 4 else aabb.expand(p)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_INDEX] = idx
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	mesh.custom_aabb = aabb.grow(max_half)
	return mesh


## k-means over clump centers (farthest-point init, deterministic): clump index -> blob index.
static func blob_groups(clumps: Array[Dictionary], k: int) -> PackedInt32Array:
	var n := clumps.size()
	var out := PackedInt32Array()
	out.resize(n)
	if n == 0:
		return out
	k = mini(k, n)
	var cents: Array[Vector3] = [clumps[0].center]
	while cents.size() < k:
		var best := 0
		var best_d := -1.0
		for i in n:
			var d := INF
			for c in cents:
				d = minf(d, c.distance_squared_to(clumps[i].center))
			if d > best_d:
				best_d = d
				best = i
		cents.append(clumps[best].center)
	for _iter in 10:
		for i in n:
			var best := 0
			for j in k:
				if clumps[i].center.distance_squared_to(cents[j]) < clumps[i].center.distance_squared_to(cents[best]):
					best = j
			out[i] = best
		var sums: Array[Vector3] = []
		var counts := PackedInt32Array()
		sums.resize(k)
		sums.fill(Vector3.ZERO)
		counts.resize(k)
		for i in n:
			sums[out[i]] += clumps[i].center
			counts[out[i]] += 1
		for j in k:
			if counts[j] > 0:
				cents[j] = sums[j] / counts[j]
	return out
