class_name VictorySim
extends RefCounted
## Elimination and match-end detection for TACTERRA RPG.
##
## `state` is duck-typed to the documented GameState API (see economy_sim.gd
## header for the rationale).
##
## check(state): any non-eliminated nation with zero territories is
## eliminated: its in-transit armies are removed, its training-queue entries
## are cleaned up, and a notification fires (BAD for the player, INFO
## otherwise). Then: player eliminated -> over/defeat (winner = surviving AI
## with the most territories, -1 if none); all AI eliminated while the player
## survives -> over/victory. Idempotent: returns immediately when state.over
## is already set, so end-game notifications fire exactly once.


static func check(state) -> void:
	if state.over:
		return
	# Never judge an uninitialised or empty world: with no territories every
	# nation would "own zero" and the match would end instantly by accident.
	if state.territories.is_empty() or state.nations.is_empty():
		return
	for n in state.nations:
		if n.eliminated:
			continue
		if state.owned_ids(n.id).is_empty():
			_eliminate(state, n)
	var p = state.player()
	if p == null:
		p = state.get_nation(0)
	if p != null and p.eliminated:
		state.over = true
		state.player_won = false
		state.winner_id = _strongest_ai(state)
		var wname := "no one"
		var w = state.get_nation(state.winner_id) if state.winner_id >= 0 else null
		if w != null:
			wname = w.name
		state.add_notification(
			"Defeat! Your nation has fallen. %s dominates Tacterra." % wname,
			Tacterra.NotifyKind.BAD)
		return
	var scenario: int = int(state.settings.get("scenario", 0))
	# Scenario victory checks (0=Skirmish, 1=Domination, 2=Survival).
	if scenario == 1 and p != null:
		var owned: int = state.owned_ids(p.id).size()
		var total: int = state.territories.size()
		if total > 0 and float(owned) / float(total) >= 0.6:
			state.over = true
			state.player_won = true
			state.winner_id = p.id
			state.add_notification(
				"Victory! You control %d%% of Tacterra." % int(100.0 * owned / total),
				Tacterra.NotifyKind.GOOD)
			return
	if scenario == 2 and p != null:
		if state.day >= 200.0:
			state.over = true
			state.player_won = true
			state.winner_id = p.id
			state.add_notification(
				"Victory! You survived 200 days against overwhelming odds.",
				Tacterra.NotifyKind.GOOD)
			return
	# Standard skirmish: eliminate all AI.
	var ai_alive := false
	for n in state.nations:
		if not n.is_player and not n.eliminated:
			ai_alive = true
			break
	if not ai_alive:
		state.over = true
		state.player_won = true
		state.winner_id = p.id if p != null else 0
		state.add_notification(
			"Victory! All rival nations have been defeated.",
			Tacterra.NotifyKind.GOOD)


static func _eliminate(state, n) -> void:
	n.eliminated = true
	n.capital_id = -1
	for a in state.transits.duplicate():
		if a.owner_id == n.id:
			state.transits.erase(a)
	for key in state.training_queues.keys():
		var arr: Array = state.training_queues[key]
		var kept: Array = []
		for e in arr:
			if int(e.get("owner_id", -1)) != n.id:
				kept.append(e)
		if kept.is_empty():
			state.training_queues.erase(key)
		else:
			state.training_queues[key] = kept
	if n.is_player:
		state.add_notification("Your nation has fallen.", Tacterra.NotifyKind.BAD)
	else:
		state.add_notification("%s has been eliminated." % n.name, Tacterra.NotifyKind.INFO)


static func _strongest_ai(state) -> int:
	var best_id := -1
	var best_count := -1
	for n in state.nations:
		if n.is_player or n.eliminated:
			continue
		var c: int = state.owned_ids(n.id).size()
		if c > best_count:
			best_count = c
			best_id = n.id
	return best_id
