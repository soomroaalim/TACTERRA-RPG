extends RefCounted
## Tests for MapGenerator (scripts/core/map_generator.gd).
## Builds GameState instances manually, runs MapGenerator.generate(state),
## and validates the produced world. Run headless via tests/run_tests.gd.


static func _make_state(map_size: int, ai_count: int, seed: int) -> GameState:
	var state := GameState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	state.rng = rng
	state.settings = {
		"map_size": map_size,
		"ai_count": ai_count,
		"difficulty": Tacterra.Difficulty.NORMAL,
		"preset": "standard",
		"speed": 1.0,
	}
	var nations: Array[NationData] = []
	for i in range(1 + ai_count):
		var n := NationData.new()
		n.id = i
		n.name = Tacterra.NATION_NAMES[i % Tacterra.NATION_NAMES.size()]
		n.color = Tacterra.NATION_COLORS[i % Tacterra.NATION_COLORS.size()]
		n.is_player = (i == 0)
		n.personality = i % 3
		n.difficulty = -1 if i == 0 else Tacterra.Difficulty.NORMAL
		nations.append(n)
	state.nations = nations
	var terrs: Array[TerritoryData] = []
	state.territories = terrs
	return state


static func run() -> Array:
	var results: Array = []
	var check := func(name: String, passed: bool, note: String) -> void:
		results.append({"name": name, "passed": passed, "note": note})

	# ------------------------------------------------- standard map, fixed seed
	var state := _make_state(Tacterra.MapSize.STANDARD, 3, 1234567)
	MapGenerator.generate(state)
	var terrs: Array[TerritoryData] = state.territories
	var target := 36

	check.call("count_in_range", terrs.size() >= target * 0.8 and terrs.size() <= target * 1.35,
		"count=%d target=%d" % [terrs.size(), target])

	var poly_ok := true
	for t in terrs:
		if t.polygon.size() < 3:
			poly_ok = false
	check.call("polygons_have_3_points", poly_ok, "checked %d territories" % terrs.size())

	var ids_ok := true
	for i in range(terrs.size()):
		if terrs[i].id != i:
			ids_ok = false
	check.call("ids_sequential", ids_ok, "n=%d" % terrs.size())

	var sym_ok := true
	var sym_note := ""
	for t in terrs:
		for nb in t.neighbors:
			if nb < 0 or nb >= terrs.size():
				sym_ok = false
				sym_note = "bad neighbor id %d on %d" % [nb, t.id]
			elif nb == t.id:
				sym_ok = false
				sym_note = "self neighbor on %d" % t.id
			elif not terrs[nb].neighbors.has(t.id):
				sym_ok = false
				sym_note = "asymmetric %d<->%d" % [t.id, nb]
	check.call("neighbors_symmetric", sym_ok, sym_note)

	# Capitals: one per nation, distinct, flagged, owned by that nation.
	var caps: Array[int] = []
	for n in state.nations:
		caps.append(n.capital_id)
	var caps_ok := caps.size() == 4
	var seen := {}
	for ni in range(caps.size()):
		var c: int = caps[ni]
		if seen.has(c) or c < 0 or c >= terrs.size():
			caps_ok = false
		else:
			seen[c] = true
			var ct := terrs[c]
			if not ct.is_capital or ct.owner_id != state.nations[ni].id or not ct.has_city:
				caps_ok = false
	check.call("capitals_assigned", caps_ok, "caps=%s" % str(caps))

	var min_d := 1.0e18
	for i in range(caps.size()):
		for j in range(i + 1, caps.size()):
			min_d = minf(min_d, terrs[caps[i]].center.distance_to(terrs[caps[j]].center))
	check.call("capitals_spread", min_d >= 500.0, "min pairwise=%.0f" % min_d)

	var names := {}
	var dup := false
	for t in terrs:
		if names.has(t.name):
			dup = true
		names[t.name] = true
	check.call("names_unique", not dup and names.size() == terrs.size(), "unique=%d" % names.size())

	# Full land-graph connectivity from the player capital (supply/AI need it).
	var reached := {}
	var queue: Array[int] = [state.nations[0].capital_id]
	reached[queue[0]] = true
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		for nb in terrs[cur].neighbors:
			if not reached.has(nb):
				reached[nb] = true
				queue.append(nb)
	check.call("graph_connected", reached.size() == terrs.size(),
		"reached %d/%d" % [reached.size(), terrs.size()])

	# Polygon sanity: every cell contains its own seed center, and no
	# center lies inside another cell (guards against broken/overlapping
	# border polygons, which would break map rendering and click selection).
	var geo_ok := true
	var geo_note := ""
	for t in terrs:
		if not Geometry2D.is_point_in_polygon(t.center, t.polygon):
			geo_ok = false
			geo_note = "t%d misses own center" % t.id
			break
	if geo_ok:
		for i in range(terrs.size()):
			for j in range(terrs.size()):
				if i != j and Geometry2D.is_point_in_polygon(terrs[i].center, terrs[j].polygon):
					geo_ok = false
					geo_note = "t%d center inside t%d" % [i, j]
					break
			if not geo_ok:
				break
	check.call("polygon_geometry", geo_ok, geo_note if not geo_note.is_empty() else "all cells sane")

	var gar_ok := true
	for t in terrs:
		if t.owner_id < 0 and t.garrison <= 0:
			gar_ok = false
		if t.owner_id >= 0 and t.garrison != 0:
			gar_ok = false
	check.call("neutral_garrisons", gar_ok, "neutral troops present, owned start at 0")

	var coastal_n := 0
	for t in terrs:
		if t.is_coastal:
			coastal_n += 1
	check.call("coastal_exists", coastal_n >= 1, "coastal=%d" % coastal_n)

	# Each nation owns its capital plus up to 2 adjacent cells.
	var own_ok := true
	for n in state.nations:
		var c := 0
		for t in terrs:
			if t.owner_id == n.id:
				c += 1
		if c < 1 or c > 3:
			own_ok = false
	check.call("starting_territories", own_ok, "")

	# Terrain mix: >= 4 kinds present, >= 15% plains/fertile.
	var kinds := {}
	var good := 0
	for t in terrs:
		kinds[t.terrain] = true
		if t.terrain == Tacterra.Terrain.PLAINS or t.terrain == Tacterra.Terrain.FERTILE:
			good += 1
	check.call("terrain_mix",
		kinds.size() >= 4 and good >= int(ceil(terrs.size() * 0.15)),
		"kinds=%d good=%d/%d" % [kinds.size(), good, terrs.size()])

	# Rivers + terrain variety must hold across seeds (noise is seed-dependent).
	var variety_ok := true
	var variety_note := ""
	for sd in [1234567, 424242, 777, 20261010]:
		var sv := _make_state(Tacterra.MapSize.STANDARD, 3, sd)
		MapGenerator.generate(sv)
		var vk := {}
		var vr := 0
		for t in sv.territories:
			vk[t.terrain] = true
			if t.has_river:
				vr += 1
		if vk.size() < 4 or vr < 1:
			variety_ok = false
			variety_note = "seed %d: kinds=%d rivers=%d" % [sd, vk.size(), vr]
	check.call("terrain_variety_across_seeds", variety_ok, variety_note)

	# Determinism: same seed -> identical world.
	var s2 := _make_state(Tacterra.MapSize.STANDARD, 3, 1234567)
	MapGenerator.generate(s2)
	var det_ok := s2.territories.size() == terrs.size()
	if det_ok:
		for i in range(terrs.size()):
			var a := terrs[i]
			var b: TerritoryData = s2.territories[i]
			if a.name != b.name or a.owner_id != b.owner_id \
					or a.center != b.center or a.terrain != b.terrain \
					or a.neighbors != b.neighbors:
				det_ok = false
				break
	check.call("deterministic", det_ok, "same seed reproduces world")

	# Different seed -> (almost surely) different world.
	var s3 := _make_state(Tacterra.MapSize.STANDARD, 3, 7654321)
	MapGenerator.generate(s3)
	var diff_names := false
	for i in range(mini(terrs.size(), s3.territories.size())):
		if terrs[i].name != (s3.territories[i] as TerritoryData).name:
			diff_names = true
			break
	check.call("seed_varies_world", diff_names, "")

	# move_cost table matches the contract.
	var mc := [
		MapGenerator.move_cost(Tacterra.Terrain.PLAINS) == 1.0,
		MapGenerator.move_cost(Tacterra.Terrain.FERTILE) == 1.0,
		MapGenerator.move_cost(Tacterra.Terrain.FOREST) == 1.2,
		MapGenerator.move_cost(Tacterra.Terrain.HILLS) == 1.3,
		MapGenerator.move_cost(Tacterra.Terrain.MOUNTAINS) == 1.6,
		MapGenerator.move_cost(Tacterra.Terrain.DESERT) == 1.2,
	]
	check.call("move_cost_table", not mc.has(false), "")

	# ------------------------------------------------------- other map sizes
	for sz in [Tacterra.MapSize.SMALL, Tacterra.MapSize.LARGE]:
		var st := _make_state(sz, 3, 999 + sz)
		MapGenerator.generate(st)
		var tg: int = Tacterra.TERR_COUNT[sz]
		var ok: bool = st.territories.size() >= tg * 0.8 and st.territories.size() <= tg * 1.35
		var caps_ok2 := true
		var seen2 := {}
		for n in st.nations:
			if seen2.has(n.capital_id) or n.capital_id < 0 or n.capital_id >= st.territories.size():
				caps_ok2 = false
			seen2[n.capital_id] = true
		check.call("size_%d_count_and_capitals" % sz, ok and caps_ok2,
			"count=%d target=%d" % [st.territories.size(), tg])

	# Small map with max AI count (6 nations) still places everyone.
	var st5 := _make_state(Tacterra.MapSize.SMALL, 5, 31337)
	MapGenerator.generate(st5)
	var caps5 := {}
	var caps5_ok := st5.nations.size() == 6
	for n in st5.nations:
		if caps5.has(n.capital_id) or n.capital_id < 0 or n.capital_id >= st5.territories.size():
			caps5_ok = false
		caps5[n.capital_id] = true
	check.call("six_nations_small_map", caps5_ok, "territories=%d" % st5.territories.size())

	return results
