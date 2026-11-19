shader_type spatial;
render_mode cull_back, specular_disabled, ambient_light_disabled;

#include "res://addons/anime_trees/shaders/cel_ramp.gdshaderinc"

uniform sampler2D bark_lines : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 lit_color : source_color = vec3(0.420, 0.416, 0.180);
uniform vec3 mid_color : source_color = vec3(0.341, 0.325, 0.153);
uniform vec3 dark_color : source_color = vec3(0.247, 0.239, 0.118);
uniform vec3 moss_lit : source_color = vec3(0.486, 0.541, 0.204);
uniform vec3 moss_mid : source_color = vec3(0.400, 0.455, 0.161);
uniform vec3 line_color : source_color = vec3(0.180, 0.169, 0.075);
uniform float bark_u_repeat = 2.0;
uniform float moss_threshold = 0.5;
uniform float blotch_scale = 0.7;
uniform float blotch_threshold = 0.68;

varying vec3 v_obj;
varying float v_moss_attr;
varying float v_moss;
varying float v_line;
varying float v_blotch;

void vertex() {
	v_obj = VERTEX;
	v_moss_attr = COLOR.r;
}

vec3 trunk_color(int band, float moss, float line) {
	vec3 c = moss > 0.5 ? cel_pick(band, moss_lit, moss_mid, dark_color) : cel_pick(band, lit_color, mid_color, dark_color);
	return mix(c, line_color, line);
}

void fragment() {
	if (lod_discard(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] == 1.0)) {
		discard;
	}
	float m = v_moss_attr * 0.7 + cel_noise(v_obj * 1.3) * 0.5;
	v_moss = step(moss_threshold + 0.25, m);
	v_line = step(0.5, texture(bark_lines, UV * vec2(bark_u_repeat, 1.0)).r) * (1.0 - v_moss);
	v_blotch = step(blotch_threshold, cel_noise(v_obj * blotch_scale + 7.0));
	ROUGHNESS = 0.5;
	ALBEDO = vec3(1.0);
	if (anime_tree_bake_mode == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = trunk_color(2 - int(v_blotch), v_moss, v_line);
	} else if (anime_tree_bake_mode == 2) {
		ALBEDO = vec3(0.0);
		vec3 n_obj = normalize((inverse(VIEW_MATRIX * MODEL_MATRIX) * vec4(NORMAL, 0.0)).xyz);
		float depth01 = (-VERTEX.z - anime_tree_bake_depth_range.x)
				/ (anime_tree_bake_depth_range.y - anime_tree_bake_depth_range.x);
		EMISSION = vec3(oct_encode(n_obj), clamp(depth01, 0.0, 1.0));
	}
}

void light() {
	if (anime_tree_bake_mode == 3) {
		DIFFUSE_LIGHT += vec3(ATTENUATION);
	} else if (anime_tree_bake_mode == 0) {
		int band = cel_band(dot(NORMAL, LIGHT), ATTENUATION, int(v_blotch));
		DIFFUSE_LIGHT += trunk_color(band, v_moss, v_line);
	}
}
