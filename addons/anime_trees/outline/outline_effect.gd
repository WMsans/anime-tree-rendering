@tool
class_name OutlineEffect
extends CompositorEffect
## Screen-space ink outline (spec §5). Add to a Camera3D's Compositor.
## Impostors write ROUGHNESS = 1.0: depth edges only (they carry baked interior ink).

@export var line_width_px := 3.0  ## at 1080p, scaled with render height
@export var depth_threshold := 0.02
@export var normal_threshold := 0.8
@export_range(0.0, 1.0) var darken := 0.35

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_normal_roughness = true
	_rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_setup)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for rid in [_pipeline, _shader, _sampler]:
			if rid.is_valid():
				_rd.free_rid(rid)


func _setup() -> void:
	if _rd == null:
		return
	var file: RDShaderFile = load("res://addons/anime_trees/outline/outline.glsl")
	_shader = _rd.shader_create_from_spirv(file.get_spirv())
	_pipeline = _rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	_sampler = _rd.sampler_create(ss)


func _render_callback(_type: int, render_data: RenderData) -> void:
	if _rd == null or not _pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var pc := PackedFloat32Array([size.x, size.y, line_width_px * size.y / 1080.0,
		depth_threshold, normal_threshold, darken, 0.0, 0.0]).to_byte_array()
	var groups := Vector3i(ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	for view in buffers.get_view_count():
		var color := _image_uniform(0, buffers.get_color_layer(view))
		var depth := _tex_uniform(1, buffers.get_depth_layer(view))
		var normal := _tex_uniform(2, buffers.get_texture("forward_clustered", "normal_roughness"))
		var set := UniformSetCacheRD.get_cache(_shader, 0, [color, depth, normal])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, set, 0)
		_rd.compute_list_set_push_constant(list, pc, pc.size())
		_rd.compute_list_dispatch(list, groups.x, groups.y, groups.z)
		_rd.compute_list_end()


func _image_uniform(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


func _tex_uniform(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(_sampler)
	u.add_id(tex)
	return u
