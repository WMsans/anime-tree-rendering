shader_type spatial;
// Camera-facing scalloped cards. All cards of a clump are slid along their view rays onto
// ONE camera-facing plane through the clump (screen shape unchanged), so clumps stack like
// painted layers. Cards of a clump share the exact same depth, so the later card in the index
// buffer wins (depth test is >=): a fixed painter's order (builder sorts cards low -> high),
// no camera-dependent z-fighting. Tone edges inside a clump are the scalloped card outlines.
// Ink: the outline pass only inks between blobs (groups of clumps, UV2.x / 4), refs 1, 8.
// Pixels shade with the exact ellipsoid normal for the normal buffer; tone is per card (card
// normal, one shadow lookup per card). No DEPTH write -> early-z stays on (DEPTH cost 7x).
render_mode skip_vertex_transform, cull_disabled, specular_disabled, ambient_light_disabled;

#include "res://addons/anime_trees/shaders/cel_ramp.gdshaderinc"

uniform sampler2D scallop_atlas : hint_default_white, filter_linear_mipmap;
// Sampled from docs/reference 1, 2, 8 (daylight canopy).
uniform vec3 lit_color : source_color = vec3(0.486, 0.690, 0.196);
uniform vec3 mid_color : source_color = vec3(0.361, 0.592, 0.137);
uniform vec3 dark_color : source_color = vec3(0.255, 0.478, 0.122);
// How far a card's own normal (vs the smooth clump surface normal) drives its tone.
// 0 = smooth, continuous light -> dark across each clump (refs 1, 8); 1 = one flat tone per card.
uniform float card_tone = 0.0;
uniform float alpha_cut = 0.5;

varying vec3 v_obj;       // point on the (bent) card, object space; lies on the pixel ray
varying vec3 v_cam_obj;   // camera position, object space
varying vec3 v_fwd_obj;   // camera forward, object space (orthographic / shadow pass)
varying vec3 v_center;
varying vec3 v_radii;
varying vec2 v_atlas_uv;
// Per-card / per-blob constants are flat: an interpolated 1.0 can arrive as 0.99999, and
// int()/floor()/hashes of it then flip with the camera (that was the tone flicker).
varying flat vec3 v_card_n;  // card normal (from clump center), object space
varying flat float v_group;  // outline blob index within the tree
varying vec3 v_shade_n;   // view space, set in fragment, read in light

// Clump plane sits this many clump radii in front of the center (hides inner branches).
uniform float clump_plane_bias = 0.5;
// Clumps whose plane would come closer than this (m) are not flattened (see vertex()).
uniform float clump_near_limit = 0.5;

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
	if (lod_out_of_range(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz)) {
		VERTEX = vec3(0.0); // whole instance out of its LOD range: collapse, skip the rest
	} else {
	vec3 center_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float half_size = CUSTOM1.w;
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
	vec3 card_c = VERTEX;
	v_card_n = normalize((card_c - v_center) / (v_radii * v_radii));
	// Slide onto the clump plane: constant view z, biased toward the camera. All clump
	// planes are parallel, so two clumps never cut each other along a straight line.
	float c_z = (MODELVIEW_MATRIX * vec4(v_center, 1.0)).z;
	float plane_z = c_z + clump_plane_bias * max(max(v_radii.x, v_radii.y), v_radii.z) * model_scale;
	// A clump whose plane would sit at/behind the near plane (camera inside or right next to
	// it) is left as plain cards: flattening it would either mirror corners behind the camera
	// in front of it (ghost leaves on the floor) or park the clump on the near plane, where it
	// covers the screen and is clipped on/off frame to frame. Per clump, so cards stay together.
	if (ortho) {
		view_pos.z = plane_z;
	} else if (plane_z < -clump_near_limit && view_pos.z < 0.0) {
		view_pos.xy *= plane_z / view_pos.z; // along its pixel ray
		view_pos.z = plane_z; // set exactly: all cards of the clump get bit-identical depth
	}
	v_obj = (inv_mv * vec4(view_pos, 1.0)).xyz;
	float cell = mod(UV2.x, 4.0);
	v_group = floor(UV2.x / 4.0);
	v_atlas_uv = (UV + vec2(mod(cell, 2.0), floor(cell / 2.0))) * 0.5;
	VERTEX = view_pos;
	NORMAL = vec3(0.0, 0.0, 1.0);
	}
}

void fragment() {
	if (texture(scallop_atlas, v_atlas_uv).a < alpha_cut) {
		discard;
	}
	bool ortho = PROJECTION_MATRIX[3][3] == 1.0;
	vec3 hit = ray_hit(v_obj, v_cam_obj, v_fwd_obj, ortho, v_center, v_radii);
	vec3 n_obj = normalize((hit - v_center) / (v_radii * v_radii));

	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	vec3 hit_view = (mv * vec4(hit, 1.0)).xyz;
	// One shadow lookup per clump, just above its top (clear of its own casters): a clump is
	// wholly in another's shadow or not. Per-pixel lookups on the curved surface picked up
	// striped acne from the flat caster planes, crawling as the cascades follow the camera.
	LIGHT_VERTEX = (mv * vec4(v_center + vec3(0.0, 1.15 * v_radii.y, 0.0), 1.0)).xyz;
	NORMAL = normalize(mat3(mv) * n_obj);
	vec3 shade_obj = normalize(mix(n_obj, v_card_n, card_tone));
	v_shade_n = normalize(mat3(mv) * shade_obj);
	// Blob id (group + tree) for the outline pass: ink only where it changes. light() is
	// custom, so roughness is otherwise unused. 32 levels in [0.1, 0.875], well above 8-bit
	// buffer precision; outline.glsl treats that range as foliage.
	ROUGHNESS = 0.1 + 0.025 * floor(cel_hash(vec3(v_group * 1.37 + 0.5) + MODEL_MATRIX[3].xyz * 0.29) * 31.99);

	ALBEDO = vec3(1.0);
	if (anime_tree_bake_mode == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = lit_color;
	} else if (anime_tree_bake_mode == 2) {
		ALBEDO = vec3(0.0);
		float depth01 = (-hit_view.z - anime_tree_bake_depth_range.x)
				/ (anime_tree_bake_depth_range.y - anime_tree_bake_depth_range.x);
		EMISSION = vec3(oct_encode(shade_obj), clamp(depth01, 0.0, 1.0));
	}
}

void light() {
	if (anime_tree_bake_mode == 3) {
		DIFFUSE_LIGHT += vec3(ATTENUATION);
	} else if (anime_tree_bake_mode == 0) {
		int band = cel_band(dot(v_shade_n, LIGHT), ATTENUATION, 0);
		DIFFUSE_LIGHT += cel_pick(band, lit_color, mid_color, dark_color);
	}
}
