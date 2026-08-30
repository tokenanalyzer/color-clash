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
