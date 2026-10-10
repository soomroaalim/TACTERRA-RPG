# Changelog — TACTERRA RPG

All notable changes to this project are documented here.
Format: `## [version] - date` with `Added / Changed / Fixed / Known issues`.

---

## [v0.1.0] - 2026-10-10

First complete playable offline milestone: a full skirmish from main menu
to victory or defeat, built in Godot 4.3-stable with GDScript.

### Added

- **World map**: procedurally generated fictional world (Delaunay/Voronoi
  territories, 3 continent masks, terrain via noise, rivers, coasts,
  cities, spread-out capitals). Map sizes: Small (24), Standard (36),
  Large (48 territories). Pan/zoom, touch-friendly selection.
- **Territory mechanics**: ownership, adjacency-validated expansion and
  attack orders, development levels (0–5), fort levels (0–3), neutral
  garrisons, border updates on capture.
- **Economy**: Credits, Supplies, Manpower. Terrain/city/capital/coastal/
  river income, development bonuses, recruitment costs, per-soldier
  upkeep and supply use, manpower regen, 3%/day desertion on unpaid
  upkeep with a one-time warning.
- **Armies**: recruit with 3-day training queues, move between connected
  territories, merge on arrival, reinforce borders, redirect while in
  transit. Travel progress shown on the map.
- **Combat**: deterministic resolution from army power
  (`troops × (1 + 0.5×training) × defender-mult × supply-mult`), terrain
  defense table, 1.25× defender bonus, documented ±10% jitter;
  casualties, captures, battle reports and notifications update the
  real game state.
- **Supply**: BFS from each capital through owned territory; cut-off
  armies fight at 60% power after a 3-day grace period and suffer 2%/day
  attrition. Supply status shown per territory and army.
- **Enemy AI**: 3 personalities (Expansionist, Defensive, Aggressive) ×
  3 difficulties (Easy, Normal, Hard). AI expands, develops/fortifies,
  recruits toward targets, attacks at difficulty-based power thresholds,
  and reinforces threatened borders — under the same rules as the player.
- **Match flow**: main menu (Play Offline, Continue, How to Play,
  Settings, Credits), match setup (map size, AI count, difficulty,
  starting preset, speed), pause + 0.5x/1x/2x/4x speed, victory/defeat
  detection, result screen with match statistics, restart / back to menu.
- **Save/load**: 3 versioned JSON slots (`user://tacterra_save_<n>.json`),
  validated on load; corrupt or incompatible saves are rejected with an
  error instead of crashing.
- **Audio**: 8 procedurally synthesized SFX (click, confirm, error,
  capture, battle, victory, defeat, notify) with a 6-player overlap pool;
  volume setting persisted via the settings screen.
- **Settings**: volume, default difficulty, map size, game speed —
  stored in `user://tacterra_settings.json`, safe defaults on corrupt data.
- **Tests**: headless suites covering map generation, orders, economy,
  combat, supply, AI, victory/defeat, save/load (incl. invalid data),
  audio and settings; run with
  `godot --headless --path . --script res://tests/run_tests.gd`.
- **Docs**: README, GAME_DESIGN, CONTROLS, TESTING, LIMITATIONS,
  ARCHITECTURE.

### Known issues

- No APK/AAB is produced in this phase (per scope); Android touch
  controls are implemented but not device-verified.
- See `docs/LIMITATIONS.md` for the full list.
