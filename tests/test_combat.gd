extends RefCounted
## Tests for CombatSim. Run via tests/run_tests.gd (static run() -> Array).


static func _t(pname: String, passed: bool, note: String = "") -> Dictionary:
	return {"name": pname, "passed": passed, "note": note}


## Builds a duel: attacker (stationed at friendly t0) vs defender at t1.
static func _duel(seed: int, atk_troops: int, def_troops: int,
		terrain: int = Tacterra.Terrain.PLAINS, def_is_army: bool = true) -> Array:
	var s := StateMock.make_state()
	s.rng.seed = seed
	var t0 := StateMock.make_territory(0, 0, Tacterra.Terrain.PLAINS, [1], 500)
	t0.is_capital = true
	t0.supplied = true
	var t1 := StateMock.make_territory(1, 1, terrain, [0], 500)
	t1.supplied = true
	if def_is_army:
		var d := ArmyData.create(1, def_troops, 1, 0.0)
		t1.army = d
	else:
		t1.owner_id = -1
		t1.garrison = def_troops
	s.territories = [t0, t1]
	var pa := StateMock.make_nation(0, "Attacker", true, 0)
	var pb := StateMock.make_nation(1, "Defender", false, 1)
	s.nations = [pa, pb]
	var atk := ArmyData.create(0, atk_troops, 0, 0.0)
	return [s, atk, t1]


