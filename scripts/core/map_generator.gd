class_name MapGenerator
extends RefCounted
## Procedural world map generation for TACTERRA RPG.
##
## Builds territories as Voronoi cells (the dual of a Delaunay triangulation),
## masks them into 3 wobbly continents, assigns terrain / cities / rivers,
## picks spread-out capitals and claims starting territories for each nation.
## Deterministic given state.rng (every random draw goes through it, and all
## FastNoiseLite instances are seeded from it).
##
## Populates state.territories and sets nation.capital_id. Does NOT create
## armies and does NOT set nation resources -- GameState.create() applies the
## economy preset afterwards.

const _CANDIDATE_MULT := 2.2 ## seed points per target territory
const _TRIES_PER_POINT := 30 ## best-of-N poisson-ish sampling
const _BORDER_MARGIN := 120.0 ## keep seed points away from the world edge
const _WOBBLE_AMP := 0.35 ## coastline noise added to the ellipse test
const _WOBBLE_FREQ := 0.004
const _MASK_ATTEMPTS := 6 ## ellipse-growth retries when land is short
const _MASK_GROWTH := 1.1 ## +10% radii per retry
const _CAPITAL_SEPS := [700.0, 620.0, 550.0, 500.0] ## min-sep thresholds, tried in order
const _CLAMP_MARGIN := 8.0 ## voronoi vertices stay inside the world rect

## Continent ellipses: [cx, cy, rx, ry].
const _ELLIPSES := [
	[800.0, 1000.0, 700.0, 750.0],
	[2100.0, 700.0, 650.0, 600.0],
	[2300.0, 1500.0, 550.0, 450.0],
]
const _WARM_ELLIPSE := 2 ## desert-prone region
const _WARM_RADIUS := 700.0


static func generate(state: GameState) -> void:
	var rng: RandomNumberGenerator = state.rng
	var settings: Dictionary = state.settings
	var map_size: int = int(settings.get("map_size", Tacterra.MapSize.STANDARD))
	var target: int = int(Tacterra.TERR_COUNT.get(map_size, 36))

	var pts := _scatter_points(rng, maxi(8, int(ceil(target * _CANDIDATE_MULT))))
	# Bounded Voronoi via mirrored ghost points: reflecting the seed set
	# across all four world borders makes every original cell bounded, so
	# polygons are true (convex, disjoint, seed-containing) Voronoi cells
	# that only need a final clip to the world rect. This avoids the
	# overlapping/broken border cells that naive circumcenter clamping
	# produces.
	var all_pts := _with_ghost_points(pts)
	var tris := Geometry2D.triangulate_delaunay(all_pts)
	if tris.size() < 9: # need at least 3 triangles for a real map
		_generate_fallback(state, rng, target)
		return

	var point_tris := _index_triangles(all_pts.size(), tris)
	var polys := _voronoi_cells(all_pts, tris, point_tris, pts.size())
	_jitter_borders(rng, polys)
	var edges := _delaunay_edges(tris)
	var land := _continent_mask(rng, pts, target)
	land = _trim_excess(land, pts, polys, target)

	# Reindex kept cells in original point order; new id == array index.
	var id_map := {}
	var land_old: Array[int] = []
	for i in range(pts.size()):
		if land[i]:
			id_map[i] = land_old.size()
			land_old.append(i)
	var n := land_old.size()
	if n == 0:
		_generate_fallback(state, rng, target)
		return

	var neighbors := _build_neighbors(edges, id_map, n)
	var coastal := _find_coastal(edges, id_map, n)
	var centers := PackedVector2Array()
	for old_i in land_old:
		centers.append(pts[old_i])
	_connect_components(neighbors, centers) # strait links between land masses

	var territories: Array[TerritoryData] = []
	territories.resize(n)
	var used_names := {}
	for new_id in range(n):
		var old: int = land_old[new_id]
		var t := TerritoryData.new()
		t.id = new_id
		t.polygon = polys[old]
		t.center = pts[old]
		t.neighbors.assign(neighbors[new_id])
		t.is_coastal = bool(coastal[new_id])
		t.name = Tacterra.random_name(rng, used_names)
		territories[new_id] = t

	_assign_terrain(rng, territories)
	_assign_cities(rng, territories)
	_assign_population(rng, territories)
	_make_rivers(rng, territories)
	_assign_capitals_and_starts(rng, territories, state.nations)

	state.territories = territories


