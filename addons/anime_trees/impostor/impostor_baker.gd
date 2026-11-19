@tool
class_name ImpostorBaker
extends Node
## Bakes relightable hemi-octahedral impostors for tree variants with this scene's sun.
## Per variant: <id>_albedo.res (lit-band color, sRGB; alpha 1 = covered, 0.5 = ink, 0 = empty)
## and <id>_ndsh.res (RG octa object normal, B depth01, A = self-shadow bits for 8 sun azimuths).

const FOLIAGE_MAT := preload("res://addons/anime_trees/materials/foliage.tres")
const IMPOSTOR_SHADER := preload("res://addons/anime_trees/shaders/impostor.gdshader")
const OutlineEffectScript := preload("res://addons/anime_trees/outline/outline_effect.gd")
const SETTLE_FRAMES := 3

@export var variants: Array[PackedScene] = []
@export var sun: DirectionalLight3D
@export var output_dir := ""  ## default: res://impostors/<scene name>/
@export var frame_px := 128
@export_tool_button("Bake impostors", "Bake") var bake_button := _bake_from_editor

## Last value written to the anime_tree_bake_mode global (the getter is editor-only).
static var bake_mode := 0
var _busy := false
var _vps: Array[SubViewport] = []
var _cams: Array[Camera3D] = []
var _holder: Node3D
var _light: DirectionalLight3D
var _compositor: Compositor


func _bake_from_editor() -> void:
	await bake()
	print("ImpostorBaker: baked %d variants into %s" % [variants.size(), _out_dir()])


func _out_dir() -> String:
	var d := output_dir
	if d == "":
		var base := owner.scene_file_path if owner else ""
		d = "res://impostors/%s/" % (base.get_file().get_basename() if base != "" else String(name))
	return d if d.ends_with("/") else d + "/"


## Re-bakes update the existing set / materials / textures in place, so scenes holding them
## keep valid references (and never embed orphaned copies on save).
func bake() -> ImpostorSet:
	if _busy:
		push_warning("ImpostorBaker: a bake is already running")
		return null
	_busy = true
	var dir := _out_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var set_path := dir + "impostor_set.tres"
	var set: ImpostorSet = load(set_path) if ResourceLoader.exists(set_path) else null
	if set == null:
		set = ImpostorSet.new()
	var baked := {}
	_make_rig()
	for ps in variants:
		var tree := ps.instantiate() if ps else null
		if not _is_bakeable(tree):
			push_warning("ImpostorBaker: skipping %s (not an imported AnimeTree)" % (ps.resource_path if ps else "null"))
			if tree:
				tree.free()
			continue
		var id: String = tree.variant_id  # read before the await: _bake_variant frees the tree
		set.entries[id] = await _bake_variant(tree, dir, set.entries.get(id))
		baked[id] = true
	for id in set.entries.keys():
		if not baked.has(id):
			set.entries.erase(id)
	_free_rig()
	_set_mode(0)
	ResourceSaver.save(set, set_path)
	if set.resource_path != set_path:
		set.take_over_path(set_path)
	_busy = false
	return set


static func _set_mode(m: int) -> void:
	bake_mode = m
	RenderingServer.global_shader_parameter_set("anime_tree_bake_mode", m)


func _is_bakeable(tree: Node) -> bool:
	if not tree is AnimeTree:
		return false
	var lod0 := tree.get_node_or_null("LOD0") as MeshInstance3D
	return lod0 != null and lod0.mesh != null and tree.get_node_or_null("LOD1") != null \
		and tree.get_node_or_null("Impostor") != null


func _exit_tree() -> void:
	if _busy:  # freed / scene closed mid-bake: don't leave every tree rendering a bake pass
		_set_mode(0)


func _make_rig() -> void:
	_free_rig()
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = env
	_compositor = Compositor.new()
	var ink := OutlineEffectScript.new()
	ink.line_width_px = 2.0 * 1080.0 / frame_px  # 2 px ink inside each frame
	_compositor.compositor_effects = [ink]
	for i in HemiOct.FRAMES * HemiOct.FRAMES:
		var vp := SubViewport.new()
		vp.size = Vector2i(frame_px, frame_px)
		vp.transparent_bg = true
		vp.use_hdr_2d = true
		vp.world_3d = world
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		vp.add_child(cam)
		add_child(vp)
		cam.make_current()
		_vps.append(vp)
		_cams.append(cam)
	_holder = Node3D.new()
	_vps[0].add_child(_holder)
	_light = DirectionalLight3D.new()
	_light.shadow_enabled = true
	_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_holder.add_child(_light)


func _free_rig() -> void:
	for vp in _vps:
		remove_child(vp)
		vp.queue_free()
	_vps.clear()
	_cams.clear()


