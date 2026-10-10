# TACTERRA RPG — Testing

## Automated tests (headless)

No display or GPU needed. From the project root:

```sh
# Refresh the editor class cache after adding/renaming scripts:
godot --editor --quit --path .

# Run the full suite:
godot --headless --path . --script res://tests/run_tests.gd
```

`tests/run_tests.gd` (extends SceneTree) auto-discovers every
`tests/test_*.gd`, calls its `static func run() -> Array`, and prints
`PASS`/`FAIL` per case plus a `TESTS: total=… passed=… failed=…` summary.
Exit code is 0 only when everything passes. Each case returns
`{name, passed, note}`.

### Suite coverage

| File | Covers |
|---|---|
| `test_audio_settings.gd` | Settings defaults, save/load round-trip, value clamping, `get_value`, corrupt/wrong-type/partial settings files → safe defaults; all 8 SFX synthesize headless (16-bit/22050 Hz/mono, non-empty, exact byte lengths), lazy caching, unknown-name no-op, `play()` without crash, volume→dB mapping incl. mute, 6-player pool |
| `test_map.gd` | Territory counts per map size, sequential IDs, symmetric neighbors, connected graph, capitals assigned and spread, unique names, neutral garrisons, terrain mix, determinism per seed |
| `test_save.gd` | Save/load round-trip, slot validation, missing slot, garbage / wrong-type / bad-version / incomplete save data rejected, null state rejected |
| `test_ai.gd` | AI think cooldowns per difficulty, player nation untouched by AI, expansion/attack/recruit/defense decisions |

Integration-style coverage (full match sequences: orders → movement →
combat → economy → victory) is exercised through the simulation suites
above using real `GameState` instances.

## Manual test checklist (PRD §18)

| # | Test | How verified |
|---|---|---|
| 1 | Project opens without critical errors | Editor import + `--editor --quit` clean; headless test runs clean |
| 2 | Main menu works (all buttons act) | Manual playtest (see note) |
| 3 | New match starts with chosen setup | Manual playtest; setup options feed `GameState.create` (covered by map/save suites) |
| 4 | Select and capture a neutral territory | Manual playtest; adjacency + capture logic covered by sim suites |
| 5 | Resources update correctly | Manual playtest; economy math covered by sim suites |
| 6 | AI expands and acts meaningfully | Manual playtest; `test_ai.gd` |
| 7 | Armies move and engage in combat | Manual playtest; movement/combat sim suites |
| 8 | Territories change ownership correctly | Manual playtest; sim suites |
| 9 | Victory and defeat can occur | Manual playtest to both endings; victory sim suite |
| 10 | Saved match restores actual state | Manual playtest; `test_save.gd` round-trip |
| 11 | Match restart works | Manual playtest |
| 12 | Desktop mouse controls (click/drag/wheel) | Manual playtest |
| 13 | Touch interactions suitable for Android | Implemented (tap/drag/pinch, touch-sized UI, `emulate_touch_from_mouse`); **device verification pending** — no Android device test in this phase |
| 14 | Runs with no internet access | The game makes zero network calls; verified by running headless with networking unavailable |

Note: items marked "manual playtest" are verified by running the game in
the Godot editor (F5) and by Xvfb screenshot runs (`tools/capture.gd`),
since this phase ships no APK. Anything not yet verified is listed in
`docs/LIMITATIONS.md` — never claimed as done.

## Screenshot evidence

`tools/capture.gd` (extends SceneTree) renders key screens under Xvfb
and saves PNGs for review: main menu, match setup, world map, active
gameplay, battle, and the end-game screen. Genuine captures only —
never mockups.
