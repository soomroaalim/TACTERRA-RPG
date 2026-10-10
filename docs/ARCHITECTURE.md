# TACTERRA RPG — Architecture & Contracts

Godot 4.3-stable, GDScript. No autoloads (keeps headless testing trivial).
The single source of truth is `GameState` (a `RefCounted`); UI renders from it
and issues orders through its methods. All simulation subsystems are static
classes operating on `GameState`. No binary assets: all art is drawn with
Polygon2D/Line2D, all SFX are synthesized at runtime.

Repo root IS the Godot project root (project.godot at top level).

## File layout

```
project.godot
icon.svg
README.md / CHANGELOG.md / docs/*.md
scripts/core/tacterra.gd          class_name Tacterra        (enums, constants, helpers)
scripts/core/territory_data.gd   class_name TerritoryData   extends RefCounted
scripts/core/nation_data.gd      class_name NationData      extends RefCounted
scripts/core/army_data.gd        class_name ArmyData        extends RefCounted
scripts/core/game_state.gd       class_name GameState       extends RefCounted
scripts/core/map_generator.gd    class_name MapGenerator     (static)
scripts/core/economy_sim.gd      class_name EconomySim      (static)
scripts/core/supply_sim.gd       class_name SupplySim       (static)
scripts/core/movement_sim.gd     class_name MovementSim     (static)
scripts/core/combat_sim.gd       class_name CombatSim       (static)
scripts/core/victory_sim.gd      class_name VictorySim      (static)
scripts/core/save_system.gd      class_name SaveSystem       (static)
scripts/core/ai/ai_brain.gd      class_name AIBrain         (static)
scripts/audio/audio_manager.gd   class_name AudioManager    extends Node
scripts/audio/game_settings.gd   class_name GameSettings     (static, user://settings.json)
scripts/ui/main_menu.gd          (+ minimal main_menu.tscn: root Control + script)
scripts/ui/match_setup.gd        (+ match_setup.tscn)
scripts/ui/game_screen.gd        (+ game_screen.tscn)  -- map + HUD, owns the GameState
scripts/ui/how_to_play.gd        (+ how_to_play.tscn)
scripts/ui/settings_screen.gd    (+ settings_screen.tscn)
scripts/ui/credits_screen.gd     (+ credits_screen.tscn)
tests/run_tests.gd               extends SceneTree, discovers test_*.gd
tests/test_<area>.gd             each has `static func run(ctx) -> Array` of {name, passed, note}
tools/capture.gd                 extends SceneTree, screenshot harness for Xvfb runs
```

Build UI programmatically inside `_ready()`; keep .tscn files to a root node
with the script attached. This avoids .tscn format errors.

## Tacterra (constants & helpers)

```gdscript
class_name Tacterra
enum Terrain { PLAINS, FERTILE, FOREST, HILLS, MOUNTAINS, DESERT }
enum Difficulty { EASY, NORMAL, HARD }
enum Personality { EXPANSIONIST, DEFENSIVE, AGGRESSIVE }
enum MapSize { SMALL, STANDARD, LARGE }
# time
const DAYS_PER_SECOND := 2.0        # at 1x speed
const SPEEDS := [0.5, 1.0, 2.0, 4.0]
# economy (per day)
const INCOME_BY_TERRAIN := {0:6.0, 1:10.0, 2:5.0, 3:4.0, 4:3.0, 5:2.0}  # indexed by Terrain
const COASTAL_BONUS := 2.0
const CITY_BONUS := 8.0
const CAPITAL_BONUS := 10.0
const DEVELOP_LEVEL_BONUS := 0.25   # +25% income per development level
const DEVELOP_MAX := 5
const FORT_DEF_BONUS := 0.20        # +20% defense per fort level
const FORT_MAX := 3
const RIVER_DEF_BONUS := 0.15
const RIVER_INCOME_BONUS := 1.0
# armies
const RECRUIT_COST := 10.0          # credits per soldier
const RECRUIT_TRAIN_DAYS := 3.0
const UPKEEP_PER_SOLDIER := 0.02    # credits per soldier per day
const SUPPLY_USE_PER_SOLDIER := 0.01
const SUPPLY_PROD_BY_TERRAIN := {0:2.0, 1:3.0, 2:1.0, 3:1.0, 4:0.5, 5:0.5}
const MANPOWER_CAP_DIV := 10        # cap = population / 10
const MANPOWER_REGEN := 0.02        # 2% of cap per day
const MOVE_SPEED := 600.0           # map units per day
const UNSUPPLIED_POWER := 0.6
const ATTRITION_PER_DAY := 0.02
const DEFENDER_BONUS := 1.25
# combat tuning
const COMBAT_LOSS_FACTOR := 0.35
# map
const WORLD_SIZE := Vector2(3200, 2000)
const TERR_COUNT := {0:24, 1:36, 2:48}  # by MapSize
const SAVE_VERSION := 1
static func terrain_name(t:int)->String
static func format_num(n:float)->String   # 1.2k / 3.4M
static func random_name(rng:RandomNumberGenerator, used:Dictionary)->String
```

