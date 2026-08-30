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
