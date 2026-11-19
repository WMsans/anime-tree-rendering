extends SceneTree
## Flyover performance check (GPU, not --headless). Renders the demo at 1920x1080 from CamFly.
## godot --path . -s tests/perf.gd [-- <CameraNode>]   exit 1 if over budget.

const FRAME_MS_BUDGET := 16.6
const DRAW_CALL_BUDGET := 1500


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := OS.get_cmdline_user_args()
	var cam_name := args[0] if args.size() > 0 else "CamFly"
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var scene: Node = (load("res://demo/forest_demo.tscn") as PackedScene).instantiate()
	scene.get_node("CameraRig").animate = false
	vp.add_child(scene)
	var cam: Camera3D = scene.find_child(cam_name, true, false)
	await process_frame  # the demo camera rig picks its own camera in _ready
	cam.make_current()
	for i in 60:
		await process_frame
	var gpu := 0.0
	var cpu := 0.0
	var draws := 0
	var t0 := Time.get_ticks_usec()
	const N := 300
	for i in N:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid())
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var frame_ms := (Time.get_ticks_usec() - t0) / 1000.0 / N
	var visible := 0
	var data: ForestData = scene.get_node("Forest").data
	for i in data.count():
		var p := data.position(i)
		if cam.is_position_in_frustum(p) and p.distance_to(cam.global_position) < 2000.0:
			visible += 1
	print("camera=%s frame_ms=%.2f gpu_ms=%.2f cpu_ms=%.2f draw_calls=%d visible_trees=%d" % [
		cam_name, frame_ms, gpu / N, cpu / N, draws, visible])
	var ok := frame_ms <= FRAME_MS_BUDGET and draws <= DRAW_CALL_BUDGET
	print("PERF ", "OK" if ok else "OVER BUDGET")
	quit(0 if ok else 1)
