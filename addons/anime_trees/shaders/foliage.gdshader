shader_type spatial;
// Camera-facing scalloped cards. Every card of a clump shades and writes depth as the
// clump ellipsoid, so normal + depth are continuous inside a clump and the outline pass
// only draws at clump silhouettes / between clumps.
render_mode skip_vertex_transform, cull_disabled, specular_disabled, ambient_light_disabled;

#include "res://addons/anime_trees/shaders/cel_ramp.gdshaderinc"

uniform sampler2D scallop_atlas : hint_default_white, filter_linear_mipmap;
uniform vec3 lit_color : source_color = vec3(0.373, 0.627, 0.165);
uniform vec3 mid_color : source_color = vec3(0.247, 0.518, 0.141);
uniform vec3 dark_color : source_color = vec3(0.173, 0.416, 0.118);
uniform float blotch_scale = 0.9;
uniform float blotch_threshold = 0.66;
uniform float near_fade_start = 1.5;
uniform float near_fade_end = 0.5;
uniform float alpha_cut = 0.5;

varying vec3 v_obj;       // fragment position on the card, object space
varying vec3 v_cam_obj;   // camera position, object space
varying vec3 v_fwd_obj;   // camera forward, object space (orthographic / shadow pass)
varying vec3 v_center;
varying vec3 v_radii;
varying vec2 v_atlas_uv;
varying float v_blotch;   // set in fragment, read in light

void vertex() {
	vec3 center_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float half_size = CUSTOM1.w;
	float d = length(center_view);
	half_size *= smoothstep(near_fade_end, near_fade_start, d);
	float a = UV2.y * TAU;
	vec2 corner = (UV * 2.0 - 1.0);
	corner = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * corner;
	// Uniform scale assumed (spec: yaw + uniform scale only).
	float model_scale = length(MODEL_MATRIX[0].xyz);
	vec3 view_pos = center_view + vec3(corner * half_size * model_scale, 0.0);
	mat4 inv_mv = inverse(MODELVIEW_MATRIX);
	v_obj = (inv_mv * vec4(view_pos, 1.0)).xyz;
	v_cam_obj = (inv_mv * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_fwd_obj = normalize((inv_mv * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	v_center = CUSTOM0.xyz;
	v_radii = CUSTOM0.w * CUSTOM1.xyz;
	float cell = UV2.x;
	v_atlas_uv = (UV + vec2(mod(cell, 2.0), floor(cell / 2.0))) * 0.5;
	VERTEX = view_pos;
	if (lod_out_of_range(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD, PROJECTION_MATRIX[3][3] == 1.0)) {
		VERTEX = vec3(0.0);
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	if (lod_discard(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] == 1.0)) {
		discard;
	}
	if (texture(scallop_atlas, v_atlas_uv).a < alpha_cut) {
		discard;
	}
	bool ortho = PROJECTION_MATRIX[3][3] == 1.0;
	vec3 rd = ortho ? v_fwd_obj : normalize(v_obj - v_cam_obj);
	vec3 ro = ortho ? v_obj - rd * dot(v_obj - v_center, rd) * 2.0 - rd * 4.0 * length(v_radii) : v_cam_obj;
	// Ray vs ellipsoid in unit-sphere space; on a miss use the closest approach (scallop fringe).
	vec3 q = (ro - v_center) / v_radii;
	vec3 dd = rd / v_radii;
	float a = dot(dd, dd);
	float b = dot(q, dd);
	float h = b * b - a * (dot(q, q) - 1.0);
	float t = h > 0.0 ? (-b - sqrt(h)) / a : -b / a;
	vec3 hit = ro + rd * t;
	vec3 n_obj = normalize((hit - v_center) / (v_radii * v_radii));

	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	vec3 hit_view = (mv * vec4(hit, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * vec4(hit_view, 1.0);
	DEPTH = clip.z / clip.w;
	LIGHT_VERTEX = hit_view; // shadows/lights sample at the ellipsoid surface, not the card
	NORMAL = normalize(mat3(mv) * n_obj);
	ROUGHNESS = 0.5;

	vec3 local = hit - v_center;
	v_blotch = step(blotch_threshold, cel_noise(local * blotch_scale + v_center * 1.7));

	ALBEDO = vec3(1.0);
	if (anime_tree_bake_mode == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = cel_pick(2 - int(v_blotch), lit_color, mid_color, dark_color);
	} else if (anime_tree_bake_mode == 2) {
		ALBEDO = vec3(0.0);
		float depth01 = (-hit_view.z - anime_tree_bake_depth_range.x)
				/ (anime_tree_bake_depth_range.y - anime_tree_bake_depth_range.x);
		EMISSION = vec3(oct_encode(n_obj), clamp(depth01, 0.0, 1.0));
	}
}

void light() {
	if (anime_tree_bake_mode == 3) {
		DIFFUSE_LIGHT += vec3(ATTENUATION);
	} else if (anime_tree_bake_mode == 0) {
		int band = cel_band(dot(NORMAL, LIGHT), ATTENUATION, int(v_blotch));
		DIFFUSE_LIGHT += cel_pick(band, lit_color, mid_color, dark_color);
	}
}
