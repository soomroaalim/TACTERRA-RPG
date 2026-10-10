extends Control
## TACTERRA RPG — credits screen.


func _ready() -> void:
	add_child(UiKit.background())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vb := UiKit.vbox(14)
	center.add_child(vb)

	var title := UiKit.make_title("TACTERRA RPG", 56)
	title.custom_minimum_size = Vector2(560, 0)
	vb.add_child(title)

	var sub := UiKit.make_label("Outthink. Outmaneuver. Conquer.", 22, UiKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	vb.add_child(UiKit.spacer(10))

	for line in [
		"Built with Godot 4.3 (GDScript)",
		"Design & code: Ember for Muhammad Haroon",
		"All map art is drawn procedurally in code.",
		"All sound effects are synthesized at runtime.",
		"No external assets. No network. No accounts.",
		"Your data never leaves your device.",
	]:
		var l := UiKit.make_label(line, 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)

	vb.add_child(UiKit.spacer(10))

	var back := UiKit.make_button("Back", 56, 20)
	back.name = "BackButton"
	back.custom_minimum_size.x = 380
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scripts/ui/main_menu.tscn"))
	var bc := CenterContainer.new()
	bc.add_child(back)
	vb.add_child(bc)
