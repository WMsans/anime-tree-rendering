shader_type spatial;
// Relightable hemi-octahedral impostor. Frame lookup is in object space, so yaw-rotated
// instances pick the right frames; self-shadow uses the bit for the sun azimuth relative
// to the instance. ROUGHNESS = 1 tells the outline pass to skip (ink is baked).
render_mode skip_vertex_transform, cull_disabled, specular_disabled, ambient_light_disabled;

#include "res://addons/anime_trees/shaders/cel_ramp.gdshaderinc"

const int FRAMES = 8; // == HemiOct.FRAMES

uniform sampler2D albedo_atlas : source_color, filter_nearest_mipmap;
uniform sampler2D ndsh_atlas : filter_nearest_mipmap; // point-sampled mips (bits stay valid)
uniform vec3 impostor_center;
uniform float impostor_radius = 1.0;
uniform vec3 mid_ratio = vec3(0.66, 0.83, 0.85);
uniform vec3 dark_ratio = vec3(0.46, 0.66, 0.72);
uniform float alpha_cut = 0.25;

varying vec4 v_uv01;   // local frame uv for frames 0,1
varying vec4 v_uv23;   // local frame uv for frames 2,3
varying vec4 v_frames; // frame index ix + iy * FRAMES
varying vec4 v_weights;
varying float v_ink;
varying float v_bits;

// --- copies of HemiOct (impostor/hemi_oct.gd) ---
vec2 hemi_dir_to_uv(vec3 d) {
	d.y = max(d.y, 0.0);
	if (dot(d.xz, d.xz) < 1e-12 && d.y <= 0.0) {
		d = vec3(1.0, 0.0, 0.0);
	}
	d /= abs(d.x) + abs(d.y) + abs(d.z);
	return vec2(d.x + d.z, d.x - d.z) * 0.5 + 0.5;
}

vec3 hemi_uv_to_dir(vec2 uv) {
	vec2 e = uv * 2.0 - 1.0;
	float px = (e.x + e.y) * 0.5;
	float pz = (e.x - e.y) * 0.5;
	return normalize(vec3(px, 1.0 - abs(px) - abs(pz), pz));
}

vec2 frame_local_uv(vec2 frame, vec3 cam, vec3 p) {
	vec3 d = hemi_uv_to_dir((frame + 0.5) / float(FRAMES));
	vec3 up = abs(d.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, -1.0);
	vec3 x = normalize(cross(up, d));
	vec3 y = cross(d, x);
	vec3 rd = p - cam;
	float t = dot(impostor_center - cam, d) / dot(rd, d);
	vec3 local = cam + rd * t - impostor_center;
	float size = 2.0 * impostor_radius;
	return vec2(dot(local, x) / size + 0.5, 0.5 - dot(local, y) / size);
}

void vertex() {
	v_main_cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	if (lod_out_of_range(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz)) {
		VERTEX = vec3(0.0); // whole instance out of its LOD range: collapse, skip the rest
	} else {
	vec3 c_view = (MODELVIEW_MATRIX * vec4(impostor_center, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec2 corner = (UV * 2.0 - 1.0) * vec2(1.0, -1.0);
	vec3 view_pos = c_view + vec3(corner * impostor_radius * s, 0.0);
	mat4 inv_mv = inverse(MODELVIEW_MATRIX);
	vec3 p_obj = (inv_mv * vec4(view_pos, 1.0)).xyz;
	vec3 cam_obj = (inv_mv * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 g = hemi_dir_to_uv(normalize(cam_obj - impostor_center)) * float(FRAMES) - 0.5;
	vec2 g0 = clamp(floor(g), vec2(0.0), vec2(float(FRAMES - 1)));
	// Sharpened bilinear weights: one frame most of the time, dithered only near the switch.
	vec2 f = clamp((g - g0 - 0.5) * 4.0 + 0.5, 0.0, 1.0);
	vec2 g1 = min(g0 + 1.0, vec2(float(FRAMES - 1)));
	vec2 fr[4] = vec2[](g0, vec2(g1.x, g0.y), vec2(g0.x, g1.y), g1);
	v_weights = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	v_frames = vec4(fr[0].x + fr[0].y * float(FRAMES), fr[1].x + fr[1].y * float(FRAMES),
			fr[2].x + fr[2].y * float(FRAMES), fr[3].x + fr[3].y * float(FRAMES));
	v_uv01 = vec4(frame_local_uv(fr[0], cam_obj, p_obj), frame_local_uv(fr[1], cam_obj, p_obj));
	v_uv23 = vec4(frame_local_uv(fr[2], cam_obj, p_obj), frame_local_uv(fr[3], cam_obj, p_obj));
	VERTEX = view_pos;
	NORMAL = vec3(0.0, 0.0, 1.0);
	}
}

void fragment() {
	if (lod_discard(MODEL_MATRIX[3].xyz, v_main_cam, FRAGCOORD.xy)) {
		discard;
	}
	// One frame per pixel, chosen by ordered dither against the weights: crisp, no ghosting.
	float n = fract(bayer4(FRAGCOORD.xy) + 0.5);
	vec4 cw = vec4(v_weights.x, v_weights.x + v_weights.y, v_weights.x + v_weights.y + v_weights.z, 2.0);
	int k = n < cw.x ? 0 : (n < cw.y ? 1 : (n < cw.z ? 2 : 3));
	vec2 luv = k == 0 ? v_uv01.xy : (k == 1 ? v_uv01.zw : (k == 2 ? v_uv23.xy : v_uv23.zw));
	float fi = k == 0 ? v_frames.x : (k == 1 ? v_frames.y : (k == 2 ? v_frames.z : v_frames.w));
	if (any(lessThan(luv, vec2(0.0))) || any(greaterThan(luv, vec2(1.0)))) {
		discard;
	}
	vec2 frame = vec2(mod(fi, float(FRAMES)), floor(fi / float(FRAMES)));
	vec2 auv = (frame + luv) / float(FRAMES);
	vec4 al = texture(albedo_atlas, auv);
	if (al.a < alpha_cut) {
		discard;
	}
	vec4 nd = texture(ndsh_atlas, auv);
	v_ink = al.a < 0.75 ? 1.0 : 0.0;
	v_bits = nd.a * 255.0;
	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	float s = length(MODEL_MATRIX[0].xyz);
	NORMAL = normalize(mat3(mv) * oct_decode(nd.rg));
	float offset = (impostor_radius - 2.0 * impostor_radius * nd.b) * s; // + = toward camera
	vec3 hit = VERTEX + normalize(-VERTEX) * offset;
	vec4 clip = PROJECTION_MATRIX * vec4(hit, 1.0);
	DEPTH = clip.z / clip.w;
	ALBEDO = al.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	if (v_ink > 0.5) {
		DIFFUSE_LIGHT += vec3(1.0);
	} else {
		vec3 l_obj = inverse(mat3(MODEL_MATRIX)) * (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz;
		float a = mod(atan(l_obj.x, l_obj.z), TAU) / (TAU / 8.0);
		int k0 = int(floor(a)) % 8;
		int k1 = (k0 + 1) % 8;
		int bits = int(v_bits + 0.5);
		float self_shadow = mix(float((bits >> k0) & 1), float((bits >> k1) & 1), fract(a));
		int band = cel_band(dot(NORMAL, LIGHT), ATTENUATION * step(0.5, self_shadow), 0);
		DIFFUSE_LIGHT += band >= 2 ? vec3(1.0) : (band == 1 ? mid_ratio : dark_ratio);
	}
}
