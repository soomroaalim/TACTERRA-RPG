extends RefCounted
## Enemy AI tests for TACTERRA RPG.
##
## Builds SYNTHETIC GameState instances by hand (TerritoryData / NationData /
## ArmyData assigned directly onto GameState.new() — never MapGenerator or
## GameState.create). Everything goes through the documented GameState API
## (order_move / order_recruit / order_develop / order_fortify, owned_ids,
## army_at, training_queues, transits), so these tests also validate that the
## AI never cheats: credits can never go negative and invalid orders fail
## gracefully instead of crashing.
##
## If scripts/core/game_state.gd is missing (or lacks the documented API),
## every test reports UNVERIFIED with the precise blocker instead of failing
## on a missing dependency.

const GS_PATH := "res://scripts/core/game_state.gd"
const AI_PATH := "res://scripts/core/ai/ai_brain.gd"

const _REQUIRED_METHODS := [
	"get_territory", "get_nation", "owned_ids", "army_at",
	"order_move", "order_recruit", "order_develop", "order_fortify",
	"add_notification",
]

const _PLANNED := [
	"ai_expand_weak_neutral",
	"ai_no_attack_below_threshold",
	"ai_recruit_toward_target",
	"ai_recruit_capital_fallback",
	"ai_easy_vs_hard_threshold",
	"ai_personality_aggressive_vs_defensive",
	"ai_think_cooldowns",
	"ai_broke_no_crash_no_debt",
	"ai_zero_territories_safe",
	"ai_defense_reinforce_border",
	"ai_hard_intercept_inbound",
	"ai_player_untouched",
]


static func run() -> Array:
	var results: Array = []
	if not FileAccess.file_exists(GS_PATH):
		for t in _PLANNED:
			results.append({"name": t, "passed": false, "note":
				"UNVERIFIED (blocked): scripts/core/game_state.gd is not present yet — " \
				+ "the AI was validated separately against a stub GameState that " \
				+ "faithfully implements the documented API; re-run once the real " \
				+ "GameState lands."})
		return results
	var gs_script: GDScript = load(GS_PATH)
	var ai_script: GDScript = load(AI_PATH)
	if gs_script == null or ai_script == null:
		for t in _PLANNED:
			results.append({"name": t, "passed": false,
				"note": "UNVERIFIED (blocked): failed to load game_state.gd or ai_brain.gd."})
		return results
	var probe: Variant = gs_script.new()
	for m in _REQUIRED_METHODS:
		if not probe.has_method(m):
			for t in _PLANNED:
				results.append({"name": t, "passed": false, "note":
					"UNVERIFIED (blocked): GameState is missing documented method '%s'." % m})
			return results
	_t_expand(ai_script, gs_script, results)
	_t_no_attack(ai_script, gs_script, results)
	_t_recruit(ai_script, gs_script, results)
	_t_recruit_fallback(ai_script, gs_script, results)
	_t_easy_vs_hard(ai_script, gs_script, results)
	_t_personality(ai_script, gs_script, results)
	_t_cooldowns(ai_script, gs_script, results)
	_t_broke(ai_script, gs_script, results)
	_t_zero_territories(ai_script, gs_script, results)
	_t_defense(ai_script, gs_script, results)
	_t_intercept(ai_script, gs_script, results)
	_t_player_untouched(ai_script, gs_script, results)
	return results


# ------------------------------------------------------------- scaffolding ---
static func _ok(results: Array, test_name: String, cond: bool, note: String) -> void:
	results.append({"name": test_name, "passed": cond, "note": note})


static func _terr(tid: int, tname: String, owner: int, neighbors: Array,
		troops: int = 0, garrison: int = 0, terrain: int = 0, pop: int = 500) -> TerritoryData:
	var t := TerritoryData.new()
	t.id = tid
	t.name = tname
	t.owner_id = owner
	t.neighbors.assign(neighbors)
	t.terrain = terrain
	t.population = pop
	t.center = Vector2(float(tid) * 700.0, 0.0)
	t.garrison = garrison
	t.supplied = true
	if troops > 0:
		t.army = ArmyData.create(owner, troops, tid)
	return t


