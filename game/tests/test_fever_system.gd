extends TestCase

func _config() -> FeverConfig:
	return FeverConfig.from_dict({
		"meter_max": 100.0,
		"gain_per_chain_step": 40.0,
		"decay_per_weak_move": 10.0,
		"weak_move_chain_threshold": 2,
		"activation_meter": 100.0,
		"duration_moves": 3,
		"score_multiplier": 1.5,
		"meter_reset_on_activate": true
	})

func test_weak_moves_decay_meter() -> void:
	var fever := FeverSystem.new(_config())
	fever.register_move(1)
	check_eq("meter_stays_at_zero_floor", fever.meter, 0.0)
	check("not_active", not fever.is_active())

func test_strong_moves_build_meter_and_activate() -> void:
	var fever := FeverSystem.new(_config())
	fever.register_move(2) # +80
	check_eq("meter_after_one_strong_move", fever.meter, 80.0)
	var activated := fever.register_move(2) # +80 -> clamps to 100, activates
	check("fever_activates_at_threshold", activated)
	check("fever_now_active", fever.is_active())
	check_eq("meter_resets_on_activation", fever.meter, 0.0)

func test_fever_multiplier_applies_while_active_and_counts_down() -> void:
	var fever := FeverSystem.new(_config())
	fever.register_move(2)
	fever.register_move(2)
	check("multiplier_active", fever.score_multiplier() == 1.5)
	for i in 3:
		fever.register_move(1)
	check("fever_expires_after_duration", not fever.is_active())
	check("multiplier_back_to_one", fever.score_multiplier() == 1.0)

func test_max_gain_per_move_prevents_one_mega_cascade_from_instant_maxing() -> void:
	var config := FeverConfig.from_dict({
		"meter_max": 100.0,
		"gain_per_chain_step": 40.0,
		"max_gain_per_move": 50.0,
		"decay_per_weak_move": 10.0,
		"weak_move_chain_threshold": 2,
		"activation_meter": 100.0,
		"duration_moves": 3,
		"score_multiplier": 1.5,
		"meter_reset_on_activate": true
	})
	var fever := FeverSystem.new(config)
	# Uncapped this would be 10 * 40 = 400 -- a single huge cascade should
	# not be able to max Fever in one move on its own.
	var activated := fever.register_move(10)
	check("single_mega_cascade_does_not_activate_fever_alone", not activated)
	check_eq("gain_capped_at_max_gain_per_move", fever.meter, 50.0)
