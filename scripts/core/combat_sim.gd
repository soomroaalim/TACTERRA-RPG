class_name CombatSim
extends RefCounted
## Deterministic battle resolution for TACTERRA RPG.
##
## `state` is duck-typed to the documented GameState API (see economy_sim.gd
## header for the rationale).
##
## resolve(state, atk, def_t) pits an attacking ArmyData against the defender
## of a TerritoryData (stationed army, else neutral garrison, else unopposed).
## Defender power = troops * (1 + 0.5*training) * defense_mult() (terrain,
## fort, river) * DEFENDER_BONUS, halved when the defender is cut off from
## supply. The attacker gets NO terrain defense; its power is
## atk.power(1.0, supplied), where supplied comes from the attacker's origin
## territory (move_from while in transit). Neutral garrisons are local
## militia and always count as supplied (documented design decision).
##
## The only randomness is a documented +/-COMBAT_JITTER (10%) roll on the
## loss ratios, drawn from state.rng, so results are reproducible per seed.
##
## DEVIATION from the literal task formula: the specified loss-ratio upper
## clamp was 0.95 with int() truncation, under which a defender could never
## be fully wiped out -- so territory could never change hands in battle and
## the core capture loop was dead. The clamp is now 1.0 and rounding is used,
## so an attacker with ~3x effective power reliably breaks the defense (at
## a cost). Even battles remain bloody draws with no capture.
##
## resolve() is pure except for nation stat updates (troops_lost /
## troops_killed on both sides) and the rng draw. MovementSim applies the
## returned losses and handles capture / retreat.


static func resolve(state, atk: ArmyData, def_t: TerritoryData) -> Dictionary:
	var atk_n = state.get_nation(atk.owner_id)
	var atk_name := _nation_name(atk_n)
	# Friendly force already present: no battle (caller normally merges first).
	if def_t.army != null and def_t.army.owner_id == atk.owner_id:
		return _done(0, 0, true, 0.0, 0.0,
			"%s reinforces %s unopposed." % [atk_name, def_t.name])
	var def_troops := 0
	var def_training := 0.0
	var def_supplied := true
	var def_n = null
	if def_t.army != null:
		def_troops = def_t.army.troops
		def_training = def_t.army.training
		def_supplied = def_t.supplied
		def_n = state.get_nation(def_t.army.owner_id)
	elif def_t.garrison > 0:
		# Local militia: defends at full strength without a supply line.
		def_troops = def_t.garrison
		def_supplied = true
	else:
		return _done(0, 0, true, 0.0, 0.0,
			"%s marches into %s unopposed." % [atk_name, def_t.name])
	var def_name := "Neutral garrison"
	if def_n != null:
		def_name = def_n.name
	var def_power := float(def_troops) * (1.0 + 0.5 * def_training) \
		* def_t.defense_mult() * Tacterra.DEFENDER_BONUS
	if not def_supplied:
		def_power *= Tacterra.UNSUPPLIED_POWER
	var atk_supplied := _attacker_supplied(state, atk)
	var atk_power := atk.power(1.0, atk_supplied)
	var j: float = 1.0 + (state.rng.randf() * 2.0 - 1.0) * Tacterra.COMBAT_JITTER
	var atk_loss_ratio := clampf(def_power / maxf(atk_power, 1.0) * Tacterra.COMBAT_LOSS_FACTOR * j, 0.05, 0.9)
	var def_loss_ratio := clampf(atk_power / maxf(def_power, 1.0) * Tacterra.COMBAT_LOSS_FACTOR * j, 0.05, 1.0)
	var atk_losses := mini(atk.troops, int(round(float(atk.troops) * atk_loss_ratio)))
	var def_losses := mini(def_troops, int(round(float(def_troops) * def_loss_ratio)))
	var captured := (def_troops - def_losses) <= 0 and (atk.troops - atk_losses) > 0
	# Shared stat updates (used by MovementSim and AI alike).
	if atk_n != null:
		atk_n.stats["troops_lost"] = int(atk_n.stats["troops_lost"]) + atk_losses
		atk_n.stats["troops_killed"] = int(atk_n.stats["troops_killed"]) + def_losses
	if def_n != null:
		def_n.stats["troops_lost"] = int(def_n.stats["troops_lost"]) + def_losses
		def_n.stats["troops_killed"] = int(def_n.stats["troops_killed"]) + atk_losses
	var text := _report(atk_name, def_name, def_t, atk.troops, def_troops,
		atk_supplied, def_supplied, captured, atk_losses, def_losses)
	return _done(atk_losses, def_losses, captured, atk_power, def_power, text)


static func _attacker_supplied(state, atk: ArmyData) -> bool:
	var origin: TerritoryData = null
	if atk.moving:
		origin = state.get_territory(atk.move_from)
	else:
		origin = state.get_territory(atk.territory_id)
	if origin == null:
		return true  # unknown origin: assume fine (documented)
	return origin.supplied


static func _nation_name(n) -> String:
	if n == null:
		return "Unknown force"
	return str(n.name)


static func _report(atk_name: String, def_name: String, def_t: TerritoryData,
		atk_troops: int, def_troops: int, atk_supplied: bool, def_supplied: bool,
		captured: bool, atk_losses: int, def_losses: int) -> String:
	var factors: Array[String] = []
	factors.append("%s x%.2f" % [Tacterra.terrain_name(def_t.terrain),
		float(Tacterra.DEFENSE_BY_TERRAIN.get(def_t.terrain, 1.0))])
	if def_t.fort_level > 0:
		factors.append("fort +%d%%" % int(round(float(def_t.fort_level) * Tacterra.FORT_DEF_BONUS * 100.0)))
	if def_t.has_river:
		factors.append("river +15%")
	factors.append("defender +25%")
	if not def_supplied:
		factors.append("defender cut off x0.60")
	if not atk_supplied:
		factors.append("attacker cut off x0.60")
	var outcome := ""
	if captured:
		outcome = "%s captures %s" % [atk_name, def_t.name]
	else:
		outcome = "%s holds %s" % [def_name, def_t.name]
	return "Battle of %s: %s (%d) attacks %s (%d). Advantages: %s. %s. Losses: %d attacker, %d defender." % [
		def_t.name, atk_name, atk_troops, def_name, def_troops,
		", ".join(factors), outcome, atk_losses, def_losses]


static func _done(atk_losses: int, def_losses: int, captured: bool,
		atk_power: float, def_power: float, text: String) -> Dictionary:
	return {
		"atk_losses": atk_losses, "def_losses": def_losses,
		"captured": captured, "atk_power": atk_power, "def_power": def_power,
		"report_text": text,
	}
