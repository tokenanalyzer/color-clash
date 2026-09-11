extends TestCase

func test_one_star_when_moves_nearly_exhausted() -> void:
	check_eq("zero_spare_moves_one_star", StarRating.stars_for(0, 20), 1)
	check_eq("few_spare_moves_one_star", StarRating.stars_for(2, 20), 1)

func test_two_stars_at_quarter_spare_moves() -> void:
	check_eq("exactly_quarter_spare_two_stars", StarRating.stars_for(5, 20), 2)
	check_eq("just_under_half_spare_two_stars", StarRating.stars_for(9, 20), 2)

func test_three_stars_at_half_spare_moves_or_more() -> void:
	check_eq("exactly_half_spare_three_stars", StarRating.stars_for(10, 20), 3)
	check_eq("all_moves_spare_three_stars", StarRating.stars_for(20, 20), 3)

func test_zero_move_limit_defaults_to_one_star() -> void:
	check_eq("degenerate_move_limit_still_one_star", StarRating.stars_for(0, 0), 1)

func test_negative_moves_left_clamped_to_one_star() -> void:
	check_eq("negative_moves_left_one_star", StarRating.stars_for(-3, 20), 1)

# --- per-level score thresholds (primary rule) ---------------------------

func test_score_thresholds_award_by_score() -> void:
	var th := [10000, 20000, 30000]
	check_eq("below_two_star_is_one", StarRating.stars_for_score(15000, th, 0, 20), 1)
	check_eq("at_two_star_threshold", StarRating.stars_for_score(20000, th, 0, 20), 2)
	check_eq("between_two_and_three", StarRating.stars_for_score(29999, th, 0, 20), 2)
	check_eq("at_three_star_threshold", StarRating.stars_for_score(30000, th, 0, 20), 3)
	check_eq("well_above_three_star", StarRating.stars_for_score(99999, th, 0, 20), 3)

func test_score_rating_ignores_spare_moves_when_thresholds_present() -> void:
	var th := [10000, 20000, 30000]
	# tons of spare moves would be 3 stars under the move rule, but a low
	# score still caps at 1 when thresholds drive the rating.
	check_eq("thresholds_take_precedence", StarRating.stars_for_score(9000, th, 20, 20), 1)

func test_missing_thresholds_fall_back_to_move_efficiency() -> void:
	check_eq("empty_thresholds_use_moves", StarRating.stars_for_score(5000, [], 10, 20), 3)
	check_eq("short_thresholds_use_moves", StarRating.stars_for_score(5000, [12345], 5, 20), 2)
	check_eq("zero_top_threshold_uses_moves", StarRating.stars_for_score(5000, [0, 0, 0], 0, 20), 1)
