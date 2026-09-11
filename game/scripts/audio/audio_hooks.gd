extends Node
## Autoload "Audio". Central SFX hook: gameplay code calls
## Audio.play(&"blast", intensity, event_index) without caring how the
## sound is produced. Right now every id in data/sfx.json is synthesized
## on demand (SfxBuilder + Synth) — no sampled/licensed audio. Calling
## register(id, stream) later swaps in a real recorded asset for that id
## with zero gameplay-code changes.
##
## `intensity` (0..1) and `event_index` (0, 1, 2, ...) let one sfx id cover
## a whole family of moments — e.g. &"match" pitches up with connection
## size, &"chain_step" climbs a scale degree with each cascade wave.

signal sound_played(id: StringName, intensity: float, event_index: int)

const _POOL_SIZE := 14
const _CACHE_CAP := 48

var _players: Array[AudioStreamPlayer] = []
var _registered_streams: Dictionary = {} # StringName -> AudioStream
var _cache: Dictionary = {} # String key -> AudioStreamWAV
var _cache_order: Array = []

func _ready() -> void:
	for i in _POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = AudioSettings.SFX_BUS
		add_child(p)
		_players.append(p)

## Wires a real recorded/licensed-clear asset in for `id`, taking priority
## over the synthesized placeholder from then on.
func register(id: StringName, stream: AudioStream) -> void:
	_registered_streams[id] = stream

func play(id: StringName, intensity: float = 0.0, event_index: int = 0, volume_db: float = 0.0) -> void:
	if not AudioSettings.sfx_enabled:
		return
	var stream: AudioStream = _registered_streams.get(id, null)
	if stream == null:
		stream = _synth_stream(id, intensity, event_index)
	if stream == null:
		return
	var player := _acquire_player()
	player.stream = stream
	player.volume_db = volume_db
	player.play()
	sound_played.emit(id, intensity, event_index)

func _acquire_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0] # a huge cascade can outrun the pool; steal the oldest

func _synth_stream(id: StringName, intensity: float, event_index: int) -> AudioStreamWAV:
	if not GameData.sfx.has(id):
		return null
	var quantized_intensity := int(round(clampf(intensity, 0.0, 1.0) * 20.0))
	var key := "%s:%d:%d" % [id, quantized_intensity, clampi(event_index, 0, 32)]
	if _cache.has(key):
		return _cache[key]
	var buf := SfxBuilder.build(GameData.sfx.get_def(id), intensity, event_index)
	if buf.is_empty():
		return null
	var stream := Synth.build_wav(buf, false)
	_cache[key] = stream
	_cache_order.append(key)
	if _cache_order.size() > _CACHE_CAP:
		_cache.erase(_cache_order.pop_front())
	return stream
