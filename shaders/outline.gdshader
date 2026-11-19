shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;

// Full-screen post-process. Drawn as the last transparent object, so it composites
// over the finished image. Needs a QuadMesh of size 2 in the node carrying it.
uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
// Line width in screen pixels.
uniform float thickness = 1.5;
// Depth gap between two surfaces, in metres, below which no line is drawn.
uniform float depth_threshold = 0.5;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

// View-space distance of the opaque surface at uv. Godot 4 uses a reverse-Z buffer,
// so depth 0 is the far plane: sky, or nothing drawn there. inv_proj has to be
// handed in because stage built-ins are only visible inside the entry points.
float view_depth(float d, vec2 uv, mat4 inv_proj) {
	if (d <= 0.0) {
		return 10000.0;
	}
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -view.z / view.w;
}

float depth_at(vec2 uv) {
	// texture() on the depth sampler is available in helper functions.
	return texture(depth_texture, uv).r;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 o = thickness / vec2(textureSize(depth_texture, 0));
	vec2 l = SCREEN_UV - vec2(o.x, 0.0);
	vec2 r = SCREEN_UV + vec2(o.x, 0.0);
	vec2 u = SCREEN_UV - vec2(0.0, o.y);
	vec2 dn = SCREEN_UV + vec2(0.0, o.y);
	float c = view_depth(depth_at(SCREEN_UV), SCREEN_UV, INV_PROJECTION_MATRIX);
	// Second derivative, not a plain difference: a surface receding from the camera
	// has a large depth difference across it but no line, and this cancels that out.
	// Across a step between two objects it equals the step in metres, which is
	// exactly what the threshold is about.
	float lap = abs(view_depth(depth_at(l), l, INV_PROJECTION_MATRIX)
			+ view_depth(depth_at(r), r, INV_PROJECTION_MATRIX) - 2.0 * c)
			+ abs(view_depth(depth_at(u), u, INV_PROJECTION_MATRIX)
			+ view_depth(depth_at(dn), dn, INV_PROJECTION_MATRIX) - 2.0 * c);
	float edge = smoothstep(depth_threshold, depth_threshold * 2.0, lap);
	ALBEDO = outline_color.rgb;
	ALPHA = edge * outline_color.a;
}
