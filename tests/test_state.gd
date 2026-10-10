extends RefCounted
## Unit tests for GameState orders + serialization.
## Uses tiny hand-built synthetic states — no dependency on MapGenerator.
## static func run() -> Array of {name, passed, note}.


static func _mk_terr(tid: int, tname: String, owner: int, terrain: int,
		cx: float, cy: float, neighbors: Array) -> TerritoryData:
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
	t.terrain = terrain
	t.owner_id = owner
	t.population = 1000
	return t


static func _mk_nation(nid: int, nname: String, is_player: bool) -> NationData:
	var n := NationData.new()
	n.id = nid
	n.name = nname
	n.color = Tacterra.NATION_COLORS[nid % Tacterra.NATION_COLORS.size()]
	n.is_player = is_player
	n.personality = Tacterra.Personality.EXPANSIONIST
	n.difficulty = -1 if is_player else Tacterra.Difficulty.NORMAL
	n.credits = 500.0
	n.supplies = 200.0
	n.manpower = 50.0
	n.capital_id = 0 if is_player else 2
	return n


## 3-territory chain: 0 (player, 100 troops) - 1 (neutral, 40 garrison)
## - 2 (AI nation, 60 troops).
static func _mini() -> GameState:
	var s := GameState.new()
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = 424242
	s.settings = {
		"map_size": Tacterra.MapSize.SMALL, "ai_count": 1,
		"difficulty": Tacterra.Difficulty.NORMAL,
		"preset": "standard", "speed": 1.0,
	}
	s.speed = 1.0
	s.day = 0.0
	s.over = false
	s.winner_id = -1
	s.player_won = false
	s.nations.append(_mk_nation(0, "Free Cities", true))
	s.nations.append(_mk_nation(1, "Rival", false))
	var t0 := _mk_terr(0, "Alpha", 0, Tacterra.Terrain.PLAINS, 100, 100, [1])
	t0.is_capital = true
	t0.has_city = true
	t0.army = ArmyData.create(0, 100, 0, 0.2)
	var t1 := _mk_terr(1, "Beta", -1, Tacterra.Terrain.FOREST, 300, 100, [0, 2])
	t1.garrison = 40
	t1.population = 500
	var t2 := _mk_terr(2, "Gamma", 1, Tacterra.Terrain.HILLS, 500, 100, [1])
	t2.army = ArmyData.create(1, 60, 2, 0.0)
	s.territories.append(t0)
	s.territories.append(t1)
	s.territories.append(t2)
	return s


static func _rec(tname: String, passed: bool, note: String) -> Dictionary:
	return {"name": tname, "passed": passed, "note": note}


