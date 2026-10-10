extends RefCounted
## Unit tests for SaveSystem: save/load round-trip, slot validation,
## corrupt/incompatible file handling. Uses hand-built synthetic states.
## Uses slot 2 only, and cleans it up afterwards.
## static func run() -> Array of {name, passed, note}.

const SLOT := 2


static func _mk_terr(tid: int, tname: String, owner: int, cx: float, cy: float,
		neighbors: Array) -> TerritoryData:
	var t := TerritoryData.new()
	t.id = tid
	t.name = tname
	t.polygon = PackedVector2Array([
		Vector2(cx - 40, cy - 40), Vector2(cx + 40, cy - 40),
		Vector2(cx + 40, cy + 40), Vector2(cx - 40, cy + 40)])
	t.center = Vector2(cx, cy)
	var nb: Array[int] = []
	for x in neighbors:
		nb.append(int(x))
	t.neighbors = nb
	t.terrain = Tacterra.Terrain.PLAINS
	t.owner_id = owner
	t.population = 1000
	return t


static func _mk_nation(nid: int, nname: String, is_player: bool) -> NationData:
	var n := NationData.new()
	n.id = nid
	n.name = nname
	n.color = Tacterra.NATION_COLORS[nid % Tacterra.NATION_COLORS.size()]
	n.is_player = is_player
	n.difficulty = -1 if is_player else Tacterra.Difficulty.NORMAL
	n.credits = 500.0
	n.supplies = 200.0
	n.manpower = 50.0
	n.capital_id = 0 if is_player else 1
	return n


static func _mini() -> GameState:
	var s := GameState.new()
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = 777
	s.settings = {"preset": "standard", "speed": 2.0}
	s.speed = 2.0
	s.day = 7.25
	s.over = false
	s.winner_id = -1
	s.nations.append(_mk_nation(0, "Free Cities", true))
	s.nations.append(_mk_nation(1, "Rival", false))
	var t0 := _mk_terr(0, "Alpha", 0, 100, 100, [1])
	t0.is_capital = true
	t0.army = ArmyData.create(0, 80, 0, 0.2)
	var t1 := _mk_terr(1, "Beta", 1, 300, 100, [0])
	s.territories.append(t0)
	s.territories.append(t1)
	return s


static func _rec(tname: String, passed: bool, note: String) -> Dictionary:
	return {"name": tname, "passed": passed, "note": note}


static func _raw_write(text: String) -> void:
	var f := FileAccess.open(SaveSystem.SAVE_PATH % SLOT, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func run() -> Array:
	var out: Array = []
	SaveSystem.delete(SLOT)

	# --- save / load round-trip -------------------------------------------
	var s := _mini()
	s.order_move(0, 0, 1, 30)
	s.order_recruit(1, 1, 5)
	s.add_notification("saved game", Tacterra.NotifyKind.GOOD)
	var sr := SaveSystem.save(s, SLOT)
	out.append(_rec("save_ok", bool(sr["ok"]), "err=" + str(sr["error"])))
	out.append(_rec("has_save_true", SaveSystem.has_save(SLOT), ""))

	var lr := SaveSystem.load(SLOT)
	var ok_l := lr[0] != null and str(lr[1]) == ""
	var note_l := "err=" + str(lr[1])
	if ok_l:
		var s2: GameState = lr[0]
		var q2: Array = s2.training_queues.get(1, [])
		ok_l = ok_l and absf(s2.day - 7.25) < 0.001 \
			and s2.speed == 2.0 \
			and s2.get_nation(1).credits == 450.0 \
			and s2.get_territory(0).army.troops == 50 \
			and s2.transits.size() == 1 and s2.transits[0].move_to == 1 \
			and s2.transits[0].troops == 30 \
			and q2.size() == 1 and int(q2[0]["troops"]) == 5 \
			and int(q2[0]["owner_id"]) == 1 \
			and s2.notifications.size() >= 2 \
			and str(s2.settings["preset"]) == "standard" \
			and s2.rng.seed == 777
		note_l = "day=%.2f credits=%.0f army=%d q=%d" % [
			s2.day, s2.get_nation(1).credits,
			s2.get_territory(0).army.troops, q2.size()]
	out.append(_rec("load_round_trip", ok_l, note_l))

	# --- delete / missing ----------------------------------------------------
	SaveSystem.delete(SLOT)
	out.append(_rec("delete_clears_save", not SaveSystem.has_save(SLOT), ""))
	lr = SaveSystem.load(1)
	out.append(_rec("load_missing_slot",
		lr[0] == null and "no save" in str(lr[1]).to_lower(), "err=" + str(lr[1])))

	# --- invalid slots ---------------------------------------------------------
	sr = SaveSystem.save(s, 5)
	out.append(_rec("save_rejects_bad_slot", not bool(sr["ok"]), "err=" + str(sr["error"])))
	sr = SaveSystem.save(s, -1)
	out.append(_rec("save_rejects_negative_slot", not bool(sr["ok"]), "err=" + str(sr["error"])))
	lr = SaveSystem.load(5)
	out.append(_rec("load_rejects_bad_slot", lr[0] == null and lr[1] != "",
		"err=" + str(lr[1])))
	out.append(_rec("has_save_rejects_bad_slot",
		not SaveSystem.has_save(5) and not SaveSystem.has_save(-1), ""))
	SaveSystem.delete(5) # must not crash

	# --- corrupt / incompatible files -------------------------------------------
	_raw_write("THIS IS NOT JSON {{{")
	lr = SaveSystem.load(SLOT)
	out.append(_rec("load_rejects_garbage",
		lr[0] == null and str(lr[1]) == "corrupt save data", "err=" + str(lr[1])))

	_raw_write("[1, 2, 3]")
	lr = SaveSystem.load(SLOT)
	out.append(_rec("load_rejects_json_array",
		lr[0] == null and str(lr[1]) == "corrupt save data", "err=" + str(lr[1])))

	_raw_write("{}")
	lr = SaveSystem.load(SLOT)
	out.append(_rec("load_rejects_empty_object",
		lr[0] == null and "incompatible" in str(lr[1]), "err=" + str(lr[1])))

	var d := _mini().to_dict()
	d["version"] = 999
	_raw_write(JSON.stringify(d))
	lr = SaveSystem.load(SLOT)
	out.append(_rec("load_rejects_bad_version",
		lr[0] == null and "incompatible" in str(lr[1]), "err=" + str(lr[1])))

	d = _mini().to_dict()
	d.erase("territories")
	_raw_write(JSON.stringify(d))
	lr = SaveSystem.load(SLOT)
	out.append(_rec("load_rejects_missing_territories",
		lr[0] == null and lr[1] != "", "err=" + str(lr[1])))

	# --- save null state ----------------------------------------------------------
	sr = SaveSystem.save(null, SLOT)
	out.append(_rec("save_rejects_null_state", not bool(sr["ok"]),
		"err=" + str(sr["error"])))

	SaveSystem.delete(SLOT)
	out.append(_rec("cleanup", not SaveSystem.has_save(SLOT), ""))
	return out
