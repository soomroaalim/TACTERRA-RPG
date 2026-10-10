extends SceneTree
## Headless test runner. Discovers tests/test_*.gd, calls static run() on each.
## Each test file: extends RefCounted, static func run() -> Array of
## {name:String, passed:bool, note:String}.
## Usage: godot --headless --path . --script res://tests/run_tests.gd


func _init() -> void:
	var files: Array[String] = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		print("TEST RUNNER ERROR: cannot open res://tests")
		quit(2)
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	files.sort()

	var total := 0
	var passed := 0
	var failed := 0
	var failed_names: Array[String] = []
	for tf in files:
		var path := "res://tests/" + tf
		var tc = load(path)
		# Guard: a script with parse errors must not abort the runner
		# before quit() (that used to hang the process indefinitely).
		var loadable := tc != null and tc is GDScript and (tc as GDScript).can_instantiate()
		if not loadable:
			print("SKIP (not loadable — parse errors?): ", path)
			failed += 1
			continue
		var results: Array = tc.run()
		for r in results:
			total += 1
			var ok: bool = r.get("passed", false)
			var nm: String = r.get("name", "?")
			var note: String = r.get("note", "")
			if ok:
				passed += 1
				print("  PASS ", nm)
			else:
				failed += 1
				failed_names.append(nm)
				print("  FAIL ", nm, " :: ", note)
	print("==================================================")
	print("TESTS: total=%d passed=%d failed=%d" % [total, passed, failed])
	if failed > 0:
		print("FAILED: ", ", ".join(failed_names))
	quit(1 if failed > 0 else 0)
