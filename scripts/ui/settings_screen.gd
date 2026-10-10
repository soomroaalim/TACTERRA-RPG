extends Control
## TACTERRA RPG — settings screen.
## Volume is stored in a local JSON file (user://tacterra_ui_settings.json)
## and, when the audio module's GameSettings exists, mirrored to it via
## duck-typed static calls (the audio module is built in parallel, so its
## exact API is probed at runtime rather than referenced directly).

const GAME_SETTINGS_PATH := "res://scripts/audio/game_settings.gd"
const LOCAL_PATH := "user://tacterra_ui_settings.json"

static var local_volume: float = 80.0 ## 0..100, used when GameSettings is absent

var _slider: HSlider
var _vol_label: Label
var _toast_layer: CanvasLayer
var _confirm_layer: CanvasLayer


func _ready() -> void:
	add_child(UiKit.background())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UiKit.make_panel()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var vb := UiKit.vbox(16)
	panel.add_child(vb)

	var title := UiKit.make_title("Settings", 44)
	vb.add_child(title)

	vb.add_child(UiKit.make_label("Volume", 20))
	var hb := UiKit.hbox(12)
	vb.add_child(hb)
	_slider = HSlider.new()
	_slider.name = "VolumeSlider"
	_slider.min_value = 0
	_slider.max_value = 100
	_slider.step = 1
	_slider.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value = _read_volume()
	_slider.value_changed.connect(_on_volume_changed)
	hb.add_child(_slider)
	_vol_label = UiKit.make_label("%d%%" % int(_slider.value), 20)
	_vol_label.custom_minimum_size = Vector2(64, 0)
	hb.add_child(_vol_label)

	var reset := UiKit.make_button("Reset Save Data", 56, 20)
	reset.name = "ResetSaveButton"
	reset.pressed.connect(_on_reset_pressed)
	vb.add_child(reset)

	vb.add_child(UiKit.make_label(
		"Reset deletes all saved matches in slots 1-3. This cannot be undone.",
		15, UiKit.TEXT_DIM))

	var back := UiKit.make_button("Back", 56, 20)
	back.name = "BackButton"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scripts/ui/main_menu.tscn"))
	vb.add_child(back)

	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 50
	add_child(_toast_layer)


func _settings_script():
	if ResourceLoader.exists(GAME_SETTINGS_PATH):
		return load(GAME_SETTINGS_PATH)
	return null


func _script_has(g, method_name: String) -> bool:
	if g == null:
		return false
	if not g.has_method("get_script_method_list"):
		return false
	for m in g.get_script_method_list():
		if m.get("name") == method_name:
			return true
	return false


func _read_volume() -> float:
	var g = _settings_script()
	if _script_has(g, "get_value"):
		# Real GameSettings API: get_value("volume", default), 0..1.
		return clampf(float(g.get_value("volume", 0.8)) * 100.0, 0.0, 100.0)
	if _script_has(g, "get_volume"):
		return clampf(float(g.get_volume()) * 100.0, 0.0, 100.0)
	if FileAccess.file_exists(LOCAL_PATH):
		var f := FileAccess.open(LOCAL_PATH, FileAccess.READ)
		if f != null:
			var d: Dictionary = JSON.parse_string(f.get_as_text())
			if d.has("volume"):
				local_volume = clampf(float(d["volume"]), 0.0, 100.0)
	return local_volume


func _write_volume(v: float) -> void:
	local_volume = v
	var g = _settings_script()
	if _script_has(g, "save_settings"):
		var d := {}
		if _script_has(g, "load_settings"):
			d = g.load_settings()
		d["volume"] = v / 100.0
		g.save_settings(d)
		return
	if _script_has(g, "set_volume"):
		g.set_volume(v / 100.0)
		return
	var f := FileAccess.open(LOCAL_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"volume": v}))


func _on_volume_changed(v: float) -> void:
	_vol_label.text = "%d%%" % int(v)
	_write_volume(v)


func _on_reset_pressed() -> void:
	_close_confirm()
	_confirm_layer = CanvasLayer.new()
	_confirm_layer.layer = 45
	add_child(_confirm_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)
	var panel := UiKit.make_panel()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var vb := UiKit.vbox(14)
	panel.add_child(vb)
	vb.add_child(UiKit.make_label("Delete all saved matches?", 24, UiKit.DANGER))
	vb.add_child(UiKit.make_label("Slots 1-3 will be erased permanently.", 17, UiKit.TEXT_DIM))
	var hb := UiKit.hbox(12)
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	var cancel := UiKit.make_small_button("Cancel")
	cancel.pressed.connect(_close_confirm)
	hb.add_child(cancel)
	var yes := UiKit.make_small_button("Delete All")
	yes.pressed.connect(_do_reset)
	hb.add_child(yes)


func _close_confirm() -> void:
	if is_instance_valid(_confirm_layer):
		_confirm_layer.queue_free()
	_confirm_layer = null


func _do_reset() -> void:
	_close_confirm()
	var deleted := 0
	for slot in range(Tacterra.SAVE_SLOTS):
		var path := "user://tacterra_save_%d.json" % slot
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(path)
			if err == OK:
				deleted += 1
	UiKit.toast(_toast_layer, "Deleted %d saved match(es)." % deleted, UiKit.GOOD)
