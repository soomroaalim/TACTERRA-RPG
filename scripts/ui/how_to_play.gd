extends Control
## TACTERRA RPG — How to Play screen.
## The rules text lives in help_text() so the game screen can show the same
## content in an in-match overlay without changing scenes.

## Scene to return to when Back is pressed (defaults to the main menu).
static var return_scene := "res://scripts/ui/main_menu.tscn"


static func help_text() -> String:
	return """[center][b][color=#f2b73e][font_size=30]HOW TO PLAY[/font_size][/color][/b][/center]

[b][color=#f2b73e]GOAL[/color][/b]
You rule a small nation on a fictional world. Rival nations surround you.
Expand your borders, grow your economy, raise armies and eliminate every
rival nation to win. Lose all your territory and your nation falls.

[b][color=#f2b73e]CONTROLS[/color][/b]
• Tap / click a territory to select it and see its details.
• Drag to pan the map. Mouse wheel or pinch to zoom.
• Tap a highlighted neighbor while in "Move / Attack" mode to march there.
• All buttons are touch-sized; no keyboard is needed.

[b][color=#f2b73e]ECONOMY — THREE RESOURCES[/color][/b]
• [b]Credits[/b]: earned daily from your territories. Spent on recruiting,
  developing land and building forts.
• [b]Supplies[/b]: produced by your land, consumed by armies. Starved
  armies lose men every day.
• [b]Manpower[/b]: limits how many soldiers you can recruit. It regrows
  slowly from your population.
Fertile land and cities earn the most. If you cannot pay upkeep, soldiers
desert (3% per day) until the debt clears.

[b][color=#f2b73e]EXPANSION[/color][/b]
Neutral (gray) territories can be captured by marching an army into them —
but their garrisons fight back. You may only move into [b]neighboring[/b]
territories. Expanding too fast leaves long borders exposed: every new
territory is another border to defend.

[b][color=#f2b73e]ARMIES & MOVEMENT[/color][/b]
Select one of your territories that has troops, press "Move / Attack", then
tap a neighboring territory. Choose how many soldiers march; the rest stay
behind. Marching takes time based on distance. Recruiting takes 3 days of
training before new soldiers arrive.

[b][color=#f2b73e]COMBAT[/color][/b]
Battles are decided by: troop numbers, defender's terrain and forts
(mountains and rivers help defenders), supply status, and training.
Attacking across a river into mountains against a fortified enemy is costly;
soften them by cutting their supply or striking where they are weak.

[b][color=#f2b73e]SUPPLY[/color][/b]
Armies must trace a path through your own territory back to your capital.
Cut-off armies fight at 60% strength after 3 days and then lose 2% of
their men per day. Watch the supply indicator on every territory.

[b][color=#f2b73e]VICTORY & DEFEAT[/color][/b]
Eliminate every rival nation to win. If you lose your last territory, you
are defeated. Use the pause menu to save; Continue on the main menu
resumes your saved match.

[b][color=#f2b73e]TIPS[/color][/b]
• Develop fertile territories first — economy wins long wars.
• Keep a reserve army behind threatened borders.
• Watch rival personalities: Expansionists grab land, Aggressives hunt
  weakness, Defenders punish reckless attacks.
"""


func _ready() -> void:
	add_child(UiKit.background())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var vb := UiKit.vbox(12)
	margin.add_child(vb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = help_text()
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rtl.add_theme_color_override("default_color", UiKit.TEXT)
	rtl.add_theme_font_size_override("normal_font_size", 18)
	rtl.add_theme_font_size_override("bold_font_size", 20)
	rtl.scroll_active = false
	scroll.add_child(rtl)

	var back := UiKit.make_button("Back", 56, 20)
	back.name = "BackButton"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(return_scene))
	vb.add_child(back)
