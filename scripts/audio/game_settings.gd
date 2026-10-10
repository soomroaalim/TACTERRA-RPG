class_name GameSettings
extends RefCounted
## Persistent player settings stored as JSON in user://.
## Never crashes on missing or corrupt files: falls back to defaults.

const PATH := "user://tacterra_settings.json"

## Defaults: volume 0.8 (0..1), difficulty 1 = Normal (Tacterra.Difficulty),
## map_size 1 = Standard (Tacterra.MapSize), speed_idx 1 = 1x (Tacterra.SPEEDS).
const DEFAULTS := {
	"volume": 0.8,
	"difficulty": 1,
	"map_size": 1,
	"speed_idx": 1,
}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate()


static func load_settings() -> Dictionary:
	var d := DEFAULTS.duplicate()
	if not FileAccess.file_exists(PATH):
		return d
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return d
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return d
	for key in DEFAULTS.keys():
		if (parsed as Dictionary).has(key):
			d[key] = _clamp_value(key, (parsed as Dictionary)[key])
	return d


static func save_settings(d: Dictionary) -> void:
	var clean := DEFAULTS.duplicate()
	for key in DEFAULTS.keys():
		if d.has(key):
			clean[key] = _clamp_value(key, d[key])
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(clean))
	f.close()


## Reads one setting from disk, returning `default` when absent or unreadable.
static func get_value(key: String, default: Variant) -> Variant:
	var d := load_settings()
	return d.get(key, default)


static func _clamp_value(key: String, value: Variant) -> Variant:
	match key:
		"volume":
			return clampf(float(value), 0.0, 1.0)
		"difficulty":
			return clampi(int(value), 0, 2)
		"map_size":
			return clampi(int(value), 0, 2)
		"speed_idx":
			return clampi(int(value), 0, 3)
	return value
