extends TestCase
## GPU: godot --path . -s tests/run_tests.gd -- --gpu --only=gpu_impostor

const OUT := "res://tests/out/impostors/"
var root: Node


func attach(r: Node) -> void:
	root = r


func _baker() -> ImpostorBaker:
	var b := ImpostorBaker.new()
	b.variants = [load("res://assets/trees/broadleaf_001.glb")]
	b.output_dir = OUT
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	b.add_child(sun)
	b.sun = sun
	root.add_child(b)
	return b


func test_bake_writes_atlases() -> void:
	var b := _baker()
	var set: ImpostorSet = await b.bake()
	b.queue_free()
	check(set != null and set.entries.has("broadleaf_001"), "entry missing")
	for suffix: String in ["_albedo.res", "_ndsh.res"]:
		var path := OUT + "broadleaf_001" + suffix
		check(ResourceLoader.exists(path), "missing " + path)
		var tex: Texture2D = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(tex.get_width() == HemiOct.FRAMES * b.frame_px, "atlas size %d" % tex.get_width())
	check(ResourceLoader.exists(OUT + "impostor_set.tres"), "set not saved")
	for suffix: String in ["_albedo.res", "_ndsh.res"]:
		var img := (ResourceLoader.load(OUT + "broadleaf_001" + suffix, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D).get_image()
		check(img.has_mipmaps(), suffix + " has no mipmaps (far impostors alias)")
	# ndsh mips must be point-sampled: every mip texel alpha (shadow bits) exists in level 0
	var nd := (ResourceLoader.load(OUT + "broadleaf_001_ndsh.res", "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D).get_image()
	if nd.has_mipmaps():
		var lvl0 := {}
		var data := nd.get_data()
		var n0 := nd.get_width() * nd.get_height() * 4
		for p in range(3, n0, 4):
			lvl0[data[p]] = true
		for p in range(n0 + 3, data.size(), 4):
			if not lvl0.has(data[p]):
				check(false, "mip shadow bits %d not in level 0 (averaged?)" % data[p])
				break
	var albedo: Image = (ResourceLoader.load(OUT + "broadleaf_001_albedo.res", "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D).get_image()
	var covered := 0
	for y in range(0, albedo.get_height(), 4):
		for x in range(0, albedo.get_width(), 4):
			covered += int(albedo.get_pixel(x, y).a > 0.25)
	check(covered > 1000, "albedo nearly empty: %d" % covered)


func test_rebake_overwrites() -> void:
	var b := _baker()
	await b.bake()
	var files_a := DirAccess.get_files_at(OUT)
	await b.bake()
	var files_b := DirAccess.get_files_at(OUT)
	b.queue_free()
	check(files_a == files_b, "%s vs %s" % [files_a, files_b])
	var set: ImpostorSet = load(OUT + "impostor_set.tres")
	check(set.entries.get("broadleaf_001") is ShaderMaterial, "entry not loadable")
