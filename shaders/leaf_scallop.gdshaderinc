// Screen-space scalloped leaf edges, shared by cel_shading and outline so both see
// the same grown shape. A non-leaf pixel near a leaf edge "becomes" that leaf (its
// colour and depth) when it falls inside a round bump growing out of the edge.
// Bumps are anchored to the leaf's world position, sized in metres: they don't
// crawl with the camera and shrink with distance.
//
// Leaf pixels are marked by the leaf material writing ROUGHNESS = 0.5.

// Biggest bump radius, metres.
uniform float bump_size = 0.5;
// Bump frequency over world space; bump spacing is about PI / bump_freq metres.
uniform float bump_freq = 4.5;
// Weight of the finer sub-bumps on top of the main ones.
uniform float sub_bump_strength = 0.35;
// Search radius cap in pixels: bumps on very near leaves are clamped to this.
uniform float max_grow_px = 40.0;

const int GROW_RINGS = 8;
const int GROW_DIRS = 16;
const float SAMPLE_INSET_PX = 4.0;

bool is_leaf(sampler2D nr_tex, vec2 uv) {
	// w is the raw roughness (measured in 4.7): leaves 0.5, other surfaces 1.0,
	// sky 0.
	return abs(texture(nr_tex, uv).w - 0.5) < 0.1;
}

// Bump radius, 0..1 of bump_size, at a world position: smooth lobes with cusps.
float bump_profile(vec3 w) {
	vec3 s = sin(w * bump_freq + vec3(0.0, 1.7, 3.1));
	vec3 s2 = sin(w.zxy * bump_freq * 2.3 + vec3(2.3, 0.4, 5.0));
	float n = mix(s.x + s.y + s.z, s2.x + s2.y + s2.z, sub_bump_strength) / 3.0 * 0.5 + 0.5;
	// Most of the range near zero (cusps), round tops (sqrt).
	return sqrt(smoothstep(0.35, 0.85, n));
}

// The uv whose colour and depth this pixel should show: itself, or the leaf pixel
// whose bump covers it.
// ponytail: brute-force ring search, run once per pixel in cel shading and 5x in
// the outline; jump flooding in a CompositorEffect if it ever costs too much.
vec2 leaf_source(vec2 uv, sampler2D depth_tex, sampler2D nr_tex, mat4 inv_proj, mat4 inv_view) {
	if (is_leaf(nr_tex, uv)) {
		return uv;
	}
	vec2 size = vec2(textureSize(depth_tex, 0));
	vec2 px = 1.0 / size;
	float pd = texture(depth_tex, uv).r;
	float step_px = max_grow_px / float(GROW_RINGS);
	for (int i = 1; i <= GROW_RINGS; i++) {
		float rad = step_px * float(i);
		// First ring that hits a leaf: bisect every hit towards its edge and keep the
		// closest, so the distance (and the leaf point) is stable pixel to pixel and
		// bump outlines aren't quantised to the ring step.
		float best = 1e6;
		float best_hi = 0.0;
		vec2 dir_sum = vec2(0.0);
		vec2 q = uv;
		for (int j = 0; j < GROW_DIRS; j++) {
			float a = (float(j) + 0.5 * float(i % 2)) * TAU / float(GROW_DIRS);
			vec2 dir = vec2(cos(a), sin(a));
			if (!is_leaf(nr_tex, uv + dir * rad * px)) {
				continue;
			}
			float lo = rad - step_px;
			float hi = rad;
			for (int k = 0; k < 4; k++) {
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
				q = uv + dir * (hi + SAMPLE_INSET_PX) * px;
			}
			dir_sum += dir;
		}
		if (best < 1e6) {
			// Colour/depth source: along the mean hit direction (a smooth edge normal)
			// and a few pixels inside the leaf. The single closest direction jumps
			// between neighbours and smears different cel bands into hairs; right at
			// the silhouette the surface is grazing and flickers.
			if (dot(dir_sum, dir_sum) > 0.25) {
				vec2 qa = uv + normalize(dir_sum) * (best_hi + SAMPLE_INSET_PX) * px;
				if (is_leaf(nr_tex, qa)) {
					q = qa;
				}
			}
			float lo = best;
			float qd = texture(depth_tex, q).r;
			// Reverse-Z: bigger is nearer. Only grow over farther surfaces.
			if (qd <= pd) {
				return uv;
			}
			vec4 v = inv_proj * vec4(q * 2.0 - 1.0, qd, 1.0);
			v.xyz /= v.w;
			vec3 w = (inv_view * vec4(v.xyz, 1.0)).xyz;
			// Depth is noisy at grazing silhouettes; drop the pattern's view-direction
			// component so that noise can't jitter the bump outline. Still anchored
			// for camera moves; drifts a little under camera rotation.
			vec3 fwd = -normalize(inv_view[2].xyz);
			w -= dot(w - inv_view[3].xyz, fwd) * fwd;
			// Pixels per metre at this distance; |inv_proj[1][1]| is tan(fov_y / 2) (sign
			// depends on the y-flip).
			float ppm = 0.5 * size.y / (abs(inv_proj[1][1]) * -v.z);
			float r_px = min(bump_size * bump_profile(w) * ppm, max_grow_px);
			return lo < r_px ? q : uv;
		}
	}
	return uv;
}
