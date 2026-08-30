class_name Synth
extends RefCounted
## Procedural DSP primitives used to generate Color Clash's entire audio
## identity at runtime — every SFX and music layer is synthesized from
## these building blocks (no sampled/licensed audio, nothing borrowed from
## any other game). Pure math, no engine audio nodes, so it is fully unit
## testable headlessly.
##
## All buffers are mono Float32 sample arrays at `mix_rate`. Envelopes
## always ramp up from 0 and decay back toward 0 so buffers loop/cut
## cleanly without clicks.

const MIX_RATE := 44100

## Original Color Clash scale: a bright major-pentatonate palette. No
## dissonant intervals -> stays pleasant even when many notes overlap
## during a big cascade. Values are semitone offsets from the root.
const SCALE_MAJOR_PENTATONIC := [0, 2, 4, 7, 9]

static func note_freq(root_freq: float, degree: int, scale: Array = SCALE_MAJOR_PENTATONIC) -> float:
	var size := scale.size()
	var octave := int(floor(float(degree) / float(size)))
	var idx := ((degree % size) + size) % size
	var semitones: int = scale[idx] + 12 * octave
	return root_freq * pow(2.0, float(semitones) / 12.0)

## Attack/decay envelope: linear ramp to 1 over `attack` seconds, then an
## exponential-feeling decay to ~0 across the rest of the duration. This
## single shape covers "plucky", "punchy" and "soft pad" characters by
## varying attack length and decay_curve.
static func _envelope(t: float, duration: float, attack: float, decay_curve: float) -> float:
	if t < attack and attack > 0.0:
		return t / attack
	var remain: float = max(duration - attack, 0.0001)
	var rt: float = clamp((t - attack) / remain, 0.0, 1.0)
	return pow(1.0 - rt, decay_curve)

static func _wave(phase: float, shape: StringName) -> float:
	match shape:
		&"sine":
			return sin(phase)
		&"triangle":
			return (2.0 / PI) * asin(sin(phase))
		&"square":
			return 1.0 if sin(phase) >= 0.0 else -1.0
		&"saw":
			var x: float = fposmod(phase, TAU) / TAU
			return 2.0 * x - 1.0
		_:
			return sin(phase)

## A tone (optionally sweeping from start_freq to end_freq) with a
## pluck/pad-style envelope. This is the workhorse for melodic SFX and
## music-layer notes.
static func generate_tone(start_freq: float, duration: float, wave_shape: StringName = &"sine", attack: float = 0.006, decay_curve: float = 2.2, end_freq: float = -1.0, volume: float = 0.8) -> PackedFloat32Array:
	var target_end := end_freq if end_freq > 0.0 else start_freq
	var n := int(round(duration * MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var f: float = lerp(start_freq, target_end, clamp(t / duration, 0.0, 1.0))
		phase += TAU * f / float(MIX_RATE)
		samples[i] = _wave(phase, wave_shape) * _envelope(t, duration, attack, decay_curve) * volume
	return samples

## Filtered noise burst — used for impacts/blasts/whooshes. `brightness`
## (0..1) controls a one-pole lowpass cutoff so bursts stay a clean "thump"
## rather than harsh hiss (0 = dull thump, 1 = bright/crisp).
static func generate_noise_burst(duration: float, attack: float = 0.002, decay_curve: float = 3.0, brightness: float = 0.5, volume: float = 0.6, rng_seed: int = 0) -> PackedFloat32Array:
	var n := int(round(duration * MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else int(duration * 1000.0 * (brightness + 1.0))
	var alpha: float = clamp(0.05 + brightness * 0.9, 0.02, 0.95)
	var filtered := 0.0
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		filtered += alpha * (raw - filtered)
		samples[i] = filtered * _envelope(t, duration, attack, decay_curve) * volume
	return samples

## Sums two buffers sample-by-sample (shorter buffer is zero-padded).
static func mix(a: PackedFloat32Array, b: PackedFloat32Array, gain_a: float = 1.0, gain_b: float = 1.0) -> PackedFloat32Array:
	var n: int = max(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var av: float = a[i] * gain_a if i < a.size() else 0.0
		var bv: float = b[i] * gain_b if i < b.size() else 0.0
		out[i] = av + bv
	return out

## Concatenates buffers in sequence (for arpeggios / short motifs).
static func concat(parts: Array) -> PackedFloat32Array:
	var total := 0
	for p in parts:
		total += (p as PackedFloat32Array).size()
	var out := PackedFloat32Array()
	out.resize(total)
	var offset := 0
	for p in parts:
		var buf: PackedFloat32Array = p
		for i in buf.size():
			out[offset + i] = buf[i]
		offset += buf.size()
	return out

## Prevents clipping/harshness by scaling the whole buffer down if its
## peak exceeds `peak`. Never boosts quiet buffers (no extra loudness push).
static func normalize_peak(samples: PackedFloat32Array, peak: float = 0.92) -> PackedFloat32Array:
	var max_abs := 0.0
	for s in samples:
		max_abs = max(max_abs, absf(s))
	if max_abs <= peak or max_abs == 0.0:
		return samples
	var scale := peak / max_abs
	var out := PackedFloat32Array()
	out.resize(samples.size())
	for i in samples.size():
		out[i] = samples[i] * scale
	return out

static func to_pcm16_bytes(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s: float = clamp(samples[i], -1.0, 1.0)
		var v: int = int(round(s * 32767.0))
		bytes.encode_s16(i * 2, v)
	return bytes

## Wraps a mono buffer as a playable (optionally looping) AudioStreamWAV.
static func build_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = to_pcm16_bytes(samples)
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