## Movement cost multiplier per terrain (used by MovementSim).
static func move_cost(terrain: int) -> float:
	match terrain:
		Tacterra.Terrain.PLAINS:
			return 1.0
		Tacterra.Terrain.FERTILE:
			return 1.0
		Tacterra.Terrain.FOREST:
			return 1.2
		Tacterra.Terrain.HILLS:
			return 1.3
		Tacterra.Terrain.MOUNTAINS:
			return 1.6
		Tacterra.Terrain.DESERT:
			return 1.2
	return 1.0


# ---------------------------------------------------------------- point scatter

## Best-of-N sampling with density noise: each candidate is scored by its
## distance-to-nearest relative to the locally desired spacing, which varies
## across the map. Dense zones accept close neighbors (small territories),
## sparse zones demand wide spacing (large territories) — this produces
## varied territory sizes instead of a uniform grid feel.
static func _scatter_points(rng: RandomNumberGenerator, count: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var w := Tacterra.WORLD_SIZE.x
	var h := Tacterra.WORLD_SIZE.y
	var m := _BORDER_MARGIN
	var dens := FastNoiseLite.new()
	dens.seed = rng.randi()
	dens.noise_type = FastNoiseLite.TYPE_SIMPLEX
	dens.frequency = 0.0016
	for i in range(count):
		var best := Vector2.ZERO
		var best_score := -1.0
		for t in range(_TRIES_PER_POINT):
			var c := Vector2(rng.randf_range(m, w - m), rng.randf_range(m, h - m))
			var dmin := 1.0e18
			for p in pts:
				var d := c.distance_squared_to(p)
				if d < dmin:
					dmin = d
			var dz: float = clampf(dens.get_noise_2d(c.x, c.y) * 0.5 + 0.5, 0.0, 1.0)
			var want := lerpf(300.0, 110.0, dz)
			var score: float = sqrt(dmin) / want
			if score > best_score:
				best_score = score
				best = c
		pts.append(best)
	return pts


# ------------------------------------------------------------------- voronoi

## Mirror the seed points across all four world borders (8 reflections).
## Ghost points bound every original Voronoi cell, so no cell runs to
## infinity and no circumcenter clamping is needed.
static func _with_ghost_points(pts: PackedVector2Array) -> PackedVector2Array:
	var all_pts := PackedVector2Array()
	all_pts.append_array(pts)
	var w := Tacterra.WORLD_SIZE.x
	var h := Tacterra.WORLD_SIZE.y
	for p in pts:
		all_pts.append(Vector2(-p.x, p.y))
		all_pts.append(Vector2(2.0 * w - p.x, p.y))
		all_pts.append(Vector2(p.x, -p.y))
		all_pts.append(Vector2(p.x, 2.0 * h - p.y))
		all_pts.append(Vector2(-p.x, -p.y))
		all_pts.append(Vector2(2.0 * w - p.x, -p.y))
		all_pts.append(Vector2(-p.x, 2.0 * h - p.y))
		all_pts.append(Vector2(2.0 * w - p.x, 2.0 * h - p.y))
	return all_pts


## Sutherland-Hodgman clip of a convex polygon to an axis-aligned rect.
## The result stays convex; a polygon containing a point strictly inside
## the rect can never clip down to nothing.
static func _clip_to_rect(poly: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var out := poly
	# left, right, top, bottom
	var edges := [
		[Vector2(rect.position.x, 0.0), Vector2(0.0, 1.0)], # x >= left, inward normal +x
		[Vector2(rect.end.x, 0.0), Vector2(-1.0, 0.0)], # x <= right
		[Vector2(0.0, rect.position.y), Vector2(0.0, 1.0)], # y >= top
		[Vector2(0.0, rect.end.y), Vector2(0.0, -1.0)], # y <= bottom
	]
	for e in edges:
		var anchor: Vector2 = e[0]
		var normal: Vector2 = e[1]
		var inp := out
		out = PackedVector2Array()
		if inp.is_empty():
			break
		var s: Vector2 = inp[inp.size() - 1]
		for v in inp:
			var v_in := (v - anchor).dot(normal) >= 0.0
			var s_in := (s - anchor).dot(normal) >= 0.0
			if v_in:
				if not s_in:
					out.append(_line_intersect(s, v, anchor, normal))
				out.append(v)
			elif s_in:
				out.append(_line_intersect(s, v, anchor, normal))
			s = v
	return out


## Intersection of segment (a, b) with the line through `anchor` with `normal`.
static func _line_intersect(a: Vector2, b: Vector2, anchor: Vector2, normal: Vector2) -> Vector2:
	var d := b - a
	var denom := d.dot(normal)
	if absf(denom) < 0.000001:
		return a
	var t := (anchor - a).dot(normal) / denom
	return a + d * clampf(t, 0.0, 1.0)

static func _index_triangles(pt_count: int, tris: PackedInt32Array) -> Array:
	var point_tris: Array = []
	for i in range(pt_count):
		point_tris.append([])
	for ti in range(tris.size() / 3):
		(point_tris[tris[ti * 3]] as Array).append(ti)
		(point_tris[tris[ti * 3 + 1]] as Array).append(ti)
		(point_tris[tris[ti * 3 + 2]] as Array).append(ti)
	return point_tris


## Circumcenter of triangle (a, b, c). Returns Vector2(1e30, 1e30) for
## degenerate (near-zero-area) triangles, which the caller skips.
static func _circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 0.0001:
		return Vector2(1.0e30, 1.0e30)
	var a2 := a.x * a.x + a.y * a.y
	var b2 := b.x * b.x + b.y * b.y
	var c2 := c.x * c.x + c.y * c.y
	var ux := (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
	var uy := (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
	return Vector2(ux, uy)


## Voronoi cell of point P = circumcenters of its adjacent triangles, sorted
## by angle around P. Only the first `original_count` points get cells
## (the rest are ghost points). Cells are clipped to the world rect; true
## Voronoi cells are convex and contain their seed, so clipping keeps them
## convex, non-empty, and pairwise disjoint.
static func _voronoi_cells(pts: PackedVector2Array, tris: PackedInt32Array, point_tris: Array, original_count: int) -> Array:
	var cells: Array = []
	var clip := Rect2(_CLAMP_MARGIN, _CLAMP_MARGIN,
		Tacterra.WORLD_SIZE.x - 2.0 * _CLAMP_MARGIN,
		Tacterra.WORLD_SIZE.y - 2.0 * _CLAMP_MARGIN)
	for pi in range(original_count):
		var c := pts[pi]
		var verts: Array[Vector2] = []
		for ti in point_tris[pi]:
			var tii: int = ti
			var cc := _circumcenter(pts[tris[tii * 3]], pts[tris[tii * 3 + 1]], pts[tris[tii * 3 + 2]])
			if cc.x > 1.0e29:
				continue # degenerate triangle
			verts.append(cc)
		var poly := PackedVector2Array()
		if verts.size() >= 3:
			verts.sort_custom(func(p: Vector2, q: Vector2) -> bool: return (p - c).angle() < (q - c).angle())
			var last := Vector2(1.0e18, 1.0e18)
			for v in verts:
				if v.distance_squared_to(last) > 4.0:
					poly.append(v)
					last = v
		if poly.size() < 3:
			poly = _fallback_hex(c)
		else:
			poly = _clip_to_rect(poly, clip)
			if poly.size() < 3:
				poly = _fallback_hex(c)
		cells.append(poly)
	return cells


## Natural-looking borders: displace every polygon vertex by smooth noise.
## The displacement is a deterministic function of the vertex POSITION (not
## the cell), so vertices shared by adjacent cells move identically — no
## gaps or overlaps are introduced. Amplitude is small relative to cell size.
static func _jitter_borders(rng: RandomNumberGenerator, polys: Array) -> void:
	var jn := FastNoiseLite.new()
	jn.seed = rng.randi()
	jn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	jn.frequency = 0.004
	var mx := Tacterra.WORLD_SIZE.x - _CLAMP_MARGIN
	var my := Tacterra.WORLD_SIZE.y - _CLAMP_MARGIN
	for pi in range(polys.size()):
		var poly: PackedVector2Array = polys[pi]
		for vi in range(poly.size()):
			var v: Vector2 = poly[vi]
			var ox := jn.get_noise_2d(v.x, v.y) * 16.0
			var oy := jn.get_noise_2d(v.y + 977.0, v.x + 313.0) * 16.0
			poly[vi] = Vector2(clampf(v.x + ox, _CLAMP_MARGIN, mx),
				clampf(v.y + oy, _CLAMP_MARGIN, my))


static func _fallback_hex(c: Vector2) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for k in range(6):
		var a := TAU * float(k) / 6.0
		var p := c + Vector2(cos(a), sin(a)) * 60.0
		p.x = clampf(p.x, _CLAMP_MARGIN, Tacterra.WORLD_SIZE.x - _CLAMP_MARGIN)
		p.y = clampf(p.y, _CLAMP_MARGIN, Tacterra.WORLD_SIZE.y - _CLAMP_MARGIN)
		poly.append(p)
	return poly


static func _delaunay_edges(tris: PackedInt32Array) -> Array[Vector2i]:
	var edges: Array[Vector2i] = []
	var seen := {}
	for ti in range(tris.size() / 3):
		var vs := [tris[ti * 3], tris[ti * 3 + 1], tris[ti * 3 + 2]]
		for k in range(3):
			var a: int = vs[k]
			var b: int = vs[(k + 1) % 3]
			var key := "%d:%d" % [mini(a, b), maxi(a, b)]
			if not seen.has(key):
				seen[key] = true
				edges.append(Vector2i(mini(a, b), maxi(a, b)))
	return edges


# ------------------------------------------------------------- continent mask

## A seed point is LAND when its center falls inside any continent ellipse,
## with simplex-noise wobble on the coastline. Grows the ellipses +10% per
## retry (up to _MASK_ATTEMPTS) when land is short; keeps best effort, never
## crashes.
static func _continent_mask(rng: RandomNumberGenerator, pts: PackedVector2Array, target: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var land: Array = []
	land.resize(pts.size())
	land.fill(false)
	for attempt in range(_MASK_ATTEMPTS):
		var s := pow(_MASK_GROWTH, attempt)
		var count := 0
		for i in range(pts.size()):
			var p := pts[i]
			var inside := false
			for e in _ELLIPSES:
				var ex: Array = e
				var dx: float = (p.x - float(ex[0])) / (float(ex[2]) * s)
				var dy: float = (p.y - float(ex[1])) / (float(ex[3]) * s)
				var v: float = dx * dx + dy * dy
				var wob := noise.get_noise_2d(p.x * _WOBBLE_FREQ, p.y * _WOBBLE_FREQ) * _WOBBLE_AMP
				if v + wob < 1.0:
					inside = true
					break
			land[i] = inside
			if inside:
				count += 1
		if count >= target * 0.8:
			return land
	return land


## When land overshoots (> N*1.3), drop the smallest cells farthest from the
## continent hearts until back in range.
static func _trim_excess(land: Array, pts: PackedVector2Array, polys: Array, target: int) -> Array:
	var ids: Array[int] = []
	for i in range(land.size()):
		if land[i]:
			ids.append(i)
	var max_keep := int(ceil(target * 1.3))
	if ids.size() <= max_keep:
		return land
	var scored: Array = []
	for i in ids:
		var dmin := 1.0e18
		for e in _ELLIPSES:
			var ex: Array = e
			dmin = minf(dmin, pts[i].distance_to(Vector2(ex[0], ex[1])))
		var area := _poly_area(polys[i])
		scored.append({"id": i, "score": dmin - sqrt(area) * 0.6})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var drop := ids.size() - max_keep
	for k in range(drop):
		land[int(scored[k]["id"])] = false
	return land


static func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(poly.size()):
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func _minf_of(vals: Array[float]) -> float:
	var m := 1.0e18
	for v in vals:
		m = minf(m, v)
	return m


static func _maxf_of(vals: Array[float]) -> float:
	var m := -1.0e18
	for v in vals:
		m = maxf(m, v)
	return m


# ----------------------------------------------------------------- neighbors

## Neighbors = cells sharing a Delaunay edge, both land. Symmetric by
## construction.
static func _build_neighbors(edges: Array[Vector2i], id_map: Dictionary, n: int) -> Array:
	var neighbors: Array = []
	for i in range(n):
		neighbors.append([])
	for e in edges:
		if id_map.has(e.x) and id_map.has(e.y):
			var na: int = id_map[e.x]
			var nb: int = id_map[e.y]
			(neighbors[na] as Array).append(nb)
			(neighbors[nb] as Array).append(na)
	return neighbors


## Coastal = land cell with a Delaunay edge to a dropped (ocean) cell.
static func _find_coastal(edges: Array[Vector2i], id_map: Dictionary, n: int) -> Array:
	var coastal: Array = []
	coastal.resize(n)
	coastal.fill(false)
	for e in edges:
		var la := id_map.has(e.x)
		var lb := id_map.has(e.y)
		if la and not lb:
			coastal[id_map[e.x]] = true
		elif lb and not la:
			coastal[id_map[e.y]] = true
	return coastal


## Guarantee a connected land graph: link each non-largest component to the
## largest one with a symmetric "strait" edge between their nearest cells.
## Keeps BFS reachability (supply, AI pathing) sound on every seed.
static func _connect_components(neighbors: Array, centers: PackedVector2Array) -> void:
	var n := centers.size()
	var comp: Array = []
	comp.resize(n)
	comp.fill(-1)
	var ncomp := 0
	for i in range(n):
		if comp[i] != -1:
			continue
		var queue: Array[int] = [i]
		comp[i] = ncomp
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for nb in neighbors[cur]:
				var nbi: int = nb
				if comp[nbi] == -1:
					comp[nbi] = ncomp
					queue.append(nbi)
		ncomp += 1
	if ncomp <= 1:
		return
	var sizes := {}
	for i in range(n):
		sizes[comp[i]] = int(sizes.get(comp[i], 0)) + 1
	var main := 0
	var main_size := -1
	for k in sizes.keys():
		if int(sizes[k]) > main_size:
			main_size = int(sizes[k])
			main = int(k)
	for c in range(ncomp):
		if c == main:
			continue
		var best_a := -1
		var best_b := -1
		var best_d := 1.0e18
		for i in range(n):
			if comp[i] != c:
				continue
			for j in range(n):
				if comp[j] != main:
					continue
				var d := centers[i].distance_squared_to(centers[j])
				if d < best_d:
					best_d = d
					best_a = i
					best_b = j
		if best_a >= 0:
			(neighbors[best_a] as Array).append(best_b)
			(neighbors[best_b] as Array).append(best_a)


# ------------------------------------------------------------------- terrain

static func _assign_terrain(rng: RandomNumberGenerator, territories: Array[TerritoryData]) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var ridge := FastNoiseLite.new()
	ridge.seed = rng.randi()
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# Sample both noises, then normalize per-map so the terrain bands are
	# robust to FastNoiseLite's seed-dependent output range (empirically it
	# clusters in a narrow band, so absolute thresholds starve mountains).
	var n1s: Array[float] = []
	var n2s: Array[float] = []
	for t in territories:
		n1s.append(noise.get_noise_2d(t.center.x * 0.0016, t.center.y * 0.0016))
		n2s.append(absf(ridge.get_noise_2d(t.center.x * 0.003, t.center.y * 0.003)))
	var lo1 := _minf_of(n1s)
	var span1 := maxf(0.0001, _maxf_of(n1s) - lo1)
	var lo2 := _minf_of(n2s)
	var span2 := maxf(0.0001, _maxf_of(n2s) - lo2)
	var we: Array = _ELLIPSES[_WARM_ELLIPSE]
	var warm := Vector2(float(we[0]), float(we[1]))
	for i in range(territories.size()):
		var t := territories[i]
		var e1 := (n1s[i] - lo1) / span1 # 0..1 elevation-ish
		var e2 := (n2s[i] - lo2) / span2 # 0..1 ridgedness (low = ridge band)
		var terr: int
		if e1 > 0.80 or (e1 > 0.64 and e2 < 0.35):
			terr = Tacterra.Terrain.MOUNTAINS
		elif e1 > 0.58:
			terr = Tacterra.Terrain.HILLS
		elif e1 > 0.36:
			terr = Tacterra.Terrain.FOREST
		elif e1 > 0.14:
			terr = Tacterra.Terrain.FERTILE
		else:
			terr = Tacterra.Terrain.PLAINS
		if t.center.distance_to(warm) < _WARM_RADIUS and e1 < 0.20:
			terr = Tacterra.Terrain.DESERT
		t.terrain = terr
	# Guarantee a playable mix: at least 15% plains/fertile.
	var good := 0
	for t in territories:
		if t.terrain == Tacterra.Terrain.PLAINS or t.terrain == Tacterra.Terrain.FERTILE:
			good += 1
	var need := int(ceil(territories.size() * 0.15)) - good
	var guard := 0
	while need > 0 and guard < 400:
		guard += 1
		var t: TerritoryData = territories[rng.randi_range(0, territories.size() - 1)]
		if t.terrain == Tacterra.Terrain.MOUNTAINS or t.terrain == Tacterra.Terrain.DESERT:
			continue
		if t.terrain == Tacterra.Terrain.PLAINS or t.terrain == Tacterra.Terrain.FERTILE:
			continue
		t.terrain = Tacterra.Terrain.PLAINS if guard % 2 == 0 else Tacterra.Terrain.FERTILE
		need -= 1


## ~25% of cells get a city, biased toward high-income cells.
static func _assign_cities(rng: RandomNumberGenerator, territories: Array[TerritoryData]) -> void:
	var order: Array[TerritoryData] = []
	order.append_array(territories)
	order.sort_custom(func(a: TerritoryData, b: TerritoryData) -> bool: return a.base_income() > b.base_income())
	var cutoff := int(ceil(order.size() * 0.4))
	for idx in range(order.size()):
		var p := 0.35 if idx < cutoff else 0.15
		if rng.randf() < p:
			order[idx].has_city = true


static func _assign_population(rng: RandomNumberGenerator, territories: Array[TerritoryData]) -> void:
	for t in territories:
		t.population = 120 + int(t.base_income() * 30.0) + rng.randi_range(0, 80)


# -------------------------------------------------------------------- rivers

## Two random walks from high ground to the nearest coast, marking has_river.
static func _make_rivers(rng: RandomNumberGenerator, territories: Array[TerritoryData]) -> void:
	var starts: Array[TerritoryData] = []
	for t in territories:
		if t.terrain == Tacterra.Terrain.MOUNTAINS or t.terrain == Tacterra.Terrain.HILLS:
			starts.append(t)
	for r in range(2):
		if starts.is_empty():
			break
		var start: TerritoryData = starts[rng.randi_range(0, starts.size() - 1)]
		starts.erase(start)
		var target := _nearest_coastal(territories, start)
		if target == null:
			continue
		var visited := {}
		var path: Array[TerritoryData] = []
		var cur := start
		var guard := 0
		while cur != target and guard < 60:
			guard += 1
			visited[cur.id] = true
			path.append(cur)
			var best: TerritoryData = null
			var best_d := 1.0e18
			for nid in cur.neighbors:
				if visited.has(nid):
					continue
				var nb: TerritoryData = territories[nid]
				var d := nb.center.distance_to(target.center) * rng.randf_range(0.75, 1.25)
				if d < best_d:
					best_d = d
					best = nb
			if best == null:
				break # boxed in; keep the partial river
			cur = best
		path.append(cur)
		for t in path:
			t.has_river = true


static func _nearest_coastal(territories: Array[TerritoryData], from: TerritoryData) -> TerritoryData:
	var best: TerritoryData = null
	var best_d := 1.0e18
	for t in territories:
		if not t.is_coastal:
			continue
		var d := t.center.distance_squared_to(from.center)
		if d < best_d:
			best_d = d
			best = t
	return best


# ------------------------------------------------------- capitals and starts

## Greedy max-min spread: first capital random, each next maximizes its
## distance to the nearest already-chosen capital. Tried against decreasing
## separation thresholds so crowded maps still place every nation.
static func _choose_capitals(rng: RandomNumberGenerator, territories: Array[TerritoryData], nation_count: int) -> Array[int]:
	var pool: Array[int] = []
	for t in territories:
		pool.append(t.id)
	var best: Array[int] = []
	for sep in _CAPITAL_SEPS:
		var attempt := _greedy_capitals(rng, territories, pool, nation_count)
		if _min_pairwise(attempt, territories) >= sep:
			return attempt
		best = attempt
	return best


static func _greedy_capitals(rng: RandomNumberGenerator, territories: Array[TerritoryData], pool: Array[int], nation_count: int) -> Array[int]:
	var chosen: Array[int] = []
	var rest := pool.duplicate()
	if rest.is_empty():
		return chosen
	chosen.append(rest[rng.randi_range(0, rest.size() - 1)])
	rest.erase(chosen[0])
	while chosen.size() < nation_count and not rest.is_empty():
		var best_id := -1
		var best_d := -1.0
		for cid in rest:
			var dmin := 1.0e18
			for done in chosen:
				dmin = minf(dmin, territories[cid].center.distance_to(territories[done].center))
			if dmin > best_d:
				best_d = dmin
				best_id = cid
		chosen.append(best_id)
		rest.erase(best_id)
	return chosen


static func _min_pairwise(caps: Array[int], territories: Array[TerritoryData]) -> float:
	if caps.size() < 2:
		return 1.0e18
	var m := 1.0e18
	for i in range(caps.size()):
		for j in range(i + 1, caps.size()):
			m = minf(m, territories[caps[i]].center.distance_to(territories[caps[j]].center))
	return m


## Each nation starts with exactly ONE territory: its capital (flagged, forced
## city). All expansion from there must go through connected neighbors, so
## empires visibly spread outward from the starting point. Unowned cells get a
## neutral garrison.
static func _assign_capitals_and_starts(rng: RandomNumberGenerator, territories: Array[TerritoryData], nations: Array[NationData]) -> void:
	var caps: Array[int] = []
	if not nations.is_empty() and not territories.is_empty():
		caps = _choose_capitals(rng, territories, nations.size())
	for ni in range(nations.size()):
		var nation: NationData = nations[ni]
		if ni >= caps.size():
			nation.capital_id = -1
			continue
		var cap: TerritoryData = territories[caps[ni]]
		cap.owner_id = nation.id
		cap.is_capital = true
		cap.has_city = true
		# Capitals are major cities: guarantee enough population to support
		# early recruitment from a single-territory start.
		cap.population = maxi(cap.population, 800)
		nation.capital_id = cap.id
	for t in territories:
		if t.owner_id < 0:
			t.garrison = 15 + int(t.base_income() * 2.0) + rng.randi_range(0, 10)
		else:
			t.garrison = 0


# ------------------------------------------------------------------ fallback

## Last-resort rectangular grid map (used only if Delaunay triangulation
## fails). Keeps the game playable instead of crashing on empty geometry.
static func _generate_fallback(state: GameState, rng: RandomNumberGenerator, target: int) -> void:
	var cols := maxi(2, int(ceil(sqrt(float(target) * 1.6))))
	var rows := maxi(2, int(ceil(float(target) / float(cols))))
	var w := Tacterra.WORLD_SIZE.x / cols
	var h := Tacterra.WORLD_SIZE.y / rows
	var territories: Array[TerritoryData] = []
	var used := {}
	var count := 0
	for r in range(rows):
		for c in range(cols):
			if count >= target:
				break
			var t := TerritoryData.new()
			t.id = count
			var x0 := c * w + 4.0
			var y0 := r * h + 4.0
			t.polygon = PackedVector2Array([
				Vector2(x0, y0), Vector2(x0 + w - 8.0, y0),
				Vector2(x0 + w - 8.0, y0 + h - 8.0), Vector2(x0, y0 + h - 8.0)])
			t.center = Vector2(x0 + w * 0.5, y0 + h * 0.5)
			t.is_coastal = (r == 0 or c == 0 or r == rows - 1 or c == cols - 1)
			t.name = Tacterra.random_name(rng, used)
			territories.append(t)
			count += 1
	for r in range(rows):
		for c in range(cols):
			var i := r * cols + c
			if i >= territories.size():
				continue
			if c + 1 < cols and i + 1 < territories.size():
				territories[i].neighbors.append(i + 1)
				territories[i + 1].neighbors.append(i)
			if r + 1 < rows and i + cols < territories.size():
				territories[i].neighbors.append(i + cols)
				territories[i + cols].neighbors.append(i)
	_assign_terrain(rng, territories)
	_assign_cities(rng, territories)
	_assign_population(rng, territories)
	_make_rivers(rng, territories)
	_assign_capitals_and_starts(rng, territories, state.nations)
	state.territories = territories
