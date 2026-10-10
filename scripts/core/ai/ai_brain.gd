class_name AIBrain
extends RefCounted
## Enemy AI "brain" for TACTERRA RPG.
##
## Called from GameState.tick for every non-eliminated, non-player nation.
## The AI issues ONLY the same order_* methods the human player uses
## (order_move / order_recruit / order_develop / order_fortify) — no free
## resources, no hidden information beyond visible armies, no cheating.
## Failed orders are skipped gracefully; the AI never touches player fields.
##
## Personalities emerge from different weights, not labels:
## - EXPANSIONIST: balanced thresholds, steady growth.
## - DEFENSIVE: fortifies threatened borders, keeps smaller armies, reinforces
##   threatened borders FIRST (before expanding/attacking) and commits 50%
##   more troops to defensive moves.
## - AGGRESSIVE: 20% larger army target, attacks at a lower power ratio.
##
## Difficulty changes think frequency, army targets and attack caution:
## EASY thinks every 5d, NORMAL every 3d, HARD every 2d;
## attack thresholds 2.2 / 1.6 / 1.35; recruit multipliers 0.6 / 1.0 / 1.2.
## HARD additionally picks the weakest valid target, refuses river-into-
## mountain assaults without overwhelming odds, and reinforces territories
## that have enemy armies inbound.

# --- tuning (documented, no magic numbers elsewhere) ---
const ECONOMY_MIN_CREDITS := 400.0 ## think about economy only above this
const RECRUIT_RESERVE_CREDITS := 100.0 ## never spend the nation below this
const RECRUIT_MANPOWER_MIN := 50.0 ## don't recruit from an empty pool
const EXPAND_RATIO := 1.2 ## needed local superiority vs neutral garrison
const EXPAND_MIN_TROOPS := 40 ## never strip a territory below this to expand
const EXPAND_SEND_FRAC := 0.8 ## fraction of the stack sent on expansion
const KILL_FOCUS_TERRITORIES := 5 ## focus-fire rivals at or below this size
const ATTACK_SEND_FRAC := 0.8 ## fraction of the stack sent on attack
const ENEMY_TRAINING_ASSUMED := 0.2 ## enemy training is unknown; AI assumes this
const DEFENSE_MAX_MOVES := 3 ## defensive redeployments per think, at most
const DEFENSE_DONOR_MIN := 60 ## interior donor must hold more than this
const DEFENSE_LEAVE_BEHIND := 40 ## troops left in a donor territory
const INTERCEPT_DONOR_MIN := 40
const INTERCEPT_SEND_CAP := 150
const INTERCEPT_MAX_MOVES := 2

const _RECRUIT_MULT := {
	Tacterra.Personality.EXPANSIONIST: 1.0,
	Tacterra.Personality.DEFENSIVE: 0.9,
	Tacterra.Personality.AGGRESSIVE: 1.2,
}
const _ATTACK_ADJ := {
	Tacterra.Personality.EXPANSIONIST: 0.0,
	Tacterra.Personality.DEFENSIVE: 0.3,
	Tacterra.Personality.AGGRESSIVE: -0.15,
}


## Per-nation AI entry point. Called from GameState.tick.
static func tick(state: GameState, nation: NationData, days: float) -> void:
	if state == null or nation == null or nation.eliminated or nation.is_player:
		return
	nation.ai_cooldown -= days
	if nation.ai_cooldown > 0.0:
		return
	nation.ai_cooldown = float(Tacterra.AI_THINK_DAYS.get(nation.difficulty, 3.0))
	_think(state, nation)


