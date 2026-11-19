shader_type spatial;
// Lit like the glb's StandardMaterial: Lambert, no specular, so the cel ramp sees
// the same view-independent lighting. cull_back: grown edges must never show the
// inside of the clump.
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
// Rough mesh-space radius of a clump, to turn angle into on-screen arc length.
uniform float clump_radius = 4.0;
// Bump radius in screen pixels, shared with leaf_scallop.gdshaderinc.
global uniform float leaf_bump_px;

// Row of n semicircles around the turn, cusps between: the scallop pass grows the
// edge by this height, so the grown edge is a row of round scallops.
float semicircles(float a, float n) {
	float u = fract(a * n / TAU) * 2.0 - 1.0;
	return sqrt(1.0 - u * u);
}

void fragment() {
	ALBEDO = albedo.rgb;

	// Bump profile (0 = cusp, 1 = bump top) for leaf_scallop.gdshaderinc, by the
	// on-screen angle around this clump's origin: stays put as the camera moves.
	// Packed into ROUGHNESS, which also marks the pixel as leaf: 0.25..0.75, others
	// are 1.0, sky 0. No visual effect: Lambert diffuse, specular off.
	float profile = 1.0;
	vec3 c = (VIEW_MATRIX * vec4(NODE_POSITION_WORLD, 1.0)).xyz;
	if (c.z < -0.1) {
		vec2 d = VERTEX.xy / -VERTEX.z - c.xy / -c.z;
		float phase = fract(sin(dot(NODE_POSITION_WORLD, vec3(12.9898, 78.233, 37.719))) * 43758.5453) * TAU;
		float a = atan(d.y, d.x) + phase;
		// Bumps are leaf_bump_px in radius on screen whatever the distance: the
		// clump's on-screen circumference sets the bump count. Blend the two nearest
		// whole counts (whole: no seam where atan wraps) so bumps morph instead of
		// popping as the camera dollies.
		float ppm = 0.5 * VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]) / -c.z;
		float r_px = clump_radius * length(MODEL_MATRIX[0].xyz) * ppm;
		// Capped: with the camera right at the clump origin ppm blows up and
		// thousands of bumps would read as noise.
		float n = clamp(TAU * r_px / (2.0 * leaf_bump_px), 3.0, 64.0);
		float n0 = floor(n);
		profile = mix(semicircles(a, n0), semicircles(a, n0 + 1.0), n - n0);
	}
	ROUGHNESS = 0.25 + 0.5 * profile;
}
