class_name ArmyData
extends RefCounted
## A stack of troops. Stationed in a territory, or in transit between two.

var owner_id: int = -1
var troops: int = 0
var training: float = 0.0 ## 0..1, multiplies power by (1 + 0.5*training)
var territory_id: int = -1 ## stationed here when not moving
var moving: bool = false
var move_from: int = -1
var move_to: int = -1
var move_progress: float = 0.0 ## days elapsed
var move_total: float = 1.0 ## days required
var unsupplied_days: float = 0.0


static func create(p_owner: int, p_troops: int, p_territory: int, p_training: float = 0.0) -> ArmyData:
	var a := ArmyData.new()
	a.owner_id = p_owner
	a.troops = p_troops
	a.territory_id = p_territory
	a.training = clampf(p_training, 0.0, 1.0)
	return a


## Effective combat power. def_mult includes terrain/fort/river/defender bonus.
func power(def_mult: float, supplied: bool) -> float:
	var p := float(troops) * (1.0 + 0.5 * training) * def_mult
	if not supplied:
		p *= Tacterra.UNSUPPLIED_POWER
	return p


func to_dict() -> Dictionary:
	return {
		"owner_id": owner_id, "troops": troops, "training": training,
		"territory_id": territory_id, "moving": moving,
		"move_from": move_from, "move_to": move_to,
		"move_progress": move_progress, "move_total": move_total,
		"unsupplied_days": unsupplied_days,
	}


static func from_dict(d: Dictionary) -> ArmyData:
	var a := ArmyData.new()
	a.owner_id = int(d.get("owner_id", -1))
	a.troops = int(d.get("troops", 0))
	a.training = clampf(float(d.get("training", 0.0)), 0.0, 1.0)
	a.territory_id = int(d.get("territory_id", -1))
	a.moving = bool(d.get("moving", false))
	a.move_from = int(d.get("move_from", -1))
	a.move_to = int(d.get("move_to", -1))
	a.move_progress = float(d.get("move_progress", 0.0))
	a.move_total = maxf(0.1, float(d.get("move_total", 1.0)))
	a.unsupplied_days = float(d.get("unsupplied_days", 0.0))
	return a