static func _nation(nid: int, nname: String, diff: int, pers: int,
		credits: float, manpower: float, capital: int, is_player: bool = false) -> NationData:
	var n := NationData.new()
	n.id = nid
	n.name = nname
	n.is_player = is_player
	n.difficulty = diff
	n.personality = pers
	n.credits = credits
	n.manpower = manpower
	n.capital_id = capital
	n.ai_cooldown = 0.0
	return n


## Hand-built GameState: fields assigned directly, no MapGenerator/create().
static func _state(gs_script: GDScript, terrs: Array, nats: Array, extra_transits: Array = []) -> Variant:
	var s: Variant = gs_script.new()
	var ta: Array[TerritoryData] = []
	ta.assign(terrs)
	var na: Array[NationData] = []
	na.assign(nats)
	var ra: Array[ArmyData] = []
	ra.assign(extra_transits)
	s.territories = ta
	s.nations = na
	s.transits = ra
	s.day = 0.0
	s.speed = 1.0
	s.settings = {}
	s.over = false
	s.winner_id = -1
	s.player_won = false
	var notifs: Array[Dictionary] = []
	var reports: Array[Dictionary] = []
	s.notifications = notifs
	s.battle_reports = reports
	s.rng = RandomNumberGenerator.new()
	s.training_queues = {}
	return s


static func _player() -> NationData:
	return _nation(0, "Player", -1, Tacterra.Personality.EXPANSIONIST, 777.0, 100.0, -1, true)


static func _find_transit(s: Variant, mfrom: int, mto: int) -> Variant:
	for tr in s.transits:
		if tr.move_from == mfrom and tr.move_to == mto:
			return tr
	return null


