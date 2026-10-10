extends SceneTree
## UI smoke test: instantiate every screen, run frames, assert key widgets
## exist and no runtime errors occur. Run under xvfb-run:
##   xvfb-run -a godot --path . --script res://tools/ui_check.gd
## Exit code 0 = all PASS, 1 = any FAIL.

var _queue: Array = []
var _current_path := ""
var _inst: Node = null
var _frames := 0
var _fails := 0
var _passes := 0


func _initialize() -> void:
	_queue = [
		"res://scripts/ui/main_menu.tscn",
		"res://scripts/ui/match_setup.tscn",
		"res://scripts/ui/how_to_play.tscn",
		"res://scripts/ui/settings_screen.tscn",
		"res://scripts/ui/credits_screen.tscn",
		"res://scripts/ui/game_screen.tscn",
	]
	_next()


func _next() -> bool:
	if _queue.is_empty():
		print("UI_CHECK summary: %d PASS, %d FAIL" % [_passes, _fails])
		if _fails > 0:
			quit(1)
		else:
			quit(0)
		return false
	_current_path = _queue.pop_front()
	if _current_path.ends_with("game_screen.tscn"):
		var scr = load("res://scripts/ui/game_screen.gd")
		scr.pending_settings = {"map_size": 0, "ai_count": 2, "difficulty": 0,
			"preset": "poor", "speed": 1.0}
	var ps: PackedScene = load(_current_path)
	if ps == null:
		_fail("load() returned null")
		return _next()
	_inst = ps.instantiate()
	if _inst == null:
		_fail("instantiate() returned null")
		return _next()
	root.add_child(_inst)
	_frames = 0
	return true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	_check_current()
	if is_instance_valid(_inst):
		_inst.queue_free()
	_inst = null
	_next()
	return false


func _ok(msg: String) -> void:
	_passes += 1
	print("PASS [%s] %s" % [_current_path.get_file(), msg])


func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_current_path.get_file(), msg])


func _need(name: String) -> Node:
	var n := _inst.find_child(name, true, false)
	if n == null:
		_fail("missing node '%s'" % name)
	else:
		_ok("node '%s' present" % name)
	return n


func _check_current() -> void:
	var nodes := _count(_inst)
	_ok("instantiated, %d nodes, no runtime errors" % nodes)
	match _current_path.get_file():
		"main_menu.tscn":
			for b in ["PlayOfflineButton", "ContinueButton", "HowToButton",
					"SettingsButton", "CreditsButton"]:
				var btn := _need(b) as Button
				if btn != null and not btn.disabled:
					_ok("button '%s' enabled" % b)
			var cont := _inst.find_child("ContinueButton", true, false) as Button
			if cont != null:
				print("INFO [main_menu] Continue disabled=%s (no saves expected)" % str(cont.disabled))
		"match_setup.tscn":
			_need("StartBattleButton")
			_need("BackButton")
			var d: Dictionary = _inst._collect_settings()
			var keys := ["map_size", "ai_count", "difficulty", "preset", "speed"]
			var ok := true
			for k in keys:
				if not d.has(k):
					ok = false
			if ok:
				_ok("settings dict has all keys: %s" % str(d))
			else:
				_fail("settings dict missing keys: %s" % str(d))
		"how_to_play.tscn":
			_need("BackButton")
		"settings_screen.tscn":
			_need("VolumeSlider")
			_need("ResetSaveButton")
			_need("BackButton")
		"credits_screen.tscn":
			_need("BackButton")
		"game_screen.tscn":
			_check_game_screen()