func _bake_variant(tree: AnimeTree, dir: String, existing: ShaderMaterial) -> ShaderMaterial:
	var id := tree.variant_id
	_holder.add_child(tree)
	tree.get_node("LOD1").visible = false
	tree.get_node("Impostor").visible = false
	var lod0: GeometryInstance3D = tree.get_node("LOD0")
	lod0.visibility_range_begin = 0.0
	lod0.visibility_range_end = 0.0
	lod0.set_instance_shader_parameter("lod_range", Vector3(0.0, 1e9, 0.0))
	var aabb: AABB = lod0.mesh.get_aabb()
	var c := aabb.get_center()
	var r := aabb.size.length() * 0.5
	for i in _cams.size():
		var d := HemiOct.frame_dir(i % HemiOct.FRAMES, i / HemiOct.FRAMES)
		_cams[i].global_transform = Transform3D(HemiOct.frame_basis(d), c + d * 2.0 * r)
		_cams[i].size = 2.0 * r
		_cams[i].near = 0.05
		_cams[i].far = 4.0 * r
	RenderingServer.global_shader_parameter_set("anime_tree_bake_depth_range", Vector2(r, 3.0 * r))
	_light.directional_shadow_max_distance = 6.0 * r

	var ink := await _pass(1, true)
	var plain := await _pass(1, false)
	var nd := await _pass(2, false)
	var el := deg_to_rad(50.0)
	if sun:
		el = asin(clampf(sun.global_basis.z.normalized().y, -1.0, 1.0))
	var shadows: Array = []
	for k in HemiOct.SHADOW_AZIMUTHS:
		var az := k * TAU / HemiOct.SHADOW_AZIMUTHS
		var to_light := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
		_light.global_basis = Basis.looking_at(-to_light, Vector3.UP if absf(to_light.y) < 0.999 else Vector3.FORWARD)
		shadows.append(await _pass(3, false))
	_holder.remove_child(tree)
	tree.free()

	var n := HemiOct.FRAMES * frame_px
	var albedo := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var ndsh := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for i in _vps.size():
		var at := Vector2i(i % HemiOct.FRAMES, i / HemiOct.FRAMES) * frame_px
		var sh: Array[PackedByteArray] = []
		for k in shadows.size():
			sh.append(shadows[k][i].get_data())
		var frames := _encode_frame(ink[i].get_data(), plain[i].get_data(), nd[i].get_data(), sh)
		albedo.blit_rect(frames[0], Rect2i(Vector2i.ZERO, Vector2i(frame_px, frame_px)), at)
		ndsh.blit_rect(frames[1], Rect2i(Vector2i.ZERO, Vector2i(frame_px, frame_px)), at)

	albedo.generate_mipmaps()
	var alb_tex := _save_tex(albedo, dir + id + "_albedo.res")
	var nd_tex := _save_tex(_point_mipmaps(ndsh), dir + id + "_ndsh.res")
	var mat := existing if existing else ShaderMaterial.new()
	mat.shader = IMPOSTOR_SHADER
	mat.set_shader_parameter("albedo_atlas", alb_tex)
	mat.set_shader_parameter("ndsh_atlas", nd_tex)
	mat.set_shader_parameter("impostor_center", c)
	mat.set_shader_parameter("impostor_radius", r)
	var lit := _foliage_param("lit_color")
	mat.set_shader_parameter("mid_ratio", _foliage_param("mid_color") / lit)
	mat.set_shader_parameter("dark_ratio", _foliage_param("dark_color") / lit)
	return mat


## Renders all frames in one bake mode. Returns RGBA8 images (albedo pass sRGB-encoded).
func _pass(mode: int, outline: bool) -> Array[Image]:
	_set_mode(mode)
	for cam in _cams:
		cam.compositor = _compositor if outline else null
	for f in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var out: Array[Image] = []
	for vp in _vps:
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if mode == 1:
			img.linear_to_srgb()
		out.append(img)
	return out


func _encode_frame(ink: PackedByteArray, plain: PackedByteArray, nd: PackedByteArray,
		sh: Array[PackedByteArray]) -> Array[Image]:
	var alb := ink.duplicate()
	var nds := nd.duplicate()
	for p in range(0, alb.size(), 4):
		if plain[p + 3] < 128:
			alb[p + 3] = 0
			nds[p + 3] = 0
			continue
		var diff := absi(ink[p] - plain[p]) + absi(ink[p + 1] - plain[p + 1]) + absi(ink[p + 2] - plain[p + 2])
		alb[p + 3] = 128 if diff > 30 else 255
		var bits := 0
		for k in sh.size():
			if sh[k][p] > 127:
				bits |= 1 << k
		nds[p + 3] = bits
	return [Image.create_from_data(frame_px, frame_px, false, Image.FORMAT_RGBA8, alb),
		Image.create_from_data(frame_px, frame_px, false, Image.FORMAT_RGBA8, nds)]


## Mip chain by point sampling: averaging would corrupt octa normals and shadow bit masks.
func _point_mipmaps(img: Image) -> Image:
	var data := img.get_data()
	var level := img
	while level.get_width() > 1:
		level = level.duplicate()
		level.resize(level.get_width() / 2, level.get_height() / 2, Image.INTERPOLATE_NEAREST)
		data.append_array(level.get_data())
	return Image.create_from_data(img.get_width(), img.get_height(), true, Image.FORMAT_RGBA8, data)


## Reuses the texture already loaded from `path` (scenes may hold it) and overwrites its data.
func _save_tex(img: Image, path: String) -> Texture2D:
	var tex: PortableCompressedTexture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as PortableCompressedTexture2D
	if tex == null:
		tex = PortableCompressedTexture2D.new()
	tex.keep_compressed_buffer = true  # outside the editor the buffer is dropped and can't be saved
	tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	ResourceSaver.save(tex, path)
	if tex.resource_path != path:
		tex.take_over_path(path)
	return tex


func _foliage_param(p: String) -> Vector3:
	var v = FOLIAGE_MAT.get_shader_parameter(p)
	if v == null:
		v = RenderingServer.shader_get_parameter_default(FOLIAGE_MAT.shader.get_rid(), p)
	var c: Color = v if v is Color else Color(v.x, v.y, v.z)
	c = c.srgb_to_linear()  # source_color uniforms are authored in sRGB; ratios must be linear
	return Vector3(c.r, c.g, c.b)
