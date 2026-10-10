class_name NationData
extends RefCounted
## One player or AI nation.

var id: int = -1
var name: String = ""
var color: Color = Color.WHITE
var is_player: bool = false
var personality: int = Tacterra.Personality.EXPANSIONIST
var difficulty: int = -1 ## -1 for the human player
var credits: float = 0.0
var supplies: float = 0.0
var manpower: float = 0.0
var capital_id: int = -1
var eliminated: bool = false
var ai_cooldown: float = 0.0 ## days until the AI thinks again
var ai_objective: String = "" ## current war objective (EXPAND/WEAKEN/DEFEND/RECOVER)
var ai_memory := {"fail": {}} ## tactical memory: {"fail": {territory_id: day}}
var broke_warned: bool = false ## upkeep-debt notification latch
var stats := {
	"captured": 0, "battles_won": 0, "battles_lost": 0,
	"troops_lost": 0, "troops_killed": 0, "income_earned": 0.0,
}


func manpower_cap(state: GameState) -> float:
	var cap := 0.0
	for tid in state.owned_ids(id):
		cap += float(state.get_territory(tid).population) / float(Tacterra.MANPOWER_CAP_DIV)
	return cap


func to_dict() -> Dictionary:
	var c: Color = color
	return {
		"id": id, "name": name, "color": [c.r, c.g, c.b, c.a],
		"is_player": is_player, "personality": personality,
		"difficulty": difficulty, "credits": credits, "supplies": supplies,
		"manpower": manpower, "capital_id": capital_id,
		"eliminated": eliminated, "ai_cooldown": ai_cooldown,
		"stats": stats.duplicate(),
	}


static func from_dict(d: Dictionary) -> NationData:
	var n := NationData.new()
	n.id = int(d.get("id", -1))
	n.name = str(d.get("name", "Nation"))
	var c: Array = d.get("color", [1, 1, 1, 1])
	n.color = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
	n.is_player = bool(d.get("is_player", false))
	n.personality = int(d.get("personality", Tacterra.Personality.EXPANSIONIST))
	n.difficulty = int(d.get("difficulty", -1))
	n.credits = float(d.get("credits", 0.0))
	n.supplies = float(d.get("supplies", 0.0))
	n.manpower = float(d.get("manpower", 0.0))
	n.capital_id = int(d.get("capital_id", -1))
	n.eliminated = bool(d.get("eliminated", false))
	n.ai_cooldown = float(d.get("ai_cooldown", 0.0))
	var st: Dictionary = d.get("stats", {})
	for k in n.stats.keys():
		if st.has(k):
			n.stats[k] = st[k]
	return n