static func _think(state: GameState, nation: NationData) -> void:
	var owned: Array[int] = state.owned_ids(nation.id)
	if owned.is_empty():
		return # landless (or data error): nothing to order, never crash
	_think_economy(state, nation, owned)
	_think_recruit(state, nation, owned)
	var defensive: bool = nation.personality == Tacterra.Personality.DEFENSIVE
	if defensive:
		_think_defense(state, nation, owned) # DEFENSIVE secures borders first
	_think_stage(state, nation, owned) # move reserves to expansion fronts
	_think_expand(state, nation, owned)
	_think_stage_attack(state, nation, owned) # concentrate for plausible attacks
	_think_attack(state, nation, owned)
	if not defensive:
		_think_defense(state, nation, owned)
	if nation.difficulty == Tacterra.Difficulty.HARD:
		_think_intercept(state, nation, owned)


# ---------------------------------------------------------------- economy ---
## 1. Spend surplus credits on development; DEFENSIVE nations fortify their
## cheapest threatened border fort instead.
static func _think_economy(state: GameState, nation: NationData, owned: Array[int]) -> void:
	if nation.credits <= ECONOMY_MIN_CREDITS:
		return
	if nation.personality == Tacterra.Personality.DEFENSIVE:
		var fort_id := -1
		var fort_cost := INF
		for tid in owned:
			var t := state.get_territory(tid)
			if t == null or t.fort_level >= Tacterra.FORT_MAX:
				continue
			if not _adjacent_to_enemy(state, t, nation.id):
				continue
			var c := t.fort_cost()
			if c >= 0.0 and c <= nation.credits * 0.5 and c < fort_cost:
				fort_cost = c
				fort_id = tid
		if fort_id >= 0:
			state.order_fortify(nation.id, fort_id)
			return
	var dev_id := -1
	var dev_inc := -1.0
	for tid in owned:
		var t := state.get_territory(tid)
		if t == null or t.development >= Tacterra.DEVELOP_MAX:
			continue
		var c := t.develop_cost()
		if c < 0.0 or c > nation.credits * 0.5:
			continue
		var inc := t.income_per_day()
		if inc > dev_inc:
			dev_inc = inc
			dev_id = tid
	if dev_id >= 0:
		state.order_develop(nation.id, dev_id)


# ---------------------------------------------------------------- recruit ---
## 2. Recruit toward a personality/difficulty-scaled army target, keeping a
## credit reserve. Recruits at the capital, or the most populous owned
## territory when the capital is lost.
static func _think_recruit(state: GameState, nation: NationData, owned: Array[int]) -> void:
	var pers_mult: float = float(_RECRUIT_MULT.get(nation.personality, 1.0))
	var diff_mult: float = float(Tacterra.AI_RECRUIT_MULT.get(nation.difficulty, 1.0))
	var target := 120.0 * float(owned.size()) * pers_mult * diff_mult
	var current := _count_troops(state, nation)
	if current >= target:
		return
	if nation.manpower <= RECRUIT_MANPOWER_MIN:
		return
	var batch: int = mini(mini(
		int(target - current),
		int(nation.manpower * 0.5)),
		int(nation.credits / (Tacterra.RECRUIT_COST * 1.5)))
	batch = mini(batch, int(maxf(0.0, nation.credits - RECRUIT_RESERVE_CREDITS) / Tacterra.RECRUIT_COST))
	if batch <= 0:
		return
	var at := _recruit_territory(state, nation, owned)
	if at < 0:
		return
	state.order_recruit(nation.id, at, batch)


## Every troop the nation owns: stationed + in transit + still training.
static func _count_troops(state: GameState, nation: NationData) -> float:
	var total := 0.0
	for tid in state.owned_ids(nation.id):
		var a := state.army_at(tid)
		if a != null and a.owner_id == nation.id:
			total += float(a.troops)
	for tr in state.transits:
		if tr.owner_id == nation.id:
			total += float(tr.troops)
	for q in state.training_queues.values():
		if q is Array:
			for entry in q:
				if entry is Dictionary and int(entry.get("owner_id", -1)) == nation.id:
					total += float(entry.get("troops", 0))
	return total


