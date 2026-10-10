extends RefCounted
## Full-match integration tests: create -> play -> save/load -> victory/defeat.
## static func run() -> Array of {name, passed, note}.


static func _t(name: String, passed: bool, note: String = "") -> Dictionary:
	return {"name": name, "passed": passed, "note": note}


static func _settings(seed: int) -> Dictionary:
	return {
		"map_size": Tacterra.MapSize.SMALL, "ai_count": 2,
		"difficulty": Tacterra.Difficulty.NORMAL, "preset": "standard",
		"speed": 1.0, "seed": seed,
	}


static func run() -> Array:
	var out: Array = []
	out.append(_new_match_sane())
	out.append(_player_expands_to_neutral())
	out.append(_connected_expansion())
	out.append(_recruit_arrives())
	out.append(_economy_moves())
	out.append(_ai_acts_over_time())
	out.append(_long_run_invariants())
	out.append(_save_load_midmatch())
	out.append(_victory_detection())
	out.append(_defeat_detection())
	out.append(_deterministic_seed())
	return out


static func _new_match_sane() -> Dictionary:
	var s: GameState = GameState.create(_settings(11))
	if s.territories.size() < 18:
		return _t("integration.new_match", false, "too few territories")
	if s.nations.size() != 3:
		return _t("integration.new_match", false, "expected 3 nations")
	var p := s.player()
	if s.owned_ids(0).size() < 1:
		return _t("integration.new_match", false, "player owns nothing")
	for n in s.nations:
		if s.get_territory(n.capital_id) == null:
			return _t("integration.new_match", false, "nation %d has no capital" % n.id)
		if s.get_territory(n.capital_id).owner_id != n.id:
			return _t("integration.new_match", false, "capital not owned")
		if s.get_territory(n.capital_id).army == null:
			return _t("integration.new_match", false, "no starting army")
	if p.credits <= 0.0 or p.supplies <= 0.0:
		return _t("integration.new_match", false, "no starting resources")
	return _t("integration.new_match", true)


static func _player_expands_to_neutral() -> Dictionary:
	var s: GameState = GameState.create(_settings(21))
	var p := s.player()
	# Find a player territory adjacent to a neutral one.
	var from_id := -1
	var neut_id := -1
	for tid in s.owned_ids(0):
		var t := s.get_territory(tid)
		for nb in t.neighbors:
			var nt := s.get_territory(nb)
			if nt.owner_id == -1:
				from_id = tid
				neut_id = nb
				break
		if from_id >= 0:
			break
	if from_id < 0:
		return _t("integration.player_expands", false, "no adjacent neutral found")
	# Beef up the army so capture is guaranteed, then order the move.
	var ft := s.get_territory(from_id)
	ft.army = ArmyData.create(0, 500, from_id, 0.5)
	var r: Dictionary = s.order_move(0, from_id, neut_id, 400)
	if not bool(r.get("ok", false)):
		return _t("integration.player_expands", false, "order failed: " + str(r.get("error")))
	for _i in 40:
		s.tick(1.0)
		if s.over:
			break
		if s.get_territory(neut_id).owner_id == 0:
			break
	if s.get_territory(neut_id).owner_id != 0:
		return _t("integration.player_expands", false, "neutral not captured after 40d")
	return _t("integration.player_expands", true)


## Empires spread outward from a single capital: the player starts with one
## territory, can only take neighbors, and all holdings stay connected.
static func _connected_expansion() -> Dictionary:
	var s: GameState = GameState.create(_settings(61))
	var p := s.player()
	if s.owned_ids(0).size() != 1:
		return _t("integration.connected_expansion", false,
			"player must start with exactly 1 territory")
	var cap := s.get_territory(p.capital_id)
	# A far, non-adjacent neutral must be rejected as a move target.
	var far := -1
	for t in s.territories:
		if t.owner_id == -1 and not cap.neighbors.has(t.id):
			far = t.id
			break
	if far < 0:
		return _t("integration.connected_expansion", false, "no far neutral found")
	cap.army = ArmyData.create(0, 900, cap.id, 0.5)
	var bad: Dictionary = s.order_move(0, cap.id, far, 500)
	if bool(bad.get("ok", false)):
		return _t("integration.connected_expansion", false,
			"disconnected attack was allowed")
	# Capture two neighbors in sequence; each must join the connected empire.
	for step in range(2):
		var from_id := -1
		var neut_id := -1
		for tid in s.owned_ids(0):
			var t := s.get_territory(tid)
			for nb in t.neighbors:
				if s.get_territory(nb).owner_id == -1:
					from_id = tid
					neut_id = nb
					break
			if from_id >= 0:
				break
		if from_id < 0:
			break # fully surrounded; still connected, still valid
		var ft := s.get_territory(from_id)
		if ft.army == null:
			ft.army = ArmyData.create(0, 900, from_id, 0.5)
		else:
			ft.army.troops = 900
		var r: Dictionary = s.order_move(0, from_id, neut_id, 700)
		if not bool(r.get("ok", false)):
			return _t("integration.connected_expansion", false,
				"neighbor order failed: " + str(r.get("error")))
		for _i in 60:
			s.tick(1.0)
			if s.over:
				break
			if s.get_territory(neut_id).owner_id == 0:
				break
		if s.get_territory(neut_id).owner_id != 0:
			return _t("integration.connected_expansion", false,
				"neighbor not captured")
	# All player territories must be reachable from the capital via owned land.
	var seen := {cap.id: true}
	var queue: Array[int] = [cap.id]
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		for nb in s.get_territory(cur).neighbors:
			if s.get_territory(nb).owner_id == 0 and not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	if seen.size() != s.owned_ids(0).size():
		return _t("integration.connected_expansion", false,
			"holdings not connected: %d of %d reachable" % [seen.size(), s.owned_ids(0).size()])
	return _t("integration.connected_expansion", true)


