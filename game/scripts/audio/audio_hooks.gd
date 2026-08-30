extends Node
## Autoload "Audio". Central sound-effect hook: gameplay code calls
## Audio.play(&"blast") without caring whether a real AudioStream is wired
## up yet. Until audio assets are produced this safely no-ops, so game-feel
## work never blocks on asset production. register() wires a real stream
## in later once audio assets land.

const _POOL_SIZE := 8

var _streams: Dictionary = {} # StringName -> AudioStream
var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for i in _POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func register(id: StringName, stream: AudioStream) -> void:
	_streams[id] = stream

func play(id: StringName, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(id, null)
	if stream == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