static func _recruit_territory(state: GameState, nation: NationData, owned: Array[int]) -> int:
	if nation.capital_id >= 0:
		var cap := state.get_territory(nation.capital_id)
		if cap != null and cap.owner_id == nation.id:
			return nation.capital_id
	# Capital lost or missing: fall back to the most populous owned territory.
	var best := -1
	var best_pop := -1
	for tid in owned:
		var t := state.get_territory(tid)
		if t != null and t.population > best_pop:
			best_pop = t.population
			best = tid
	return best


# ------------------------------------------------------------------ stage ---
## 2b. Stage troops toward expansion fronts. Expansion and attack orders can
## only launch from territories that already hold troops, so without staging
## reserves would sit in the capital forever. For each owned territory next to
## a takeable neutral, pull troops from the richest ADJACENT owned donor until
## the staging territory can overmatch the garrison.
static func _think_stage(state: GameState, nation: NationData, owned: Array[int]) -> void:
	var moves := 0
	for tid in owned:
		if moves >= 2:
			break
		var t := state.get_territory(tid)
		if t == null:
			continue
		# Weakest takeable neutral neighbor determines the requirement.
		var need := -1.0
		for nid in t.neighbors:
			var nt := state.get_territory(nid)
			if nt == null or nt.owner_id != -1:
				continue
			var req := float(nt.garrison) * nt.defense_mult() * EXPAND_RATIO \
				+ float(EXPAND_MIN_TROOPS)
			if need < 0.0 or req < need:
				need = req
		if need < 0.0:
			continue # no neutral neighbor
		var have := 0
		var sa := state.army_at(tid)
		if sa != null and sa.owner_id == nation.id:
			have = sa.troops
		if float(have) >= need:
			continue # already staged; the expand step handles it
		# Pull from adjacent owned donors, strongest first, until staged.
		var donors: Array = []
		for did in t.neighbors:
			var dt := state.get_territory(did)
			if dt == null or dt.owner_id != nation.id:
				continue
			var da := state.army_at(did)
			if da != null and da.owner_id == nation.id \
					and da.troops > EXPAND_MIN_TROOPS:
				donors.append(did)
		donors.sort_custom(func(a, b):
			return state.army_at(a).troops > state.army_at(b).troops)
		var staged := false
		for did in donors:
			if float(have) >= need:
				break
			var da := state.army_at(did)
			if da == null:
				continue
			var send := mini(da.troops - EXPAND_MIN_TROOPS,
				int(need) - have + EXPAND_MIN_TROOPS)
			if send < 20:
				continue
			var res: Dictionary = state.order_move(nation.id, did, tid, send)
			if bool(res.get("ok", false)):
				have += send
				staged = true
		if staged:
			moves += 1


# ----------------------------------------------------------------- expand ---
## 3. Seize adjacent neutral territories where the local stack overmatches the
## garrison (troops > garrison * defense_mult * 1.3). One order per think on
## EASY, two on NORMAL/HARD.
static func _think_expand(state: GameState, nation: NationData, owned: Array[int]) -> void:
	var limit := 1
	if nation.difficulty != Tacterra.Difficulty.EASY:
		limit = 2
	var done := 0
	for tid in owned:
		if done >= limit:
			break
		var t := state.get_territory(tid)
		if t == null:
			continue
		var army := state.army_at(tid)
		if army == null or army.owner_id != nation.id or army.troops <= EXPAND_MIN_TROOPS:
			continue
		for nid in t.neighbors:
			if done >= limit:
				break
			var nt := state.get_territory(nid)
			if nt == null or nt.owner_id != -1:
				continue # neutral expansion only; wars are step 4
			if float(army.troops) > float(nt.garrison) * nt.defense_mult() * EXPAND_RATIO:
				var send := int(float(army.troops) * EXPAND_SEND_FRAC)
				if send <= 0:
					continue
				var res: Dictionary = state.order_move(nation.id, tid, nid, send)
				if bool(res.get("ok", false)):
					done += 1
					army = state.army_at(tid) # refresh: the stack just shrank
					if army == null or army.troops <= EXPAND_MIN_TROOPS:
						break