static func _recruit_arrives() -> Dictionary:
	var s: GameState = GameState.create(_settings(31))
	var cap := s.player().capital_id
	var before: int = s.get_territory(cap).army.troops
	var r: Dictionary = s.order_recruit(0, cap, 50)
	if not bool(r.get("ok", false)):
		return _t("integration.recruit_arrives", false, "order failed")
	for _i in 6:
		s.tick(1.0)
	var after: int = s.get_territory(cap).army.troops
	if after < before + 50:
		return _t("integration.recruit_arrives", false, "troops did not arrive (%d -> %d)" % [before, after])
	return _t("integration.recruit_arrives", true)


static func _economy_moves() -> Dictionary:
	var s: GameState = GameState.create(_settings(41))
	var c0: float = s.player().credits
	for _i in 10:
		s.tick(1.0)
	var c1: float = s.player().credits
	if c1 <= c0:
		return _t("integration.economy", false, "credits did not grow (%f -> %f)" % [c0, c1])
	return _t("integration.economy", true)


static func _ai_acts_over_time() -> Dictionary:
	var s: GameState = GameState.create(_settings(51))
	var ai_start := 0
	for n in s.nations:
		if not n.is_player:
			ai_start += s.owned_ids(n.id).size()
	for _i in 60:
		s.tick(1.0)
		if s.over:
			break
	var battles: int = s.battle_reports.size()
	var notifs: int = s.notifications.size()
	if battles == 0 and notifs == 0:
		return _t("integration.ai_acts", false, "no battles and no notifications in 60d")
	return _t("integration.ai_acts", true, "%d battles, %d notifications" % [battles, notifs])


static func _long_run_invariants() -> Dictionary:
	var s: GameState = GameState.create(_settings(61))
	for _i in 200:
		s.tick(1.0)
		if s.over:
			break
	for n in s.nations:
		if n.credits < 0.0 or n.supplies < 0.0 or n.manpower < 0.0:
			return _t("integration.invariants", false, "negative resource for nation %d" % n.id)
		for tid in s.owned_ids(n.id):
			var a := s.get_territory(tid).army
			if a != null and a.troops < 0:
				return _t("integration.invariants", false, "negative troops")
	for tr in s.transits:
		if tr.troops < 0:
			return _t("integration.invariants", false, "negative transit troops")
	return _t("integration.invariants", true, "day=%d over=%s" % [int(s.day), str(s.over)])


static func _save_load_midmatch() -> Dictionary:
	var s: GameState = GameState.create(_settings(71))
	for _i in 25:
		s.tick(1.0)
	var terr0 := s.owned_ids(0).size()
	var day0 := s.day
	var r: Dictionary = SaveSystem.save(s, 2)
	if not bool(r.get("ok", false)):
		return _t("integration.save_load", false, "save failed: " + str(r.get("error")))
	var loaded: Array = SaveSystem.load(2)
	if loaded[0] == null:
		return _t("integration.save_load", false, "load failed: " + str(loaded[1]))
	var s2: GameState = loaded[0]
	if s2.owned_ids(0).size() != terr0:
		return _t("integration.save_load", false, "territory count mismatch")
	if absf(s2.day - day0) > 0.001:
		return _t("integration.save_load", false, "day mismatch")
	# Loaded state must keep simulating.
	for _i in 10:
		s2.tick(1.0)
	SaveSystem.delete(2)
	return _t("integration.save_load", true)


static func _victory_detection() -> Dictionary:
	var s: GameState = GameState.create(_settings(81))
	for t in s.territories:
		if t.owner_id != 0:
			t.owner_id = 0
			t.garrison = 0
			t.army = null
	s.tick(1.0)
	if not s.over or not s.player_won:
		return _t("integration.victory", false, "victory not detected")
	return _t("integration.victory", true)


static func _defeat_detection() -> Dictionary:
	var s: GameState = GameState.create(_settings(91))
	for t in s.territories:
		if t.owner_id == 0:
			t.owner_id = 1
			t.army = null
	s.tick(1.0)
	if not s.over or s.player_won:
		return _t("integration.defeat", false, "defeat not detected")
	return _t("integration.defeat", true)


static func _deterministic_seed() -> Dictionary:
	var a: GameState = GameState.create(_settings(101))
	var b: GameState = GameState.create(_settings(101))
	if a.territories.size() != b.territories.size():
		return _t("integration.determinism", false, "territory count differs")
	for i in a.territories.size():
		if a.territories[i].name != b.territories[i].name:
			return _t("integration.determinism", false, "names differ")
		if a.territories[i].owner_id != b.territories[i].owner_id:
			return _t("integration.determinism", false, "owners differ")
	return _t("integration.determinism", true)
