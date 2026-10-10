class_name AudioManager
extends Node
## Procedural SFX synthesizer + playback pool. No audio assets are needed:
## every sound is generated at runtime as an AudioStreamWAV (16-bit mono,
## 22050 Hz) and cached after first use.
##
## Playback uses a round-robin pool of AudioStreamPlayer children so
## overlapping sounds (e.g. battle + capture) do not cut each other off.
## Safe to use headless: synthesis is pure math, and play() is a no-op when
## muted, the name is unknown, or the node is outside a live scene tree.

const MIX_RATE := 22050
const POOL_SIZE := 6
const FADE_MS := 5.0 ## click-free fade in/out at note boundaries

const SFX_NAMES: Array[String] = [
	"click", "confirm", "error", "capture",
	"battle", "victory", "defeat", "notify",
]

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next := 0
var _volume := 0.8


func _ready() -> void:
	_ensure_players()


func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SfxPlayer%d" % i
		p.volume_db = _db_for(_volume)
		p.bus = &"Master"
		add_child(p)
		_players.append(p)


static func _db_for(v: float) -> float:
	if v <= 0.001:
		return -80.0
	return linear_to_db(clampf(v, 0.0, 1.0))


func set_volume(v: float) -> void:
	_volume = clampf(v, 0.0, 1.0)
	var db := _db_for(_volume)
	for p in _players:
		p.volume_db = db


func get_volume() -> float:
	return _volume


func has_sfx(sfx_name: String) -> bool:
	return sfx_name in SFX_NAMES


## Returns the synthesized stream for `sfx_name`, generating and caching it
## on first use. Returns null for unknown names.
func get_sfx(sfx_name: String) -> AudioStreamWAV:
	if not has_sfx(sfx_name):
		return null
	if _streams.has(sfx_name):
		return _streams[sfx_name]
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = _build(sfx_name)
	_streams[sfx_name] = wav
	return wav


## Plays a named sound. No-op when muted, when the name is unknown, or when
## this node is not inside a live scene tree (e.g. headless unit tests).
func play(sfx_name: String) -> void:
	if _volume <= 0.0:
		return
	if not is_inside_tree():
		return
	var stream := get_sfx(sfx_name)
	if stream == null:
		return
	_ensure_players()
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.play()


# ---------------------------------------------------------------- synthesis

func _build(sfx_name: String) -> PackedByteArray:
	match sfx_name:
		"click": # 60ms 880Hz sine blip with decay
			return _tone(880.0, 60.0, "sine", 5.0, 0.8)
		"confirm": # two-tone 660 -> 990Hz
			return _concat([
				_tone(660.0, 90.0, "sine", 4.0, 0.8),
				_tone(990.0, 140.0, "sine", 4.0, 0.8),
			])
		"error": # 140ms 160Hz square-ish buzz
			return _tone(160.0, 140.0, "squareish", 2.5, 0.7)
		"capture": # rising arpeggio 440 / 554 / 659Hz
			return _concat([
				_tone(440.0, 110.0, "sine", 3.5, 0.8),
				_tone(554.37, 110.0, "sine", 3.5, 0.8),
				_tone(659.25, 160.0, "sine", 3.5, 0.8),
			])
		"battle": # 300ms noise burst + low thump
			return _battle_sound()
		"victory": # 4-note fanfare 523 / 659 / 784 / 1046Hz
			return _concat([
				_tone(523.25, 150.0, "sine", 3.0, 0.85),
				_tone(659.25, 150.0, "sine", 3.0, 0.85),
				_tone(783.99, 150.0, "sine", 3.0, 0.85),
				_tone(1046.5, 300.0, "sine", 2.5, 0.9),
			])
		"defeat": # descending 392 / 311 / 262Hz
			return _concat([
				_tone(392.0, 180.0, "sine", 3.0, 0.8),
				_tone(311.13, 180.0, "sine", 3.0, 0.8),
				_tone(261.63, 320.0, "sine", 2.5, 0.8),
			])
		"notify": # soft 1200Hz ping, 80ms
			return _tone(1200.0, 80.0, "sine", 6.0, 0.5)
	return PackedByteArray()


## Single enveloped tone. `decay` is the exponential falloff over the tone's
## own duration; a 5ms fade in/out removes edge clicks.
func _tone(freq: float, dur_ms: float, wave: String, decay: float, vol: float) -> PackedByteArray:
	var n := int(MIX_RATE * dur_ms / 1000.0)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var fade_n := maxi(int(MIX_RATE * FADE_MS / 1000.0), 1)
	var dur_s := dur_ms / 1000.0
	for i in n:
		var t := float(i) / MIX_RATE
		var s := 0.0
		match wave:
			"sine":
				s = sin(TAU * freq * t)
			"squareish": # sine body + squared edge = buzzy but not harsh
				var ph := sin(TAU * freq * t)
				s = 0.65 * sign(ph) + 0.35 * ph
		var env := exp(-decay * t / dur_s)
		var fade := 1.0
		if i < fade_n:
			fade = float(i) / float(fade_n)
		elif i >= n - fade_n:
			fade = float(n - i) / float(fade_n)
		var v := int(clampf(s * env * fade * vol, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return bytes


func _battle_sound() -> PackedByteArray:
	var dur_ms := 300.0
	var n := int(MIX_RATE * dur_ms / 1000.0)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fade_n := maxi(int(MIX_RATE * FADE_MS / 1000.0), 1)
	var dur_s := dur_ms / 1000.0
	for i in n:
		var t := float(i) / MIX_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var thump := sin(TAU * 70.0 * t)
		var env := exp(-3.0 * t / dur_s)
		var fade := 1.0
		if i < fade_n:
			fade = float(i) / float(fade_n)
		elif i >= n - fade_n:
			fade = float(n - i) / float(fade_n)
		var s := (0.55 * noise + 0.6 * thump) * env * fade * 0.8
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return bytes


func _concat(parts: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for p in parts:
		out.append_array(p as PackedByteArray)
	return out
