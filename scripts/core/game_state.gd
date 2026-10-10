class_name GameState
extends RefCounted
## TACTERRA RPG — the single source of truth for a match.
##
## Holds all world state (territories, nations, transits, training queues,
## notifications, battle reports). Simulation subsystems are static classes
## that operate on a GameState; the UI renders from it and issues orders
## through its order_* methods. Every order validates and returns
## {ok:bool, error:String}.

var territories: Array[TerritoryData] = []
var nations: Array[NationData] = [] ## index == id; player is id 0
var transits: Array[ArmyData] = [] ## armies currently moving between territories
var training_queues: Dictionary = {} ## int territory_id -> Array of {troops, days_left, owner_id}
var day: float = 0.0
var speed: float = 1.0 ## 0 = paused; otherwise game-days/sec multiplier
var settings: Dictionary = {}
var over: bool = false
var winner_id: int = -1
var player_won: bool = false
var notifications: Array[Dictionary] = [] ## {day, text, kind}
var battle_reports: Array[Dictionary] = []
var rng: RandomNumberGenerator = null


# ---------------------------------------------------------------- creation --

## Build a fresh match from setup settings:
## {map_size:int, ai_count:int, difficulty:int, preset:String, speed:float}.
static func create(p_settings: Dictionary) -> GameState:
	var s := GameState.new()
	s.rng = RandomNumberGenerator.new()
	if p_settings.has("seed"):
		s.rng.seed = int(p_settings["seed"])
	else:
		s.rng.randomize()
	s.settings = {
		"map_size": int(p_settings.get("map_size", Tacterra.MapSize.STANDARD)),
		"ai_count": clampi(int(p_settings.get("ai_count", 3)), 2, 5),
		"difficulty": int(p_settings.get("difficulty", Tacterra.Difficulty.NORMAL)),
		"preset": str(p_settings.get("preset", "standard")),
		"speed": float(p_settings.get("speed", 1.0)),
	}
	s.speed = float(s.settings["speed"])
	s.day = 0.0
	s.over = false
	s.winner_id = -1
	s.player_won = false

	# Player nation (id 0).
	var p := NationData.new()
	p.id = 0
	p.name = "Free Cities"
	p.is_player = true
	p.color = Tacterra.NATION_COLORS[0]
	p.personality = Tacterra.Personality.EXPANSIONIST
	p.difficulty = -1
	s.nations.append(p)

	# AI nations (ids 1..N), personalities cycle EXPANSIONIST/DEFENSIVE/AGGRESSIVE.
	var pers := [Tacterra.Personality.EXPANSIONIST,
		Tacterra.Personality.DEFENSIVE, Tacterra.Personality.AGGRESSIVE]
	for i in range(int(s.settings["ai_count"])):
		var n := NationData.new()
		n.id = i + 1
		if i < Tacterra.NATION_NAMES.size():
			n.name = Tacterra.NATION_NAMES[i]
		else:
			n.name = "Rival %d" % (i + 1)
		n.color = Tacterra.NATION_COLORS[(i + 1) % Tacterra.NATION_COLORS.size()]
		n.personality = pers[i % pers.size()]
		n.difficulty = int(s.settings["difficulty"])
		s.nations.append(n)

	# Map + capitals + starting territories.
	MapGenerator.generate(s)

	# Starting resources by preset.
	var preset: String = str(s.settings["preset"])
	var credits := 500.0
	var supplies := 200.0
	var troops := 300
	match preset:
		"poor":
			credits = 250.0
			supplies = 120.0
			troops = 180
		"rich":
			credits = 900.0
			supplies = 350.0
			troops = 450
	for n in s.nations:
		n.credits = credits
		n.supplies = supplies
		n.manpower = n.manpower_cap(s) * 0.5
		var cap := s.get_territory(n.capital_id)
		if cap != null:
			cap.army = ArmyData.create(n.id, troops, cap.id, 0.2)
	return s


# -------------------------------------------------------------------- tick --

## Advance the simulation by `days` game-days. FIXED order of operations:
## 1) day, 2) AI, 3) movement/combat, 4) economy, 5) supply recompute
## (incl. attrition inside SupplySim), 6) victory check, 7) trim feeds.
func tick(days: float) -> void:
	if over or days <= 0.0:
		return
	day += days
	for n in nations:
		if not n.is_player and not n.eliminated:
			AIBrain.tick(self, n, days)
	MovementSim.tick(self, days)
	EconomySim.tick(self, days)
	SupplySim.recompute(self)
	VictorySim.check(self)
	_trim_feeds()


func _trim_feeds() -> void:
	while notifications.size() > 60:
		notifications.pop_front()
	while battle_reports.size() > 20:
		battle_reports.pop_front()


