extends RefCounted
## Tests for EconomySim. Run via tests/run_tests.gd (static run() -> Array).


static func _t(pname: String, passed: bool, note: String = "") -> Dictionary:
	return {"name": pname, "passed": passed, "note": note}


static func _base() -> StateMock:
	var s := StateMock.make_state()
	var t0 := StateMock.make_territory(0, 0, Tacterra.Terrain.FERTILE, [1], 1000)
	t0.has_city = true
	t0.is_capital = true
	var t1 := StateMock.make_territory(1, 0, Tacterra.Terrain.PLAINS, [0], 1000)
	s.territories = [t0, t1]
	var p := StateMock.make_nation(0, "Player", true, 0)
	p.credits = 500.0
	p.supplies = 200.0
	p.manpower = 0.0
	s.nations = [p]
	return s


static func run() -> Array:
	var out: Array = []

	# 1. Income math: fertile+city+capital = 28/day, plains = 6/day -> 34/day.
	var s := _base()
	EconomySim.tick(s, 1.0)
	var p = s.get_nation(0)
	out.append(_t("economy.income_exact",
		is_equal_approx(p.credits, 534.0) and is_equal_approx(float(p.stats["income_earned"]), 34.0),
		"credits=%.2f income_earned=%.2f" % [p.credits, float(p.stats["income_earned"])]))

	# 2. Upkeep is paid when affordable: 150 troops * 0.02 = 3/day.
	s = _base()
	p = s.get_nation(0)
	StateMock.station(s, 0, 0, 100)
	StateMock.launch(s, 0, 0, 1, 50)
	EconomySim.tick(s, 1.0)
	out.append(_t("economy.upkeep_paid",
		is_equal_approx(p.credits, 531.0) and not p.broke_warned,
		"credits=%.2f broke=%s" % [p.credits, str(p.broke_warned)]))

	# 3. Unpaid upkeep: treasury emptied, 3% desertion, latched notification.
	s = _base()
	p = s.get_nation(0)
	for t in s.territories:
		t.terrain = Tacterra.Terrain.DESERT
		t.has_city = false
	# income now 2+2=4/day < upkeep of 1000 troops (20/day) -> broke.
	p.credits = 0.0
	var a := StateMock.station(s, 0, 0, 1000)
	EconomySim.tick(s, 1.0)
	var desert_ok := a.troops == 970  # round(1000 * 0.03 * 1)
	var note_ok := StateMock.has_notification(s, Tacterra.NotifyKind.BAD, "desert")
	out.append(_t("economy.broke_desertion",
		is_equal_approx(p.credits, 0.0) and desert_ok and p.broke_warned and note_ok,
		"credits=%.2f troops=%d warned=%s note=%s" % [p.credits, a.troops, str(p.broke_warned), str(note_ok)]))

	# 4. Broke latch resets once upkeep is affordable again.
	p.credits = 1000.0
	EconomySim.tick(s, 1.0)
	out.append(_t("economy.broke_reset",
		not p.broke_warned and p.credits < 1000.0,
		"broke=%s credits=%.2f" % [str(p.broke_warned), p.credits]))

	# 5. Desertion minimum: 1 troop lost when army > 10 even if 3% rounds to 0.
	s = _base()
	p = s.get_nation(0)
	p.credits = 0.0
	for t in s.territories:
		t.terrain = Tacterra.Terrain.DESERT
		t.has_city = false
	# income now 2+2=4/day; a huge army guarantees broke.
	var small := StateMock.station(s, 0, 0, 20)
	var big := StateMock.station(s, 1, 0, 5000)
	EconomySim.tick(s, 1.0)  # income 4, upkeep 5020*0.02=100.4 -> broke
	var small_loss := 20 - small.troops  # round(20*0.03)=1 -> max(1,1)=1
	out.append(_t("economy.desertion_min_one",
		small_loss == 1 and big.troops == 5000 - 150,
		"small lost %d, big now %d" % [small_loss, big.troops]))

	# 6. Manpower regen: cap = 2000/10 = 200; +2%/day; clamped at cap.
	s = _base()
	p = s.get_nation(0)
	p.manpower = 199.0
	EconomySim.tick(s, 1.0)
	out.append(_t("economy.manpower_cap",
		is_equal_approx(p.manpower, 200.0),
		"manpower=%.2f" % p.manpower))

	# 7. Supplies: production minus use; clamped at zero, never negative.
	s = _base()
	p = s.get_nation(0)
	p.supplies = 0.0
	StateMock.station(s, 0, 0, 10000)  # use = 100/day vs prod 7/day
	EconomySim.tick(s, 1.0)
	var starved: float = p.supplies
	s = _base()
	p = s.get_nation(0)
	p.supplies = 0.0
	EconomySim.tick(s, 1.0)  # prod 12/day (10 on capital fertile+city, 2 plains), no troops
	out.append(_t("economy.supplies",
		is_equal_approx(starved, 0.0) and is_equal_approx(p.supplies, 12.0),
		"starved=%.2f normal=%.2f" % [starved, p.supplies]))

	# 8. Training queue: recruits arrive after their days_left, queue cleaned.
	s = _base()
	s.training_queues[1] = [{"troops": 50, "days_left": 1.0, "owner_id": 0}]
	EconomySim.tick(s, 0.5)
	var mid := s.get_territory(1).army == null and s.training_queues.has(1)
	EconomySim.tick(s, 0.5)
	var t1 = s.get_territory(1)
	out.append(_t("economy.training_deliver",
		mid and t1.army != null and t1.army.troops == 50 and not s.training_queues.has(1),
		"mid_pending=%s troops=%d queue_gone=%s" % [str(mid),
			t1.army.troops if t1.army != null else -1, str(not s.training_queues.has(1))]))

	# 9. Training merge: weighted training average with veterans.
	s = _base()
	StateMock.station(s, 1, 0, 100, 0.5)
	s.training_queues[1] = [{"troops": 50, "days_left": 0.5, "owner_id": 0}]
	EconomySim.tick(s, 1.0)
	t1 = s.get_territory(1)
	out.append(_t("economy.training_merge",
		t1.army.troops == 150 and is_equal_approx(t1.army.training, 100.0 * 0.5 / 150.0),
		"troops=%d training=%.4f" % [t1.army.troops, t1.army.training]))

	# 10. Recruits discarded when the territory changed hands (player notified).
	s = _base()
	var ai := StateMock.make_nation(1, "AI", false, 5)
	s.nations.append(ai)
	s.get_territory(1).owner_id = 1
	s.training_queues[1] = [{"troops": 50, "days_left": 0.5, "owner_id": 0}]
	EconomySim.tick(s, 1.0)
	t1 = s.get_territory(1)
	out.append(_t("economy.training_discard",
		(t1.army == null or t1.army.owner_id != 0) \
			and StateMock.has_notification(s, Tacterra.NotifyKind.BAD, "changed hands"),
		"army_owner=%d notified=%s" % [t1.army.owner_id if t1.army != null else -2,
			str(StateMock.has_notification(s, Tacterra.NotifyKind.BAD, "changed hands"))]))

	# 11. Eliminated nations are skipped entirely.
	s = _base()
	p = s.get_nation(0)
	p.eliminated = true
	p.credits = 10.0
	EconomySim.tick(s, 1.0)
	out.append(_t("economy.eliminated_skipped",
		is_equal_approx(p.credits, 10.0),
		"credits=%.2f" % p.credits))

	return out
