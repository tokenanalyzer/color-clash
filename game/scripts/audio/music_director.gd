extends Node
## Autoload "Music". Adaptive vertical-layer music system: every layer in
## data/music.json (pad/bass/arpeggio/perc/fever_lead) is a seamless loop
## rendered once at boot and started together so they stay phase-locked.
## Gameplay code never restarts or swaps tracks — it just calls
## set_state(&"active"/&"high"/&"fever"/&"tension"/...) and the relevant
## layers crossfade in/out. This is what makes intensity changes feel
## seamless instead of a jarring track switch.

signal state_changed(state: StringName)

var _layer_players: Dictionary = {} # String layer_id -> AudioStreamPlayer
var _current_state: StringName = &"idle"
var _started := false
var _fade_tween: Tween

## A single real-track player for non-gameplay ambience (menu/map) — see
## play_ambient()/stop_ambient(). Independent of the layered gameplay system
## above (which only ever runs during actual level play), so it can never
## stack with it; only one of the two is ever audible at a time in practice.
var _ambient_player: AudioStreamPlayer
var _ambient_id: StringName = &""
var _ambient_tween: Tween

func _ready() -> void:
	for layer_id in GameData.music.layers.keys():
		var player := AudioStreamPlayer.new()
		player.bus = AudioSettings.MUSIC_BUS
		player.volume_db = -80.0
		add_child(player)
		var buf := MusicLayerBuilder.build(GameData.music, StringName(String(layer_id)))
		if not buf.is_empty():
			player.stream = Synth.build_wav(buf, true)
		_layer_players[layer_id] = player

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = AudioSettings.MUSIC_BUS
	_ambient_player.volume_db = -80.0
	add_child(_ambient_player)

## Crossfades to a real looping ambient track (AssetLibrary.audio() id) for
## a non-gameplay screen (menu/map). Calling it again with the same `id` is
## a no-op; a different `id` crossfades in place. No-op (silently) if the
## track failed to load, so a missing asset just stays silent instead of
## erroring.
func play_ambient(id: StringName, fade: float = 0.8) -> void:
	if id == _ambient_id and _ambient_player.playing:
		return
	var stream := AssetLibrary.audio(id)
	if stream == null:
		return
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	_ambient_id = id
	if _ambient_tween != null and _ambient_tween.is_valid():
		_ambient_tween.kill()
	_ambient_tween = create_tween()
	if _ambient_player.playing:
		_ambient_tween.tween_property(_ambient_player, "volume_db", -80.0, fade * 0.5)
	_ambient_tween.tween_callback(func():
		_ambient_player.stream = stream
		_ambient_player.play(0.0))
	_ambient_tween.tween_property(_ambient_player, "volume_db", 0.0, fade)

func stop_ambient(fade: float = 0.6) -> void:
	if not _ambient_player.playing:
		return
	_ambient_id = &""
	if _ambient_tween != null and _ambient_tween.is_valid():
		_ambient_tween.kill()
	_ambient_tween = create_tween()
	_ambient_tween.tween_property(_ambient_player, "volume_db", -80.0, fade)
	_ambient_tween.tween_callback(func():
		_ambient_player.stop()
		_ambient_player.stream = null)

## Starts every layer looping together (silent layers just sit at -80dB
## until a state pulls them up) and snaps to the idle mix.
func start() -> void:
	if _started:
		return
	_started = true
	for p in _layer_players.values():
		var player: AudioStreamPlayer = p
		if player.stream != null:
			player.play(0.0)
	set_state(&"idle", true)

func fade_out_and_stop(duration: float = 0.6) -> void:
	if not _started:
		return
	_started = false
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var tween := create_tween()
	tween.set_parallel(true)
	for p in _layer_players.values():
		tween.tween_property(p, "volume_db", -80.0, duration)
	tween.chain().tween_callback(_stop_all)

func _stop_all() -> void:
	for p in _layer_players.values():
		(p as AudioStreamPlayer).stop()

## Crossfades the layer mix toward the named intensity state (see
## data/music.json's "states"). Safe to call every move — a no-op repeat
## call is skipped, and re-entering a state cancels any in-flight fade.
func set_state(state: StringName, instant: bool = false) -> void:
	if state == _current_state and not instant:
		return
	_current_state = state
	state_changed.emit(state)
	var gains: Dictionary = GameData.music.states.get(String(state), {})
	var crossfade: float = 0.0 if instant else GameData.music.crossfade_seconds

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	if crossfade <= 0.0:
		for layer_id in _layer_players.keys():
			(_layer_players[layer_id] as AudioStreamPlayer).volume_db = _target_db(gains, layer_id)
		return

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	for layer_id in _layer_players.keys():
		var p: AudioStreamPlayer = _layer_players[layer_id]
		_fade_tween.tween_property(p, "volume_db", _target_db(gains, layer_id), crossfade).set_trans(Tween.TRANS_SINE)

func _target_db(gains: Dictionary, layer_id) -> float:
	var gain: float = float(gains.get(layer_id, 0.0))
	return linear_to_db(gain) if gain > 0.0001 else -80.0

func current_state() -> StringName:
	return _current_state