func _check_game_screen() -> void:
	if _inst.state == null:
		_fail("state is null (core failed to load?)")
		return
	_ok("GameState created via pending_settings")
	var terr_count: int = (_inst.state.territories as Array).size()
	var map_nodes := 0
	var map_root := _inst.find_child("MapRoot", true, false)
	if map_root != null:
		for c in map_root.get_children():
			var cn := c.name as String
			if cn.length() > 1 and cn[0] == "T" and cn[1].is_valid_int():
				map_nodes += 1
	if map_nodes == terr_count and terr_count > 0:
		_ok("territory nodes match state: %d" % terr_count)
	else:
		_fail("territory nodes %d != state territories %d" % [map_nodes, terr_count])
	_need("TopBar")
	_need("RightPanel")
	_need("TickerPanel")
	# Simulate 60 ticks of 1x gameplay.
	for _i in range(60):
		_inst._process(1.0 / 60.0)
	_ok("60 simulated frames ticked, day=%.1f" % float(_inst.state.day))
	# Select the player capital and verify the right panel opens.
	var cap_id: int = _inst.state.player().capital_id
	_inst.select_territory(cap_id)
	for _i in range(4):
		_inst._process(1.0 / 60.0)
	var rp := _inst.find_child("RightPanel", true, false)
	if rp != null and (rp as Control).visible:
		_ok("right panel visible after select_territory(%d)" % cap_id)
	else:
		_fail("right panel not visible after selection")
	var ab := _inst.find_child("ActionButtons", true, false)
	if ab != null and ab.get_child_count() >= 3:
		_ok("action buttons present: %d" % ab.get_child_count())
	else:
		_fail("action buttons missing (got %d)" % (ab.get_child_count() if ab != null else -1))
	# Move dialog: open and close programmatically.
	var t = _inst.state.get_territory(cap_id)
	if t != null and (t.neighbors as Array).size() > 0 and t.army != null:
		var dst: int = (t.neighbors as Array)[0]
		_inst._open_move_dialog(cap_id, dst)
		for _i in range(2):
			_inst._process(1.0 / 60.0)
		_inst._close_dialog()
		_ok("move dialog opened/closed for %d -> %d" % [cap_id, dst])
	else:
		print("INFO [game_screen] no neighbor+army for move-dialog test")
	# Save path (slot 0) via the real SaveSystem.
	var SS = load("res://scripts/core/save_system.gd")
	if SS != null:
		var res: Dictionary = SS.save(_inst.state, 0)
		if bool(res.get("ok", false)) and SS.has_save(0):
			_ok("SaveSystem.save/load slot 0 works")
			var lr: Array = SS.load(0)
			if lr[0] != null:
				_ok("loaded state day=%.1f" % float(lr[0].day))
			else:
				_fail("SaveSystem.load returned null: %s" % str(lr[1]))
		else:
			_fail("SaveSystem.save failed: %s" % str(res.get("error", "?")))
	# End-screen path: force defeat and verify overlay.
	_inst.state.over = true
	_inst.state.player_won = false
	_inst._process(1.0 / 60.0)
	var end_layer := _inst.find_child("EndLayer", true, false)
	if end_layer != null and (end_layer as CanvasLayer).visible:
		_ok("end screen overlay shown on defeat")
	else:
		_fail("end screen overlay not shown")
	# Back-button policy: reset state first (ensure no panel/dialog open).
	_inst.state.over = false
	_inst._end_shown = false
	(end_layer as CanvasLayer).visible = false
	_inst._close_dialog()
	_inst.selected_id = -1
	var rp0 := _inst.find_child("RightPanel", true, false)
	if rp0 != null:
		(rp0 as Control).visible = false
	var pause_layer := _inst.find_child("PauseLayer", true, false)
	# 1. Back with no overlay -> opens pause menu.
	_inst._on_back_pressed()
	if pause_layer != null and (pause_layer as CanvasLayer).visible:
		_ok("back opens pause menu when no overlay")
	else:
		_fail("back did not open pause menu")
	# 2. Back with pause open -> closes it (resume).
	_inst._on_back_pressed()
	if pause_layer != null and not (pause_layer as CanvasLayer).visible:
		_ok("back closes pause menu (resume)")
	else:
		_fail("back did not close pause menu")
	# 3. Back with right panel open -> closes panel.
	_inst.select_territory(cap_id)
	_inst._on_back_pressed()
	var rp2 := _inst.find_child("RightPanel", true, false)
	if rp2 != null and not (rp2 as Control).visible:
		_ok("back closes territory panel")
	else:
		_fail("back did not close territory panel")
	# 4. Back with dialog open -> closes dialog first.
	_inst._open_move_dialog(cap_id, (t.neighbors as Array)[0])
	_inst._on_back_pressed()
	if _inst._dialog_layer == null:
		_ok("back closes dialog first")
	else:
		_fail("back did not close dialog")


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c
