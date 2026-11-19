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


func test_rebake_keeps_live_references() -> void:
	# Scenes hold the loaded set; a re-bake must update it in place, not orphan it.
	var b := _baker()
	await b.bake()
	var held: ImpostorSet = load(OUT + "impostor_set.tres")
	var held_mat: ShaderMaterial = held.entries["broadleaf_001"]
	var held_tex: Texture2D = held_mat.get_shader_parameter("albedo_atlas")
	await b.bake()
	b.queue_free()
	check(held.resource_path == OUT + "impostor_set.tres", "set lost its path: '%s'" % held.resource_path)
	check(held_tex.resource_path == OUT + "broadleaf_001_albedo.res", "texture lost its path: '%s'" % held_tex.resource_path)
	check(held.entries["broadleaf_001"] == held_mat, "material replaced instead of updated")


var _first_done := false


func _bake_in_background(b: ImpostorBaker) -> void:
	await b.bake()
	_first_done = true


func test_concurrent_bake_is_rejected() -> void:
	var b := _baker()
	_first_done = false
	_bake_in_background.call(b)  # not awaited: still running
	var second: ImpostorSet = await b.bake()
	check(second == null, "second bake should be rejected while one is running")
	while not _first_done:
		await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	check(b.get_child_count() == 1, "rig not freed: %d children" % b.get_child_count())
	b.queue_free()


func test_bad_variant_skipped_and_cleaned_up() -> void:
	var b := _baker()
	var bad := PackedScene.new()
	bad.pack(Node3D.new())
	b.variants = [bad, load("res://assets/trees/broadleaf_001.glb")]
	var set: ImpostorSet = await b.bake()
	await Engine.get_main_loop().process_frame
	check(set != null and set.entries.has("broadleaf_001"), "good variant not baked")
	check(ImpostorBaker.bake_mode == 0, "bake mode left set: %d" % ImpostorBaker.bake_mode)
	check(b.get_child_count() == 1, "rig not freed: %d children" % b.get_child_count())
	b.queue_free()


func _impostor_coverage(cam_dir: Vector3) -> int:
	# Renders one impostor (always in impostor range) and counts covered pixels.
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var set: ImpostorSet = load(OUT + "impostor_set.tres")
	var t: AnimeTree = (load("res://assets/trees/broadleaf_001.glb") as PackedScene).instantiate()
	t.impostor_set = set
	t.lod0_end = 0.5
	t.lod1_end = 1.0
	vp.add_child(t)
	var cam := Camera3D.new()
	cam.fov = 4.0
	vp.add_child(cam)
	var c: Vector3 = (set.entries["broadleaf_001"] as ShaderMaterial).get_shader_parameter("impostor_center")
	cam.look_at_from_position(c + cam_dir.normalized() * 300.0, c, Vector3.FORWARD if absf(cam_dir.y) > 0.99 else Vector3.UP)
	cam.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			n += int(img.get_pixel(x, y).a > 0.5)
	return n


func test_impostor_dither_band_keeps_coverage() -> void:
	# Straight down is a permanent 4-frame dither (8x8 grid has no centre frame); mip selection
	# there must not collapse coverage compared with a view inside a single frame.
	var b := _baker()
	await b.bake()
	b.queue_free()
	var in_frame := await _impostor_coverage(HemiOct.frame_dir(4, 4))
	var band := await _impostor_coverage(Vector3.UP)
	check(in_frame > 500, "baseline coverage too small: %d" % in_frame)
	check(absf(band - in_frame) < 0.35 * in_frame, "dither band coverage %d vs in-frame %d" % [band, in_frame])