# ------------------------------------------------------------------ orders --

static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


static func _ok() -> Dictionary:
	return {"ok": true, "error": ""}


## Movement cost multiplier per terrain (averaged over origin + destination).
static func terrain_move_cost(t: int) -> float:
	match t:
		Tacterra.Terrain.PLAINS:
			return 1.0
		Tacterra.Terrain.FERTILE:
			return 1.0
		Tacterra.Terrain.FOREST:
			return 1.2
		Tacterra.Terrain.HILLS:
			return 1.3
		Tacterra.Terrain.MOUNTAINS:
			return 1.6
		Tacterra.Terrain.DESERT:
			return 1.2
	return 1.0


## March `troops` from a stationed army to a neighboring territory.
func order_move(nation_id: int, from_id: int, to_id: int, troops: int) -> Dictionary:
	var n := get_nation(nation_id)
	if n == null:
		return _fail("Unknown nation.")
	if n.eliminated:
		return _fail("That nation is eliminated.")
	if over:
		return _fail("The match is over.")
	var tfrom := get_territory(from_id)
	if tfrom == null:
		return _fail("Unknown territory.")
	if tfrom.owner_id != nation_id:
		return _fail("You do not own that territory.")
	if not tfrom.neighbors.has(to_id):
		return _fail("Those territories are not connected.")
	if troops <= 0:
		return _fail("Must move at least 1 troop.")
	var st := tfrom.army
	if st == null or st.troops < troops:
		return _fail("Not enough troops stationed there.")
	var tto := get_territory(to_id)
	if tto == null:
		return _fail("Unknown destination.")
	var dist: float = tfrom.center.distance_to(tto.center)
	var cost := (terrain_move_cost(tfrom.terrain) + terrain_move_cost(tto.terrain)) * 0.5
	var total := maxf(0.1, dist / Tacterra.MOVE_SPEED * cost)
	var mv := ArmyData.new()
	mv.owner_id = nation_id
	mv.troops = troops
	mv.training = st.training
	mv.moving = true
	mv.move_from = from_id
	mv.move_to = to_id
	mv.territory_id = -1
	mv.move_progress = 0.0
	mv.move_total = total
	st.troops -= troops
	if st.troops <= 0:
		tfrom.army = null
	transits.append(mv)
	if n.is_player:
		add_notification("Marching %d troops: %s -> %s." % [troops, tfrom.name, tto.name],
			Tacterra.NotifyKind.INFO)
	return _ok()


## Spend credits + manpower to train troops at an owned territory.
## Troops arrive in `training_queues[territory_id]` after RECRUIT_TRAIN_DAYS.
func order_recruit(nation_id: int, territory_id: int, troops: int) -> Dictionary:
	var n := get_nation(nation_id)
	if n == null:
		return _fail("Unknown nation.")
	if n.eliminated:
		return _fail("That nation is eliminated.")
	if over:
		return _fail("The match is over.")
	var t := get_territory(territory_id)
	if t == null:
		return _fail("Unknown territory.")
	if t.owner_id != nation_id:
		return _fail("You do not own that territory.")
	if troops <= 0:
		return _fail("Must recruit at least 1 troop.")
	var cost := float(troops) * Tacterra.RECRUIT_COST
	if n.credits < cost:
		return _fail("Insufficient credits (need %s)." % Tacterra.format_num(cost))
	if n.manpower < float(troops):
		return _fail("Insufficient manpower.")
	n.credits -= cost
	n.manpower -= float(troops)
	if not training_queues.has(territory_id):
		training_queues[territory_id] = []
	var q: Array = training_queues[territory_id]
	q.append({"troops": troops, "days_left": Tacterra.RECRUIT_TRAIN_DAYS,
		"owner_id": nation_id})
	if n.is_player:
		add_notification("Recruiting %d troops at %s (%s credits)." % [troops, t.name,
			Tacterra.format_num(cost)], Tacterra.NotifyKind.INFO)
	return _ok()


func order_develop(nation_id: int, territory_id: int) -> Dictionary:
	var n := get_nation(nation_id)
	if n == null:
		return _fail("Unknown nation.")
	if n.eliminated:
		return _fail("That nation is eliminated.")
	if over:
		return _fail("The match is over.")
	var t := get_territory(territory_id)
	if t == null:
		return _fail("Unknown territory.")
	if t.owner_id != nation_id:
		return _fail("You do not own that territory.")
	var cost := t.develop_cost()
	if cost < 0.0:
		return _fail("Development is already at maximum level.")
	if n.credits < cost:
		return _fail("Insufficient credits (need %s)." % Tacterra.format_num(cost))
	n.credits -= cost
	t.development += 1
	if n.is_player:
		add_notification("%s developed to level %d." % [t.name, t.development],
			Tacterra.NotifyKind.GOOD)
	return _ok()


