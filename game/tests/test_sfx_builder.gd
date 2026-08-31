extends TestCase

func _simple_def() -> Dictionary:
	return {
		"layers": [
			{ "kind": "tone", "wave": "sine", "freq_mode": "absolute", "base_freq": 400.0, "freq_range": 400.0, "duration": 0.1, "attack": 0.005, "decay_curve": 2.0, "volume": 0.6 }
		]
	}

func test_build_returns_nonempty_buffer_for_known_def() -> void:
	var buf := SfxBuilder.build(_simple_def(), 0.0, 0)
	check("buffer_nonempty", buf.size() > 0)

func test_build_returns_empty_for_missing_layers() -> void:
	var buf := SfxBuilder.build({}, 0.0, 0)
	check_eq("empty_def_yields_empty_buffer", buf.size(), 0)

func test_intensity_changes_output() -> void:
	var low := SfxBuilder.build(_simple_def(), 0.0, 0)
	var high := SfxBuilder.build(_simple_def(), 1.0, 0)
	check("intensity_changes_waveform", low != high)

func test_scale_mode_uses_event_index_and_intensity() -> void:
	var def := {
		"layers": [
			{ "kind": "tone", "wave": "triangle", "freq_mode": "scale", "scale_root": 440.0, "scale_degree": 0, "intensity_degree_span": 2, "duration": 0.08, "attack": 0.003, "decay_curve": 2.5, "volume": 0.5 }
		]
	}
	var a := SfxBuilder.build(def, 0.0, 0)
	var b := SfxBuilder.build(def, 0.0, 3)
	check("event_index_changes_pitch", a != b)

func test_layered_noise_and_tone_produces_bounded_output() -> void:
	var def := {
		"layers": [
			{ "kind": "noise", "start": 0.0, "duration": 0.2, "attack": 0.002, "decay_curve": 2.5, "brightness": 0.3, "volume": 0.5 },
			{ "kind": "tone", "wave": "sine", "freq_mode": "absolute", "base_freq": 100.0, "freq_range": 0.0, "duration": 0.2, "attack": 0.001, "decay_curve": 2.0, "volume": 0.6 }
		]
	}
	var buf := SfxBuilder.build(def, 0.5, 0)
	var bounded := true
	for s in buf:
		if absf(s) > 1.0001 or is_nan(s) or is_inf(s):
			bounded = false
			break
	check("bounded_amplitude", bounded)

func test_all_configured_sfx_ids_build_valid_buffers() -> void:
	var data := JsonLoader.load_json("res://data/sfx.json")
	var cfg := SfxConfig.from_dict(data)
	var all_ok := true
	for id in ["select", "match", "blast", "chain_step", "power_bomb", "power_lightning", "power_freeze", "power_chain", "power_rainbow", "combo_ding", "fever_activate", "level_complete", "level_failed", "shuffle", "button_tap", "tension_pulse", "timebomb_explode", "timebomb_tick"]:
		if not cfg.has(StringName(id)):
			all_ok = false
			continue
		var buf := SfxBuilder.build(cfg.get_def(StringName(id)), 0.6, 2)
		if buf.is_empty():
			all_ok = false
	check("every_documented_sfx_id_builds", all_ok)
