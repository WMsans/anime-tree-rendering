extends SceneTree
## Regenerates scallop_atlas.png and bark_lines.png (committed outputs).
## godot --headless --path . -s addons/anime_trees/textures/make_textures.gd

const OUT := "res://addons/anime_trees/textures/"
const CELL := 1024  # rendered at 2x, downsampled to 512 per cell for anti-aliasing


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var atlas := Image.create(CELL * 2, CELL * 2, false, Image.FORMAT_LA8)
	for cell in 4:
		_draw_blob(atlas, Vector2i(cell % 2, cell / 2) * CELL, rng)
	atlas.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	atlas.save_png(ProjectSettings.globalize_path(OUT + "scallop_atlas.png"))
	_bark(rng).save_png(ProjectSettings.globalize_path(OUT + "bark_lines.png"))
	print("textures written")
	quit()


## Cauliflower blob: a few base circles, each ringed by scallop circles, each of those
## ringed again by smaller scallops on their outward side (fractal edge of refs 1, 2, 8).
func _draw_blob(img: Image, origin: Vector2i, rng: RandomNumberGenerator) -> void:
	var c := Vector2(CELL, CELL) * 0.5
	var circles: Array[Vector3] = []  # x, y, r
	var base_r := CELL * 0.2
	for i in 3:
		var o := Vector2.from_angle(rng.randf() * TAU) * base_r * rng.randf_range(0.0, 0.25)
		circles.append(Vector3(c.x + o.x, c.y + o.y, base_r * rng.randf_range(0.85, 1.0)))
	var level1: Array[Vector3] = []
	for b: Vector3 in circles.duplicate():
		var n := rng.randi_range(6, 8)
		for k in n:
			var a := TAU * (k + rng.randf_range(-0.3, 0.3)) / n
			var r := b.z * rng.randf_range(0.42, 0.6)
			var p := Vector2(b.x, b.y) + Vector2.from_angle(a) * b.z * rng.randf_range(0.8, 1.0)
			level1.append(Vector3(p.x, p.y, r))
	circles.append_array(level1)
	for s in level1:
		var out_a := (Vector2(s.x, s.y) - c).angle()
		var n := rng.randi_range(4, 6)
		for k in n:
			var a := out_a + lerpf(-1.6, 1.6, (k + 0.5) / n) + rng.randf_range(-0.15, 0.15)
			var r := s.z * rng.randf_range(0.3, 0.42)
			var p := Vector2(s.x, s.y) + Vector2.from_angle(a) * s.z * 0.92
			if (p - c).length() + r < CELL * 0.49:
				circles.append(Vector3(p.x, p.y, r))
	for ci in circles:
		var x0 := int(maxf(0, ci.x - ci.z)); var x1 := int(minf(CELL - 1, ci.x + ci.z))
		var y0 := int(maxf(0, ci.y - ci.z)); var y1 := int(minf(CELL - 1, ci.y + ci.z))
		var r2 := ci.z * ci.z
		for y in range(y0, y1 + 1):
			var dy := y + 0.5 - ci.y
			var span := sqrt(maxf(0.0, r2 - dy * dy))
			var xa := maxi(x0, int(ceil(ci.x - span - 0.5)))
			var xb := mini(x1, int(floor(ci.x + span - 0.5)))
			if xb >= xa:
				img.fill_rect(Rect2i(origin.x + xa, origin.y + y, xb - xa + 1, 1), Color(1, 1, 1, 1))


## Tileable wavy vertical bark lines, broken into strokes. White = line.
func _bark(rng: RandomNumberGenerator) -> Image:
	var size := 512
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	for i in 11:
		var x0 := rng.randf() * size
		var amp := rng.randf_range(4, 14)
		var k := float(rng.randi_range(1, 3))
		var ph := rng.randf() * TAU
		var w := rng.randf_range(1.2, 2.6)
		var gap_ph := rng.randf() * TAU
		for y in size:
			if sin(TAU * y / size * 2.0 + gap_ph) > 0.75:
				continue  # stroke gap; period divides size, so it tiles
			var x := x0 + amp * sin(TAU * y / size * k + ph)
			for dx in range(int(-w - 1), int(w + 2)):
				var cov := clampf(w - absf(dx + fposmod(x, 1.0) - 0.5), 0.0, 1.0)
				var px := posmod(int(x) + dx, size)
				var old := img.get_pixel(px, y).r
				img.set_pixel(px, y, Color.from_hsv(0, 0, maxf(old, cov)))
	return img
