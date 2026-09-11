class_name SfxBuilder
extends RefCounted
## Builds a PCM sample buffer for one SFX id from its data-driven
## definition (data/sfx.json), given play-time intensity/event_index
## parameters — e.g. a bigger connected group raises `intensity`, and each
## successive chain wave raises `event_index`, so pitch/energy audibly
## tracks what just happened on the board. Pure function, no AudioStream or
## Node involved, so it's directly unit testable.

static func build(def: Dictionary, intensity: float, event_index: int) -> PackedFloat32Array:
	var layers: Array = def.get("layers", [])
	if layers.is_empty():
		return PackedFloat32Array()

	var pieces: Array = []
	var max_end := 0.0
	for layer in layers:
		var start: float = float(layer.get("start", 0.0))
		var kind := String(layer.get("kind", "tone"))
		var buf: PackedFloat32Array
		if kind == "noise":
			var duration: float = float(layer.get("duration", 0.2))
			buf = Synth.generate_noise_burst(
				duration,
				float(layer.get("attack", 0.002)),
				float(layer.get("decay_curve", 2.5)),
				float(layer.get("brightness", 0.5)),
				float(layer.get("volume", 0.5))
			)
		else:
			var freq := _resolve_freq(layer, intensity, event_index)
			var duration: float = float(layer.get("duration", 0.15))
			var end_ratio: float = float(layer.get("end_freq_ratio", -1.0))
			var end_freq := freq * end_ratio if end_ratio > 0.0 else -1.0
			buf = Synth.generate_tone(
				freq,
				duration,
				StringName(String(layer.get("wave", "sine"))),
				float(layer.get("attack", 0.005)),
				float(layer.get("decay_curve", 2.5)),
				end_freq,
				float(layer.get("volume", 0.5))
			)
		pieces.append({"start": start, "buf": buf})
		max_end = max(max_end, start + float(buf.size()) / float(Synth.MIX_RATE))

	var total_samples := int(round(max_end * Synth.MIX_RATE))
	if total_samples <= 0:
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	out.resize(total_samples)
	for piece in pieces:
		var offset := int(round(float(piece["start"]) * Synth.MIX_RATE))
		var buf: PackedFloat32Array = piece["buf"]
		for i in buf.size():
			var idx := offset + i
			if idx >= 0 and idx < total_samples:
				out[idx] += buf[i]
	return Synth.normalize_peak(out)

static func _resolve_freq(layer: Dictionary, intensity: float, event_index: int) -> float:
	var mode := String(layer.get("freq_mode", "absolute"))
	if mode == "scale":
		var root: float = float(layer.get("scale_root", 440.0))
		var degree: int = int(layer.get("scale_degree", 0))
		var span: int = int(layer.get("intensity_degree_span", 0))
		var total_degree := degree + int(round(float(span) * clamp(intensity, 0.0, 1.0))) + event_index
		return Synth.note_freq(root, total_degree)
	var base: float = float(layer.get("base_freq", 440.0))
	var range_hz: float = float(layer.get("freq_range", 0.0))
	return base + range_hz * clamp(intensity, 0.0, 1.0)
