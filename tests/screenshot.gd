## Renders tree_demo from a few camera positions and saves <out_prefix>_<n>.png:
## 0 default, 1 moved 1 m on x (crawl check), 2 close to TreeB, 3 close moved 0.3 m,
## 4 close dollied 0.6 m back (crawl check for the bump count).
## godot --path . --script tests/screenshot.gd -- <out_prefix>
extends SceneTree

const SHOTS := [Vector3(0, 5, 24), Vector3(1, 5, 24), Vector3(0.5, 4.5, 3), Vector3(0.8, 4.5, 3), Vector3(0.5, 4.5, 3.6)]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var prefix: String = OS.get_cmdline_user_args()[0]
	var scene: Node = load("res://demo/tree_demo.tscn").instantiate()
	# Drop the fly-camera script: stray mouse input at startup would turn the view.
	var cam: Camera3D = scene.get_node("Camera3D")
	cam.set_script(null)
	root.add_child(scene)
	for i in SHOTS.size():
		cam.position = SHOTS[i]
		for f in 10:
			await process_frame
		root.get_texture().get_image().save_png("%s_%d.png" % [prefix, i])
	quit()
