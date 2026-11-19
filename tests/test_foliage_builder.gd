extends TestCase

const CLUMPS: Array[Dictionary] = [
	{center = Vector3(0, 5, 0), radius = 2.0, scale = Vector3(1, 0.8, 1)},
	{center = Vector3(3, 6, 1), radius = 1.5, scale = Vector3(1, 0.7, 1)},
	{center = Vector3(-2, 4, -1), radius = 1.0, scale = Vector3(1, 1, 1)},
]


func _arrays(seed := 1) -> Array:
	return FoliageBuilder.build(CLUMPS, 20, 1.0, seed).surface_get_arrays(0)


func test_card_count() -> void:
	var a := _arrays()
	check(a[Mesh.ARRAY_VERTEX].size() == 240, "verts %d" % a[Mesh.ARRAY_VERTEX].size())
	check(a[Mesh.ARRAY_INDEX].size() == 360, "indices %d" % a[Mesh.ARRAY_INDEX].size())


func test_custom0_is_center() -> void:
	var a := _arrays()
	var c0: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	for card in 60:
		var clump: Dictionary = CLUMPS[card / 20]
		for k in 4:
			var i := (card * 4 + k) * 4
			var c := Vector3(c0[i], c0[i + 1], c0[i + 2])
			check(c.is_equal_approx(clump.center), "vertex %d center %s" % [card * 4 + k, c])
			check(near(c0[i + 3], clump.radius), "radius")


func test_cards_inside_ellipsoid() -> void:
	var v: PackedVector3Array = _arrays()[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var clump: Dictionary = CLUMPS[i / 80]
		var local: Vector3 = (v[i] - clump.center) / (clump.radius * clump.scale)
		check(local.length() <= 1.0001, "vertex %d outside: %f" % [i, local.length()])


func test_deterministic() -> void:
	check(_arrays(5)[Mesh.ARRAY_VERTEX] == _arrays(5)[Mesh.ARRAY_VERTEX], "same seed differs")
	check(_arrays(5)[Mesh.ARRAY_VERTEX] != _arrays(6)[Mesh.ARRAY_VERTEX], "different seeds equal")


func test_load_clumps() -> void:
	var path := "res://assets/trees/broadleaf_001.clumps.json"
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var clumps := FoliageBuilder.load_clumps(path)
	check(clumps.size() == raw.clumps.size(), "count")
	check(clumps[0].center is Vector3, "center type")


func test_blob_groups() -> void:
	var clumps := FoliageBuilder.load_clumps("res://assets/trees/broadleaf_001.clumps.json")
	var g := FoliageBuilder.blob_groups(clumps, 7)
	check(g.size() == clumps.size(), "one group per clump")
	var used := {}
	for x in g:
		check(x >= 0 and x < 7, "group %d out of range" % x)
		used[x] = true
	check(used.size() == 7, "all blobs used: %d" % used.size())
	# Group index rides in UV2.x above the atlas cell; cards sorted bottom -> top per clump.
	var a := _arrays()
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in uv2.size():
		check(fmod(uv2[i].x, 4.0) <= 3.0, "cell")
	for card in 59:
		if card % 20 != 19:
			check(v[card * 4].y <= v[card * 4 + 4].y, "card %d not sorted by height" % card)