# ---------------------------------------------------------- stage_attack ---
## 3b. Concentrate for plausible attacks. Like expansion staging, but aimed at
## enemy neighbors: pull adjacent donors to a border territory when the
## shortfall to the attack threshold looks closable, so _think_attack can fire.
static func _think_stage_attack(state: GameState, nation: NationData, owned: Array[int]) -> void:
	var threshold: float = float(Tacterra.AI_ATTACK_THRESHOLD.get(nation.difficulty, 1.4))
	threshold += float(_ATTACK_ADJ.get(nation.personality, 0.0))
	var moves := 0
	for tid in owned:
		if moves >= 2:
			break
		var t := state.get_territory(tid)
		if t == null:
			continue
		var army := state.army_at(tid)
		var atk_power := 0.0
		if army != null and army.owner_id == nation.id:
			atk_power = army.power(1.0, t.supplied)
		# Weakest enemy neighbor by estimated defense.
		var best_eid := -1
		var best_est := INF
		for eid in t.neighbors:
			var et := state.get_territory(eid)
			if et == null or et.owner_id == -1 or et.owner_id == nation.id:
				continue
			var est := _estimate_defense(state, et)
			if est < best_est:
				best_est = est
				best_eid = eid
		if best_eid < 0:
			continue
		var need := best_est * threshold + 40.0 - atk_power
		if need <= 0.0:
			continue # already strong enough; attack step handles it
		if need > atk_power * 2.0 + 200.0:
			continue # hopeless even concentrated; don't bleed the border
		var donors: Array = []
		for did in t.neighbors:
			var dt := state.get_territory(did)
			if dt == null or dt.owner_id != nation.id:
				continue
			var da := state.army_at(did)
			if da != null and da.owner_id == nation.id \
					and da.troops > EXPAND_MIN_TROOPS:
				donors.append(did)
		donors.sort_custom(func(a, b):
			return state.army_at(a).troops > state.army_at(b).troops)
		var staged := false
		for did in donors:
			if need <= 0.0:
				break
			var da := state.army_at(did)
			if da == null:
				continue
			var send := mini(da.troops - EXPAND_MIN_TROOPS, int(need) + EXPAND_MIN_TROOPS)
			if send < 20:
				continue
			var res: Dictionary = state.order_move(nation.id, did, tid, send)
			if bool(res.get("ok", false)):
				need -= float(send)
				staged = true
		if staged:
			moves += 1


# ----------------------------------------------------------------- attack ---
## 4. Attack adjacent enemy territories when the estimated power ratio beats
## the difficulty/personality threshold. HARD picks the weakest valid target
## and refuses river-into-mountain assaults without overwhelming odds.
static func _think_attack(state: GameState, nation: NationData, owned: Array[int]) -> void:
	var threshold: float = float(Tacterra.AI_ATTACK_THRESHOLD.get(nation.difficulty, 1.6))
	threshold += float(_ATTACK_ADJ.get(nation.personality, 0.0))
	var hard: bool = nation.difficulty == Tacterra.Difficulty.HARD
	var limit := 2 if hard else 1
	var cands: Array = [] # [from_id, to_id, est_def_power]
	for tid in owned:
		var t := state.get_territory(tid)
		if t == null:
			continue
		var army := state.army_at(tid)
		if army == null or army.owner_id != nation.id or army.troops <= 0:
			continue
		var atk_power := army.power(1.0, t.supplied)
		for eid in t.neighbors:
			var et := state.get_territory(eid)
			if et == null or et.owner_id == -1 or et.owner_id == nation.id:
				continue
			var est := _estimate_defense(state, et)
			var ratio := atk_power / maxf(1.0, est)
			if ratio <= threshold:
				continue
			if hard and et.has_river and et.terrain == Tacterra.Terrain.MOUNTAINS \
					and ratio <= threshold + 0.4:
				continue # documented HARD caution
			cands.append([tid, eid, est])
	if cands.is_empty():
		return
	# Kill focus: when a bordered rival is down to a few territories, finish it
	# instead of scattering attacks. This is what lets matches actually end.
	var prey := _weakest_bordered_enemy(state, nation, cands)
	if prey >= 0:
		var focused: Array = []
		for c in cands:
			var et := state.get_territory(int(c[1]))
			if et != null and et.owner_id == prey:
				focused.append(c)
		if not focused.is_empty():
			cands = focused
	if hard:
		cands.sort_custom(func(a, b): return float(a[2]) < float(b[2])) # weakest first
	var done := 0
	for c in cands:
		if done >= limit:
			break
		var from_id := int(c[0])
		var to_id := int(c[1])
		var army := state.army_at(from_id)
		if army == null or army.owner_id != nation.id or army.troops <= 0:
			continue
		var send := int(float(army.troops) * ATTACK_SEND_FRAC)
		if send <= 0:
			continue
		var res: Dictionary = state.order_move(nation.id, from_id, to_id, send)
		if bool(res.get("ok", false)):
			done += 1


