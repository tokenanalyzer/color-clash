extends TestCase

func _config() -> PowerConfig:
	return PowerConfig.from_dict({
		"thresholds": [
			{"power": "chain", "min_size": 12, "count": 3},
			{"power": "chain", "min_size": 9, "count": 2},
			{"power": "chain", "min_size": 6, "count": 1},
			{"power": "lightning", "min_size": 5, "count": 1},
			{"power": "bomb", "min_size": 4, "count": 1},
			{"power": "none", "min_size": 3, "count": 0}
		],
		"definitions": {},
		"base_points_per_piece": 10
	})

func test_small_group_yields_no_power() -> void:
	check_eq("size_three_no_power", _config().powers_for_group_size(3).size(), 0)
	check_eq("size_two_below_min_no_power", _config().powers_for_group_size(2).size(), 0)

func test_single_power_tiers() -> void:
	check_eq("size_four_one_bomb", _config().powers_for_group_size(4).size(), 1)
	check_eq("size_five_one_lightning", _config().powers_for_group_size(5).size(), 1)
	check_eq("size_six_one_chain", _config().powers_for_group_size(6).size(), 1)

func test_multi_power_tiers_scale_with_group_size() -> void:
	var cfg := _config()
	check_eq("size_nine_two_powers", cfg.powers_for_group_size(9).size(), 2)
	check_eq("size_twelve_three_powers", cfg.powers_for_group_size(12).size(), 3)
	check_eq("size_twenty_still_three_via_highest_threshold", cfg.powers_for_group_size(20).size(), 3)

func test_multi_power_tiers_all_same_type() -> void:
	var cfg := _config()
	for p in cfg.powers_for_group_size(9):
		check_eq("nine_tier_power_is_chain", String(p), "chain")

func test_power_for_group_size_returns_first_of_the_plan() -> void:
	var cfg := _config()
	check_eq("singular_helper_matches_plan_head", cfg.power_for_group_size(9), cfg.powers_for_group_size(9)[0])
	check_eq("singular_helper_none_for_too_small", cfg.power_for_group_size(3), &"none")

func test_min_group_size_is_lowest_threshold() -> void:
	check_eq("min_group_size_is_three", _config().min_group_size(), 3)

func test_count_defaults_to_one_when_omitted() -> void:
	var cfg := PowerConfig.from_dict({
		"thresholds": [{"power": "bomb", "min_size": 4}],
		"definitions": {},
		"base_points_per_piece": 10
	})
	check_eq("omitted_count_defaults_to_one", cfg.powers_for_group_size(4).size(), 1)
