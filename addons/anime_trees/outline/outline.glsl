#[compute]
#version 450
// Ink outline. Depth edges: second derivative of reverse-Z NDC depth (zero on planes,
// so ground at grazing angles stays clean), only on the nearer side of a step, so the ink
// takes the color of the object in front. Normal edges: one-sided (+x/+y) to keep width.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D normal_tex;

layout(push_constant, std430) uniform Params {
	vec2 size;
	float width;
	float depth_threshold;
	float normal_threshold;
	float darken;
	float pad0;
	float pad1;
} p;

float depth_at(ivec2 c) {
	return texelFetch(depth_tex, clamp(c, ivec2(0), ivec2(p.size) - 1), 0).r;
}

// Godot packs a dynamic-object bit into roughness; undo it (normal_roughness_compatibility).
vec4 normal_rough_at(ivec2 c) {
	vec4 nr = texelFetch(normal_tex, clamp(c, ivec2(0), ivec2(p.size) - 1), 0);
	float r = nr.w > 0.5 ? 1.0 - nr.w : nr.w;
	return vec4(normalize(nr.xyz * 2.0 - 1.0), r / (127.0 / 255.0));
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(px, ivec2(p.size)))) {
		return;
	}
	float d = depth_at(px);
	if (d <= 0.0) {
		return; // sky (reverse Z far plane)
	}
	vec4 nr = normal_rough_at(px);
	if (nr.w > 0.99) {
		return; // no-outline flag (impostors carry baked ink)
	}
	int w = max(1, int(round(p.width)));
	const ivec2 dirs[4] = ivec2[](ivec2(1, 0), ivec2(0, 1), ivec2(1, 1), ivec2(1, -1));
	bool edge = false;
	for (int i = 0; i < 4 && !edge; i++) {
		ivec2 o = dirs[i] * w;
		float lap = 2.0 * d - depth_at(px + o) - depth_at(px - o);
		edge = lap / d > p.depth_threshold;
		if (!edge && i < 2) {
			ivec2 q = px + dirs[i] * w;
			if (depth_at(q) > 0.0) {
				vec4 nq = normal_rough_at(q);
				edge = nq.w <= 0.99 && 1.0 - dot(nr.xyz, nq.xyz) > p.normal_threshold;
			}
		}
	}
	if (edge) {
		vec4 c = imageLoad(color_image, px);
		imageStore(color_image, px, vec4(c.rgb * p.darken, c.a));
	}
}