## Weakest bordered rival nation id, or -1 when no rival is weak enough to
## focus-fire (more than KILL_FOCUS_TERRITORIES territories). Only nations we
## actually border (appear as a candidate target) are considered.
static func _weakest_bordered_enemy(state: GameState, nation: NationData, cands: Array) -> int:
	var bordered := {}
	for c in cands:
		var et := state.get_territory(int(c[1]))
		if et != null and et.owner_id != -1 and et.owner_id != nation.id:
			bordered[et.owner_id] = true
	var prey := -1
	var prey_count := 999
	for eid in bordered.keys():
		var n := state.get_nation(int(eid))
		if n == null or n.eliminated:
			continue
		var count := state.owned_ids(n.id).size()
		if count <= KILL_FOCUS_TERRITORIES and count < prey_count:
			prey_count = count
			prey = n.id
	return prey


## Estimated defensive power of a territory as seen by an attacker.
## Enemy training is not scouted precisely, so the AI assumes a modest
## ENEMY_TRAINING_ASSUMED level (documented interpretation of the spec).
static func _estimate_defense(state: GameState, def_t: TerritoryData) -> float:
	var troops := 0.0
	var ea := state.army_at(def_t.id)
	if ea != null and ea.owner_id == def_t.owner_id:
		troops = float(ea.troops)
	var train_factor := 1.0 + 0.5 * ENEMY_TRAINING_ASSUMED
	return troops * train_factor * def_t.defense_mult() * Tacterra.DEFENDER_BONUS


# ---------------------------------------------------------------- defense ---
## 5. Shift troops from safe interior donors to threatened borders.
## A border is threatened when a neighboring enemy army's power exceeds
## 1.2x the stationed defensive power.
static func _think_defense(state: GameState, nation: NationData, owned: Array[int]) -> void:
	var defensive: bool = nation.personality == Tacterra.Personality.DEFENSIVE
	var moves := 0
	for tid in owned:
		if moves >= DEFENSE_MAX_MOVES:
			break
		var t := state.get_territory(tid)
		if t == null:
			continue
		var threat := _threat_troops_at(state, t, nation.id)
		if threat <= 0:
			continue
		var own_troops := 0
		var own_army := state.army_at(tid)
		if own_army != null and own_army.owner_id == nation.id:
			own_troops = own_army.troops
		var needed := maxi(0, int(float(threat) * 1.3) - own_troops)
		if needed <= 0:
			continue
		var donor := _find_donor(state, nation, owned, t)
		if donor < 0:
			continue
		var darmy := state.army_at(donor)
		if darmy == null:
			continue
		var amount := mini(darmy.troops - DEFENSE_LEAVE_BEHIND, needed)
		if defensive:
			amount = int(float(amount) * 1.5) # DEFENSIVE commits reserves
		amount = clampi(amount, 0, darmy.troops)
		if amount < 10:
			continue
		var res: Dictionary = state.order_move(nation.id, donor, tid, amount)
		if bool(res.get("ok", false)):
			moves += 1


