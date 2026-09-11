extends TestCase

func _no_nan_or_clip(samples: PackedFloat32Array) -> bool:
	for s in samples:
		if is_nan(s) or is_inf(s):
			return false
		if absf(s) > 1.0001:
			return false
	return true

func test_generate_tone_length_matches_duration() -> void:
	var samples := Synth.generate_tone(440.0, 0.1, &"sine")
	check_eq("tone_sample_count", samples.size(), int(round(0.1 * Synth.MIX_RATE)))

func test_generate_tone_is_finite_and_bounded() -> void:
	var samples := Synth.generate_tone(440.0, 0.2, &"square", 0.01, 2.0)
	check("tone_finite_and_bounded", _no_nan_or_clip(samples))

func test_generate_tone_starts_and_ends_near_silence() -> void:
	# Attack/decay envelope should avoid clicks: first and last samples
	# should be much quieter than the peak.
	var samples := Synth.generate_tone(440.0, 0.2, &"sine", 0.01, 2.0)
	var peak := 0.0
	for s in samples:
		peak = max(peak, absf(s))
	check("starts_near_silence", absf(samples[0]) < peak * 0.3)
	check("ends_near_silence", absf(samples[samples.size() - 1]) < peak * 0.3)

func test_higher_frequency_has_more_zero_crossings() -> void:
	var low := Synth.generate_tone(220.0, 0.1, &"sine", 0.0, 0.5)
	var high := Synth.generate_tone(880.0, 0.1, &"sine", 0.0, 0.5)
	check("high_freq_more_crossings", _zero_crossings(high) > _zero_crossings(low))

func _zero_crossings(samples: PackedFloat32Array) -> int:
	var count := 0
	for i in range(1, samples.size()):
		if (samples[i - 1] < 0.0) != (samples[i] < 0.0):
			count += 1
	return count

func test_generate_noise_burst_is_finite_and_bounded() -> void:
	var samples := Synth.generate_noise_burst(0.15, 0.005, 2.0, 0.5, 0.6)
	check("noise_finite_and_bounded", _no_nan_or_clip(samples))
	check("noise_nonempty", samples.size() > 0)

func test_note_freq_matches_known_intervals() -> void:
	# Octave up (5 scale degrees in the pentatonic scale) should double frequency.
	var root := Synth.note_freq(440.0, 0)
	var octave_up := Synth.note_freq(440.0, Synth.SCALE_MAJOR_PENTATONIC.size())
	check_eq("root_is_root", root, 440.0)
	check("octave_doubles_frequency", absf(octave_up - 880.0) < 0.01)

func test_mix_sums_buffers_and_pads_shorter_one() -> void:
	var a := PackedFloat32Array([0.1, 0.2, 0.3])
	var b := PackedFloat32Array([0.5, 0.5])
	var mixed := Synth.mix(a, b)
	check_eq("mixed_length_is_longer_buffer", mixed.size(), 3)
	check("mixed_sums_overlap", absf(mixed[0] - 0.6) < 0.0001)
	check("mixed_keeps_tail_of_longer", absf(mixed[2] - 0.3) < 0.0001)

func test_normalize_peak_scales_down_loud_buffer_only() -> void:
	var loud := PackedFloat32Array([0.0, 1.5, -1.5, 0.5])
	var normalized := Synth.normalize_peak(loud, 0.9)
	var peak := 0.0
	for s in normalized:
		peak = max(peak, absf(s))
	check("normalized_peak_at_target", absf(peak - 0.9) < 0.001)

	var quiet := PackedFloat32Array([0.0, 0.1, -0.1])
	var unchanged := Synth.normalize_peak(quiet, 0.9)
	check_eq("quiet_buffer_untouched", unchanged[1], quiet[1])

func test_build_wav_produces_correctly_sized_stream() -> void:
	var samples := Synth.generate_tone(440.0, 0.05, &"sine")
	var stream := Synth.build_wav(samples, false)
	check_eq("wav_mix_rate", stream.mix_rate, Synth.MIX_RATE)
	check_eq("wav_byte_length", stream.data.size(), samples.size() * 2)
	check("wav_not_looping_by_default", stream.loop_mode == AudioStreamWAV.LOOP_DISABLED)

func test_build_wav_loop_mode_when_requested() -> void:
	var samples := Synth.generate_tone(440.0, 0.05, &"sine")
	var stream := Synth.build_wav(samples, true)
	check("wav_loops_when_requested", stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
