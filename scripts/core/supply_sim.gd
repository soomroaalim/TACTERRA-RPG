class_name SupplySim
extends RefCounted
## Supply-line simulation for TACTERRA RPG.
##
## `state` is duck-typed to the documented GameState API (see economy_sim.gd
## header for the rationale).
##
## recompute(state): BFS from each non-eliminated nation's capital through
##   territories owned by that nation; sets TerritoryData.supplied. Neutral
##   territories are always marked unsupplied (irrelevant: their garrisons
##   are exempt from attrition by design). A nation whose capital is missing
##   or no longer owned has no supplied territories.
## apply_attrition(state, days): the second half of the supply step. It needs
##   the day delta, which recompute() does not receive, so it is a separate
##   static. GameState.tick MUST call BOTH, in order:
##       SupplySim.recompute(self)
##       SupplySim.apply_attrition(self, days)
##   (ARCHITECTURE.md tick order step 5: "recompute(self) then attrition".)
##   Stationed armies use their territory's supplied flag; in-transit armies
##   use their destination's flag, but only when the destination is owned by
##   the same nation (otherwise unsupplied). Past UNSUPPLIED_GRACE_DAYS an
##   army loses ATTRITION_PER_DAY troops/day (rounded up); a wiped-out army
##   is removed and the player is notified.


static func recompute(state) -> void:
	for t in state.territories:
		t.supplied = false
	for n in state.nations:
		if n.eliminated:
			continue
		if n.capital_id < 0:
			continue
		var cap = state.get_territory(n.capital_id)
		if cap == null or cap.owner_id != n.id:
			continue
		var visited := {}
		var queue: Array = [n.capital_id]
		visited[n.capital_id] = true
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			var ct = state.get_territory(cur)
			if ct == null:
				continue
			ct.supplied = true
			for nb in ct.neighbors:
				if visited.has(nb):
					continue
				var nt = state.get_territory(nb)
				if nt != null and nt.owner_id == n.id:
					visited[nb] = true
					queue.append(nb)


static func apply_attrition(state, days: float) -> void:
	if days <= 0.0:
		return
	for t in state.territories:
		var a = t.army
		if a == null:
			continue
		_attrit_one(a, t.supplied, days)
		if a.troops <= 0:
			t.army = null
			_notify_destroyed(state, a, "at " + t.name)
	var dead: Array = []
	for a in state.transits:
		_attrit_one(a, _transit_supplied(state, a), days)
		if a.troops <= 0:
			dead.append(a)
	for a in dead:
		state.transits.erase(a)
		_notify_destroyed(state, a, "in transit")


static func _attrit_one(a, supplied: bool, days: float) -> void:
	if supplied:
		a.unsupplied_days = 0.0
		return
	a.unsupplied_days += days
	if a.unsupplied_days > Tacterra.UNSUPPLIED_GRACE_DAYS and a.troops > 0:
		var loss := int(ceil(float(a.troops) * Tacterra.ATTRITION_PER_DAY * days))
		a.troops = maxi(0, a.troops - loss)


static func _transit_supplied(state, a) -> bool:
	var dest = state.get_territory(a.move_to)
	if dest == null:
		return true  # unknown destination: assume fine (documented)
	return dest.owner_id == a.owner_id and dest.supplied


static func _notify_destroyed(state, a, where: String) -> void:
	var n = state.get_nation(a.owner_id)
	if n != null and n.is_player:
		state.add_notification(
			"An army %s starved: cut off from supply." % where,
			Tacterra.NotifyKind.BAD)
