@tool
extends EditorScenePostImport
## Set project-wide via [importer_defaults] scene. Acts only on glbs that have a
## <name>.clumps.json sidecar (written by tools/treegen); other scenes pass through.

const FoliageBuilderScript := preload("res://addons/anime_trees/foliage/foliage_builder.gd")
const AnimeTreeScript := preload("res://addons/anime_trees/tree/anime_tree.gd")
const FOLIAGE_MAT := "res://addons/anime_trees/materials/foliage.tres"
const TRUNK_MAT := "res://addons/anime_trees/materials/trunk.tres"
## Per-preset LOD distance multiplier (big trees stay detailed further out).
const LOD_MUL := {banyan = 1.5, jungle_tall = 1.3, leaning = 1.0, broadleaf = 0.6}
const FOLIAGE_FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)


func _post_import(scene: Node) -> Object:
	var json_path := get_source_file().get_basename() + ".clumps.json"
	if not FileAccess.file_exists(json_path):
		return scene
	var root := build_tree(scene, json_path)
	scene.free()
	return root


static func build_tree(scene: Node, json_path: String) -> Node3D:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var clumps := FoliageBuilderScript.load_clumps(json_path)
	var seed := int(meta.seed)
	var trunk_mat := _mat(TRUNK_MAT)
	var foliage_mat := _mat(FOLIAGE_MAT)

	var root := Node3D.new()
	root.set_script(AnimeTreeScript)
	root.name = json_path.get_file().get_basename().get_basename()  # strip .clumps.json
	root.variant_id = root.name
	var mul: float = LOD_MUL.get(meta.preset, 1.0)
	root.lod0_end *= mul
	root.lod1_end *= mul

	var lod0 := _merge([
		[_mesh(scene, "Trunk_LOD0"), trunk_mat, 0],
		[_mesh(scene, "Roots_LOD0"), trunk_mat, 0],
		[FoliageBuilderScript.build(clumps, 20, 1.0, seed), foliage_mat, FOLIAGE_FORMAT],
	])
	var lod1 := _merge([
		[_mesh(scene, "Trunk_LOD1"), trunk_mat, 0],
		[_mesh(scene, "Roots_LOD1"), trunk_mat, 0],
		[FoliageBuilderScript.build(clumps, 6, 1.6, seed), foliage_mat, FOLIAGE_FORMAT],
	])
	_add(root, "LOD0", lod0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_add(root, "LOD1", lod1, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	var aabb := lod0.get_aabb()
	var quad := QuadMesh.new()
	var d := aabb.size.length()
	quad.size = Vector2(d, d)
	quad.center_offset = aabb.get_center()
	var imp := _add(root, "Impostor", quad, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	imp.visible = false  # enabled once an ImpostorSet is assigned (Task 7)
	root.apply_lod()
	return root


static func _mat(path: String) -> Material:
	return load(path) if ResourceLoader.exists(path) else StandardMaterial3D.new()


static func _mesh(scene: Node, name: String) -> Mesh:
	var mi := scene.find_child(name, true, false) as MeshInstance3D
	return mi.mesh if mi else null


## parts: [[mesh or null, material, extra format flags]] -> one surface per part (LODs stripped)
static func _merge(parts: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	for p in parts:
		var m: Mesh = p[0]
		if m == null:
			continue
		for s in m.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s), [], {}, p[2])
			out.surface_set_material(out.get_surface_count() - 1, p[1])
		if m.custom_aabb != AABB():
			out.custom_aabb = out.get_aabb().merge(m.custom_aabb)
	return out


static func _add(root: Node3D, name: String, mesh: Mesh, shadows: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.cast_shadow = shadows
	root.add_child(mi)
	mi.owner = root
	return mi
