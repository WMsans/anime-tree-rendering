@tool
class_name Forest
extends Node3D
## Scatters tree variants and renders them as per-cell MultiMeshes, one per variant per LOD.
## Cell visibility ranges are widened by the cell radius; the shaders cull/dither each
## instance by its own distance (lod_range), so LOD still switches per tree.

@export var data: ForestData
@export var impostor_set: ImpostorSet
@export var ground: MeshInstance3D
@export var cell_size := 128.0     ## LOD1 / impostor cells
@export var lod0_cell_size := 32.0 ## LOD0 cells: small, so culled-but-drawn full trees stay few
@export var scatter_rect := Rect2(-200, -200, 400, 400)
@export var density_per_ha := 120.0
@export var variant_weights := PackedFloat32Array()  ## empty = uniform
@export var seed := 1
@export_tool_button("Scatter", "RandomNumberGenerator") var scatter_button := _scatter_and_rebuild
@export_tool_button("Rebuild", "Reload") var rebuild_button := rebuild

const LODS := ["LOD0", "LOD1", "Impostor"]
var _built: Node3D
var _warned := {}


func _ready() -> void:
	rebuild()


func _scatter_and_rebuild() -> void:
	scatter()
	rebuild()


## Deterministic jittered grid inside scatter_rect, snapped to `ground`.
func scatter() -> void:
	if data == null:
		data = ForestData.new()
	data.clear()
	var nv := data.variant_scenes.size()
	if nv == 0:
		push_warning("Forest: no variant_scenes in data")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var spacing := sqrt(10000.0 / maxf(density_per_ha, 0.01))
	var tri: TriangleMesh
	var gx := Transform3D.IDENTITY
	if ground and ground.mesh:
		tri = ground.mesh.generate_triangle_mesh()
		gx = ground.global_transform if ground.is_inside_tree() else ground.transform
	var gx_inv := gx.affine_inverse()
	var y := scatter_rect.position.y + spacing * 0.5
	while y < scatter_rect.end.y:
		var x := scatter_rect.position.x + spacing * 0.5
		while x < scatter_rect.end.x:
			var p := Vector3(x + rng.randf_range(-0.4, 0.4) * spacing, 0.0, y + rng.randf_range(-0.4, 0.4) * spacing)
			var v := _pick_variant(rng, nv)
			var yaw := rng.randf() * TAU
			var s := rng.randf_range(0.85, 1.2)
			x += spacing
			if tri:
				var hit := tri.intersect_ray(gx_inv * Vector3(p.x, 10000.0, p.z), gx_inv.basis * Vector3.DOWN)
				if hit.is_empty():
					continue
				p = gx * (hit.position as Vector3)
			data.add(v, p, yaw, s)
		y += spacing


func _pick_variant(rng: RandomNumberGenerator, nv: int) -> int:
	if variant_weights.size() != nv:
		return rng.randi_range(0, nv - 1)
	return rng.rand_weighted(variant_weights)


func rebuild() -> void:
	if _built:
		remove_child(_built)
		_built.free()
	_built = Node3D.new()
	_built.name = "_cells"
	add_child(_built)  # no owner: generated, never saved into the scene
	if data == null or data.count() == 0:
		return
	var variants := []
	for ps in data.variant_scenes:
		variants.append(_variant_info(ps))
	for lod: String in LODS:
		var size := lod0_cell_size if lod == "LOD0" else cell_size
		_build_lod(lod, size, ForestChunker.chunk(data, size), variants)


func _build_lod(lod: String, size: float, cells: Dictionary, variants: Array) -> void:
	var half := size * 0.5 * sqrt(2.0)
	for cell: Vector2i in cells:
		var center := Vector3((cell.x + 0.5) * size, 0.0, (cell.y + 0.5) * size)
		for vi: int in cells[cell]:
			var info: Dictionary = variants[vi]
			if info.meshes.has(lod):
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = info.meshes[lod]
				var xs: Array = cells[cell][vi]
				mm.instance_count = xs.size()
				for i in xs.size():
					mm.set_instance_transform(i, Transform3D(xs[i].basis, xs[i].origin - center))
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "%d_%d_%s_%s" % [cell.x, cell.y, info.id, lod]
				mmi.multimesh = mm
				mmi.position = center
				if info.materials.has(lod):
					mmi.material_override = info.materials[lod]
				mmi.cast_shadow = info.shadows[lod]
				var r: Vector2 = info.ranges[lod]  # begin, end
				mmi.visibility_range_begin = maxf(0.0, r.x - half) if r.x > 0.0 else 0.0
				mmi.visibility_range_end = r.y + half
				mmi.set_instance_shader_parameter("lod_range", r)
				_built.add_child(mmi)


func _variant_info(ps: PackedScene) -> Dictionary:
	var tree := ps.instantiate() as AnimeTree
	var info := {id = tree.variant_id, meshes = {}, materials = {}, shadows = {}, ranges = {}}
	var ranges := {LOD0 = Vector2(0.0, tree.lod0_end), LOD1 = Vector2(tree.lod0_end, tree.lod1_end),
		Impostor = Vector2(tree.lod1_end, tree.impostor_end)}
	for lod: String in LODS:
		var mi := tree.get_node_or_null(lod) as MeshInstance3D
		if mi == null:
			continue
		if lod == "Impostor":
			var mat: Material = impostor_set.entries.get(tree.variant_id) if impostor_set else null
			if mat == null:
				if not _warned.has(tree.variant_id):
					_warned[tree.variant_id] = true
					push_warning("Forest: no baked impostor for %s; far trees skipped" % tree.variant_id)
				continue
			info.materials[lod] = mat
		info.meshes[lod] = mi.mesh
		info.shadows[lod] = mi.cast_shadow
		info.ranges[lod] = ranges[lod]
	tree.free()
	return info
