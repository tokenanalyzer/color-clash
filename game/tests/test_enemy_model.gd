extends TestCase
## Data-driven enemy roster (data/enemies.json) — pure view, no save state.

func test_ten_enemies_defined() -> void:
	check_eq("enemy count", EnemyModel.all_enemy_ids().size(), 10)
	check_eq("shadow_ghost tier", String(EnemyModel.enemy_def(&"shadow_ghost").get("tier", "")), "normal")
	check_eq("ice_wraith is a mini_boss", String(EnemyModel.enemy_def(&"ice_wraith").get("tier", "")), "mini_boss")

func test_boss_stage_detection() -> void:
	check("stage 10 is a boss stage", EnemyModel.is_boss_stage(10))
	check("stage 50 is a boss stage", EnemyModel.is_boss_stage(50))
	check("stage 7 is not", not EnemyModel.is_boss_stage(7))
	check("stage 0 is not", not EnemyModel.is_boss_stage(0))

func test_boss_assignments_match_the_five_chapters() -> void:
	check_eq("forest boss (10)", String(EnemyModel.boss_for_stage(10)), "poison_beast")
	check_eq("ice boss (20)", String(EnemyModel.boss_for_stage(20)), "ice_wraith")
	check_eq("fire boss (30)", String(EnemyModel.boss_for_stage(30)), "dark_knight")
	check_eq("desert boss (40)", String(EnemyModel.boss_for_stage(40)), "chaos_sorcerer")
	check_eq("final boss (50) is Jinn", String(EnemyModel.boss_for_stage(50)), "jinn")
	check_eq("non-boss stage has no boss", String(EnemyModel.boss_for_stage(23)), "")

func test_normal_stage_enemy_is_deterministic_from_the_island_roster() -> void:
	var a := EnemyModel.enemy_for_stage(3)
	var b := EnemyModel.enemy_for_stage(3)
	check_eq("same enemy for the same stage", a, b)
	var roster := EnemyModel.roster_for_island(0)
	check("stage-3 enemy is from island 0's roster", roster.has(a))
	check("island 2 roster has fire_imp", EnemyModel.roster_for_island(2).has(&"fire_imp"))

func test_one_persistent_minor_villain_per_chapter() -> void:
	# 2026-09-05 hard requirement: the SAME minor villain (normal stages) AND
	# boss (the chapter's 10th stage) appear across an entire 10-stage
	# island — never rotating per stage.
	var chapters := [
		{"stages": [1, 2, 5, 9, 10], "id": "poison_beast"},
		{"stages": [11, 12, 15, 19, 20], "id": "ice_wraith"},
		{"stages": [21, 22, 25, 29, 30], "id": "dark_knight"},
		{"stages": [31, 32, 35, 39, 40], "id": "chaos_sorcerer"},
	]
	for chapter in chapters:
		for stage in chapter["stages"]:
			check_eq("stage %d shows %s" % [stage, chapter["id"]],
				String(EnemyModel.enemy_for_stage(stage)), String(chapter["id"]))
	# Island 5 (41-49 normal, 50 = Jinn) is the one exception: its persistent
	# minor villain (stone_golem) is NOT the same id as the stage-50 boss.
	for stage in [41, 42, 45, 49]:
		check_eq("stage %d shows stone_golem" % stage, String(EnemyModel.enemy_for_stage(stage)), "stone_golem")
	check_eq("stage 50 is Jinn (final boss, not stone_golem)", String(EnemyModel.enemy_for_stage(50)), "jinn")

func test_boss_hp_concept_is_fully_removed() -> void:
	# 2026-09-07: the minor-villain health bar / boss-HP mechanic is gone.
	# EnemyModel no longer exposes any HP accessor — finale stages are won
	# by their objectives, not by depleting a bar.
	var em := EnemyModel.new()
	check("EnemyModel.boss_hp() removed", not em.has_method("boss_hp"))
	check("EnemyModel.base_hp() removed", not em.has_method("base_hp"))
	check("but the villain roster / boss-for-stage identity still works",
		String(EnemyModel.boss_for_stage(10)) == "poison_beast")
