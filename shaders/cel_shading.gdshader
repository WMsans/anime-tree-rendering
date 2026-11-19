shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;

// Full-screen cel-shading pass, same setup as outline.gdshader: a size-2 QuadMesh
// drawn in the transparent pass, just before the outline.
//
// Lighting is already baked into the screen colour, so the bands come from its
// luminance: the ramp maps luminance to a new luminance (and optional tint),
// hue is kept. The ramp needs view-independent input: no specular, no sky
// reflections, Lambert diffuse, or bands flicker as the camera moves.

// Luminance in, banded colour out. Use a constant-interpolation gradient.
uniform sampler2D ramp : source_color, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;
	float d = texture(depth_texture, SCREEN_UV).r;
	// Reverse-Z: 0 is the far plane, i.e. sky. Leave it smooth.
	if (d > 0.0) {
		float lum = max(dot(col, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
		// Screen colour is linear; look up with gamma luminance so ramp stops read
		// like the picker values. source_color already returns the ramp linear.
		float x = clamp(pow(lum, 1.0 / 2.2), 0.0, 1.0);
		col = col / lum * texture(ramp, vec2(x, 0.5)).rgb;
	}
	ALBEDO = col;
}
