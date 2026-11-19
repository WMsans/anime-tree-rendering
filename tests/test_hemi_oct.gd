extends TestCase


func _v2near(a: Vector2, b: Vector2, eps := 1e-4) -> bool:
	return a.distance_to(b) <= eps


func test_up_maps_to_center() -> void:
	check(_v2near(HemiOct.dir_to_uv(Vector3.UP), Vector2(0.5, 0.5)), str(HemiOct.dir_to_uv(Vector3.UP)))


func test_horizon_maps_to_border() -> void:
	for a in 16:
		var d := Vector3(cos(a * TAU / 16), 0, sin(a * TAU / 16))
		var uv := HemiOct.dir_to_uv(d)
		var m := maxf(absf(uv.x - 0.5), absf(uv.y - 0.5))
		check(near(m, 0.5), "horizon dir %s -> %s" % [d, uv])


func test_round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 50:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.01, 1), rng.randf_range(-1, 1)).normalized()
		var back := HemiOct.uv_to_dir(HemiOct.dir_to_uv(d))
		check(back.distance_to(d) < 1e-4, "%s -> %s" % [d, back])


func test_dir_to_uv_below_horizon_clamps() -> void:
	var below := HemiOct.dir_to_uv(Vector3(1, -0.5, 0).normalized())
	check(_v2near(below, HemiOct.dir_to_uv(Vector3(1, 0, 0))), str(below))
	var straight_down := HemiOct.dir_to_uv(Vector3.DOWN)
	check(straight_down.x >= 0.0 and straight_down.x <= 1.0 and not is_nan(straight_down.x), "down finite")


func test_frame_dir_corners_horizon() -> void:
	check(HemiOct.frame_dir(0, 0).y < 0.2, str(HemiOct.frame_dir(0, 0)))
	check(near(HemiOct.frame_dir(0, 0).length(), 1.0), "unit")


func test_shadow_weights_wrap() -> void:
	var a := HemiOct.shadow_weights(-PI / 8)
	var b := HemiOct.shadow_weights(15 * PI / 8)
	check(a.is_equal_approx(b), "%s vs %s" % [a, b])
	check(HemiOct.shadow_weights(TAU + 0.1).is_equal_approx(HemiOct.shadow_weights(0.1)), "wrap > TAU")
	for i in 40:
		var w := HemiOct.shadow_weights(i * 0.37 - 5.0)
		check(int(w.y) == (int(w.x) + 1) % 8, "k1 = k0+1: %s" % w)
		check(w.z >= 0.0 and w.z < 1.0, "t range")
	check(HemiOct.shadow_weights(PI / 4 * 3 + 1e-4).x == 3.0, "k0 at 135deg")
