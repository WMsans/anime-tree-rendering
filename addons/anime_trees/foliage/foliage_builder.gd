@tool
class_name FoliageBuilder
extends RefCounted
## Builds the leaf-clump card mesh. Shader contract (foliage.gdshader):
##   VERTEX  = card center (object space), expanded to a camera-facing quad in the shader
##   UV      = card corner 0..1
##   UV2     = (scallop atlas cell 0..3, random 0..1)
##   CUSTOM0 = clump center xyz, clump radius
##   CUSTOM1 = clump ellipsoid scale xyz, card half-size

const CORNERS := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]


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
	for clump in clumps:
		var center: Vector3 = clump.center
		var radius: float = clump.radius
		var scl: Vector3 = clump.scale
		var half := radius * 0.45 * card_size_mul
		max_half = maxf(max_half, half)
		for i in cards_per_clump:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			while dir.length_squared() > 1.0 or dir.length_squared() < 1e-4:
				dir = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			var p := center + dir.normalized() * radius * rng.randf_range(0.55, 0.95) * scl
			var cell := float(rng.randi_range(0, 3))
			var rnd := rng.randf()
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
