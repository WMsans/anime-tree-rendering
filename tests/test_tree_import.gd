extends TestCase

var tree: Node


func _load(name := "banyan_001") -> Node:
	return (load("res://assets/trees/%s.glb" % name) as PackedScene).instantiate()


func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	return n


func test_scene_structure() -> void:
	tree = _load()
	check(tree is AnimeTree, "root is %s" % tree.get_class())
	for n in ["LOD0", "LOD1", "Impostor"]:
		check(tree.get_node_or_null(n) is MeshInstance3D, "missing " + n)
	check(tree.variant_id == "banyan_001", "variant_id %s" % tree.variant_id)
	tree.free()


func test_visibility_ranges() -> void:
	tree = _load()
	tree.apply_lod()
	var l0: GeometryInstance3D = tree.get_node("LOD0")
	var l1: GeometryInstance3D = tree.get_node("LOD1")
	var im: GeometryInstance3D = tree.get_node("Impostor")
	check(near(l0.visibility_range_end, tree.lod0_end), "LOD0 end")
	check(near(l1.visibility_range_begin, tree.lod0_end), "LOD1 begin")
	check(near(l1.visibility_range_end, tree.lod1_end), "LOD1 end")
	check(near(im.visibility_range_begin, tree.lod1_end), "Impostor begin")
	check(near(im.visibility_range_end, tree.impostor_end), "Impostor end")
	for g in [l0, l1, im]:
		check(g.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF, "fade mode")
	check(tree.lod0_end > 30.0, "banyan LOD distance multiplier applied: %f" % tree.lod0_end)
	tree.free()


func test_lod1_cheaper() -> void:
	tree = _load()
	var t0 := _tris(tree.get_node("LOD0").mesh)
	var t1 := _tris(tree.get_node("LOD1").mesh)
	check(t1 < 0.5 * t0, "LOD1 %d vs LOD0 %d" % [t1, t0])
	tree.free()


func test_no_auto_lods() -> void:
	tree = _load()
	var mesh: Mesh = tree.get_node("LOD0").mesh
	for s in mesh.get_surface_count():
		var lods: Array = RenderingServer.mesh_get_surface(mesh.get_rid(), s).get("lods", [])
		check(lods.is_empty(), "surface %d has %d auto LODs" % [s, lods.size()])
	tree.free()


func test_shadows() -> void:
	tree = _load()
	check(tree.get_node("LOD0").cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "LOD0 casts")
	check(tree.get_node("LOD1").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "LOD1 off")
	check(tree.get_node("Impostor").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Impostor off")
	tree.free()


func test_imported_foliage_overlaps_trunk_top() -> void:
	for name in ["banyan_001", "leaning_001", "jungle_tall_001", "broadleaf_001"]:
		tree = _load(name)
		var mesh: ArrayMesh = tree.get_node("LOD0").mesh
		var trunk := _surface_aabb(mesh, 0)
		var foliage := _surface_aabb(mesh, mesh.get_surface_count() - 1)
		check(foliage.get_center().y > 0.4 * trunk.size.y, "%s foliage center too low" % name)
		check(foliage.intersects(trunk), "%s foliage not on trunk" % name)
		tree.free()


func _surface_aabb(mesh: ArrayMesh, s: int) -> AABB:
	var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
	var a := AABB(v[0], Vector3.ZERO)
	for p in v:
		a = a.expand(p)
	return a