static func run() -> Array:
	var out: Array = []

	# 1. Unopposed territory: no losses, captured.
	var d := _duel(1, 100, 0)
	var s: StateMock = d[0]
	var t1: TerritoryData = d[2]
	t1.army = null
	t1.garrison = 0
	var r: Dictionary = CombatSim.resolve(s, d[1], t1)
	out.append(_t("combat.unopposed",
		int(r["atk_losses"]) == 0 and int(r["def_losses"]) == 0 and bool(r["captured"]),
		str(r["report_text"])))

	# 2. Determinism: identical seeds -> identical results.
	var a1 := _duel(42, 200, 100, Tacterra.Terrain.HILLS)
	var r1: Dictionary = CombatSim.resolve(a1[0], a1[1], a1[2])
	var a2 := _duel(42, 200, 100, Tacterra.Terrain.HILLS)
	var r2: Dictionary = CombatSim.resolve(a2[0], a2[1], a2[2])
	var det_ok := int(r1["atk_losses"]) == int(r2["atk_losses"]) \
		and int(r1["def_losses"]) == int(r2["def_losses"]) \
		and bool(r1["captured"]) == bool(r2["captured"]) \
		and str(r1["report_text"]) == str(r2["report_text"]) \
		and is_equal_approx(float(r1["atk_power"]), float(r2["atk_power"]))
	out.append(_t("combat.deterministic", det_ok,
		"atk_losses=%d/%d" % [int(r1["atk_losses"]), int(r2["atk_losses"])]))

	# 3. Overwhelming attacker (~4x power) always captures, at a cost.
	d = _duel(7, 200, 50)
	r = CombatSim.resolve(d[0], d[1], d[2])
	out.append(_t("combat.overwhelming_wins",
		bool(r["captured"]) and int(r["atk_losses"]) > 0 \
			and int(r["atk_losses"]) < 200 and int(r["def_losses"]) == 50,
		"captured=%s atk_losses=%d def_losses=%d" % [str(bool(r["captured"])),
			int(r["atk_losses"]), int(r["def_losses"])]))

	# 4. Terrain favors the defender: equal troops in mountains -> attacker
	#    bleeds more and fails to capture.
	d = _duel(7, 100, 100, Tacterra.Terrain.MOUNTAINS)
	r = CombatSim.resolve(d[0], d[1], d[2])
	out.append(_t("combat.mountains_favor_defender",
		not bool(r["captured"]) and int(r["atk_losses"]) > int(r["def_losses"]),
		"captured=%s atk=%d def=%d" % [str(bool(r["captured"])),
			int(r["atk_losses"]), int(r["def_losses"])]))

	# 5. Even battle on plains: both bleed ~55%, nobody captures.
	d = _duel(7, 100, 100)
	r = CombatSim.resolve(d[0], d[1], d[2])
	var atk_l := int(r["atk_losses"])
	var def_l := int(r["def_losses"])
	out.append(_t("combat.even_draw",
		not bool(r["captured"]) and atk_l >= 35 and atk_l <= 70 \
			and def_l >= 35 and def_l <= 65,
		"atk=%d def=%d" % [atk_l, def_l]))

	# 5b. Decisive 2:1 POWER ratio captures the territory (loss factor 0.55).
	# Note: 280v100 troops ≈ 2.24x power after the 1.25x defender bonus.
	d = _duel(7, 280, 100)
	r = CombatSim.resolve(d[0], d[1], d[2])
	out.append(_t("combat.two_to_one_captures",
		bool(r["captured"]) and int(r["def_losses"]) == 100,
		"captured=%s atk_losses=%d power_ratio=%.2f" % [str(bool(r["captured"])),
			int(r["atk_losses"]), float(r["atk_power"]) / maxf(1.0, float(r["def_power"]))]))

	# 6. Unsupplied attacker fights at 60% power.
	var ds := _duel(7, 100, 100)
	var rs: Dictionary = CombatSim.resolve(ds[0], ds[1], ds[2])
	var du := _duel(7, 100, 100)
	(du[0] as StateMock).get_territory(0).supplied = false
	var ru: Dictionary = CombatSim.resolve(du[0], du[1], du[2])
	out.append(_t("combat.unsupplied_attacker",
		is_equal_approx(float(ru["atk_power"]), float(rs["atk_power"]) * 0.6),
		"supplied=%.1f unsupplied=%.1f" % [float(rs["atk_power"]), float(ru["atk_power"])]))

	# 7. Nation stats are updated by resolve().
	d = _duel(7, 200, 50)
	s = d[0]
	r = CombatSim.resolve(s, d[1], d[2])
	var pa = s.get_nation(0)
	var pb = s.get_nation(1)
	out.append(_t("combat.stats",
		int(pa.stats["troops_lost"]) == int(r["atk_losses"]) \
			and int(pa.stats["troops_killed"]) == int(r["def_losses"]) \
			and int(pb.stats["troops_lost"]) == int(r["def_losses"]) \
			and int(pb.stats["troops_killed"]) == int(r["atk_losses"]),
		"a_lost=%d b_lost=%d" % [int(pa.stats["troops_lost"]), int(pb.stats["troops_lost"])]))

	# 8. Neutral garrison battle works and names the garrison.
	d = _duel(7, 200, 40, Tacterra.Terrain.PLAINS, false)
	r = CombatSim.resolve(d[0], d[1], d[2])
	out.append(_t("combat.garrison",
		bool(r["captured"]) and str(r["report_text"]).contains("Neutral garrison"),
		"captured=%s" % str(bool(r["captured"]))))

	# 9. Report names the territory and the deciding factors.
	d = _duel(7, 100, 100, Tacterra.Terrain.MOUNTAINS)
	r = CombatSim.resolve(d[0], d[1], d[2])
	var txt := str(r["report_text"])
	out.append(_t("combat.report_text",
		txt.contains("Terr1") and txt.contains("Mountains") and txt.contains("x1.50"),
		txt))

	# 10. At ~3x effective power the attacker always captures (decisive
	# combat, loss factor 0.55). Fixed seeds make the sweep deterministic.
	# (188 vs 50 +25% defender bonus = 3.008x power.)
	const EXPECTED_WINS_3X := 20  # measured 2026-10-10: 20/20 seeds capture
	var wins := 0
	for seed in range(1000, 1020):
		var dd := _duel(seed, 188, 50)
		var rr: Dictionary = CombatSim.resolve(dd[0], dd[1], dd[2])
		if bool(rr["captured"]):
			wins += 1
	out.append(_t("combat.three_x_usually_wins", wins == EXPECTED_WINS_3X,
		"captured %d/20 (expected %d)" % [wins, EXPECTED_WINS_3X]))

	return out
