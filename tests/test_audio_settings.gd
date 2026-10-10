extends RefCounted
## Audio + settings tests.
## static func run() -> Array of {name:String, passed:bool, note:String}.
## Run: godot --headless --path . --script res://tests/run_tests.gd


static func _t(name: String, passed: bool, note: String = "") -> Dictionary:
	return {"name": name, "passed": passed, "note": note}


static func _cleanup_settings() -> void:
	if FileAccess.file_exists(GameSettings.PATH):
		DirAccess.remove_absolute(GameSettings.PATH)


static func run() -> Array:
	var results: Array = []

	# ---------------------------------------------------------- GameSettings
	_cleanup_settings()

	var d := GameSettings.load_settings()
	results.append(_t("settings_defaults_volume",
		absf(float(d.get("volume", -1.0)) - 0.8) < 0.0001,
		"volume=" + str(d.get("volume"))))
	results.append(_t("settings_defaults_difficulty",
		int(d.get("difficulty", -1)) == 1, "difficulty=" + str(d.get("difficulty"))))
	results.append(_t("settings_defaults_map_size",
		int(d.get("map_size", -1)) == 1, "map_size=" + str(d.get("map_size"))))
	results.append(_t("settings_defaults_speed_idx",
		int(d.get("speed_idx", -1)) == 1, "speed_idx=" + str(d.get("speed_idx"))))

	# Round-trip: save custom values, load them back.
	GameSettings.save_settings({"volume": 0.3, "difficulty": 2, "map_size": 0, "speed_idx": 3})
	var d2 := GameSettings.load_settings()
	results.append(_t("settings_roundtrip",
		absf(float(d2["volume"]) - 0.3) < 0.0001
		and int(d2["difficulty"]) == 2
		and int(d2["map_size"]) == 0
		and int(d2["speed_idx"]) == 3,
		JSON.stringify(d2)))

	# Clamping on load.
	GameSettings.save_settings({"volume": 2.0, "difficulty": 9, "map_size": -5, "speed_idx": 99})
	var d3 := GameSettings.load_settings()
	results.append(_t("settings_clamp_volume_high",
		absf(float(d3["volume"]) - 1.0) < 0.0001, "volume=" + str(d3["volume"])))
	results.append(_t("settings_clamp_difficulty",
		int(d3["difficulty"]) == 2, "difficulty=" + str(d3["difficulty"])))
	results.append(_t("settings_clamp_map_size",
		int(d3["map_size"]) == 0, "map_size=" + str(d3["map_size"])))
	results.append(_t("settings_clamp_speed_idx",
		int(d3["speed_idx"]) == 3, "speed_idx=" + str(d3["speed_idx"])))

	GameSettings.save_settings({"volume": -0.5})
	var d4 := GameSettings.load_settings()
	results.append(_t("settings_clamp_volume_low",
		absf(float(d4["volume"]) - 0.0) < 0.0001, "volume=" + str(d4["volume"])))

	# get_value helper.
	GameSettings.save_settings({"volume": 0.42})
	results.append(_t("settings_get_value_present",
		absf(float(GameSettings.get_value("volume", 0.9)) - 0.42) < 0.0001,
		"got=" + str(GameSettings.get_value("volume", 0.9))))
	results.append(_t("settings_get_value_missing",
		absf(float(GameSettings.get_value("nope_key", 0.9)) - 0.9) < 0.0001,
		"got=" + str(GameSettings.get_value("nope_key", 0.9))))

	# Corrupt file (garbage bytes) -> defaults, no crash.
	var f := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
	f.store_string("this is not { valid json !!! <garbage bytes>")
	f.close()
	var d5 := GameSettings.load_settings()
	results.append(_t("settings_corrupt_garbage",
		absf(float(d5["volume"]) - 0.8) < 0.0001 and int(d5["difficulty"]) == 1,
		"fell back to defaults"))

	# Valid JSON but wrong type -> defaults, no crash.
	var f2 := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
	f2.store_string("[1, 2, 3]")
	f2.close()
	var d6 := GameSettings.load_settings()
	results.append(_t("settings_corrupt_wrong_type",
		absf(float(d6["volume"]) - 0.8) < 0.0001,
		"fell back to defaults"))

	# Missing keys in a valid file keep defaults for those keys.
	var f3 := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
	f3.store_string('{"volume": 0.25}')
	f3.close()
	var d7 := GameSettings.load_settings()
	results.append(_t("settings_partial_file",
		absf(float(d7["volume"]) - 0.25) < 0.0001 and int(d7["difficulty"]) == 1,
		JSON.stringify(d7)))

	_cleanup_settings()

	# --------------------------------------------------------- AudioManager
	var am := AudioManager.new()

	# Synthesis is pure math: must work headless, with no scene tree.
	var ok_all := true
	var notes := PackedStringArray()
	for sfx_name in AudioManager.SFX_NAMES:
		var wav := am.get_sfx(sfx_name)
		var good := wav != null \
			and wav.format == AudioStreamWAV.FORMAT_16_BITS \
			and wav.mix_rate == AudioManager.MIX_RATE \
			and not wav.stereo \
			and wav.data.size() > 0
		if not good:
			ok_all = false
			notes.append(sfx_name)
	results.append(_t("audio_synth_all_8", ok_all,
		"bad: " + ", ".join(notes) if not ok_all else "8/8 streams valid"))

	# Exact byte lengths for two representative sounds
	# (60ms and 300ms at 22050 Hz, 16-bit mono).
	var click_wav := am.get_sfx("click")
	var battle_wav := am.get_sfx("battle")
	var click_samples := int(AudioManager.MIX_RATE * 60.0 / 1000.0)
	var battle_samples := int(AudioManager.MIX_RATE * 300.0 / 1000.0)
	results.append(_t("audio_click_length",
		click_wav.data.size() == click_samples * 2,
		"bytes=" + str(click_wav.data.size()) + " expected=" + str(click_samples * 2)))
	results.append(_t("audio_battle_length",
		battle_wav.data.size() == battle_samples * 2,
		"bytes=" + str(battle_wav.data.size()) + " expected=" + str(battle_samples * 2)))

	# Caching: same object returned on repeat requests.
	results.append(_t("audio_stream_cached",
		am.get_sfx("click") == am.get_sfx("click"),
		"lazy cache hit"))

	# Unknown names: no-op, no crash.
	var unknown_ok := true
	am.play("does_not_exist")
	if am.get_sfx("does_not_exist") != null:
		unknown_ok = false
	if am.has_sfx("does_not_exist"):
		unknown_ok = false
	results.append(_t("audio_unknown_name_noop", unknown_ok,
		"play() no-op, get_sfx() null, has_sfx() false"))

	# play() every known name headless (no tree): must not crash or error.
	for sfx_name in AudioManager.SFX_NAMES:
		am.play(sfx_name)
	results.append(_t("audio_play_all_headless", true,
		"8/8 play() calls returned without crash"))

	# Volume: mapping to volume_db, muting skips playback.
	am._ensure_players()
	am.set_volume(0.5)
	var db_ok := absf(am._players[0].volume_db - linear_to_db(0.5)) < 0.01
	am.set_volume(0.0)
	var mute_ok := absf(am._players[0].volume_db - (-80.0)) < 0.01
	am.play("click") # muted: must be a silent no-op, no crash
	am.set_volume(1.5) # clamped to 1.0
	var clamp_ok := absf(am.get_volume() - 1.0) < 0.0001 \
		and absf(am._players[0].volume_db - linear_to_db(1.0)) < 0.01
	am.set_volume(-2.0) # clamped to 0.0
	clamp_ok = clamp_ok and absf(am.get_volume() - 0.0) < 0.0001
	results.append(_t("audio_set_volume_db", db_ok and mute_ok and clamp_ok,
		"db@0.5=" + str(am._players[0].volume_db)))

	# Pool size per contract.
	results.append(_t("audio_pool_size",
		am._players.size() == AudioManager.POOL_SIZE,
		"players=" + str(am._players.size())))

	am.free()
	return results
