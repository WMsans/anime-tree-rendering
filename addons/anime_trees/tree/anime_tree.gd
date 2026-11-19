@tool
class_name AnimeTree
extends Node3D
## Root of an imported tree variant. Children: LOD0, LOD1, Impostor (MeshInstance3D).
## Manual LOD via Godot visibility ranges; distances are per tree and editable.

@export var lod0_end := 30.0:
	set(v): lod0_end = v; apply_lod()
@export var lod1_end := 120.0:
	set(v): lod1_end = v; apply_lod()
@export var impostor_end := 2000.0:
	set(v): impostor_end = v; apply_lod()
@export var fade_margin := 8.0:
	set(v): fade_margin = v; apply_lod()
@export var impostor_set: ImpostorSet:
	set(v): impostor_set = v; _apply_impostor()
@export var variant_id := ""


func _ready() -> void:
	apply_lod()
	_apply_impostor()


func _apply_impostor() -> void:
	var imp := get_node_or_null("Impostor") as MeshInstance3D
	if imp == null:
		return
	var mat: Material = impostor_set.entries.get(variant_id) if impostor_set else null
	imp.material_override = mat
	imp.visible = mat != null


## Visibility ranges overlap by fade_margin; inside the overlap the shaders dither-crossfade
## (lod_range instance uniform). Godot's own fade is alpha-blended, which would drop the
## trees out of the depth/normal buffers and so out of the outline.
func apply_lod() -> void:
	var m := fade_margin
	var ranges := {
		"LOD0": Vector2(0.0, lod0_end),
		"LOD1": Vector2(lod0_end, lod1_end),
		"Impostor": Vector2(lod1_end, impostor_end),
	}
	for n in ranges:
		var g := get_node_or_null(n) as GeometryInstance3D
		if g == null:
			continue
		var r: Vector2 = ranges[n]
		g.visibility_range_begin = maxf(0.0, r.x - m) if r.x > 0.0 else 0.0
		g.visibility_range_end = r.y + m if n != "Impostor" else r.y
		g.visibility_range_begin_margin = 0.0
		g.visibility_range_end_margin = 0.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		g.set_instance_shader_parameter("lod_range", Vector3(r.x, r.y, m))
