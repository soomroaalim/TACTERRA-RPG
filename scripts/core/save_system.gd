class_name SaveSystem
extends RefCounted
## TACTERRA RPG — versioned local save/load.
##
## Saves are JSON files at user://tacterra_save_<slot>.json (slots 0..2).
## SaveSystem never crashes on bad data: every failure returns a human
## readable error string.

const SAVE_PATH := "user://tacterra_save_%d.json"


static func _path(slot: int) -> String:
	return SAVE_PATH % slot


static func save(state: GameState, slot: int) -> Dictionary:
	if slot < 0 or slot >= Tacterra.SAVE_SLOTS:
		return {"ok": false, "error": "Invalid save slot."}
	if state == null:
		return {"ok": false, "error": "No game state to save."}
	var text := JSON.stringify(state.to_dict())
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Could not write save file."}
	f.store_string(text)
	f.close()
	return {"ok": true, "error": ""}


## Returns [state: GameState, error: String].
static func load(slot: int) -> Array:
	if slot < 0 or slot >= Tacterra.SAVE_SLOTS:
		return [null, "Invalid save slot."]
	var path := _path(slot)
	if not FileAccess.file_exists(path):
		return [null, "No save in slot %d." % slot]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return [null, "Could not read save file."]
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return [null, "corrupt save data"]
	return GameState.load_dict(parsed)


static func has_save(slot: int) -> bool:
	if slot < 0 or slot >= Tacterra.SAVE_SLOTS:
		return false
	return FileAccess.file_exists(_path(slot))


static func delete(slot: int) -> void:
	if slot < 0 or slot >= Tacterra.SAVE_SLOTS:
		return
	var path := _path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
