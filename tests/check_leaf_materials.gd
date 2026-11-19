## Every leaf surface uses the leaf ShaderMaterial; trunk/branch keep glb materials.
## godot --headless --path . --script tests/check_leaf_materials.gd
extends SceneTree

const LEAF := ["res://demo/assets/trees/leaf_green.tres", "res://demo/assets/trees/leaf_light.tres"]
const TREES := ["tree_a", "tree_b", "tree_c", "pine_a", "pine_b"]


func _initialize() -> void:
	var failed := false
	for t in TREES:
		var scene: Node = load("res://demo/assets/trees/%s.glb" % t).instantiate()
		var leaf := 0
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				if m.resource_path in LEAF and m is ShaderMaterial:
					leaf += 1
				elif m is ShaderMaterial or not m.resource_name in ["Tree_Trunk", "Tree_Branch"]:
					print("FAIL: %s %s %s" % [t, mi.name, m.resource_name])
					failed = true
		if leaf == 0:
			print("FAIL: %s has no leaf surfaces" % t)
			failed = true
		scene.free()
	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)
