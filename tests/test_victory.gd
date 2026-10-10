extends RefCounted
## Tests for VictorySim (elimination, defeat, victory). Run via tests/run_tests.gd.


static func _t(pname: String, passed: bool, note: String = "") -> Dictionary:
	return {"name": pname, "passed": passed, "note": note}


static func _base() -> StateMock:
	var s := StateMock.make_state()
	# Player: t0 (capital). AI 1: t1, t2 (capital t1). AI 2: t3 (capital).
	var t0 := StateMock.make_territory(0, 0, Tacterra.Terrain.PLAINS, [], 500)
	t0.is_capital = true
	var t1 := StateMock.make_territory(1, 1, Tacterra.Terrain.PLAINS, [], 500)
	t1.is_capital = true
	var t2 := StateMock.make_territory(2, 1, Tacterra.Terrain.PLAINS, [], 500)
	var t3 := StateMock.make_territory(3, 2, Tacterra.Terrain.PLAINS, [], 500)
	t3.is_capital = true
	s.territories = [t0, t1, t2, t3]
	var p := StateMock.make_nation(0, "Player", true, 0)
	var a1 := StateMock.make_nation(1, "Rival1", false, 1)
	var a2 := StateMock.make_nation(2, "Rival2", false, 3)
	s.nations = [p, a1, a2]
	return s


static func run() -> Array:
	var out: Array = []

	# 1. A nation with no territories is eliminated (transits removed, notified).
	var s := _base()
	var a2 = s.get_nation(2)
	s.get_territory(3).owner_id = 0  # AI 2 loses its only territory
	var tr := StateMock.launch(s, 2, 3, 0, 40, 1.0)
	s.training_queues[3] = [{"troops": 10, "days_left": 1.0, "owner_id": 2}]
	VictorySim.check(s)
	out.append(_t("victory.elimination",
		a2.eliminated and not s.transits.has(tr) \
			and not s.training_queues.has(3) \
			and StateMock.has_notification(s, Tacterra.NotifyKind.INFO, "eliminated"),
		"eliminated=%s transits=%d queue_gone=%s" % [str(a2.eliminated),
			s.transits.size(), str(not s.training_queues.has(3))]))

	# 2. Player elimination -> defeat; winner = strongest surviving AI.
	s = _base()
	s.get_territory(0).owner_id = 1  # player loses everything
	VictorySim.check(s)
	out.append(_t("victory.defeat",
		s.over and not s.player_won and s.winner_id == 1 \
			and StateMock.has_notification(s, Tacterra.NotifyKind.BAD, "Defeat"),
		"over=%s won=%s winner=%d" % [str(s.over), str(s.player_won), s.winner_id]))

	# 3. All AI eliminated -> victory for the surviving player.
	s = _base()
	s.get_territory(1).owner_id = 0
	s.get_territory(2).owner_id = 0
	s.get_territory(3).owner_id = 0
	VictorySim.check(s)
	var p = s.get_nation(0)
	out.append(_t("victory.victory",
		s.over and s.player_won and s.winner_id == 0 and not p.eliminated \
			and StateMock.has_notification(s, Tacterra.NotifyKind.GOOD, "Victory"),
		"over=%s won=%s winner=%d" % [str(s.over), str(s.player_won), s.winner_id]))

	# 4. Idempotent: a second check changes nothing and notifies nothing new.
	s = _base()
	s.get_territory(1).owner_id = 0
	s.get_territory(2).owner_id = 0
	s.get_territory(3).owner_id = 0
	VictorySim.check(s)
	var n1 := s.notifications.size()
	VictorySim.check(s)
	out.append(_t("victory.idempotent",
		s.notifications.size() == n1 and s.over,
		"notifications=%d -> %d" % [n1, s.notifications.size()]))

	# 5. No false elimination: nations holding territory are untouched.
	s = _base()
	VictorySim.check(s)
	var untouched := true
	for n in s.nations:
		untouched = untouched and not n.eliminated
	out.append(_t("victory.no_false_positive",
		untouched and not s.over,
		"over=%s" % str(s.over)))

	# 6. Defeat takes precedence when everyone falls together.
	s = _base()
	for t in s.territories:
		t.owner_id = -1  # everyone loses everything
	VictorySim.check(s)
	out.append(_t("victory.mutual_destruction",
		s.over and not s.player_won and s.winner_id == -1,
		"over=%s won=%s winner=%d" % [str(s.over), str(s.player_won), s.winner_id]))

	return out
