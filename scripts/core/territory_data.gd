class_name TerritoryData
extends RefCounted
## One province on the world map.

var id: int = -1
var name: String = ""
var polygon: PackedVector2Array = PackedVector2Array()
var center: Vector2 = Vector2.ZERO
var neighbors: Array[int] = []
var terrain: int = Tacterra.Terrain.PLAINS
var is_coastal: bool = false
var has_city: bool = false
var is_capital: bool = false
var has_river: bool = false
var population: int = 100
var development: int = 0 ## 0..Tacterra.DEVELOP_MAX
var fort_level: int = 0 ## 0..Tacterra.FORT_MAX
var owner_id: int = -1 ## -1 = neutral
var garrison: int = 0 ## neutral defense troops
var army: ArmyData = null ## stationed army (null when empty)
var supplied: bool = true


func is_owned_by(nid: int) -> bool:
	return owner_id == nid


func base_income() -> float:
	var inc: float = Tacterra.INCOME_BY_TERRAIN.get(terrain, 5.0)
	if is_coastal:
		inc += Tacterra.COASTAL_BONUS
	if has_city:
		inc += Tacterra.CITY_BONUS
	if is_capital:
		inc += Tacterra.CAPITAL_BONUS
	if has_river:
		inc += Tacterra.RIVER_INCOME_BONUS
	return inc


func income_per_day() -> float:
	return base_income() * (1.0 + Tacterra.DEVELOP_LEVEL_BONUS * float(development))


func supply_production() -> float:
	var s: float = Tacterra.SUPPLY_PROD_BY_TERRAIN.get(terrain, 1.0)
	if has_city:
		s += Tacterra.SUPPLY_CITY_BONUS
	if is_capital:
		s += Tacterra.SUPPLY_CAPITAL_BONUS
	return s


## Defense multiplier for whoever DEFENDS this territory.
func defense_mult() -> float:
	var m: float = Tacterra.DEFENSE_BY_TERRAIN.get(terrain, 1.0)
	m *= 1.0 + Tacterra.FORT_DEF_BONUS * float(fort_level)
	if has_river:
		m *= 1.0 + Tacterra.RIVER_DEF_BONUS
	return m


func develop_cost() -> float:
	if development >= Tacterra.DEVELOP_MAX:
		return -1.0
	return 100.0 * pow(2.0, float(development))


func fort_cost() -> float:
	if fort_level >= Tacterra.FORT_MAX:
		return -1.0
	return 80.0 * pow(2.0, float(fort_level))


func to_dict() -> Dictionary:
	var poly: Array = []
	for p in polygon:
		poly.append([p.x, p.y])
	var nb: Array = []
	nb.assign(neighbors)
	return {
		"id": id, "name": name, "polygon": poly, "center": [center.x, center.y],
		"neighbors": nb, "terrain": terrain, "is_coastal": is_coastal,
		"has_city": has_city, "is_capital": is_capital, "has_river": has_river,
		"population": population, "development": development,
		"fort_level": fort_level, "owner_id": owner_id, "garrison": garrison,
		"army": army.to_dict() if army != null else null,
		"supplied": supplied,
	}


static func from_dict(d: Dictionary) -> TerritoryData:
	var t := TerritoryData.new()
	t.id = int(d.get("id", -1))
	t.name = str(d.get("name", "Unnamed"))
	var poly := PackedVector2Array()
	for pv in d.get("polygon", []):
		poly.append(Vector2(float(pv[0]), float(pv[1])))
	t.polygon = poly
	var c: Array = d.get("center", [0, 0])
	t.center = Vector2(float(c[0]), float(c[1]))
	t.neighbors.assign(d.get("neighbors", []))
	t.terrain = int(d.get("terrain", Tacterra.Terrain.PLAINS))
	t.is_coastal = bool(d.get("is_coastal", false))
	t.has_city = bool(d.get("has_city", false))
	t.is_capital = bool(d.get("is_capital", false))
	t.has_river = bool(d.get("has_river", false))
	t.population = int(d.get("population", 100))
	t.development = int(d.get("development", 0))
	t.fort_level = int(d.get("fort_level", 0))
	t.owner_id = int(d.get("owner_id", -1))
	t.garrison = int(d.get("garrison", 0))
	var ad = d.get("army", {})
	t.army = ArmyData.from_dict(ad) if ad is Dictionary and not ad.is_empty() else null
	t.supplied = bool(d.get("supplied", true))
	return t
