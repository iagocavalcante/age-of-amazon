# scripts/autoloads/Sfx.gd
extends Node

# Procedural audio, in the same spirit as the procedural art: every sound is
# synthesized into an AudioStreamWAV at startup — chops, bow twangs, thuds,
# chimes, and a looping jungle ambience with baked bird chirps. Playback is
# a small round-robin player pool; world sounds are skipped when they happen
# far off-camera. Volume/mute persist to user://settings.json and the HUD
# exposes a control.

const SAMPLE_RATE: int = 22050
const SETTINGS_PATH: String = "user://settings.json"
const POOL_SIZE: int = 10
const HEARING_RANGE: float = 900.0  # world px from camera center

var muted: bool = false
var volume: float = 0.8  # 0..1 master

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _ambience: AudioStreamPlayer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	if Net.is_headless_server() or DisplayServer.get_name() == "headless":
		pass  # still build streams so harnesses can assert on them
	_rng.randomize()
	_build_streams()
	for _i in range(POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _streams["ambience"]
	_ambience.volume_db = -14.0
	add_child(_ambience)
	_load_settings()
	_apply()

	EventBus.world_ready.connect(ambience_start)
	EventBus.building_constructed.connect(func(b: Node2D) -> void:
		play("built", b.global_position))
	EventBus.game_over.connect(func(winner: int) -> void:
		ambience_stop()
		play("victory" if winner == GameManager.local_player_id else "defeat"))
	EventBus.unit_died.connect(func(u: Node2D) -> void:
		play("die", u.global_position))
	EventBus.animal_hunted.connect(func(a: Node2D, _h: Node2D, _f: int) -> void:
		play("die", a.global_position))

# --- Playback ---

func play(sound: String, world_pos: Variant = null, volume_db: float = 0.0) -> void:
	if muted or not _streams.has(sound):
		return
	if world_pos is Vector2 and not _audible(world_pos):
		return
	var player: AudioStreamPlayer = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	player.stream = _streams[sound]
	player.volume_db = volume_db + linear_to_db(maxf(volume, 0.01))
	player.pitch_scale = _rng.randf_range(0.93, 1.07)
	player.play()

func ambience_start() -> void:
	if Net.is_headless_server() or muted or _ambience.playing:
		return
	_ambience.play()

func ambience_stop() -> void:
	_ambience.stop()

func _audible(world_pos: Vector2) -> bool:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return true
	return camera.global_position.distance_to(world_pos) < HEARING_RANGE / camera.zoom.x

# --- Settings ---

func set_muted(value: bool) -> void:
	muted = value
	_apply()
	_save_settings()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	_apply()
	_save_settings()

func _apply() -> void:
	AudioServer.set_bus_mute(0, muted)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.01)))
	if muted:
		_ambience.stop()

func _save_settings() -> void:
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"muted": muted, "volume": volume}))

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if parsed is Dictionary:
		muted = bool(parsed.get("muted", false))
		volume = clampf(float(parsed.get("volume", 0.8)), 0.0, 1.0)

# --- Synthesis ---

func _build_streams() -> void:
	_streams["chop"] = _render(0.10, func(t: float, p: float) -> float:
		return (_noise() * 0.7 + sin(TAU * 170.0 * t) * 0.5) * pow(1.0 - p, 3.0))
	_streams["tick"] = _render(0.07, func(t: float, p: float) -> float:
		return sin(TAU * 880.0 * t) * 0.5 * pow(1.0 - p, 2.0))
	_streams["hammer"] = _render(0.11, func(t: float, p: float) -> float:
		return (_noise() * 0.5 + sin(TAU * 300.0 * t) * 0.6) * pow(1.0 - p, 3.5))
	_streams["bow"] = _render(0.16, func(t: float, p: float) -> float:
		return (sin(TAU * (420.0 - 200.0 * p) * t) * 0.5 + _noise() * 0.25 * (1.0 - p)) \
			* pow(1.0 - p, 1.6))
	_streams["hit"] = _render(0.09, func(t: float, p: float) -> float:
		return (sin(TAU * 120.0 * t) * 0.8 + _noise() * 0.3) * pow(1.0 - p, 2.5))
	_streams["die"] = _render(0.28, func(t: float, p: float) -> float:
		return sin(TAU * (110.0 - 50.0 * p) * t) * 0.6 * pow(1.0 - p, 1.5))
	_streams["click"] = _render(0.035, func(t: float, p: float) -> float:
		return sin(TAU * 1100.0 * t) * 0.35 * (1.0 - p))
	_streams["built"] = _chime([523.25, 659.25, 783.99], 0.14)
	_streams["victory"] = _chime([523.25, 659.25, 783.99, 1046.5], 0.2)
	_streams["defeat"] = _chime([392.0, 311.13, 261.63], 0.24)
	_streams["ambience"] = _render_ambience(7.0)

func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)

func _render(duration: float, sample: Callable) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var progress: float = float(i) / count
		var value: int = int(clampf(sample.call(t, progress), -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, value)
	return _wav(bytes)

# Sequential soft tones (square-ish envelope per note).
func _chime(freqs: Array, note_len: float) -> AudioStreamWAV:
	var count: int = int(note_len * freqs.size() * SAMPLE_RATE)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var per_note: int = int(note_len * SAMPLE_RATE)
	for i in range(count):
		var note: int = mini(i / per_note, freqs.size() - 1)
		var t: float = float(i) / SAMPLE_RATE
		var np: float = float(i % per_note) / per_note
		var value: float = sin(TAU * freqs[note] * t) * 0.45 * pow(1.0 - np, 1.2)
		bytes.encode_s16(i * 2, int(value * 32000.0))
	return _wav(bytes)

# A soft filtered-noise bed with baked bird chirps, looped.
func _render_ambience(duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var low: float = 0.0
	# Pre-roll chirps: [start_sample, base_freq, length_samples]
	var chirps: Array = []
	for _i in range(9):
		chirps.append([_rng.randi_range(0, count - 4000),
			_rng.randf_range(1400.0, 2600.0), _rng.randi_range(900, 2200)])
	for i in range(count):
		var t: float = float(i) / SAMPLE_RATE
		low = low * 0.986 + _noise() * 0.014  # cheap lowpass wind bed
		var value: float = low * 1.7
		for chirp: Array in chirps:
			var offset: int = i - int(chirp[0])
			if offset >= 0 and offset < int(chirp[2]):
				var cp: float = float(offset) / float(chirp[2])
				value += sin(TAU * (chirp[1] + sin(cp * TAU * 3.0) * 220.0) * t) \
					* 0.16 * sin(cp * PI)
		bytes.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 30000.0))
	var wav: AudioStreamWAV = _wav(bytes)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = count
	return wav

func _wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
