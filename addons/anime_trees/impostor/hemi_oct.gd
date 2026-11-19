@tool
class_name HemiOct
extends RefCounted
## Hemi-octahedral mapping (Y-up, upper hemisphere) for impostor frames.
## The GLSL copies in shaders/impostor.gdshader MUST stay identical.

const FRAMES := 8          ## FRAMES x FRAMES capture grid
const SHADOW_AZIMUTHS := 8 ## baked self-shadow sun azimuths


## Direction (object space) -> 0..1. Below-horizon directions clamp to the horizon.
static func dir_to_uv(d: Vector3) -> Vector2:
	d.y = maxf(d.y, 0.0)
	if Vector2(d.x, d.z).length_squared() < 1e-12 and d.y <= 0.0:
		d = Vector3(1, 0, 0)
	d /= absf(d.x) + absf(d.y) + absf(d.z)
	return Vector2(d.x + d.z, d.x - d.z) * 0.5 + Vector2(0.5, 0.5)


static func uv_to_dir(uv: Vector2) -> Vector3:
	var e := uv * 2.0 - Vector2.ONE
	var px := (e.x + e.y) * 0.5
	var pz := (e.x - e.y) * 0.5
	return Vector3(px, 1.0 - absf(px) - absf(pz), pz).normalized()


static func frame_dir(ix: int, iy: int) -> Vector3:
	return uv_to_dir((Vector2(ix, iy) + Vector2(0.5, 0.5)) / FRAMES)


## Camera basis used to capture a frame looking from direction `d` toward the object.
## Matches Basis.looking_at(-d, up) with the up rule below; mirrored in the shader.
static func frame_basis(d: Vector3) -> Basis:
	var up := Vector3.UP if absf(d.y) < 0.999 else Vector3(0, 0, -1)
	var x := up.cross(d).normalized()
	return Basis(x, d.cross(x), d)


## Sun azimuth relative to the tree (radians, any range) -> (k0, k1, t):
## blend baked azimuth k0 toward k1 by t.
static func shadow_weights(rel_azimuth: float) -> Vector3:
	var a := fposmod(rel_azimuth, TAU) / (TAU / SHADOW_AZIMUTHS)
	var k0 := int(floor(a)) % SHADOW_AZIMUTHS
	return Vector3(k0, (k0 + 1) % SHADOW_AZIMUTHS, a - floor(a))
