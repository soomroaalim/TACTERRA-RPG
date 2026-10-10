class_name Tacterra
extends RefCounted
## Global constants, enums, and helpers for TACTERRA RPG.

enum Terrain { PLAINS, FERTILE, FOREST, HILLS, MOUNTAINS, DESERT }
enum Difficulty { EASY, NORMAL, HARD }
enum Personality { EXPANSIONIST, DEFENSIVE, AGGRESSIVE }
enum MapSize { SMALL, STANDARD, LARGE }
enum NotifyKind { INFO, GOOD, BAD, BATTLE }

# --- time ---
const DAYS_PER_SECOND := 2.0 ## game-days per real second at 1x speed
const SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]

# --- economy (per day) ---
const INCOME_BY_TERRAIN := {
	Terrain.PLAINS: 6.0, Terrain.FERTILE: 10.0, Terrain.FOREST: 5.0,
	Terrain.HILLS: 4.0, Terrain.MOUNTAINS: 3.0, Terrain.DESERT: 2.0,
}
const COASTAL_BONUS := 2.0
const CITY_BONUS := 8.0
const CAPITAL_BONUS := 10.0
const DEVELOP_LEVEL_BONUS := 0.25
const DEVELOP_MAX := 5
const FORT_DEF_BONUS := 0.20
const FORT_MAX := 3
const RIVER_DEF_BONUS := 0.15
const RIVER_INCOME_BONUS := 1.0
const DEFENSE_BY_TERRAIN := {
	Terrain.PLAINS: 1.0, Terrain.FERTILE: 1.0, Terrain.FOREST: 1.15,
	Terrain.HILLS: 1.25, Terrain.MOUNTAINS: 1.5, Terrain.DESERT: 0.9,
}

# --- armies ---
const RECRUIT_COST := 10.0
const RECRUIT_TRAIN_DAYS := 3.0
const UPKEEP_PER_SOLDIER := 0.02
const SUPPLY_USE_PER_SOLDIER := 0.01
const SUPPLY_PROD_BY_TERRAIN := {
	Terrain.PLAINS: 2.0, Terrain.FERTILE: 3.0, Terrain.FOREST: 1.0,
	Terrain.HILLS: 1.0, Terrain.MOUNTAINS: 0.5, Terrain.DESERT: 0.5,
}
const SUPPLY_CITY_BONUS := 2.0
const SUPPLY_CAPITAL_BONUS := 5.0
const MANPOWER_CAP_DIV := 10
const MANPOWER_REGEN := 0.02
const MOVE_SPEED := 600.0
const UNSUPPLIED_POWER := 0.6
const UNSUPPLIED_GRACE_DAYS := 3.0
const ATTRITION_PER_DAY := 0.02
const DESERTION_PER_DAY := 0.03
const DEFENDER_BONUS := 1.25
const COMBAT_LOSS_FACTOR := 0.35
const COMBAT_JITTER := 0.10 ## +/-10% rng jitter on losses (documented)

# --- map ---
const WORLD_SIZE := Vector2(3200, 2000)
const TERR_COUNT := { MapSize.SMALL: 24, MapSize.STANDARD: 36, MapSize.LARGE: 48 }
const SAVE_VERSION := 1
const SAVE_SLOTS := 3

const AI_THINK_DAYS := { Difficulty.EASY: 5.0, Difficulty.NORMAL: 3.0, Difficulty.HARD: 2.0 }
const AI_ATTACK_THRESHOLD := { Difficulty.EASY: 1.9, Difficulty.NORMAL: 1.4, Difficulty.HARD: 1.2 }
const AI_RECRUIT_MULT := { Difficulty.EASY: 0.6, Difficulty.NORMAL: 1.0, Difficulty.HARD: 1.2 }

const NATION_COLORS: Array[Color] = [
	Color("3fa7ff"), # player - blue
	Color("ff5a5a"), # AI 1 - red
	Color("ffb02e"), # AI 2 - amber
	Color("7ee081"), # AI 3 - green
	Color("c77dff"), # AI 4 - violet
	Color("ff7ad9"), # AI 5 - pink
]
const NEUTRAL_COLOR := Color("9aa3ad")

const NAME_A := ["Vel", "Kha", "Dun", "Mor", "Zeth", "Bal", "Tor", "Rha", "Kel", "Ost",
	"Mar", "Fen", "Gar", "Hol", "Ith", "Jor", "Qel", "Sar", "Thur", "Ul"]
const NAME_B := ["mor", "dun", "via", "stan", "garth", "holm", "wick", "ford", "mark", "ria",
	"dor", "nia", "thos", "kesh", "lund", "mere", "port", "shire", "vall", "zar"]
const NATION_NAMES := ["Austerra", "Velmora", "Khadun", "Ostmark", "Zethria", "Dunhollow"]


static func terrain_name(t: int) -> String:
	match t:
		Terrain.PLAINS: return "Plains"
		Terrain.FERTILE: return "Fertile"
		Terrain.FOREST: return "Forest"
		Terrain.HILLS: return "Hills"
		Terrain.MOUNTAINS: return "Mountains"
		Terrain.DESERT: return "Desert"
	return "Unknown"


static func difficulty_name(d: int) -> String:
	match d:
		Difficulty.EASY: return "Easy"
		Difficulty.NORMAL: return "Normal"
		Difficulty.HARD: return "Hard"
	return "?"


static func personality_name(p: int) -> String:
	match p:
		Personality.EXPANSIONIST: return "Expansionist"
		Personality.DEFENSIVE: return "Defensive"
		Personality.AGGRESSIVE: return "Aggressive"
	return "?"


static func format_num(n: float) -> String:
	var a := absf(n)
	if a >= 1_000_000.0:
		return "%.1fM" % (n / 1_000_000.0)
	if a >= 10_000.0:
		return "%.1fk" % (n / 1000.0)
	if a >= 1000.0:
		return "%.2fk" % (n / 1000.0)
	return str(int(round(n)))


static func random_name(rng: RandomNumberGenerator, used: Dictionary) -> String:
	for _i in 40:
		var nm: String = NAME_A[rng.randi_range(0, NAME_A.size() - 1)] \
			+ NAME_B[rng.randi_range(0, NAME_B.size() - 1)]
		if not used.has(nm):
			used[nm] = true
			return nm
	var fallback := "Terra%d" % used.size()
	used[fallback] = true
	return fallback
