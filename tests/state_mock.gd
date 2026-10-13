class_name StateMock
extends RefCounted
## Test-only stand-in for GameState (which is built in parallel).
## Implements exactly the documented GameState fields/methods the simulation
## subsystems use, plus small fixture builders. NOT part of the game.
## Named state_mock.gd (not test_*.gd) so the test runner skips it.

var territories: Array = []
var nations: Array = []
var transits: Array = []
var day: float = 0.0
var speed: float = 1.0
var settings: Dictionary = {}
var over: bool = false
var winner_id: int = -1
var last_ownership_change_day: float = 0.0
var player_won: bool = false
var notifications: Array = []
var battle_reports: Array = []
var rng := RandomNumberGenerator.new()
var training_queues: Dictionary = {}


func get_territory(tid: int):
	for t in territories:
		if t.id == tid:
			return t
	return null


func get_nation(nid: int):
	for n in nations:
		if n.id == nid:
			return n
	return null


func player():
	return get_nation(0)


func owned_ids(nid: int) -> Array:
	var out: Array = []
	for t in territories:
		if t.owner_id == nid:
			out.append(t.id)
	return out


func army_at(tid: int):
	var t = get_territory(tid)
	return t.army if t != null else null


func add_notification(text: String, kind: int) -> void:
	notifications.append({"day": day, "text": text, "kind": kind})


func add_battle_report(d: Dictionary) -> void:
	battle_reports.append(d)


static func make_state() -> StateMock:
	var s := StateMock.new()
	s.rng.seed = 12345
	s.settings = {"map_size": 1, "ai_count": 1, "difficulty": 1,
		"preset": "standard", "speed": 1.0}
	return s


static func make_territory(tid: int, owner: int, terrain: int, neighbors: Array,
		population: int = 100, garrison: int = 0) -> TerritoryData:
	var t := TerritoryData.new()
	t.id = tid
	t.name = "Terr%d" % tid
	t.owner_id = owner
	t.terrain = terrain
	t.neighbors.assign(neighbors)
	t.population = population
	t.garrison = garrison
	t.center = Vector2(float(tid) * 700.0, 0.0)
	return t


static func make_nation(nid: int, pname: String, is_player: bool, capital: int) -> NationData:
	var n := NationData.new()
	n.id = nid
	n.name = pname
	n.is_player = is_player
	n.capital_id = capital
	n.credits = 500.0
	n.supplies = 200.0
	n.manpower = 50.0
	return n


static func station(state: StateMock, tid: int, owner: int, troops: int,
		training: float = 0.0) -> ArmyData:
	var t = state.get_territory(tid)
	var a := ArmyData.create(owner, troops, tid, training)
	t.army = a
	return a


static func launch(state: StateMock, owner: int, from_id: int, to_id: int,
		troops: int, total: float = 2.0) -> ArmyData:
	var a := ArmyData.create(owner, troops, from_id)
	a.moving = true
	a.move_from = from_id
	a.move_to = to_id
	a.move_progress = 0.0
	a.move_total = total
	state.transits.append(a)
	return a


static func has_notification(state: StateMock, kind: int, substr: String) -> bool:
	for n in state.notifications:
		if int(n.get("kind", -1)) == kind \
				and str(n.get("text", "")).contains(substr):
			return true
	return false