static func run() -> Array:
	var out: Array = []

	# --- order_move -------------------------------------------------------
	var s := _mini()
	var r := s.order_move(0, 0, 1, 40)
	var tr: ArmyData = s.transits[0] if not s.transits.is_empty() else null
	# dist 200, costs PLAINS 1.0 / FOREST 1.2 -> avg 1.1 -> 200/600*1.1
	var expect_total := 200.0 / Tacterra.MOVE_SPEED * 1.1
	var ok_move := bool(r["ok"]) and s.get_territory(0).army.troops == 60 \
		and tr != null and tr.moving and tr.territory_id == -1 \
		and tr.move_from == 0 and tr.move_to == 1 and tr.troops == 40 \
		and absf(tr.move_total - expect_total) < 0.001 \
		and absf(tr.training - 0.2) < 0.0001
	out.append(_rec("move_valid", ok_move,
		"remaining=%d total=%.4f expect=%.4f" % [
			s.get_territory(0).army.troops if s.get_territory(0).army else -1,
			tr.move_total if tr else -1.0, expect_total]))

	s = _mini()
	r = s.order_move(0, 0, 2, 10)
	out.append(_rec("move_rejects_non_neighbor", not bool(r["ok"]) and s.transits.is_empty(),
		"err=" + str(r["error"])))

	s = _mini()
	r = s.order_move(0, 0, 1, 999)
	out.append(_rec("move_rejects_too_many_troops", not bool(r["ok"]) and s.transits.is_empty(),
		"err=" + str(r["error"])))

	s = _mini()
	r = s.order_move(0, 2, 1, 10)
	out.append(_rec("move_rejects_enemy_territory", not bool(r["ok"]) and s.transits.is_empty(),
		"err=" + str(r["error"])))

	s = _mini()
	r = s.order_move(0, 0, 1, 0)
	out.append(_rec("move_rejects_zero_troops", not bool(r["ok"]),
		"err=" + str(r["error"])))

	s = _mini()
	r = s.order_move(0, 0, 1, 100)
	out.append(_rec("move_all_troops_clears_stationed",
		bool(r["ok"]) and s.get_territory(0).army == null and s.transits.size() == 1,
		"err=" + str(r["error"])))

	s = _mini()
	r = s.order_move(99, 0, 1, 10)
	out.append(_rec("move_rejects_unknown_nation", not bool(r["ok"]),
		"err=" + str(r["error"])))

	s = _mini()
	s.over = true
	r = s.order_move(0, 0, 1, 10)
	out.append(_rec("move_rejected_when_over", not bool(r["ok"]),
		"err=" + str(r["error"])))

	s = _mini()
	var before := s.notifications.size()
	s.order_move(0, 0, 1, 10)
	out.append(_rec("move_player_emits_notification",
		s.notifications.size() == before + 1, "n=%d" % s.notifications.size()))

	# --- order_recruit ----------------------------------------------------
	s = _mini()
	r = s.order_recruit(0, 0, 10)
	var q: Array = s.training_queues.get(0, [])
	var ok_rec := bool(r["ok"]) and s.player().credits == 400.0 \
		and s.player().manpower == 40.0 and q.size() == 1 \
		and int(q[0]["troops"]) == 10 and int(q[0]["owner_id"]) == 0 \
		and absf(float(q[0]["days_left"]) - Tacterra.RECRUIT_TRAIN_DAYS) < 0.001
	out.append(_rec("recruit_valid", ok_rec,
		"credits=%.0f manpower=%.0f q=%d" % [s.player().credits, s.player().manpower, q.size()]))

	s = _mini()
	s.player().credits = 5.0
	r = s.order_recruit(0, 0, 10)
	out.append(_rec("recruit_rejects_insufficient_credits",
		not bool(r["ok"]) and s.player().credits == 5.0
		and not s.training_queues.has(0), "err=" + str(r["error"])))

	s = _mini()
	s.player().manpower = 2.0
	r = s.order_recruit(0, 0, 10)
	out.append(_rec("recruit_rejects_insufficient_manpower",
		not bool(r["ok"]) and s.player().manpower == 2.0, "err=" + str(r["error"])))

	s = _mini()
	r = s.order_recruit(0, 2, 5)
	out.append(_rec("recruit_rejects_enemy_territory", not bool(r["ok"]),
		"err=" + str(r["error"])))

	s = _mini()
	r = s.order_recruit(0, 0, -3)
	out.append(_rec("recruit_rejects_negative", not bool(r["ok"]),
		"err=" + str(r["error"])))

	# --- develop / fortify -------------------------------------------------
	s = _mini()
	r = s.order_develop(0, 0)
	out.append(_rec("develop_valid",
		bool(r["ok"]) and s.get_territory(0).development == 1
		and s.player().credits == 400.0, "err=" + str(r["error"])))

	s = _mini()
	s.get_territory(0).development = Tacterra.DEVELOP_MAX
	r = s.order_develop(0, 0)
	out.append(_rec("develop_rejects_maxed",
		not bool(r["ok"]) and "max" in str(r["error"]).to_lower(), "err=" + str(r["error"])))

	s = _mini()
	s.player().credits = 10.0
	r = s.order_develop(0, 0)
	out.append(_rec("develop_rejects_insufficient_credits", not bool(r["ok"]),
		"err=" + str(r["error"])))

	s = _mini()
	r = s.order_fortify(0, 0)
	out.append(_rec("fortify_valid",
		bool(r["ok"]) and s.get_territory(0).fort_level == 1
		and s.player().credits == 420.0, "err=" + str(r["error"])))

	s = _mini()
	s.get_territory(0).fort_level = Tacterra.FORT_MAX
	r = s.order_fortify(0, 0)
	out.append(_rec("fortify_rejects_maxed",
		not bool(r["ok"]) and "max" in str(r["error"]).to_lower(), "err=" + str(r["error"])))

	s = _mini()
	r = s.order_fortify(1, 0)
	out.append(_rec("fortify_rejects_wrong_owner", not bool(r["ok"]),
		"err=" + str(r["error"])))

	# --- helpers ------------------------------------------------------------
	s = _mini()
	var owned := s.owned_ids(0)
	out.append(_rec("helpers_owned_ids", owned.size() == 1 and owned[0] == 0,
		"owned=" + str(owned)))
	out.append(_rec("helpers_get_bad_ids",
		s.get_territory(99) == null and s.get_territory(-1) == null
		and s.get_nation(99) == null and s.army_at(99) == null
		and s.army_at(1) == null and s.army_at(0) != null,
		"nulls ok, army_at(0) set"))
	out.append(_rec("helpers_player", s.player() != null and s.player().id == 0,
		"name=" + (s.player().name if s.player() else "?")))

	# --- serialization round-trip -------------------------------------------
	s = _mini()
	s.day = 12.5
	s.order_move(0, 0, 1, 40)
	s.order_recruit(0, 0, 10)
	s.add_notification("hello", Tacterra.NotifyKind.INFO)
	s.add_battle_report({"text": "test battle", "day": 12.5})
	var text := JSON.stringify(s.to_dict())
	var parsed = JSON.parse_string(text)
	var lr := GameState.load_dict(parsed)
	var ok_rt := bool(lr[1] == "") and lr[0] != null
	var note_rt := "load_err=" + str(lr[1])
	if ok_rt:
		var s2: GameState = lr[0]
		var q2: Array = s2.training_queues.get(0, [])
		ok_rt = ok_rt and absf(s2.day - 12.5) < 0.001 \
			and s2.get_nation(0).credits == 400.0 \
			and s2.get_nation(0).manpower == 40.0 \
			and s2.get_territory(0).army.troops == 60 \
			and s2.get_territory(1).owner_id == -1 \
			and s2.transits.size() == 1 and s2.transits[0].move_to == 1 \
			and s2.transits[0].troops == 40 \
			and q2.size() == 1 and int(q2[0]["troops"]) == 10 \
			and s2.notifications.size() >= 3 \
			and s2.battle_reports.size() == 1 \
			and int(s2.settings["ai_count"]) == 1 \
			and s2.rng.seed == 424242 \
			and s2.get_territory(0).neighbors.size() == 1 \
			and s2.get_territory(0).neighbors[0] == 1
		note_rt = "day=%.1f terrs=%d nats=%d transits=%d" % [
			s2.day, s2.territories.size(), s2.nations.size(), s2.transits.size()]
	out.append(_rec("save_dict_round_trip", ok_rt, note_rt))

	var back := GameState.from_dict(parsed)
	out.append(_rec("from_dict_alias_ok", back != null and absf(back.day - 12.5) < 0.001,
		"null=" + str(back == null)))

	# --- load_dict validation ------------------------------------------------
	var bad := (JSON.parse_string(text) as Dictionary).duplicate(true)
	bad["version"] = 999
	var lr2 := GameState.load_dict(bad)
	out.append(_rec("load_rejects_bad_version", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	bad = (JSON.parse_string(text) as Dictionary).duplicate(true)
	bad.erase("nations")
	lr2 = GameState.load_dict(bad)
	out.append(_rec("load_rejects_missing_key", lr2[0] == null and "missing key" in str(lr2[1]),
		"err=" + str(lr2[1])))

	lr2 = GameState.load_dict({})
	out.append(_rec("load_rejects_empty_dict", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	lr2 = GameState.load_dict([1, 2, 3])
	out.append(_rec("load_rejects_array_no_crash", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	lr2 = GameState.load_dict("garbage string")
	out.append(_rec("load_rejects_string_no_crash", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	bad = (JSON.parse_string(text) as Dictionary).duplicate(true)
	bad["territories"] = []
	lr2 = GameState.load_dict(bad)
	out.append(_rec("load_rejects_empty_territories", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	bad = (JSON.parse_string(text) as Dictionary).duplicate(true)
	(bad["territories"] as Array)[0]["polygon"] = [1, 2, 3]
	lr2 = GameState.load_dict(bad)
	out.append(_rec("load_rejects_bad_polygon_no_crash", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	bad = (JSON.parse_string(text) as Dictionary).duplicate(true)
	(bad["nations"] as Array)[0]["color"] = "red"
	lr2 = GameState.load_dict(bad)
	out.append(_rec("load_rejects_bad_color_no_crash", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	bad = (JSON.parse_string(text) as Dictionary).duplicate(true)
	bad["day"] = "twelve"
	lr2 = GameState.load_dict(bad)
	out.append(_rec("load_rejects_bad_day_type", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	bad = (JSON.parse_string(text) as Dictionary).duplicate(true)
	bad["settings"] = "standard"
	lr2 = GameState.load_dict(bad)
	out.append(_rec("load_rejects_bad_settings_type", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	bad = (JSON.parse_string(text) as Dictionary).duplicate(true)
	((bad["training_queues"] as Array)[0]["queue"] as Array)[0]["troops"] = "lots"
	lr2 = GameState.load_dict(bad)
	out.append(_rec("load_rejects_bad_queue_entry_no_crash", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	bad = (JSON.parse_string(text) as Dictionary).duplicate(true)
	(bad["territories"] as Array)[0]["army"]["troops"] = null
	lr2 = GameState.load_dict(bad)
	out.append(_rec("load_rejects_null_army_troops", lr2[0] == null and lr2[1] != "",
		"err=" + str(lr2[1])))

	# --- feed trimming --------------------------------------------------------
	s = _mini()
	for i in range(70):
		s.add_notification("n%d" % i, Tacterra.NotifyKind.INFO)
	for i in range(25):
		s.add_battle_report({"text": "b%d" % i})
	out.append(_rec("feeds_trimmed", s.notifications.size() == 60
		and s.battle_reports.size() == 20
		and str(s.notifications[0]["text"]) == "n10"
		and str(s.notifications[59]["text"]) == "n69",
		"n=%d b=%d" % [s.notifications.size(), s.battle_reports.size()]))

	return out
