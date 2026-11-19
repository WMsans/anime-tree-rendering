extends TestCase


func _data(n: int) -> ForestData:
	var d := ForestData.new()
	d.variant_scenes = [load("res://assets/trees/broadleaf_001.glb"), load("res://assets/trees/leaning_001.glb")]
	for i in n:
		d.add(i % 2, Vector3(i * 7.0 - 300.0, 0, (i % 13) * 11.0 - 50.0), i * 0.3, 1.0)
	return d


func test_chunk_negative_coords() -> void:
	check(ForestChunker.cell_of(Vector3(-0.5, 0, -64.5), 64.0) == Vector2i(-1, -2), str(ForestChunker.cell_of(Vector3(-0.5, 0, -64.5), 64.0)))
	check(ForestChunker.cell_of(Vector3(63.9, 5, 0), 64.0) == Vector2i(0, 0), "positive edge")


func test_chunk_empty() -> void:
	check(ForestChunker.chunk(ForestData.new(), 64.0).is_empty(), "empty data -> {}")


func test_chunk_counts() -> void:
	var cells := ForestChunker.chunk(_data(100), 64.0)
	var total := 0
	for cell in cells:
		for v in cells[cell]:
			total += cells[cell][v].size()
	check(total == 100, "total %d" % total)
	check(cells.size() > 1, "should span several cells")


func test_transform_has_yaw_scale() -> void:
	var d := ForestData.new()
	d.variant_scenes = [load("res://assets/trees/broadleaf_001.glb")]
	d.add(0, Vector3(1, 2, 3), 1.0, 1.2)
	var cells := ForestChunker.chunk(d, 64.0)
	var t: Transform3D = cells[Vector2i(0, 0)][0][0]
	check(t.basis.is_equal_approx(Basis(Vector3.UP, 1.0).scaled(Vector3.ONE * 1.2)), str(t.basis))
	check(t.origin.is_equal_approx(Vector3(1, 2, 3)), str(t.origin))


func _forest() -> Forest:
	var f := Forest.new()
	f.data = ForestData.new()
	f.data.variant_scenes = [load("res://assets/trees/broadleaf_001.glb"), load("res://assets/trees/jungle_tall_001.glb")]
	f.scatter_rect = Rect2(-50, -50, 100, 100)
	f.density_per_ha = 50.0
	f.seed = 7
	return f


func test_scatter_deterministic() -> void:
	var a := _forest()
	a.scatter()
	var b := _forest()
	b.scatter()
	check(a.data.count() > 20, "count %d" % a.data.count())
	check(a.data.instances == b.data.instances and a.data.scales == b.data.scales, "not deterministic")
	a.free()
	b.free()


func test_scatter_on_ground() -> void:
	var f := _forest()
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	g.mesh = pm
	g.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(10.0)), Vector3(0, 5, 0))
	f.ground = g
	f.scatter()
	var plane := Plane(g.transform.basis.y.normalized(), g.transform.origin)
	for i in f.data.count():
		var p := f.data.position(i)
		var expected: Vector3 = plane.intersects_ray(Vector3(p.x, 1000, p.z), Vector3.DOWN)
		check(absf(p.y - expected.y) < 0.05, "instance %d y %f vs %f" % [i, p.y, expected.y])
	g.free()
	f.free()


func test_forest_without_impostor_set() -> void:
	var f := _forest()
	f.scatter()
	f.rebuild()
	var mmis := f.find_children("*", "MultiMeshInstance3D", true, false)
	var names := mmis.map(func(n): return String(n.name))
	check(mmis.size() > 0, "no multimeshes")
	check(names.any(func(n): return n.contains("LOD0")), "no LOD0 multimesh")
	check(not names.any(func(n): return n.contains("Impostor")), "impostor multimesh without a set")
	f.free()


func test_cell_ranges_cover_instances() -> void:
	var f := _forest()
	f.scatter()
	f.rebuild()
	var n0 := 0
	var n1 := 0
	for mmi in f.get_child(0).get_children():
		var lod0: bool = String(mmi.name).ends_with("LOD0")
		var lr: Vector3 = mmi.get_instance_shader_parameter("lod_range")
		var half := (f.lod0_cell_size if lod0 else f.cell_size) * 0.5 * sqrt(2.0)
		check(absf(mmi.visibility_range_end - (lr.y + lr.z + half)) < 0.01, "%s end %f" % [mmi.name, mmi.visibility_range_end])
		n0 += int(lod0)
		n1 += int(String(mmi.name).ends_with("LOD1"))
	check(n0 > n1, "LOD0 should use smaller cells: %d vs %d" % [n0, n1])
	f.free()
