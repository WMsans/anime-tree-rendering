// Screen-space scalloped leaf edges, shared by cel_shading and outline so both see
// the same grown shape. A non-leaf pixel near a leaf edge "becomes" that leaf (its
// colour and depth) when it falls inside a round bump growing out of the edge.
//
// The leaf material (leaf.gdshader) writes ROUGHNESS = 0.25 + 0.5 * profile:
// 0.25..0.75 marks a leaf pixel, and profile (0..1) is the bump height there,
// computed per clump so the bumps don't crawl. Other surfaces are 1.0, sky 0.

// Biggest bump radius, metres. Bumps scale with distance like the geometry.
uniform float bump_size = 0.5;
// Search radius cap in pixels: bumps on very near leaves are clamped to this.
uniform float max_grow_px = 256.0;

// Rings are spaced exponentially from MIN_RING_PX to max_grow_px: fine near the
// edge (small, far bumps), coarse far out (big, near bumps).
const int GROW_RINGS = 10;
const int GROW_DIRS = 16;
const float MIN_RING_PX = 2.0;
const float SAMPLE_INSET_PX = 4.0;

float leaf_w(sampler2D nr_tex, vec2 uv) {
	// w is the raw roughness (measured in Godot 4.7).
	return texture(nr_tex, uv).w;
}

bool is_leaf(sampler2D nr_tex, vec2 uv) {
	return abs(leaf_w(nr_tex, uv) - 0.5) < 0.26;
}

float ring_px(int i) {
	return i == 0 ? 0.0 : MIN_RING_PX * pow(max_grow_px / MIN_RING_PX, float(i - 1) / float(GROW_RINGS - 1));
}

// The uv whose colour and depth this pixel should show: itself, or the leaf pixel
// whose bump covers it.
// ponytail: brute-force ring search, run once per pixel in cel shading and 5x in
// the outline; jump flooding in a CompositorEffect if it ever costs too much.
vec2 leaf_source(vec2 uv, sampler2D depth_tex, sampler2D nr_tex, mat4 inv_proj) {
	if (is_leaf(nr_tex, uv)) {
		return uv;
	}
	vec2 size = vec2(textureSize(depth_tex, 0));
	vec2 px = 1.0 / size;
	float pd = texture(depth_tex, uv).r;
	for (int i = 1; i <= GROW_RINGS; i++) {
		float rad = ring_px(i);
		// First ring that hits a leaf: bisect every hit towards its edge and keep the
		// closest. This pixel grows when it's within the bump height at that nearest
		// edge point, so the grown edge traces the profile: semicircle profile,
		// semicircle scallops.
		float best = 1e6;
		float best_hi = 0.0;
		vec2 best_dir = vec2(0.0);
		vec2 dir_sum = vec2(0.0);
		for (int j = 0; j < GROW_DIRS; j++) {
			float a = (float(j) + 0.5) * TAU / float(GROW_DIRS);
			vec2 dir = vec2(cos(a), sin(a));
			if (!is_leaf(nr_tex, uv + dir * rad * px)) {
				continue;
			}
			float lo = ring_px(i - 1);
			float hi = rad;
			for (int k = 0; k < 6; k++) {
				float mid = 0.5 * (lo + hi);
				if (is_leaf(nr_tex, uv + dir * mid * px)) {
					hi = mid;
				} else {
					lo = mid;
				}
			}
			if (lo < best) {
				best = lo;
				best_hi = hi;
				best_dir = dir;
			}
			dir_sum += dir;
		}
		if (best >= 1e6) {
			continue;
		}
		// Colour/depth source: a few pixels inside the leaf (right at the silhouette
		// the surface is grazing and flickers), along the mean hit direction (the
		// single closest direction jumps between neighbours and smears cel bands).
		vec2 q = uv + best_dir * (best_hi + SAMPLE_INSET_PX) * px;
		if (dot(dir_sum, dir_sum) > 0.25) {
			vec2 qa = uv + normalize(dir_sum) * (best_hi + SAMPLE_INSET_PX) * px;
			if (is_leaf(nr_tex, qa)) {
				q = qa;
			}
		}
		float qd = texture(depth_tex, q).r;
		// Reverse-Z: bigger is nearer. Only grow over farther surfaces.
		if (qd <= pd) {
			return uv;
		}
		vec4 v = inv_proj * vec4(q * 2.0 - 1.0, qd, 1.0);
		// Pixels per metre at this distance; |inv_proj[1][1]| is tan(fov_y / 2) (its
		// sign depends on the projection's y-flip).
		float ppm = 0.5 * size.y / (abs(inv_proj[1][1]) * (-v.z / v.w));
		float profile = clamp((leaf_w(nr_tex, uv + best_dir * best_hi * px) - 0.25) / 0.5, 0.0, 1.0);
		float r_px = min(bump_size * profile * ppm, max_grow_px);
		return best < r_px ? q : uv;
	}
	return uv;
}
