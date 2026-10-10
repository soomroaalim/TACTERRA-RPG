extends Control
## TACTERRA RPG — match setup screen.
## Every option maps into the settings Dictionary that GameState.create()
## expects: {map_size:int, ai_count:int, difficulty:int, preset:String,
## speed:float}. Defaults: Standard / 3 AI / Normal / Standard / 1x.

const GameScreen := preload("res://scripts/ui/game_screen.gd")

const MAP_NAMES := ["Small (24 lands)", "Standard (36 lands)", "Large (48 lands)"]
const AI_NAMES := ["2 rivals", "3 rivals", "4 rivals", "5 rivals"]
const DIFF_NAMES := ["Easy", "Normal", "Hard"]
const PRESET_NAMES := ["Poor (250c / 120s / 180 troops)",
	"Standard (500c / 200s / 300 troops)", "Rich (900c / 350s / 450 troops)"]
const PRESET_IDS := ["poor", "standard", "rich"]
const SPEED_NAMES := ["0.5x", "1x", "2x", "4x"]
const SPEED_VALS := [0.5, 1.0, 2.0, 4.0]

var _opts := {}


func _ready() -> void:
	add_child(UiKit.background())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UiKit.make_panel()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var vb := UiKit.vbox(14)
	panel.add_child(vb)

	var title := UiKit.make_title("New Match", 44)
	vb.add_child(title)

	_opts["map"] = _add_option(vb, "Map size", MAP_NAMES, 1)
	_opts["ai"] = _add_option(vb, "AI opponents", AI_NAMES, 1)
	_opts["diff"] = _add_option(vb, "Difficulty", DIFF_NAMES, 1)
	_opts["preset"] = _add_option(vb, "Starting resources", PRESET_NAMES, 1)
	_opts["speed"] = _add_option(vb, "Game speed", SPEED_NAMES, 1)

	vb.add_child(UiKit.make_label(
		"Defeat every rival nation to win. Lose all your land and you fall.",
		16, UiKit.TEXT_DIM))

	var start := UiKit.make_button("Start Battle", 64, 24)
	start.name = "StartBattleButton"
	start.pressed.connect(_on_start)
	vb.add_child(start)

	var back := UiKit.make_button("Back", 56, 20)
	back.name = "BackButton"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scripts/ui/main_menu.tscn"))
	vb.add_child(back)


func _add_option(vb: VBoxContainer, caption: String, items: Array, default_idx: int) -> OptionButton:
	vb.add_child(UiKit.make_label(caption, 18))
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH)
	ob.add_theme_font_size_override("font_size", 18)
	ob.add_theme_color_override("font_color", UiKit.TEXT)
	for it in items:
		ob.add_item(str(it))
	ob.selected = default_idx
	vb.add_child(ob)
	return ob


func _collect_settings() -> Dictionary:
	return {
		"map_size": int((_opts["map"] as OptionButton).selected),
		"ai_count": int((_opts["ai"] as OptionButton).selected) + 2,
		"difficulty": int((_opts["diff"] as OptionButton).selected),
		"preset": PRESET_IDS[int((_opts["preset"] as OptionButton).selected)],
		"speed": float(SPEED_VALS[int((_opts["speed"] as OptionButton).selected)]),
	}


func _on_start() -> void:
	GameScreen.pending_settings = _collect_settings()
	GameScreen.pending_state = null
	get_tree().change_scene_to_file("res://scripts/ui/game_screen.tscn")
