## Renders tree_demo twice (camera moved 1 m on x in between) and saves PNGs.
## godot --path . --script tests/screenshot.gd -- <out_prefix>
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var prefix: String = OS.get_cmdline_user_args()[0]
	var scene: Node = load("res://demo/tree_demo.tscn").instantiate()
	# Drop the fly-camera script: stray mouse input at startup would turn the view.
	scene.get_node("Camera3D").set_script(null)
	root.add_child(scene)
	for i in 2:
		for f in 10:
			await process_frame
		root.get_texture().get_image().save_png("%s_%d.png" % [prefix, i])
		scene.get_node("Camera3D").position.x += 1.0
	quit()
