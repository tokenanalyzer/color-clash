extends TestCase

func _config() -> MusicConfig:
	return MusicConfig.from_dict({
		"bpm": 120.0,
		"bars": 1,
		"beats_per_bar": 4,
		"root_freq": 220.0,
		"layers": {
			"pad": { "kind": "tone", "wave": "sine", "attack": 0.1, "decay_curve": 1.0, "volume": 0.2, "notes": [{"beat": 0, "degree": 0, "duration_beats": 1.9}] },
			"bass_pulse": { "kind": "pattern", "wave": "triangle", "attack": 0.005, "decay_curve": 3.0, "volume": 0.2, "pattern_degrees": [0], "step_beats": 1.0, "note_beats": 0.3 },
			"perc": { "kind": "pattern_noise", "attack": 0.001, "decay_curve": 4.0, "volume": 0.1, "brightness": 0.7, "step_beats": 1.0, "note_beats": 0.05 }
		},
		"states": {},
		"crossfade_seconds": 1.0
	})

func test_layer_buffer_length_matches_one_loop() -> void:
	var cfg := _config()
	var buf := MusicLayerBuilder.build(cfg, &"bass_pulse")
	var expected := int(round(cfg.loop_seconds() * Synth.MIX_RATE))
	check_eq("loop_length_matches_config", buf.size(), expected)

func test_all_layer_kinds_produce_same_length_buffer() -> void:
	var cfg := _config()
	var expected := int(round(cfg.loop_seconds() * Synth.MIX_RATE))
	for layer_id in ["pad", "bass_pulse", "perc"]:
		var buf := MusicLayerBuilder.build(cfg, StringName(layer_id))
		check_eq("layer_%s_length" % layer_id, buf.size(), expected)

func test_layers_stay_in_sync_by_sharing_loop_length() -> void:
	# The whole point of vertical layering: every layer must be exactly the
	# same length so they loop together without drifting out of phase.
	var cfg := _config()
	var a := MusicLayerBuilder.build(cfg, &"pad").size()
	var b := MusicLayerBuilder.build(cfg, &"bass_pulse").size()
	var c := MusicLayerBuilder.build(cfg, &"perc").size()
	check_eq("pad_bass_same_length", a, b)
	check_eq("bass_perc_same_length", b, c)

func test_missing_layer_returns_empty_buffer() -> void:
	var cfg := _config()
	var buf := MusicLayerBuilder.build(cfg, &"nonexistent")
	check_eq("missing_layer_empty", buf.size(), 0)

func test_no_nan_or_clipping_in_rendered_layer() -> void:
	var cfg := _config()
	var buf := MusicLayerBuilder.build(cfg, &"pad")
	var ok := true
	for s in buf:
		if is_nan(s) or is_inf(s) or absf(s) > 1.0001:
			ok = false
			break
	check("pad_layer_finite_and_bounded", ok)

func test_real_music_config_all_layers_build_and_match_length() -> void:
	var data := JsonLoader.load_json("res://data/music.json")
	var cfg := MusicConfig.from_dict(data)
	var expected := int(round(cfg.loop_seconds() * Synth.MIX_RATE))
	var all_match := true
	for layer_id in cfg.layers.keys():
		var buf := MusicLayerBuilder.build(cfg, StringName(String(layer_id)))
		if buf.size() != expected:
			all_match = false
	check("all_production_layers_match_loop_length", all_match)
