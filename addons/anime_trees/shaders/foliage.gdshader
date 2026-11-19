shader_type spatial;
// Camera-facing scalloped cards. Each card corner is slid along its view ray onto the clump
// ellipsoid (screen shape unchanged), and every pixel shades with the exact ellipsoid
// normal, so depth + normal are continuous inside a clump and the outline pass only draws
// at clump silhouettes / between clumps. No DEPTH write -> early-z stays on.
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

varying vec3 v_obj;       // point on the (bent) card, object space; lies on the pixel ray
varying vec3 v_cam_obj;   // camera position, object space
varying vec3 v_fwd_obj;   // camera forward, object space (orthographic / shadow pass)
varying vec3 v_center;
varying vec3 v_radii;
varying vec2 v_atlas_uv;
varying float v_blotch;   // set in fragment, read in light

// Ray vs ellipsoid in unit-sphere space; on a miss, the closest approach (scallop fringe).
vec3 ellipsoid_hit(vec3 ro, vec3 rd, vec3 c, vec3 radii) {
	vec3 q = (ro - c) / radii;
	vec3 dd = rd / radii;
	float a = dot(dd, dd);
	float b = dot(q, dd);
	float h = b * b - a * (dot(q, q) - 1.0);
	float t = h > 0.0 ? (-b - sqrt(h)) / a : -b / a;
	return ro + rd * t;
}

// Ray through object-space point p: from the camera, or along forward for ortho (shadows).
vec3 ray_hit(vec3 p, vec3 cam, vec3 fwd, bool ortho, vec3 c, vec3 radii) {
	vec3 rd = ortho ? fwd : normalize(p - cam);
	vec3 ro = ortho ? p - rd * (dot(p - c, rd) + 4.0 * length(radii)) : cam;
	return ellipsoid_hit(ro, rd, c, radii);
}

void vertex() {
	v_main_cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	if (lod_out_of_range(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz)) {
		VERTEX = vec3(0.0); // whole instance out of its LOD range: collapse, skip the rest
	} else {
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
	v_cam_obj = (inv_mv * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_fwd_obj = normalize((inv_mv * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	v_center = CUSTOM0.xyz;
	v_radii = CUSTOM0.w * CUSTOM1.xyz;
	bool ortho = PROJECTION_MATRIX[3][3] == 1.0;
	v_obj = ray_hit((inv_mv * vec4(view_pos, 1.0)).xyz, v_cam_obj, v_fwd_obj, ortho, v_center, v_radii);
	view_pos = (MODELVIEW_MATRIX * vec4(v_obj, 1.0)).xyz;
	float cell = UV2.x;
	v_atlas_uv = (UV + vec2(mod(cell, 2.0), floor(cell / 2.0))) * 0.5;
	VERTEX = view_pos;
	NORMAL = vec3(0.0, 0.0, 1.0);
	}
}

void fragment() {
	if (lod_discard(MODEL_MATRIX[3].xyz, v_main_cam, FRAGCOORD.xy)) {
		discard;
	}
	if (texture(scallop_atlas, v_atlas_uv).a < alpha_cut) {
		discard;
	}
	bool ortho = PROJECTION_MATRIX[3][3] == 1.0;
	vec3 hit = ray_hit(v_obj, v_cam_obj, v_fwd_obj, ortho, v_center, v_radii);
	vec3 n_obj = normalize((hit - v_center) / (v_radii * v_radii));

	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	vec3 hit_view = (mv * vec4(hit, 1.0)).xyz;
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
