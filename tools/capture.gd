extends SceneTree
## Screenshot harness for Xvfb runs. Captures: main menu, game map (fresh),
## gameplay after simulated days, a battle report dialog, and the end screen.
## Usage: xvfb-run -a godot --path . --script res://tools/capture.gd
## Writes PNGs to /tmp/tacterra_shots/.

const OUT := "/tmp/tacterra_shots"
const GS_SCRIPT := "res://scripts/ui/game_screen.gd"


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [OUT, name])
	print("SHOT ", name, " -> ", err)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_call_deferred_start()


func _call_deferred_start() -> void:
	_start.call_deferred()


func _clear() -> void:
	for c in root.get_children():
		c.queue_free()
	await process_frame


func _start() -> void:
	# 1. Main menu.
	var menu: Control = load("res://scripts/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _shot("01_main_menu")
	await _clear()

	# 2. Fresh game map (standard, 3 AI, seed fixed for a nice layout).
	var gs: GDScript = load(GS_SCRIPT)
	gs.set("pending_settings", {
		"map_size": Tacterra.MapSize.STANDARD, "ai_count": 3,
		"difficulty": Tacterra.Difficulty.NORMAL, "preset": "standard",
		"speed": 0.0, "seed": 2026,
	})
	var game: Control = load("res://scripts/ui/game_screen.tscn").instantiate()
	root.add_child(game)
	# Let it build and render.
	for _i in 30:
		await process_frame
	await _shot("02_map_fresh")

	# 3. Gameplay after 40 simulated days (AI expands, borders shift).
	# Also select the player capital to show the territory info panel.
	var state = game.get("state")
	if state != null:
		for _i in 40:
			state.tick(1.0)
		game.select_territory(state.player().capital_id)
	for _i in 20:
		await process_frame
	await _shot("03_gameplay_day40")
	await _clear()

	# 4. Battle: fresh state, force a big attack, capture the report dialog.
	gs.set("pending_settings", {
		"map_size": Tacterra.MapSize.SMALL, "ai_count": 2,
		"difficulty": Tacterra.Difficulty.NORMAL, "preset": "standard",
		"speed": 0.0, "seed": 99,
	})
	var game2: Control = load("res://scripts/ui/game_screen.tscn").instantiate()
	root.add_child(game2)
	for _i in 30:
		await process_frame
	var s2 = game2.get("state")
	if s2 != null:
		# Player doomstack vs weakest adjacent enemy/neutral.
		var from_id := -1
		var to_id := -1
		for tid in s2.owned_ids(0):
			var t = s2.get_territory(tid)
			for nb in t.neighbors:
				if s2.get_territory(nb).owner_id != 0:
					from_id = tid
					to_id = nb
					break
			if from_id >= 0:
				break
		if from_id >= 0:
			var ft = s2.get_territory(from_id)
			ft.army = ArmyData.create(0, 900, from_id, 0.8)
			s2.order_move(0, from_id, to_id, 800)
			for _i in 30:
				s2.tick(1.0)
			# Open the reports dialog if the screen exposes it.
			if game2.has_method("show_reports"):
				game2.show_reports()
	for _i in 20:
		await process_frame
	await _shot("04_battle")
	await _clear()

	# 5. End screen: hand the player the whole map, tick once, capture.
	gs.set("pending_settings", {
		"map_size": Tacterra.MapSize.SMALL, "ai_count": 2,
		"difficulty": Tacterra.Difficulty.EASY, "preset": "standard",
		"speed": 0.0, "seed": 5,
	})
	var game3: Control = load("res://scripts/ui/game_screen.tscn").instantiate()
	root.add_child(game3)
	for _i in 30:
		await process_frame
	var s3 = game3.get("state")
	if s3 != null:
		for t in s3.territories:
			if t.owner_id != 0:
				t.owner_id = 0
				t.army = null
				t.garrison = 0
		s3.tick(1.0)
	for _i in 20:
		await process_frame
	await _shot("05_victory")
	print("CAPTURE DONE")
	quit(0)
