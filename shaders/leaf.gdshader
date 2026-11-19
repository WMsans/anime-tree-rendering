shader_type spatial;
// Lit like the glb's StandardMaterial: Lambert, no specular, so the cel ramp sees
// the same view-independent lighting. cull_back: the silhouette cut must never
// reveal the inside of the clump.
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(1.0);

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
}