func order_fortify(nation_id: int, territory_id: int) -> Dictionary:
	var n := get_nation(nation_id)
	if n == null:
		return _fail("Unknown nation.")
	if n.eliminated:
		return _fail("That nation is eliminated.")
	if over:
		return _fail("The match is over.")
	var t := get_territory(territory_id)
	if t == null:
		return _fail("Unknown territory.")
	if t.owner_id != nation_id:
		return _fail("You do not own that territory.")
	var cost := t.fort_cost()
	if cost < 0.0:
		return _fail("Fortifications are already at maximum level.")
	if n.credits < cost:
		return _fail("Insufficient credits (need %s)." % Tacterra.format_num(cost))
	n.credits -= cost
	t.fort_level += 1
	if n.is_player:
		add_notification("%s fortified to level %d." % [t.name, t.fort_level],
			Tacterra.NotifyKind.GOOD)
	return _ok()


# ----------------------------------------------------------------- helpers --

func get_territory(tid: int) -> TerritoryData:
	if tid >= 0 and tid < territories.size():
		var fast := territories[tid]
		if fast.id == tid:
			return fast
	for t in territories:
		if t.id == tid:
			return t
	return null


func get_nation(nid: int) -> NationData:
	if nid >= 0 and nid < nations.size():
		var fast := nations[nid]
		if fast.id == nid:
			return fast
	for n in nations:
		if n.id == nid:
			return n
	return null


func player() -> NationData:
	if nations.is_empty():
		return null
	return nations[0]


func owned_ids(nid: int) -> Array[int]:
	var out: Array[int] = []
	for t in territories:
		if t.owner_id == nid:
			out.append(t.id)
	return out


## Stationed army only (null when empty). Transits are tracked separately.
func army_at(tid: int) -> ArmyData:
	var t := get_territory(tid)
	if t == null:
		return null
	return t.army


func add_notification(text: String, kind: int) -> void:
	notifications.append({"day": day, "text": text, "kind": kind})
	while notifications.size() > 60:
		notifications.pop_front()


func add_battle_report(d: Dictionary) -> void:
	battle_reports.append(d)
	while battle_reports.size() > 20:
		battle_reports.pop_front()


# ---------------------------------------------------------- serialization --

func to_dict() -> Dictionary:
	var terrs: Array = []
	for t in territories:
		terrs.append(t.to_dict())
	var nats: Array = []
	for n in nations:
		nats.append(n.to_dict())
	var trs: Array = []
	for a in transits:
		trs.append(a.to_dict())
	var tq: Array = []
	for key in training_queues.keys():
		var entries: Array = []
		for e in training_queues[key]:
			entries.append({
				"troops": int(e.get("troops", 0)),
				"days_left": float(e.get("days_left", 0.0)),
				"owner_id": int(e.get("owner_id", -1)),
			})
		tq.append({"territory_id": int(key), "queue": entries})
	return {
		"version": Tacterra.SAVE_VERSION,
		"day": day,
		"speed": speed,
		"settings": settings.duplicate(true),
		"over": over,
		"winner_id": winner_id,
		"player_won": player_won,
		"rng_seed": rng.seed if rng != null else 0,
		"territories": terrs,
		"nations": nats,
		"transits": trs,
		"training_queues": tq,
		"notifications": notifications.duplicate(true),
		"battle_reports": battle_reports.duplicate(true),
	}


## Lenient alias: returns the state, or null when the data is invalid.
static func from_dict(d: Dictionary) -> GameState:
	var r := load_dict(d)
	return r[0]


