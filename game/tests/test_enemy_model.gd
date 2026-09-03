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

func test_hp_scales_by_tier_and_chapter() -> void:
	check_eq("normal base hp", EnemyModel.base_hp(&"normal"), 3)
	check_eq("final boss base hp", EnemyModel.base_hp(&"final_boss"), 30)
	check_eq("stage-50 boss hp is the final-boss hp", EnemyModel.boss_hp(50), 30)
	check("stage-40 boss hp > stage-10 boss hp (later chapter hits harder)",
		EnemyModel.boss_hp(40) > EnemyModel.boss_hp(10))
	check_eq("non-boss stage boss_hp is 0", EnemyModel.boss_hp(12), 0)
