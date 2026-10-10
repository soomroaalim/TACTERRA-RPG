# TACTERRA RPG — Current Limitations (honest list)

This is the v0.1.0 offline milestone. The following are known limits —
nothing here is presented as complete.

## Explicitly out of scope for this phase

- **No APK / AAB.** Per the project brief, no Android package is
  generated, signed, or distributed in this phase.
- **No online multiplayer**, matchmaking, leaderboards, accounts,
  cloud saves, ads, or in-app purchases.
- **No external AI APIs.** All AI is local deterministic GDScript.
- No music: audio is 8 synthesized sound effects only.

## Platform verification

- Tested on **desktop** (Godot 4.3 editor runs, headless test suite,
  Xvfb screenshot runs). Android compatibility is by design (touch
  input, GL Compatibility renderer, 1280×720 stretch layout) but
  **no Android device test has been performed** — do not claim
  device-verified touch handling.
- Performance on low-end Android hardware is unmeasured; the simulation
  is tick-based and cheap, but large maps on weak GPUs are unverified.

## Gameplay simplifications (by design for v0.1.0)

- One unit type (soldiers); no unit composition beyond the training
  level. Combat has a documented ±10% jitter — the only randomness.
- Diplomacy, trade, espionage, and alliances are not implemented;
  every AI nation is a potential enemy.
- Single victory condition: eliminate all rival nations. No
  timed/score/alternate victory modes yet.
- Supply sources are capitals only; there is no naval or air layer.
- Map is fictional and regenerated per match — no hand-crafted
  scenarios or scenario editor.

## Technical notes

- Saves are local JSON (`user://`); deleting app data deletes saves
  and settings. No migration path is needed yet (save version 1).
- Settings and save files are plain JSON — editable by the user;
  corrupt files safely fall back to defaults / rejection, never a crash.
- The editor class cache must be refreshed (`godot --editor --quit
  --path .`) after adding or renaming scripts before headless runs
  resolve `class_name` references.
