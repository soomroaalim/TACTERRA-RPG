# TACTERRA RPG

**Outthink. Outmaneuver. Conquer.**

An offline 2D territorial warfare strategy game: build a fictional nation,
expand across a living world map, manage credits, supplies and manpower,
maneuver armies, outsmart rival AI rulers, and conquer every rival nation.

- Engine: **Godot 4.3-stable**, GDScript, GL Compatibility renderer
- Fully offline: no accounts, no network, no AI APIs, no ads, no purchases
- Original art drawn in code (Polygon2D/Line2D); all sound effects
  synthesized at runtime — no binary assets in the repository

## Requirements

- Godot **4.3-stable** (the exact version this project targets)
- A desktop OS that runs the Godot editor (Windows, macOS, Linux) for
  development and testing; the project is Android-compatible by design
  (touch input, GL Compatibility renderer)

## Clone and run

```sh
git clone https://github.com/soomroaalim/TACTERRA-RPG.git
cd tacterra
```

1. Open Godot 4.3.
2. **Import** the project: point the project manager at this folder
   (`project.godot` lives at the repository root).
3. Press **F5** (or the Play button) to run. The main scene is
   `res://scripts/ui/main_menu.tscn`.

No export, no build step, and no internet connection are needed to play.

## How to play (summary)

1. **Main menu → Play Offline** opens match setup: choose map size,
   number of AI opponents, AI difficulty, starting preset, and game speed.
2. You start as one nation among several on a fictional world map.
   Select a territory to inspect it; expand into neutral lands, develop
   your economy, recruit armies, and attack rivals through connected
   territories.
3. Balance **Credits** (build/recruit), **Supplies** (keep armies fed),
   and **Manpower** (limits recruitment). Cut-off armies fight weaker.
4. **Victory:** eliminate every rival AI nation. **Defeat:** lose all of
   your territories. Pause anytime; save to one of 3 slots and continue later.
5. Full instructions live in-game under **How to Play**;
   see `docs/CONTROLS.md` and `docs/GAME_DESIGN.md` for details.

## Features

- Fictional world map: multiple landmasses, terrain types
  (plains, fertile, forest, hills, mountains, desert), rivers, coasts,
  cities and capitals — all procedurally generated per match
- Territory expansion with real adjacency rules (no teleporting across
  the map), development levels, and fortifications
- Three-resource economy: Credits, Supplies, Manpower, with upkeep,
  desertion on unpaid wages, and supply lines from your capital
- Army management: recruit (with training time), move, reinforce,
  merge, and fight — deterministic, explainable combat
- Supply simulation: armies cut off from the capital lose power and
  suffer attrition, shown clearly on the map and in panels
- AI opponents with three personalities (Expansionist, Defensive,
  Aggressive) and three difficulties (Easy, Normal, Hard); they expand,
  recruit, attack, defend, and can be eliminated under the same rules
- Match setup, pause/speed controls (0.5x–4x), notifications, battle
  reports, end-of-match result screen with statistics
- Save/load: 3 versioned local slots, validated on load
- Settings screen: volume, default difficulty, map size, game speed —
  persisted to `user://tacterra_settings.json`
- Procedural SFX (click, confirm, error, capture, battle, victory,
  defeat, notify) with working volume control; no audio files

## Testing

Automated tests run headless — no display needed:

```sh
godot --headless --path . --script res://tests/run_tests.gd
```

The runner discovers every `tests/test_*.gd` and reports pass/fail per
case. See `docs/TESTING.md` for what each file covers and the manual
test checklist.

## Project structure

```
project.godot            # project root IS the Godot project root
scripts/core/            # simulation: game state, map gen, economy,
                         # supply, movement, combat, victory, saves, AI
scripts/audio/           # procedural SFX (AudioManager) + GameSettings
scripts/ui/              # main menu, match setup, game screen,
                         # how-to-play, settings, credits
tests/                   # headless test runner + test_*.gd suites
tools/                   # screenshot harness for Xvfb runs
docs/                    # architecture, design, controls, testing,
                         # limitations
```

Single source of truth: `GameState` (RefCounted). UI renders from it and
issues orders through its methods; all subsystems are static classes
operating on it. No autoloads. See `docs/ARCHITECTURE.md`.

## Current limitations

This milestone is desktop-tested and ships **no APK/AAB** and **no
multiplayer** (both explicitly out of scope). Touch controls are
implemented for Android but not yet device-verified. Full list:
`docs/LIMITATIONS.md`.

## License

Original work created for this project. All code, generated map art,
and synthesized sound effects are original; no third-party assets are
included or required.
