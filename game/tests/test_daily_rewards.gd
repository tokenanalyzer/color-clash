extends TestCase
## Pure 7-day daily-reward streak maths (no clock, no save — the screen
## injects today's day index and the persisted streak state).

func test_first_ever_claim_is_day_one() -> void:
	var s := DailyRewards.claim_state(20000, -1, 0)
	check("claimable", s["claimable"])
	check_eq("day_one", s["day"], 1)
	check("not_a_reset", not s["reset"])

func test_second_claim_same_day_is_not_claimable() -> void:
	var s := DailyRewards.claim_state(20000, 20000, 1)
	check("not_claimable_again_today", not s["claimable"])
	check_eq("shows_current_streak_day", s["day"], 1)

func test_consecutive_day_advances_the_streak() -> void:
	var s := DailyRewards.claim_state(20001, 20000, 3)
	check("claimable", s["claimable"])
	check_eq("advances_to_day_four", s["day"], 4)
	check("not_a_reset", not s["reset"])

func test_completing_day_seven_then_next_day_wraps_to_day_one() -> void:
	var s := DailyRewards.claim_state(20008, 20007, 7)
	check("claimable", s["claimable"])
	check_eq("new_cycle_day_one", s["day"], 1)
	check("is_a_reset", s["reset"])

func test_missing_a_day_resets_the_streak() -> void:
	var s := DailyRewards.claim_state(20005, 20000, 4)
	check("claimable", s["claimable"])
	check_eq("back_to_day_one", s["day"], 1)
	check("is_a_reset", s["reset"])

func test_clock_moving_backwards_is_not_claimable() -> void:
	var s := DailyRewards.claim_state(19999, 20000, 2)
	check("not_claimable", not s["claimable"])

func test_streak_after_claim_is_clamped_to_cycle() -> void:
	check_eq("day_three_persists_as_three", DailyRewards.streak_after_claim(3), 3)
	check_eq("clamps_low", DailyRewards.streak_after_claim(0), 1)
	check_eq("clamps_high", DailyRewards.streak_after_claim(99), 7)

func test_day_index_is_utc_day_number() -> void:
	check_eq("epoch_is_day_zero", DailyRewards.day_index(0.0), 0)
	check_eq("one_day_later", DailyRewards.day_index(86400.0), 1)
	check_eq("mid_day_rounds_down", DailyRewards.day_index(86400.0 + 43200.0), 1)

func test_reward_table_has_seven_entries_and_a_big_finish() -> void:
	check_eq("seven_days", DailyRewards.TABLE.size(), 7)
	var d7: Dictionary = DailyRewards.reward_for_day(7)
	check("day_seven_has_coins", int(d7.get("coins", 0)) > 0)
	check("day_seven_has_boosters", (d7.get("boosters", {}) as Dictionary).size() > 0)
	var d3: Dictionary = DailyRewards.reward_for_day(3)
	check("day_three_is_a_booster_day", (d3.get("boosters", {}) as Dictionary).size() > 0)