## TerritoryData

Fields: `id:int`, `name:String`, `polygon:PackedVector2Array`,
`center:Vector2`, `neighbors:Array[int]`, `terrain:int`,
`is_coastal:bool`, `has_city:bool`, `is_capital:bool`, `has_river:bool`,
`population:int`, `development:int` (0..5), `fort_level:int` (0..3),
`owner_id:int` (-1 = neutral), `garrison:int` (neutral troops),
`army:ArmyData` (null when empty), `supplied:bool` (recomputed),
`move_incoming:Array` (army ids in transit — handled via GameState.transits).

Methods:
- `base_income() -> float`
- `income_per_day() -> float`  # base * (1 + 0.25*development) + bonuses
- `defense_mult() -> float`    # terrain + fort + river, for the DEFENDER
- `develop_cost() -> float`    # 100 * 2^development, -1 if maxed
- `fort_cost() -> float`       # 80 * 2^fort_level, -1 if maxed
- `is_owned_by(nid:int) -> bool`
- `to_dict() -> Dictionary`, `static from_dict(d:Dictionary) -> TerritoryData`

Terrain defense table (defender multiplier):
PLAINS 1.0, FERTILE 1.0, FOREST 1.15, HILLS 1.25, MOUNTAINS 1.5, DESERT 0.9.

## NationData

Fields: `id:int`, `name:String`, `color:Color`, `is_player:bool`,
`personality:int`, `difficulty:int` (AI only; player = -1),
`credits:float`, `supplies:float`, `manpower:float`,
`capital_id:int`, `eliminated:bool`,
`ai_cooldown:float` (days until next AI think),
`stats:Dictionary` {captured, battles_won, battles_lost, troops_lost,
  troops_killed, income_earned},
`to_dict()`, `static from_dict(d)`.

## ArmyData

Fields: `owner_id:int`, `troops:int`, `training:float` (0..1),
`territory_id:int`, `moving:bool`, `move_from:int`, `move_to:int`,
`move_progress:float` (days elapsed), `move_total:float` (days),
`unsupplied_days:float`.
Methods:
- `power(def_mult:float, supplied:bool) -> float` =
  `troops * (1.0 + 0.5*training) * def_mult * (supplied ? 1.0 : UNSUPPLIED_POWER)`
- `to_dict()`, `static from_dict(d)`.

## GameState (the world)

Fields: `territories:Array[TerritoryData]`, `nations:Array[NationData]`
(index == id; player is id 0), `transits:Array[ArmyData]` (moving armies),
`day:float`, `speed:float` (0 = paused), `settings:Dictionary`
{map_size:int, ai_count:int, difficulty:int, preset:String, speed:float},
`over:bool`, `winner_id:int` (-1 = ongoing), `player_won:bool`,
`notifications:Array[Dictionary]` ({day, text, kind}),
`battle_reports:Array[Dictionary]`, `rng:RandomNumberGenerator`.

Creation: `static create(p_settings:Dictionary) -> GameState`
- calls MapGenerator.generate(self)
- applies preset: "standard" {credits:500, supplies:200, troops:300},
  "poor" {250, 120, 180}, "rich" {900, 350, 450}

