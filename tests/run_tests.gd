extends SceneTree
## godot --headless --path . -s tests/run_tests.gd            (CPU tests)
## godot --path . -s tests/run_tests.gd -- --gpu               (also tests/test_gpu_*.gd)
## Optional filter: -- --only=<substring of file name>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var gpu := "--gpu" in args
	var only := ""
	for a in args:
		if a.begins_with("--only="):
			only = a.substr(7)
	var failed := 0
	var ran := 0
	for f in DirAccess.get_files_at("res://tests"):
		if not (f.begins_with("test_") and f.ends_with(".gd")) or f == "test_case.gd":
			continue
		if f.begins_with("test_gpu_") and not gpu:
			continue
		if only != "" and not only in f:
			continue
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			printerr("FAIL %s: script failed to load" % f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			var t: TestCase = script.new()
			if t.has_method("attach"):
				t.attach(root)
			t.current = f + "::" + name
			await t.call(name)
			ran += 1
			for msg in t.failures:
				printerr("FAIL ", msg)
			failed += t.failures.size()
			if t.has_method("cleanup"):
				t.cleanup()
	print("ran %d tests, %d failures" % [ran, failed])
	quit(1 if failed > 0 else 0)
