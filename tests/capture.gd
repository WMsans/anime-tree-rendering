extends SceneTree
## Renders a scene from a named camera into a fixed-size offscreen viewport and saves a PNG.
## Needs a GPU (not --headless):
## godot --path . -s tests/capture.gd -- <scene.tscn> <out.png> [CameraNode] [frames] [WxH]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var size := Vector2i(1920, 1080)
	if a.size() > 4:
		var wh := a[4].split("x")
		size = Vector2i(int(wh[0]), int(wh[1]))
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var scene: Node = (load(a[0]) as PackedScene).instantiate()
	vp.add_child(scene)
	if a.size() > 2 and a[2] != "":
		(scene.find_child(a[2], true, false) as Camera3D).make_current()
	var frames := int(a[3]) if a.size() > 3 else 30
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(a[1].get_base_dir())
	vp.get_texture().get_image().save_png(a[1])
	print("saved ", a[1])
	quit()
