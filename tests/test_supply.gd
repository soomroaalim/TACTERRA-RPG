extends RefCounted
## Tests for SupplySim (BFS supply lines + attrition). Run via tests/run_tests.gd.


static func _t(pname: String, passed: bool, note: String = "") -> Dictionary:
	return {"name": pname, "passed": passed, "note": note}


static func _base() -> StateMock:
	var s := StateMock.make_state()
	# t0: capital (owner 0) -- t1 (owner 0).  t2 (owner 0, disconnected pocket)
	# -- t3 (neutral).
	var t0 := StateMock.make_territory(0, 0, Tacterra.Terrain.PLAINS, [1], 500)
	t0.is_capital = true
	var t1 := StateMock.make_territory(1, 0, Tacterra.Terrain.PLAINS, [0], 500)
	var t2 := StateMock.make_territory(2, 0, Tacterra.Terrain.PLAINS, [3], 500)
	var t3 := StateMock.make_territory(3, -1, Tacterra.Terrain.PLAINS, [2], 100)
	s.territories = [t0, t1, t2, t3]
	var p := StateMock.make_nation(0, "Player", true, 0)
	s.nations = [p]
	return s


static func run() -> Array:
	var out: Array = []

	# 1. BFS: capital-connected territories supplied; pocket + neutral not.
	var s := _base()
	SupplySim.recompute(s)
	var t0 = s.get_territory(0)
	var t1 = s.get_territory(1)
	var t2 = s.get_territory(2)
	var t3 = s.get_territory(3)
	out.append(_t("supply.bfs",
		t0.supplied and t1.supplied and not t2.supplied and not t3.supplied,
		"t0=%s t1=%s t2=%s t3=%s" % [str(t0.supplied), str(t1.supplied),
			str(t2.supplied), str(t3.supplied)]))

	# 2. Missing/unowned capital -> nobody supplied.
	s = _base()
	s.get_nation(0).capital_id = 99
	SupplySim.recompute(s)
	var any_sup := false
	for t in s.territories:
		any_sup = any_sup or t.supplied
	out.append(_t("supply.no_capital", not any_sup, "any_supplied=%s" % str(any_sup)))

	# 3. Transit heading to a friendly supplied territory stays supplied.
	s = _base()
	SupplySim.recompute(s)
	var a := StateMock.launch(s, 0, 0, 1, 50)
	SupplySim.apply_attrition(s, 1.0)
	out.append(_t("supply.transit_supplied",
		is_equal_approx(a.unsupplied_days, 0.0) and a.troops == 50,
		"days=%.1f troops=%d" % [a.unsupplied_days, a.troops]))

	# 4. Transit heading into neutral/enemy land counts as unsupplied.
	s = _base()
	SupplySim.recompute(s)
	a = StateMock.launch(s, 0, 1, 3, 50)  # t3 is neutral
	SupplySim.apply_attrition(s, 1.0)
	out.append(_t("supply.transit_unsupplied",
		is_equal_approx(a.unsupplied_days, 1.0) and a.troops == 50,  # grace: no loss yet
		"days=%.1f troops=%d" % [a.unsupplied_days, a.troops]))

	# 5. Grace period: no losses within 3 days; attrition after.
	s = _base()
	SupplySim.recompute(s)
	var g := StateMock.station(s, 2, 0, 100)  # t2 unsupplied
	SupplySim.apply_attrition(s, 1.0)
	var grace_ok := g.troops == 100 and is_equal_approx(g.unsupplied_days, 1.0)
	g.unsupplied_days = 3.0
	SupplySim.apply_attrition(s, 1.0)  # days -> 4.0 > 3: loss ceil(100*0.02)=2
	out.append(_t("supply.attrition",
		grace_ok and g.troops == 98 and is_equal_approx(g.unsupplied_days, 4.0),
		"grace_troops_ok=%s troops=%d days=%.1f" % [str(grace_ok), g.troops, g.unsupplied_days]))

	# 6. Reconnecting supply resets the unsupplied counter.
	s = _base()
	t1 = s.get_territory(1)
	t2 = s.get_territory(2)
	t1.neighbors.append(2)
	t2.neighbors.append(1)
	g = StateMock.station(s, 2, 0, 100)
	g.unsupplied_days = 5.0
	SupplySim.recompute(s)
	SupplySim.apply_attrition(s, 1.0)
	out.append(_t("supply.resupply_reset",
		t2.supplied and is_equal_approx(g.unsupplied_days, 0.0) and g.troops == 100,
		"supplied=%s days=%.1f troops=%d" % [str(t2.supplied), g.unsupplied_days, g.troops]))

	# 7. An army attrited to zero is removed and the player is notified.
	s = _base()
	SupplySim.recompute(s)
	g = StateMock.station(s, 2, 0, 1)
	g.unsupplied_days = 10.0
	SupplySim.apply_attrition(s, 1.0)  # loss ceil(1*0.02)=1 -> 0
	t2 = s.get_territory(2)
	out.append(_t("supply.destroyed",
		t2.army == null \
			and StateMock.has_notification(s, Tacterra.NotifyKind.BAD, "cut off"),
		"army_gone=%s notified=%s" % [str(t2.army == null),
			str(StateMock.has_notification(s, Tacterra.NotifyKind.BAD, "cut off"))]))

	# 8. Transit destroyed by attrition is removed from the transit list.
	s = _base()
	SupplySim.recompute(s)
	a = StateMock.launch(s, 0, 1, 3, 1)
	a.unsupplied_days = 10.0
	SupplySim.apply_attrition(s, 1.0)
	out.append(_t("supply.transit_destroyed",
		s.transits.is_empty(),
		"transits=%d" % s.transits.size()))

	return out
