class_name MovementSim
extends RefCounted
## Army movement and arrival resolution for TACTERRA RPG.
##
## `state` is duck-typed to the documented GameState API (see economy_sim.gd
## header for the rationale).
##
## tick(state, days): advances every transit's move_progress by days (armies
## whose owner was eliminated are removed). Arrivals resolve in order:
##   own territory      -> merge into the stationed army (troops added,
##                         training averaged weighted by troops)
##   neutral, no garrison -> peaceful capture
##   neutral garrison / enemy army -> CombatSim.resolve, then capture or
##     retreat.
## Ownership is re-evaluated at arrival, so mid-transit ownership changes are
## handled naturally. Every battle emits a battle report; the player gets a
## notification when involved. A failed attacker retreats to its origin if
## still friendly; otherwise the survivors are lost behind enemy lines
## (documented design decision).


static func tick(state, days: float) -> void:
	if days <= 0.0:
		return
	for a in state.transits.duplicate():
		var n = state.get_nation(a.owner_id)
		if n == null or n.eliminated:
			state.transits.erase(a)
			continue
		a.move_progress += days
	var arrivals: Array = []
	for a in state.transits.duplicate():
		if a.troops <= 0:
			state.transits.erase(a)
		elif a.move_progress >= a.move_total:
			arrivals.append(a)
	for a in arrivals:
		if state.transits.has(a):
			state.transits.erase(a)
			_arrive(state, a)


static func _arrive(state, a) -> void:
	var t: TerritoryData = state.get_territory(a.move_to)
	if t == null:
		_disband(state, a, "their destination vanished")
		return
	if t.owner_id == a.owner_id:
		if t.army == null:
			_station(state, a, t)
		elif t.army.owner_id == a.owner_id:
			_merge_into(t.army, a)
		else:
			_do_battle(state, a, t)  # inconsistent data: fight it out
	elif t.owner_id == -1:
		if t.garrison > 0 or (t.army != null and t.army.owner_id != a.owner_id):
			_do_battle(state, a, t)
		else:
			_capture(state, a, t, true)
	else:
		_do_battle(state, a, t)


static func _station(state, a, t: TerritoryData) -> void:
	a.moving = false
	a.territory_id = t.id
	a.move_from = -1
	a.move_to = -1
	a.move_progress = 0.0
	a.move_total = 1.0
	a.unsupplied_days = 0.0
	t.army = a


static func _merge_into(stationed, a) -> void:
	var total: int = stationed.troops + a.troops
	if total > 0:
		stationed.training = (stationed.training * float(stationed.troops) \
			+ a.training * float(a.troops)) / float(total)
	stationed.troops = total
	stationed.unsupplied_days = maxf(stationed.unsupplied_days, a.unsupplied_days)


static func _do_battle(state, a, t: TerritoryData) -> void:
	var atk_n: NationData = state.get_nation(a.owner_id)
	if atk_n == null:
		_disband(state, a, "their nation is gone")
		return
	var def_owner := -1
	if t.army != null and t.army.owner_id != a.owner_id:
		def_owner = t.army.owner_id
	elif t.owner_id != -1 and t.owner_id != a.owner_id:
		def_owner = t.owner_id
	var def_n: NationData = state.get_nation(def_owner) if def_owner >= 0 else null
	var res: Dictionary = CombatSim.resolve(state, a, t)
	var atk_losses := int(res["atk_losses"])
	var def_losses := int(res["def_losses"])
	a.troops = maxi(0, a.troops - atk_losses)
	if t.army != null and t.army.owner_id != a.owner_id:
		t.army.troops = maxi(0, t.army.troops - def_losses)
		if t.army.troops <= 0:
			t.army = null
	elif t.owner_id == -1:
		t.garrison = maxi(0, t.garrison - def_losses)
	var captured := bool(res["captured"])
	state.add_battle_report({
		"day": state.day, "text": str(res["report_text"]),
		"territory_id": t.id, "territory": t.name,
		"attacker": a.owner_id, "defender": def_owner,
		"atk_losses": atk_losses, "def_losses": def_losses,
		"captured": captured,
	})
	var atk_is_player := atk_n.is_player
	var def_is_player := def_n != null and def_n.is_player
	if captured:
		atk_n.stats["battles_won"] = int(atk_n.stats["battles_won"]) + 1
		if def_n != null:
			def_n.stats["battles_lost"] = int(def_n.stats["battles_lost"]) + 1
		if atk_is_player:
			state.add_notification(
				"Victory at %s! Enemy lost %d, we lost %d." % [t.name, def_losses, atk_losses],
				Tacterra.NotifyKind.BATTLE)
		elif def_is_player:
			state.add_notification(
				"We lost %s to %s!" % [t.name, atk_n.name],
				Tacterra.NotifyKind.BAD)
		_capture(state, a, t, false)
	else:
		atk_n.stats["battles_lost"] = int(atk_n.stats["battles_lost"]) + 1
		if def_n != null:
			def_n.stats["battles_won"] = int(def_n.stats["battles_won"]) + 1
		if atk_is_player:
			state.add_notification(
				"Attack on %s repelled. We lost %d." % [t.name, atk_losses],
				Tacterra.NotifyKind.BATTLE)
		elif def_is_player:
			state.add_notification(
				"%s defended against %s!" % [t.name, atk_n.name],
				Tacterra.NotifyKind.BATTLE)
		_retreat(state, a)


static func _capture(state, a, t: TerritoryData, peaceful: bool) -> void:
	var prev_owner := t.owner_id
	var atk_n: NationData = state.get_nation(a.owner_id)
	t.army = null
	t.garrison = 0
	t.owner_id = a.owner_id
	if t.is_capital:
		t.is_capital = false
		if prev_owner >= 0:
			_relocate_capital(state, prev_owner)
	_station(state, a, t)
	if atk_n != null:
		atk_n.stats["captured"] = int(atk_n.stats["captured"]) + 1
		if atk_n.is_player:
			var how := "unopposed" if peaceful else "in battle"
			state.add_notification(
				"Captured %s %s!" % [t.name, how],
				Tacterra.NotifyKind.GOOD)


static func _relocate_capital(state, nid: int) -> void:
	var n = state.get_nation(nid)
	if n == null or n.eliminated:
		return
	var owned: Array = state.owned_ids(nid)
	if owned.is_empty():
		n.capital_id = -1  # VictorySim will eliminate the nation
		return
	var best := -1
	var best_inc := -1.0
	for tid in owned:
		var tt: TerritoryData = state.get_territory(tid)
		if tt == null:
			continue
		var inc := tt.income_per_day()
		if inc > best_inc:
			best_inc = inc
			best = tid
	if best >= 0:
		var nt = state.get_territory(best)
		nt.is_capital = true
		n.capital_id = best


static func _retreat(state, a) -> void:
	if a.troops <= 0:
		return
	var home: TerritoryData = state.get_territory(a.move_from)
	if home != null and home.owner_id == a.owner_id:
		if home.army == null:
			_station(state, a, home)
		elif home.army.owner_id == a.owner_id:
			_merge_into(home.army, a)
		else:
			_disband(state, a, "their home territory was occupied")
	else:
		_disband(state, a, "they were cut off from home")


static func _disband(state, a, reason: String) -> void:
	var n = state.get_nation(a.owner_id)
	if n != null and n.is_player and a.troops > 0:
		state.add_notification(
			"An army of %d was lost: %s." % [a.troops, reason],
			Tacterra.NotifyKind.BAD)
