class_name MusicLayerBuilder
extends RefCounted
## Renders one seamless-looping music layer buffer from data/music.json.
## All layers are rendered to the exact same sample length (one loop at the
## configured bpm/bars), so when MusicDirector starts them together they
## stay phase-locked as their gains crossfade in and out. Pure function —
## unit testable without any audio playback.

static func build(config: MusicConfig, layer_id: StringName) -> PackedFloat32Array:
	var layer: Dictionary = config.layers.get(String(layer_id), {})
	if layer.is_empty():
		return PackedFloat32Array()

	var beat_seconds := 60.0 / config.bpm
	var loop_seconds := config.loop_seconds()
	var total_samples := int(round(loop_seconds * Synth.MIX_RATE))
	var out := PackedFloat32Array()
	out.resize(total_samples)

	var kind := String(layer.get("kind", "tone"))
	var wave := StringName(String(layer.get("wave", "sine")))
	var attack: float = float(layer.get("attack", 0.01))
	var decay_curve: float = float(layer.get("decay_curve", 2.0))
	var volume: float = float(layer.get("volume", 0.2))
	var root: float = config.root_freq
	var scale_size: int = Synth.SCALE_MAJOR_PENTATONIC.size()

	if kind == "tone":
		for note in layer.get("notes", []):
			var beat: float = float(note.get("beat", 0.0))
			var degree: int = int(note.get("degree", 0))
			var dur_beats: float = float(note.get("duration_beats", 1.0))
			var start_t := beat * beat_seconds
			var dur_t: float = min(dur_beats * beat_seconds, loop_seconds - start_t)
			if dur_t <= 0.0:
				continue
			var freq := Synth.note_freq(root, degree)
			var buf := Synth.generate_tone(freq, dur_t, wave, attack, decay_curve, -1.0, volume)
			_add_at(out, buf, start_t)
	elif kind == "pattern":
		var degrees: Array = layer.get("pattern_degrees", [0])
		var step_beats: float = float(layer.get("step_beats", 0.5))
		var note_beats: float = float(layer.get("note_beats", step_beats * 0.9))
		var octave_offset: int = int(layer.get("octave_offset", 0))
		var steps := int(round(loop_seconds / (step_beats * beat_seconds)))
		for i in steps:
			var start_t := float(i) * step_beats * beat_seconds
			var dur_t: float = min(note_beats * beat_seconds, loop_seconds - start_t)
			if dur_t <= 0.0:
				continue
			var degree: int = int(degrees[i % degrees.size()]) + octave_offset * scale_size
			var freq := Synth.note_freq(root, degree)
			var buf := Synth.generate_tone(freq, dur_t, wave, attack, decay_curve, -1.0, volume)
			_add_at(out, buf, start_t)
	elif kind == "pattern_noise":
		var step_beats: float = float(layer.get("step_beats", 0.5))
		var note_beats: float = float(layer.get("note_beats", 0.05))
		var offset_beats: float = float(layer.get("offset_beats", 0.0))
		var brightness: float = float(layer.get("brightness", 0.6))
		var steps := int(round(loop_seconds / (step_beats * beat_seconds)))
		for i in steps:
			var start_t := (float(i) * step_beats + offset_beats) * beat_seconds
			if start_t >= loop_seconds:
				continue
			var dur_t: float = min(note_beats * beat_seconds, loop_seconds - start_t)
			if dur_t <= 0.0:
				continue
			var buf := Synth.generate_noise_burst(dur_t, attack, decay_curve, brightness, volume, i + 1)
			_add_at(out, buf, start_t)

	return Synth.normalize_peak(out, 0.85)

static func _add_at(out: PackedFloat32Array, buf: PackedFloat32Array, start_t: float) -> void:
	var offset := int(round(start_t * Synth.MIX_RATE))
	for i in buf.size():
		var idx := offset + i
		if idx >= 0 and idx < out.size():
			out[idx] += buf[i]
