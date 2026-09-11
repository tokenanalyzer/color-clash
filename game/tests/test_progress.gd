extends TestCase
## Exercises the Progress autoload directly, like test_economy.gd does.
## Uses high level ids from the real campaign (data/levels.json has 25) so
## repeated CI runs against the same persisted user:// save don't collide
## with progress a human playtester might have made on early levels.

const _TEST_LEVEL_A := 24
const _TEST_LEVEL_B := 25

func test_first_level_always_unlocked() -> void:
	var first_id := GameData.levels.first_level_id()
	check("first_level_unlocked", Progress.is_unlocked(first_id))

func test_level_locked_until_previous_completed() -> void:
	if not Progress.is_completed(_TEST_LEVEL_A):
		check("later_level_starts_locked", not Progress.is_unlocked(_TEST_LEVEL_B))
	Progress.record_completion(_TEST_LEVEL_A, 2, 5000)
	check("level_unlocks_after_previous_completed", Progress.is_unlocked(_TEST_LEVEL_B))

func test_record_completion_persists_stars_and_score() -> void:
	# Relative to whatever's already persisted (this suite may re-run
	# against the same save across sessions) rather than an absolute value,
	# so it stays correct however many times it's been run before.
	var baseline_score := Progress.get_best_score(_TEST_LEVEL_B)
	var new_score := baseline_score + 1000
	Progress.record_completion(_TEST_LEVEL_B, 3, new_score)
	check("level_marked_completed", Progress.is_completed(_TEST_LEVEL_B))
	check_eq("stars_recorded", Progress.get_stars(_TEST_LEVEL_B), 3)
	check_eq("best_score_recorded", Progress.get_best_score(_TEST_LEVEL_B), new_score)

func test_record_completion_only_ever_improves() -> void:
	var before_score := Progress.get_best_score(_TEST_LEVEL_B)
	var before_stars := Progress.get_stars(_TEST_LEVEL_B)
	Progress.record_completion(_TEST_LEVEL_B, 1, 1) # a strictly worse attempt
	check_eq("stars_do_not_regress", Progress.get_stars(_TEST_LEVEL_B), before_stars)
	check_eq("best_score_does_not_regress", Progress.get_best_score(_TEST_LEVEL_B), before_score)
	var improved_score := before_score + 500
	Progress.record_completion(_TEST_LEVEL_B, 3, improved_score)
	check_eq("best_score_improves_when_higher", Progress.get_best_score(_TEST_LEVEL_B), improved_score)

func test_current_level_id_is_first_incomplete_unlocked_level() -> void:
	var current := Progress.current_level_id()
	check("current_level_is_unlocked", Progress.is_unlocked(current))
