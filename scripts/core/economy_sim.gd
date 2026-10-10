class_name EconomySim
extends RefCounted
## Per-day economic simulation for TACTERRA RPG.
##
## `state` is intentionally untyped: it is duck-typed to the documented
## GameState API (nations, territories, transits, training_queues,
## owned_ids(), get_territory(), get_nation(), add_notification()). This keeps
## the sim compilable and unit-testable independent of game_state.gd build
## order, and it works unchanged with the real GameState.
##
## Per tick, for each non-eliminated nation, in order:
##  1. income: sum of income_per_day() over owned territories -> credits and
##     stats["income_earned"].
##  2. manpower: regen toward cap, where cap = sum(population) /
##     MANPOWER_CAP_DIV over owned territories. The cap formula is inlined
##     here instead of calling NationData.manpower_cap(state) so this file
##     has no GameState type dependency; the formula is identical.
##  3. supplies: stockpile += (production - use) * days, clamped at >= 0.
##     An empty stockpile carries no direct penalty; attrition is driven by
##     SupplySim connectivity, per the architecture doc.
##  4. upkeep: troops * UPKEEP_PER_SOLDIER * days. If credits cover it, pay
##     and clear the broke latch; otherwise credits = 0 and every stationed
##     and in-transit army deserts DESERTION_PER_DAY (rounded, minimum 1
##     troop when the army has more than 10). The "treasury empty"
##     notification fires once per broke spell, player only.
##  5. training queues: entries count down by days; finished recruits join
##     the territory army (created when empty, weighted training merge
##     otherwise). If the queue owner no longer owns the territory, the
##     recruits are discarded (player gets a notification).


static func tick(state, days: float) -> void:
	if days <= 0.0:
		return
	for n in state.nations:
		if n.eliminated:
			continue
		_apply_income(state, n, days)
		_apply_manpower(state, n, days)
		_apply_supplies(state, n, days)
		_apply_upkeep(state, n, days)
	_apply_training_queues(state, days)


static func _apply_income(state, n, days: float) -> void:
	var inc := 0.0
	for tid in state.owned_ids(n.id):
		var t = state.get_territory(tid)
		if t != null:
			inc += t.income_per_day()
	inc *= days
	n.credits += inc
	n.stats["income_earned"] = float(n.stats["income_earned"]) + inc


static func _apply_manpower(state, n, days: float) -> void:
	var cap := 0.0
	for tid in state.owned_ids(n.id):
		var t = state.get_territory(tid)
		if t != null:
			cap += float(t.population) / float(Tacterra.MANPOWER_CAP_DIV)
	n.manpower = minf(cap, n.manpower + cap * Tacterra.MANPOWER_REGEN * days)


static func _apply_supplies(state, n, days: float) -> void:
	var prod := 0.0
	for tid in state.owned_ids(n.id):
		var t = state.get_territory(tid)
		if t != null:
			prod += t.supply_production()
	var troops := 0
	for tid in state.owned_ids(n.id):
		var t = state.get_territory(tid)
		if t != null and t.army != null:
			troops += t.army.troops
	for a in state.transits:
		if a.owner_id == n.id:
			troops += a.troops
	var delta := (prod - float(troops) * Tacterra.SUPPLY_USE_PER_SOLDIER) * days
	n.supplies = maxf(0.0, n.supplies + delta)


static func _apply_upkeep(state, n, days: float) -> void:
	var troops := 0
	var armies: Array = []
	for tid in state.owned_ids(n.id):
		var t = state.get_territory(tid)
		if t != null and t.army != null:
			troops += t.army.troops
			armies.append(t.army)
	for a in state.transits:
		if a.owner_id == n.id:
			troops += a.troops
			armies.append(a)
	var cost := float(troops) * Tacterra.UPKEEP_PER_SOLDIER * days
	if n.credits >= cost:
		n.credits -= cost
		n.broke_warned = false
		return
	# Treasury cannot cover upkeep: empty it, troops desert.
	n.credits = 0.0
	for a in armies:
		var loss := int(round(float(a.troops) * Tacterra.DESERTION_PER_DAY * days))
		if a.troops > 10:
			loss = maxi(loss, 1)
		a.troops = maxi(0, a.troops - loss)
	_remove_empty_armies(state, n.id)
	if not n.broke_warned:
		n.broke_warned = true
		if n.is_player:
			state.add_notification(
				"Treasury empty! Unpaid troops are deserting (-%d%%/day)." % int(round(Tacterra.DESERTION_PER_DAY * 100.0)),
				Tacterra.NotifyKind.BAD)


static func _remove_empty_armies(state, owner_id: int) -> void:
	for t in state.territories:
		if t.army != null and t.army.owner_id == owner_id and t.army.troops <= 0:
			t.army = null
	for a in state.transits.duplicate():
		if a.owner_id == owner_id and a.troops <= 0:
			state.transits.erase(a)


static func _apply_training_queues(state, days: float) -> void:
	for key in state.training_queues.keys():
		var tid := int(key)
		var arr: Array = state.training_queues[key]
		var remaining: Array = []
		for e in arr:
			var entry: Dictionary = e
			entry["days_left"] = float(entry.get("days_left", 0.0)) - days
			if float(entry["days_left"]) > 0.0:
				remaining.append(entry)
			else:
				_deliver_recruits(state, tid, entry)
		if remaining.is_empty():
			state.training_queues.erase(key)
		else:
			state.training_queues[key] = remaining


static func _deliver_recruits(state, tid: int, entry: Dictionary) -> void:
	var owner_id := int(entry.get("owner_id", -1))
	var troops := int(entry.get("troops", 0))
	if troops <= 0:
		return
	var n: NationData = state.get_nation(owner_id)
	var t: TerritoryData = state.get_territory(tid)
	if n == null or n.eliminated or t == null:
		return  # owner gone or territory gone: silently discard
	if t.owner_id != owner_id:
		if n.is_player:
			state.add_notification(
				"Recruits for %s were lost: the territory changed hands." % t.name,
				Tacterra.NotifyKind.BAD)
		return
	if t.army == null:
		t.army = ArmyData.create(owner_id, troops, tid, 0.0)
	elif t.army.owner_id == owner_id:
		var total: int = t.army.troops + troops
		# Fresh recruits have training 0: weighted average with veterans.
		t.army.training = (t.army.training * float(t.army.troops)) / float(total)
		t.army.troops = total
	else:
		# Should not happen (owner holds the territory but not its army).
		if n.is_player:
			state.add_notification(
				"Recruits for %s were lost: unexpected garrison." % t.name,
				Tacterra.NotifyKind.BAD)