Per-frame: `tick(days:float)` — order of operations (FIXED):
1. `day += days`
2. `AIBrain.tick(self, days)` (each non-eliminated, non-player nation)
3. `MovementSim.tick(self, days)` (advance transits, resolve arrivals incl. combat)
4. `EconomySim.tick(self, days)`
5. `SupplySim.recompute(self)` then attrition
6. `VictorySim.check(self)` → sets over/winner_id/player_won
7. trim notifications to last 60

Player/AI orders (all validate and return `{ok:bool, error:String}`):
- `order_move(nation_id, from_id, to_id, troops) -> Dictionary`
- `order_recruit(nation_id, territory_id, troops) -> Dictionary`
- `order_develop(nation_id, territory_id) -> Dictionary`
- `order_fortify(nation_id, territory_id) -> Dictionary`
- `training_queues` — Dictionary territory_id -> Array of {troops, days_left, owner_id};
  recruited troops arrive after RECRUIT_TRAIN_DAYS. Stored on GameState,
  saved/loaded.
- helpers: `get_territory(id)`, `get_nation(id)`, `player()`,
  `owned_ids(nid) -> Array[int]`, `army_at(tid) -> ArmyData` (stationed or null),
  `add_notification(text, kind)`, `add_battle_report(d)`.

Serialization: `to_dict() -> Dictionary` (includes version),
`static from_dict(d) -> GameState` (validates; returns null + error via
second return — use `static load_dict(d) -> Array [state, error]`).

## Subsystem contracts (all static, operate on GameState)

- `MapGenerator.generate(state)` — Voronoi via Delaunay dual
  (Geometry2D.triangulate_delaunay), continent masks (3 ellipses + noise),
  terrain via FastNoiseLite, rivers as 2 random walks, capitals spread with
  min distance, each nation gets capital + adjacent starting territories,
  neutral garrisons 20 + value*40, names via Tacterra.random_name.
- `EconomySim.tick(state, days)` — income, upkeep, supply prod/use,
  manpower regen, training queue progress; unpaid upkeep → desertion 3%/day
  + notification (once per nation until resolved).
- `SupplySim.recompute(state)` — BFS from each capital through owned
  territories; sets territory.supplied; armies beyond grace take attrition.
- `MovementSim.tick(state, days)` — advance transits; on arrival:
  own → merge; neutral → CombatSim vs garrison then capture;
  enemy → CombatSim battle. Emits battle reports + notifications.
- `CombatSim.resolve(state, atk:ArmyData, def_t: TerritoryData) -> Dictionary`
  {atk_losses, def_losses, captured:bool, report_text}. Deterministic given
  state (rng only for ±10% jitter — document it).
- `VictorySim.check(state)` — 0 territories → eliminated (remove transits,
  notification); player eliminated → over/defeat; all AI eliminated → over/victory.
- `SaveSystem.save(state, slot:int) -> Dictionary {ok, error}`,
  `SaveSystem.load(slot:int) -> Array [state, error]`,
  `SaveSystem.has_save(slot) -> bool`, slots 0..2, path
  `user://tacterra_save_<slot>.json`.

## AIBrain.tick(state, nation, days)

Per-nation cooldown by difficulty: EASY 5d, NORMAL 3d, HARD 2d.
On think, in order:
1. If credits > 400: develop best-income territory (or fortify most-threatened
   border if DEFENSIVE).
2. Recruit toward target_troops = 120 * territory_count * personality_mult *
   difficulty_mult (EASY 0.6, NORMAL 1.0, HARD 1.2; AGGRESSIVE 1.2, DEFENSIVE 0.9).
3. Expansion: adjacent neutral where local power > garrison*1.3 → move order.
4. Attack: adjacent enemy where power ratio > threshold (EASY 2.2, NORMAL 1.6,
   HARD 1.35; AGGRESSIVE -0.15, DEFENSIVE +0.3) → attack weakest such.
5. Defense: shift troops from safe interior to threatened border (border =
   adjacent to enemy/neutral).
6. H
...[truncated 3346 chars]