## Strongest neighboring enemy army troop count threatening `t`, or 0 when the
## border holds (enemy power <= 1.2x our stationed defensive power).
static func _threat_troops_at(state: GameState, t: TerritoryData, nid: int) -> int:
	var own_power := 0.0
	var oa := state.army_at(t.id)
	if oa != null and oa.owner_id == nid:
		own_power = oa.power(t.defense_mult(), t.supplied)
	var worst := 0
	for eid in t.neighbors:
		var et := state.get_territory(eid)
		if et == null:
			continue
		if et.owner_id == -1 or et.owner_id == nid:
			continue
		var ea := state.army_at(eid)
		if ea == null or ea.owner_id != et.owner_id:
			continue
		if ea.power(1.0, et.supplied) > own_power * 1.2 and ea.troops > worst:
			worst = ea.troops
	return worst


## Safest interior donor for a threatened territory: owned, non-border (every
## neighbor friendly), holding > DEFENSE_DONOR_MIN troops. Prefers donors
## adjacent to the threatened territory (so order_move stays legal), then the
## largest stack, then the nearest.
static func _find_donor(state: GameState, nation: NationData, owned: Array[int], threatened: TerritoryData) -> int:
	var best := -1
	var best_score := -INF
	for tid in owned:
		if tid == threatened.id:
			continue
		var t := state.get_territory(tid)
		if t == null or _is_border(state, t, nation.id):
			continue
		var a := state.army_at(tid)
		if a == null or a.owner_id != nation.id or a.troops <= DEFENSE_DONOR_MIN:
			continue
		var score := float(a.troops) - t.center.distance_to(threatened.center) * 0.01
		if threatened.neighbors.has(tid):
			score += 100000.0 # adjacency keeps the move order legal
		if score > best_score:
			best_score = score
			best = tid
	return best


# --------------------------------------------------------------- intercept ---
## 6. HARD bonus: reinforce own territories that have enemy armies inbound.
## The donor must be adjacent to the threatened territory for the move order
## to be legal.
static func _think_intercept(state: GameState, nation: NationData, owned: Array[int]) -> void:
	var done := 0
	for tr in state.transits:
		if done >= INTERCEPT_MAX_MOVES:
			break
		if tr.owner_id == nation.id or tr.owner_id == -1:
			continue
		var target := state.get_territory(tr.move_to)
		if target == null or target.owner_id != nation.id:
			continue
		var best := -1
		var best_score := -INF
		for tid in owned:
			if tid == tr.move_to:
				continue
			var a := state.army_at(tid)
			if a == null or a.owner_id != nation.id or a.troops <= INTERCEPT_DONOR_MIN:
				continue
			var t := state.get_territory(tid)
			if t == null or not t.neighbors.has(tr.move_to):
				continue # non-adjacent reinforcement could never arrive
			var score := float(a.troops) - t.center.distance_to(target.center)
			if score > best_score:
				best_score = score
				best = tid
		if best < 0:
			continue
		var darmy := state.army_at(best)
		var amount := mini(darmy.troops - INTERCEPT_DONOR_MIN, INTERCEPT_SEND_CAP)
		if amount <= 0:
			continue
		var res: Dictionary = state.order_move(nation.id, best, tr.move_to, amount)
		if bool(res.get("ok", false)):
			done += 1


# ----------------------------------------------------------------- helpers ---
## True when any neighbor of `t` is not owned by `nid` (neutral or enemy).
static func _is_border(state: GameState, t: TerritoryData, nid: int) -> bool:
	for nb in t.neighbors:
		var nt := state.get_territory(nb)
		if nt != null and nt.owner_id != nid:
			return true
	return false


## True when any neighbor of `t` is owned by a rival nation.
static func _adjacent_to_enemy(state: GameState, t: TerritoryData, nid: int) -> bool:
	for nb in t.neighbors:
		var nt := state.get_territory(nb)
		if nt != null and nt.owner_id != -1 and nt.owner_id != nid:
			return true
	return false
