// Shared by foliage, trunk and impostor shaders. Keep impostor relighting identical.

// 0 = normal render; impostor bake (Task 7): 1 = lit-band base color as EMISSION,
// 2 = octa object normal (RG) + depth01 (B) as EMISSION, 3 = ATTENUATION only.
global uniform int anime_tree_bake_mode;
global uniform vec2 anime_tree_bake_depth_range; // view-space near/far of the baked object

const float CEL_BAND_HI = 0.55;
const float CEL_BAND_LO = 0.15;

// 2 = lit, 1 = mid, 0 = dark. `shift` (0/1) lowers the band, used for blotches.
int cel_band(float ndotl, float shadow, int shift) {
	float l = ndotl * shadow;
	int b = l > CEL_BAND_HI ? 2 : (l > CEL_BAND_LO ? 1 : 0);
	return max(b - shift, 0);
}

vec3 cel_pick(int band, vec3 lit, vec3 mid, vec3 dark) {
	return band >= 2 ? lit : (band == 1 ? mid : dark);
}

vec2 oct_encode(vec3 n) {
	n /= abs(n.x) + abs(n.y) + abs(n.z);
	vec2 e = n.y >= 0.0 ? n.xz : (1.0 - abs(n.zx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.z >= 0.0 ? 1.0 : -1.0);
	return e * 0.5 + 0.5;
}

vec3 oct_decode(vec2 e) {
	e = e * 2.0 - 1.0;
	vec3 n = vec3(e.x, 1.0 - abs(e.x) - abs(e.y), e.y);
	float t = max(-n.y, 0.0);
	n.x += n.x >= 0.0 ? -t : t;
	n.z += n.z >= 0.0 ? -t : t;
	return normalize(n);
}

float cel_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float cel_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(cel_hash(i), cel_hash(i + vec3(1, 0, 0)), f.x),
	               mix(cel_hash(i + vec3(0, 1, 0)), cel_hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(cel_hash(i + vec3(0, 0, 1)), cel_hash(i + vec3(1, 0, 1)), f.x),
	               mix(cel_hash(i + vec3(0, 1, 1)), cel_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
