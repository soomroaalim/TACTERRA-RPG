extends RefCounted
## Tests for MovementSim (transit advance, merge, capture, battle, retreat).
## Run via tests/run_tests.gd (static run() -> Array).


static func _t(pname: String, passed: bool, note: String = "") -> Dictionary:
	return {"name": pname, "passed": passed, "note": note}


static func _base() -> StateMock:
	var s := StateMock.make_state()
	# t0: player capital -- t1: player -- t2: neutral empty -- t3: neutral
	# garrison 40 -- t4: AI army 50 -- t5: AI capital (fertile, army 20).
	var t0 := StateMock.make_territory(0, 0, Tacterra.Terrain.PLAINS, [1], 500)
	t0.is_capital = true
	t0.supplied = true
	var t1 := StateMock.make_territory(1, 0, Tacterra.Terrain.PLAINS, [0, 2], 500)
	t1.supplied = true
	var t2 := StateMock.make_territory(2, -1, Tacterra.Terrain.PLAINS, [1, 3], 100)
	var t3 := StateMock.make_territory(3, -1, Tacterra.Terrain.PLAINS, [2, 4], 100, 40)
	var t4 := StateMock.make_territory(4, 1, Tacterra.Terrain.PLAINS, [3, 5], 500)
	var t5 := StateMock.make_territory(5, 1, Tacterra.Terrain.FERTILE, [4], 800)
	t5.is_capital = true
	s.territories = [t0, t1, t2, t3, t4, t5]
	var p := StateMock.make_nation(0, "Player", true, 0)
	p.credits = 100000.0  # economy ticks in the smoke test must not go broke
	var ai := StateMock.make_nation(1, "Rival", false, 5)
	ai.credits = 100000.0
	s.nations = [p, ai]
	StateMock.station(s, 4, 1, 50)
	StateMock.station(s, 5, 1, 20)
	return s


