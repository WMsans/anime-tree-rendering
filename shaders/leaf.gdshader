shader_type spatial;
// Lit like the glb's StandardMaterial: Lambert, no specular, so the cel ramp sees
// the same view-independent lighting. cull_back: grown edges must never show the
// inside of the clump.
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
// Distance between bump centres along a clump's edge, metres.
uniform float bump_spacing = 0.8;
// Rough mesh-space radius of a clump, to turn angle into arc length.
uniform float clump_radius = 4.0;

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
		// Whole number of bumps per turn, so there's no seam where atan wraps.
		float n = max(3.0, round(TAU * clump_radius * length(MODEL_MATRIX[0].xyz) / bump_spacing));
		// Semicircle per bump, cusps between: the scallop pass grows the edge by this
		// height, so the grown edge is a row of round scallops.
		float u = fract(a * n / TAU) * 2.0 - 1.0;
		profile = sqrt(1.0 - u * u);
	}
	ROUGHNESS = 0.25 + 0.5 * profile;
}