# ------------------------------------------------------------------ tests ---
## AI expands into a weak neutral neighbor: 200 troops vs garrison 20.
## Expect one transit T0->N with int(200*EXPAND_SEND_FRAC)=160 troops.
static func _t_expand(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	var aix := _nation(1, "AI", Tacterra.Difficulty.NORMAL,
		Tacterra.Personality.EXPANSIONIST, 300.0, 10.0, 0)
	var en := _nation(2, "Enemy", Tacterra.Difficulty.EASY,
		Tacterra.Personality.DEFENSIVE, 0.0, 0.0, -1)
	var t0 := _terr(0, "T0", 1, [1], 200)
	var tn := _terr(1, "N", -1, [0], 0, 20)
	var s: Variant = _state(gs, [t0, tn], [pl, aix, en])
	ai.tick(s, aix, 1.0)
	var tr: Variant = _find_transit(s, 0, 1)
	_ok(results, "ai_expand_weak_neutral",
		tr != null and tr.troops == 160 and s.transits.size() == 1,
		"expected one 160-troop transit 0->1; got %d transits" % s.transits.size())


## AI must NOT attack when the power ratio is below threshold.
## 100 vs 200 on plains: ratio ~0.36 < 1.2 (HARD aggressive). No transit.
static func _t_no_attack(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	var aix := _nation(1, "AI", Tacterra.Difficulty.HARD,
		Tacterra.Personality.AGGRESSIVE, 300.0, 10.0, 0)
	var en := _nation(2, "Enemy", Tacterra.Difficulty.NORMAL,
		Tacterra.Personality.DEFENSIVE, 500.0, 100.0, 1)
	var t0 := _terr(0, "T0", 1, [1], 100)
	var t1 := _terr(1, "T1", 2, [0], 200)
	var s: Variant = _state(gs, [t0, t1], [pl, aix, en])
	ai.tick(s, aix, 1.0)
	_ok(results, "ai_no_attack_below_threshold",
		s.transits.is_empty() and aix.credits == 300.0,
		"expected no attack orders; transits=%d credits=%.0f" % [s.transits.size(), aix.credits])


## AI recruits toward its target: 2 territories NORMAL expansionist -> 240.
## 50 stationed, 5000 credits, 500 manpower -> batch 190 at the capital.
## Economy step develops the capital first (5000-100), then recruits.
static func _t_recruit(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	var aix := _nation(1, "AI", Tacterra.Difficulty.NORMAL,
		Tacterra.Personality.EXPANSIONIST, 5000.0, 500.0, 0)
	var cap := _terr(0, "Cap", 1, [1], 50, 0, 0, 1000)
	cap.is_capital = true
	var t1 := _terr(1, "T1", 1, [0], 0, 0, 0, 500)
	var s: Variant = _state(gs, [cap, t1], [pl, aix])
	ai.tick(s, aix, 1.0)
	var q: Array = s.training_queues.get(0, [])
	var queued := 0
	for e in q:
		queued += int(e.get("troops", 0))
	_ok(results, "ai_recruit_toward_target",
		queued == 190 and is_equal_approx(aix.credits, 3000.0),
		"expected 190 queued at capital, credits 3000; got queued=%d credits=%.0f" % [queued, aix.credits])


## Capital lost -> recruits at the most populous owned territory instead.
static func _t_recruit_fallback(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	var aix := _nation(1, "AI", Tacterra.Difficulty.NORMAL,
		Tacterra.Personality.EXPANSIONIST, 5000.0, 500.0, 2) # capital id 2: enemy-held
	var en := _nation(2, "Enemy", Tacterra.Difficulty.EASY,
		Tacterra.Personality.DEFENSIVE, 0.0, 0.0, 2)
	var t0 := _terr(0, "Big", 1, [1], 0, 0, 0, 800)
	var t1 := _terr(1, "Small", 1, [0], 0, 0, 0, 300)
	var te := _terr(2, "Lost", 2, [], 0)
	var s: Variant = _state(gs, [t0, t1, te], [pl, aix, en])
	ai.tick(s, aix, 1.0)
	var q: Array = s.training_queues.get(0, [])
	var queued := 0
	for e in q:
		queued += int(e.get("troops", 0))
	_ok(results, "ai_recruit_capital_fallback",
		queued == 240 and not s.training_queues.has(2),
		"expected 240 queued at fallback territory 0; queues=%s" % str(s.training_queues.keys()))


## EASY vs HARD on the identical scenario: 110 vs 50 on plains.
## ratio = 110 / (50*1.1*1.25) = 1.6 -> HARD (1.35) attacks, EASY (2.2) doesn't.
## Also verifies per-difficulty think cooldowns (5.0 vs 2.0).
static func _t_easy_vs_hard(ai: GDScript, gs: GDScript, results: Array) -> void:
	var mk := func(diff: int) -> Array:
		var pl := _player()
		var ax: NationData = _nation(1, "AI", diff,
			Tacterra.Personality.EXPANSIONIST, 300.0, 10.0, 0)
		var en := _nation(2, "Enemy", Tacterra.Difficulty.NORMAL,
			Tacterra.Personality.DEFENSIVE, 0.0, 0.0, 1)
		var t0 := _terr(0, "T0", 1, [1], 110)
		var t1 := _terr(1, "T1", 2, [0], 50)
		var st: Variant = _state(gs, [t0, t1], [pl, ax, en])
		ai.tick(st, ax, 1.0)
		return [st, ax]
	var easy: Array = mk.call(Tacterra.Difficulty.EASY)
	var hard: Array = mk.call(Tacterra.Difficulty.HARD)
	var se: Variant = easy[0]
	var ne: NationData = easy[1]
	var sh: Variant = hard[0]
	var nh: NationData = hard[1]
	var hard_tr: Variant = _find_transit(sh, 0, 1)
	_ok(results, "ai_easy_vs_hard_threshold",
		se.transits.is_empty() and hard_tr != null and hard_tr.troops == 88 \
			and is_equal_approx(ne.ai_cooldown, 5.0) and is_equal_approx(nh.ai_cooldown, 2.0),
		"easy transits=%d (want 0), hard attack troops=%s (want 88), cooldowns=%.1f/%.1f (want 5.0/2.0)" % [
			se.transits.size(),
			str(hard_tr.troops) if hard_tr != null else "none",
			ne.ai_cooldown, nh.ai_cooldown])


## Personality must be visible: AGGRESSIVE (threshold 1.45) attacks at a ratio
## where DEFENSIVE (threshold 1.9) holds back. Same 110-vs-50 setup (ratio 1.6).
static func _t_personality(ai: GDScript, gs: GDScript, results: Array) -> void:
	var mk := func(pers: int) -> Variant:
		var pl := _player()
		var ax: NationData = _nation(1, "AI", Tacterra.Difficulty.NORMAL, pers, 300.0, 10.0, 0)
		var en := _nation(2, "Enemy", Tacterra.Difficulty.NORMAL,
			Tacterra.Personality.DEFENSIVE, 0.0, 0.0, 1)
		var t0 := _terr(0, "T0", 1, [1], 110)
		var t1 := _terr(1, "T1", 2, [0], 50)
		var st: Variant = _state(gs, [t0, t1], [pl, ax, en])
		ai.tick(st, ax, 1.0)
		return st
	var aggr: Variant = mk.call(Tacterra.Personality.AGGRESSIVE)
	var defe: Variant = mk.call(Tacterra.Personality.DEFENSIVE)
	_ok(results, "ai_personality_aggressive_vs_defensive",
		_find_transit(aggr, 0, 1) != null and defe.transits.is_empty(),
		"aggressive transits=%d (want >=1), defensive transits=%d (want 0)" % [
			aggr.transits.size(), defe.transits.size()])


## Cooldown gating: think once, then stay quiet until the cooldown expires.
static func _t_cooldowns(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	var ne: NationData = _nation(1, "EasyAI", Tacterra.Difficulty.EASY,
		Tacterra.Personality.EXPANSIONIST, 100.0, 10.0, -1)
	var nh: NationData = _nation(2, "HardAI", Tacterra.Difficulty.HARD,
		Tacterra.Personality.EXPANSIONIST, 100.0, 10.0, -1)
	var s: Variant = _state(gs, [], [pl, ne, nh])
	ai.tick(s, ne, 1.0)
	ai.tick(s, nh, 1.0)
	var first_ok := is_equal_approx(ne.ai_cooldown, 5.0) and is_equal_approx(nh.ai_cooldown, 2.0)
	ai.tick(s, ne, 1.0) # cooldown still > 0 -> no re-think, just decrement
	ai.tick(s, nh, 1.0)
	_ok(results, "ai_think_cooldowns",
		first_ok and is_equal_approx(ne.ai_cooldown, 4.0) and is_equal_approx(nh.ai_cooldown, 1.0),
		"cooldowns after two ticks: easy=%.1f (want 4.0), hard=%.1f (want 1.0)" % [ne.ai_cooldown, nh.ai_cooldown])


## Broke AI: no crash, credits never negative, unaffordable orders fail cleanly.
static func _t_broke(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	var aix := _nation(1, "AI", Tacterra.Difficulty.NORMAL,
		Tacterra.Personality.EXPANSIONIST, 0.0, 0.0, 0)
	var t0 := _terr(0, "T0", 1, [1], 100)
	var tn := _terr(1, "N", -1, [0], 0, 500) # far too strong to expand into
	var s: Variant = _state(gs, [t0, tn], [pl, aix])
	ai.tick(s, aix, 1.0)
	var r1: Dictionary = s.order_recruit(1, 0, 10)
	var r2: Dictionary = s.order_develop(1, 0)
	_ok(results, "ai_broke_no_crash_no_debt",
		aix.credits == 0.0 and s.transits.is_empty() \
			and not bool(r1.get("ok", true)) and not bool(r2.get("ok", true)),
		"credits=%.0f (want 0), transits=%d, recruit ok=%s, develop ok=%s" % [
			aix.credits, s.transits.size(), str(r1.get("ok")), str(r2.get("ok"))])


## Nation with zero territories: think must no-op safely.
static func _t_zero_territories(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	var aix := _nation(1, "AI", Tacterra.Difficulty.HARD,
		Tacterra.Personality.AGGRESSIVE, 1000.0, 100.0, -1)
	var s: Variant = _state(gs, [], [pl, aix])
	ai.tick(s, aix, 1.0)
	_ok(results, "ai_zero_territories_safe",
		s.transits.is_empty() and aix.credits == 1000.0,
		"no crash; transits=%d credits=%.0f" % [s.transits.size(), aix.credits])


## DEFENSIVE AI reinforces a threatened border from the interior BEFORE
## attacking: B(50) threatened by E(150); I(200, interior, adjacent) donates.
## needed = int(150*1.3)-50 = 145; defensive x1.5 -> 217, clamped to 200.
static func _t_defense(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	var aix := _nation(1, "AI", Tacterra.Difficulty.NORMAL,
		Tacterra.Personality.DEFENSIVE, 300.0, 10.0, 1)
	var en := _nation(2, "Enemy", Tacterra.Difficulty.NORMAL,
		Tacterra.Personality.AGGRESSIVE, 500.0, 100.0, 2)
	var b := _terr(0, "Border", 1, [1, 2], 50)
	var i := _terr(1, "Interior", 1, [0], 200)
	i.is_capital = true
	var e := _terr(2, "Foe", 2, [0], 150)
	var s: Variant = _state(gs, [b, i, e], [pl, aix, en])
	ai.tick(s, aix, 1.0)
	var tr: Variant = _find_transit(s, 1, 0)
	_ok(results, "ai_defense_reinforce_border",
		tr != null and tr.troops == 200 and s.transits.size() == 1,
		"expected one 200-troop transit 1->0; got %d transits" % s.transits.size())


## HARD AI intercepts: enemy army in transit toward our territory B.
## A(100, adjacent to B) reinforces B with min(100-40, 150) = 60.
static func _t_intercept(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	var aix := _nation(1, "AI", Tacterra.Difficulty.HARD,
		Tacterra.Personality.EXPANSIONIST, 300.0, 10.0, 0)
	var en := _nation(2, "Enemy", Tacterra.Difficulty.NORMAL,
		Tacterra.Personality.AGGRESSIVE, 500.0, 100.0, 2)
	var a := _terr(0, "A", 1, [1], 100)
	a.is_capital = true
	var b := _terr(1, "B", 1, [0, 2])
	var e := _terr(2, "E", 2, [1])
	var inbound := ArmyData.create(2, 80, 2)
	inbound.moving = true
	inbound.move_from = 2
	inbound.move_to = 1
	var s: Variant = _state(gs, [a, b, e], [pl, aix, en], [inbound])
	ai.tick(s, aix, 1.0)
	var tr: Variant = _find_transit(s, 0, 1)
	_ok(results, "ai_hard_intercept_inbound",
		tr != null and tr.troops == 60 and s.transits.size() == 2,
		"expected reinforcement transit 0->1 with 60 troops; total transits=%d" % s.transits.size())


## The AI must never spend or alter the player's resources/territories.
static func _t_player_untouched(ai: GDScript, gs: GDScript, results: Array) -> void:
	var pl := _player()
	pl.capital_id = 0
	var aix := _nation(1, "AI", Tacterra.Difficulty.NORMAL,
		Tacterra.Personality.EXPANSIONIST, 300.0, 10.0, 1)
	var p := _terr(0, "Home", 0, [], 100)
	p.is_capital = true
	var t0 := _terr(1, "T0", 1, [2], 200)
	var tn := _terr(2, "N", -1, [1], 0, 20)
	var s: Variant = _state(gs, [p, t0, tn], [pl, aix])
	ai.tick(s, aix, 1.0)
	_ok(results, "ai_player_untouched",
		is_equal_approx(pl.credits, 777.0) and p.owner_id == 0 and p.army.troops == 100,
		"player credits=%.0f (want 777), territory owner=%d, troops=%d" % [
			pl.credits, p.owner_id, p.army.troops if p.army != null else -1])