static func run() -> Array:
	var out: Array = []

	# 1. Transit advances but does not arrive early.
	var s := _base()
	var a := StateMock.launch(s, 0, 0, 1, 50, 2.0)
	MovementSim.tick(s, 1.0)
	out.append(_t("movement.advance",
		is_equal_approx(a.move_progress, 1.0) and s.transits.has(a) \
			and s.get_territory(1).army == null,
		"progress=%.1f in_transit=%s" % [a.move_progress, str(s.transits.has(a))]))

	# 2. Arrival at own territory merges (troops add, training weighted).
	s = _base()
	StateMock.station(s, 1, 0, 100, 0.5)
	var m := StateMock.launch(s, 0, 0, 1, 50, 1.0)
	m.training = 0.0
	MovementSim.tick(s, 1.0)
	var t1: TerritoryData = s.get_territory(1)
	out.append(_t("movement.merge",
		s.transits.is_empty() and t1.army.troops == 150 \
			and is_equal_approx(t1.army.training, 100.0 * 0.5 / 150.0),
		"troops=%d training=%.4f" % [t1.army.troops, t1.army.training]))

	# 3. Peaceful capture of an empty neutral territory.
	s = _base()
	StateMock.launch(s, 0, 1, 2, 80, 1.0)
	MovementSim.tick(s, 1.0)
	var t2 = s.get_territory(2)
	var p = s.get_nation(0)
	out.append(_t("movement.peaceful_capture",
		t2.owner_id == 0 and t2.army != null and t2.army.troops == 80 \
			and int(p.stats["captured"]) == 1 \
			and StateMock.has_notification(s, Tacterra.NotifyKind.GOOD, "Captured Terr2"),
		"owner=%d troops=%d captured=%d" % [t2.owner_id,
			t2.army.troops if t2.army != null else -1, int(p.stats["captured"])]))

	# 4. Neutral garrison battle: deterministic, garrison reduced or captured.
	s = _base()
	s.rng.seed = 7
	StateMock.launch(s, 0, 1, 3, 200, 1.0)  # 200 vs garrison 40 -> capture
	MovementSim.tick(s, 1.0)
	var t3: TerritoryData = s.get_territory(3)
	var rep_ok := s.battle_reports.size() == 1 \
		and bool(s.battle_reports[0].get("captured", false))
	out.append(_t("movement.garrison_battle",
		rep_ok and t3.owner_id == 0 and t3.garrison == 0 and t3.army.troops > 0,
		"owner=%d survivors=%d reports=%d" % [t3.owner_id,
			t3.army.troops if t3.army != null else -1, s.battle_reports.size()]))

	# 5. Determinism of the battle path: same seed -> same survivors.
	var s2 := _base()
	s2.rng.seed = 7
	StateMock.launch(s2, 0, 1, 3, 200, 1.0)
	MovementSim.tick(s2, 1.0)
	out.append(_t("movement.battle_deterministic",
		s2.get_territory(3).army.troops == t3.army.troops,
		"%d vs %d" % [t3.army.troops, s2.get_territory(3).army.troops]))

	# 6. Failed attack: survivors retreat to origin, defender weakened.
	s = _base()
	s.rng.seed = 7
	StateMock.launch(s, 0, 1, 4, 30, 1.0)  # 30 vs 50 + 25% defender bonus
	MovementSim.tick(s, 1.0)
	var t4: TerritoryData = s.get_territory(4)
	t1 = s.get_territory(1)
	var atk_surv := t1.army.troops if t1.army != null else -1
	var def_surv := t4.army.troops if t4.army != null else -1
	out.append(_t("movement.failed_attack_retreat",
		t4.owner_id == 1 and atk_surv > 0 and atk_surv < 30 \
			and def_surv > 0 and def_surv < 50 \
			and int(s.get_nation(0).stats["battles_lost"]) == 1 \
			and s.battle_reports.size() == 1 \
			and not bool(s.battle_reports[0].get("captured", true)),
		"origin_troops=%d def_troops=%d" % [atk_surv, def_surv]))

	# 7. Capturing a capital relocates it to the owner's best territory.
	s = _base()
	s.rng.seed = 7
	StateMock.launch(s, 0, 1, 5, 200, 1.0)  # not adjacent, but orders aren't checked here
	# fix adjacency for honesty: t1 neighbors include 5 for this test
	s.get_territory(1).neighbors.append(5)
	MovementSim.tick(s, 1.0)
	var ai = s.get_nation(1)
	var t5 = s.get_territory(5)
	out.append(_t("movement.capital_relocate",
		t5.owner_id == 0 and not t5.is_capital \
			and ai.capital_id == 4 and s.get_territory(4).is_capital \
			and not ai.eliminated,
		"ai_capital=%d t4_capital=%s" % [ai.capital_id, str(s.get_territory(4).is_capital)]))

	# 8. Transits of an eliminated owner are removed, not processed.
	s = _base()
	var dead := StateMock.launch(s, 1, 4, 3, 40, 1.0)
	s.get_nation(1).eliminated = true
	MovementSim.tick(s, 1.0)
	out.append(_t("movement.dead_owner_removed",
		not s.transits.has(dead) and s.get_territory(3).garrison == 40,
		"transits=%d" % s.transits.size()))

	# 9. Integration smoke: a few full pipeline days on a small map.
	s = _base()
	s.rng.seed = 99
	StateMock.station(s, 1, 0, 250)
	StateMock.launch(s, 0, 1, 3, 200, 2.0)  # arrives day 2, 200 vs garrison 40
	for d in range(5):
		s.day += 1.0
		MovementSim.tick(s, 1.0)
		EconomySim.tick(s, 1.0)
		SupplySim.recompute(s)
		SupplySim.apply_attrition(s, 1.0)
		VictorySim.check(s)
	t3 = s.get_territory(3)
	var smoke_ok := t3.owner_id == 0 and not s.over
	out.append(_t("movement.pipeline_smoke",
		smoke_ok,
		"t3_owner=%d over=%s reports=%d notifs=%d" % [t3.owner_id, str(s.over),
			s.battle_reports.size(), s.notifications.size()]))

	return out
