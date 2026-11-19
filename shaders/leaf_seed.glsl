#[compute]
#version 450

// Jump flood: for every pixel, the coordinates of the nearest leaf pixel (leaf
// pixels have roughness 0.25..0.75, see leaf.gdshader). step 0 seeds, step > 0
// is one jump pass. Pixels with no leaf in reach hold NONE.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D nr_tex;
layout(rg32f, set = 0, binding = 1) uniform restrict readonly image2D src;
layout(rg32f, set = 0, binding = 2) uniform restrict writeonly image2D dst;

layout(push_constant, std430) uniform Params {
	ivec2 size;
	int step;
	int pad;
} p;

const vec2 NONE = vec2(-1e6);

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(c, p.size))) {
		return;
	}
	if (p.step == 0) {
		bool leaf = abs(texelFetch(nr_tex, c, 0).w - 0.5) < 0.26;
		imageStore(dst, c, vec4(leaf ? vec2(c) : NONE, 0.0, 0.0));
		return;
	}
	vec2 best = imageLoad(src, c).xy;
	float best_d = distance(best, vec2(c));
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 n = c + ivec2(x, y) * p.step;
			if (any(lessThan(n, ivec2(0))) || any(greaterThanEqual(n, p.size))) {
				continue;
			}
			vec2 s = imageLoad(src, n).xy;
			float d = distance(s, vec2(c));
			if (d < best_d) {
				best_d = d;
				best = s;
			}
		}
	}
	imageStore(dst, c, vec4(best, 0.0, 0.0));
}
