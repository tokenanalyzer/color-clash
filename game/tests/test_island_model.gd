extends TestCase
## IslandModel is a pure view of the existing campaign + ProgressService:
## it groups the flat 50-level campaign into islands of exactly 10 and never
## adds save state or changes unlock rules. These assert the grouping maths;
## progress-dependent values are checked as ranges (the shared save may have
## any state) like the other economy/progress tests.

func test_island_count_is_levels_over_ten() -> void:
	var expected: int = int(ceil(float(GameData.levels.count()) / 10.0))
	check_eq("island_count", IslandModel.island_count(), expected)
	check("at least 5 islands for the 50-level campaign", IslandModel.island_count() >= 5)

func test_level_to_island_index() -> void:
	var ids: Array = GameData.levels.ordered_ids
	check_eq("first level in island 0", IslandModel.island_index_for_level(ids[0]), 0)
	check_eq("10th level in island 0", IslandModel.island_index_for_level(ids[9]), 0)
	check_eq("11th level in island 1", IslandModel.island_index_for_level(ids[10]), 1)
	check_eq("20th level in island 1", IslandModel.island_index_for_level(ids[19]), 1)
	check_eq("50th level in island 4", IslandModel.island_index_for_level(ids[49]), 4)

func test_level_ids_for_island_are_ten_consecutive() -> void:
	var ids: Array = GameData.levels.ordered_ids
	var isl0 := IslandModel.level_ids_for_island(0)
	check_eq("island 0 holds 10 levels", isl0.size(), 10)
	check_eq("island 0 starts at campaign level 1", isl0[0], int(ids[0]))
	check_eq("island 0 ends at campaign level 10", isl0[9], int(ids[9]))
	var isl2 := IslandModel.level_ids_for_island(2)
	check_eq("island 2 first id", isl2[0], int(ids[20]))
	check_eq("island 2 last id", isl2[9], int(ids[29]))
	check_eq("island_total(3)", IslandModel.island_total(3), 10)

func test_names_and_theme_resolve() -> void:
	for i in IslandModel.island_count():
		check("island %d has a name" % i, IslandModel.island_name(i).length() > 0)
		check("island %d has a theme id" % i, String(IslandModel.island_theme(i)).begins_with("env_"))

func test_first_island_always_unlocked_and_state_valid() -> void:
	check("island 0 is unlocked", IslandModel.is_island_unlocked(0))
	var done := IslandModel.island_completed_count(0)
	check("completed count in range", done >= 0 and done <= 10)
	check("island_state is one of the known values",
		IslandModel.island_state(0) in [&"locked", &"current", &"complete"])
	var cur := IslandModel.current_island_index()
	check("current island index in range", cur >= 0 and cur < IslandModel.island_count())

func test_locked_island_derives_from_sequential_rule() -> void:
	# A far island is unlocked iff its first level is unlocked under the
	# existing ProgressService rule — IslandModel must not invent its own.
	var last := IslandModel.island_count() - 1
	var first_of_last := IslandModel.level_ids_for_island(last)[0]
	check_eq("island unlock == first-level unlock",
		IslandModel.is_island_unlocked(last), Progress.is_unlocked(first_of_last))
