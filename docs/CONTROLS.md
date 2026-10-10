# TACTERRA RPG — Controls

The game is designed for Android touch first, with full mouse support
for desktop testing. No keyboard shortcuts are required for anything.

## Desktop (mouse)

| Action | Input |
|---|---|
| Select territory | Left click |
| Pan map | Left-drag on empty map area |
| Zoom | Mouse wheel, or on-screen + / − buttons |
| Confirm / cancel dialogs | Click the dialog buttons |

## Android (touch)

| Action | Input |
|---|---|
| Select territory | Tap (forgiving hit area — you don't need pixel precision) |
| Pan map | Drag one finger |
| Zoom | Pinch with two fingers, or on-screen + / − buttons |
| All buttons and panels | Tap; sized for fingers, no tiny controls |

`emulate_touch_from_mouse` is enabled, so mouse input exercises the
same touch path during desktop testing.

## Per screen

**Main menu** — Play Offline · Continue (enabled only when a save
exists) · How to Play · Settings · Credits. Every button performs its
action; there are no decorative buttons.

**Match setup** — Map size (Small/Standard/Large) · AI opponents
(count) · AI difficulty (Easy/Normal/Hard) · Starting preset
(Poor/Standard/Rich) · Game speed default. Every option changes the
generated match. *Start Match* begins; *Back* returns to the menu.

**Game screen**

- Top bar: Credits, Supplies, Manpower (live values), day counter,
  pause, and speed selector (0.5× / 1× / 2× / 4×).
- Tap a territory to select it (highlighted). The info panel shows:
  name, owner, terrain, population/manpower, income, defense bonuses,
  stationed army, supply status, and available actions.
- Tap one of your territories, then a connected territory, to issue a
  **move/attack** order; a confirmation shows the troops and the
  estimated odds before you commit.
- **Recruit** / **Develop** / **Fortify** buttons appear on your own
  territories, each showing its cost before you confirm. You can never
  spend resources you don't have — the game blocks it with a reason.
- Army markers show positions; arrows show movement and attacks;
  notifications and battle reports appear in the feed panel.
- Menu button: Save (3 slots), Settings, How to Play, Quit to main menu.

**How to Play** — scrollable guide: controls, economy, combat,
supply, objectives.

**Settings** — Volume slider (applies immediately to SFX) · default
AI difficulty · default map size · default game speed. Saved
automatically to `user://tacterra_settings.json` and restored on launch.

**Credits** — game title, engine (Godot 4.3), contributors.

**Result screen** (victory/defeat) — outcome, match statistics
(territories captured, battles won/lost, troops lost/killed, income
earned, duration), *New Match* and *Main Menu* buttons.