## Validated load. Returns [state: GameState, error: String].
## NEVER crashes on structural problems: returns [null, "reason"] instead.
static func load_dict(d) -> Array:
	if not (d is Dictionary):
		return [null, "save data is not a dictionary"]
	if int(d.get("version", -1)) != Tacterra.SAVE_VERSION:
		return [null, "incompatible version"]
	# Required scalar keys must be present AND correctly typed (JSON only
	# produces num/str/bool/null, so a wrong type here means a bad file).
	for k in ["day", "speed", "rng_seed", "winner_id"]:
		if not d.has(k) or not _is_num(d[k]):
			return [null, "missing or bad key: " + k]
	if not d.has("settings") or not (d["settings"] is Dictionary):
		return [null, "missing or bad key: settings"]
	for k in ["over", "player_won", "territories", "nations", "transits",
			"training_queues", "notifications", "battle_reports"]:
		if not d.has(k):
			return [null, "missing key: " + k]
	var terrs = d["territories"]
	var nats = d["nations"]
	var trs = d["transits"]
	var tq = d["training_queues"]
	var notifs = d["notifications"]
	var reps = d["battle_reports"]
	if not (terrs is Array) or terrs.is_empty():
		return [null, "save has no territories"]
	if not (nats is Array) or nats.is_empty():
		return [null, "save has no nations"]
	if not (trs is Array):
		return [null, "bad transits"]
	if not (tq is Array):
		return [null, "bad training queues"]
	if not (notifs is Array) or not (reps is Array):
		return [null, "bad notification log"]
	for td in terrs:
		var terr_err := _check_territory_dict(td)
		if terr_err != "":
			return [null, "bad territory: " + terr_err]
	for nd in nats:
		var nat_err := _check_nation_dict(nd)
		if nat_err != "":
			return [null, "bad nation: " + nat_err]
	for ad in trs:
		var army_err := _check_army_dict(ad)
		if army_err != "":
			return [null, "bad transit: " + army_err]
	for qe in tq:
		var q_err := _check_queue_entry(qe)
		if q_err != "":
			return [null, "bad training queue: " + q_err]

	var s := GameState.new()
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = int(d["rng_seed"])
	s.day = float(d["day"])
	s.speed = float(d["speed"])
	s.settings = (d["settings"] as Dictionary).duplicate(true)
	s.over = bool(d["over"])
	s.winner_id = int(d["winner_id"])
	s.player_won = bool(d["player_won"])
	for td in terrs:
		s.territories.append(TerritoryData.from_dict(td))
	for nd in nats:
		s.nations.append(NationData.from_dict(nd))
	for ad in trs:
		s.transits.append(ArmyData.from_dict(ad))
	for qe in tq:
		var tid := int(qe["territory_id"])
		var q: Array = []
		for e in qe["queue"]:
			q.append({"troops": int(e["troops"]), "days_left": float(e["days_left"]),
				"owner_id": int(e["owner_id"])})
		s.training_queues[tid] = q
	for rn in notifs:
		if rn is Dictionary:
			s.notifications.append(rn)
	for rb in reps:
		if rb is Dictionary:
			s.battle_reports.append(rb)
	return [s, ""]


## Pre-validation so nested from_dict() calls can never crash on bad saves.
## (their from_dict() implementations index into arrays and cast scalars.)
static func _is_num(v) -> bool:
	return v is int or v is float


static func _check_army_dict(d) -> String:
	if not (d is Dictionary):
		return "not a dictionary"
	for k in ["owner_id", "troops", "territory_id", "move_from", "move_to",
			"training", "move_progress", "move_total", "unsupplied_days"]:
		# NOTE: null is rejected too — their from_dict() calls int()/float()
		# on the raw value, and int(null) is a runtime error.
		if d.has(k) and not _is_num(d[k]):
			return "bad " + k
	return ""


static func _check_territory_dict(d) -> String:
	if not (d is Dictionary):
		return "not a dictionary"
	var poly = d.get("polygon", [])
	if not (poly is Array):
		return "bad polygon"
	for pv in poly:
		if not (pv is Array) or pv.size() < 2 \
				or not _is_num(pv[0]) or not _is_num(pv[1]):
			return "bad polygon point"
	var c = d.get("center", [])
	if not (c is Array) or c.size() < 2 or not _is_num(c[0]) or not _is_num(c[1]):
		return "bad center"
	var nb = d.get("neighbors", [])
	if not (nb is Array):
		return "bad neighbors"
	for nx in nb:
		if not _is_num(nx):
			return "bad neighbor id"
	var ad = d.get("army", null)
	if ad != null:
		var army_err := _check_army_dict(ad)
		if army_err != "":
			return "bad army: " + army_err
	return ""


static func _check_nation_dict(d) -> String:
	if not (d is Dictionary):
		return "not a dictionary"
	var c = d.get("color", null)
	if c != null:
		if not (c is Array) or c.size() < 4:
			return "bad color"
		for cv in c:
			if not _is_num(cv):
				return "bad color"
	for k in ["credits", "supplies", "manpower", "ai_cooldown"]:
		# null rejected: NationData.from_dict() casts these with float().
		if d.has(k) and not _is_num(d[k]):
			return "bad " + k
	var st = d.get("stats", null)
	if st != null and not (st is Dictionary):
		return "bad stats"
	return ""


static func _check_queue_entry(qe) -> String:
	if not (qe is Dictionary):
		return "not a dictionary"
	if not qe.has("territory_id") or not qe.has("queue"):
		return "missing fields"
	var q = qe["queue"]
	if not (q is Array):
		return "bad queue"
	for e in q:
		if not (e is Dictionary):
			return "bad entry"
		for ek in ["troops", "days_left", "owner_id"]:
			if not e.has(ek) or not _is_num(e[ek]):
				return "entry bad " + ek
	return ""
