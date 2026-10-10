extends Control
## TACTERRA RPG — main menu.
## Buttons: Play Offline -> match_setup; Continue -> game_screen with the
## newest save (disabled when no save exists); How to Play; Settings; Credits.

const GameScreen := preload("res://scripts/ui/game_screen.gd")
const SS_PATH := "res://scripts/core/save_system.gd"

var _continue_btn: Button
var _back_press_time := 0.0 ## for double-press-to-exit on Android


func _notification(what: int) -> void:
	# Android system Back button. On the main menu, require a double-press
	# to exit (explicit confirmation), instead of quitting immediately.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _back_press_time < 3.0:
			get_tree().quit()
		else:
			_back_press_time = now
			# Simple centered label (no CanvasLayer needed here).
			var lbl := Label.new()
			lbl.text = "Press back again to exit."
			lbl.add_theme_font_size_override("font_size", 22)
			lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			lbl.position -= Vector2(140, 120)
			add_child(lbl)
			var tw := create_tween()
			tw.tween_interval(2.0)
			tw.tween_callback(lbl.queue_free)
		get_viewport().set_input_as_handled()


func _ready() -> void:
	add_child(UiKit.background())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vb := UiKit.vbox(14)
	center.add_child(vb)

	var title := UiKit.make_title("TACTERRA RPG", 72)
	title.custom_minimum_size = Vector2(560, 0)
	vb.add_child(title)

	var sub := UiKit.make_label("Outthink. Outmaneuver. Conquer.", 24, UiKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	vb.add_child(UiKit.spacer(18))

	var play := UiKit.make_button("Play Offline", 64, 24)
	play.name = "PlayOfflineButton"
	play.custom_minimum_size.x = 380
	play.pressed.connect(_on_play)
	vb.add_child(play)

	_continue_btn = UiKit.make_button("Continue", 64, 24)
	_continue_btn.name = "ContinueButton"
	_continue_btn.custom_minimum_size.x = 380
	_continue_btn.pressed.connect(_on_continue)
	vb.add_child(_continue_btn)
	_refresh_continue()

	var how := UiKit.make_button("How to Play", 56, 20)
	how.name = "HowToButton"
	how.custom_minimum_size.x = 380
	how.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scripts/ui/how_to_play.tscn"))
	vb.add_child(how)

	var settings := UiKit.make_button("Settings", 56, 20)
	settings.name = "SettingsButton"
	settings.custom_minimum_size.x = 380
	settings.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scripts/ui/settings_screen.tscn"))
	vb.add_child(settings)

	var credits := UiKit.make_button("Credits", 56, 20)
	credits.name = "CreditsButton"
	credits.custom_minimum_size.x = 380
	credits.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scripts/ui/credits_screen.tscn"))
	vb.add_child(credits)

	vb.add_child(UiKit.spacer(10))
	var ver := UiKit.make_label("v1.0  •  fully offline  •  no accounts, no ads", 15, UiKit.TEXT_DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ver)


func _save_system():
	if ResourceLoader.exists(SS_PATH):
		return load(SS_PATH)
	return null


func _refresh_continue() -> void:
	var has := false
	var ss = _save_system()
	if ss != null:
		for slot in range(Tacterra.SAVE_SLOTS):
			if bool(ss.has_save(slot)):
				has = true
				break
	_continue_btn.disabled = not has
	_continue_btn.tooltip_text = "Resume your saved match" if has else "No saved match yet"


func _on_play() -> void:
	GameScreen.pending_settings = {}
	GameScreen.pending_state = null
	get_tree().change_scene_to_file("res://scripts/ui/match_setup.tscn")


func _on_continue() -> void:
	var ss = _save_system()
	if ss == null:
		return
	for slot in range(Tacterra.SAVE_SLOTS):
		if bool(ss.has_save(slot)):
			var res: Array = ss.load(slot)
			var loaded_state = res[0]
			var err := str(res[1])
			if loaded_state != null:
				GameScreen.pending_settings = {}
				GameScreen.pending_state = loaded_state
				get_tree().change_scene_to_file("res://scripts/ui/game_screen.tscn")
				return
			else:
				_refresh_continue()
				return
