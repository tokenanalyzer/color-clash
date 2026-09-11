extends TestCase
## Regression guard for the 2026-09-10 fix: with the 100-level-per-island
## progression, the chapter BOSS / MAIN BOSS (Jinn) must appear ONLY on an
## island's finale local level — never on an ordinary mid-island level, no
## matter which authored campaign level (1..50) that slot happens to reuse.
##
## Before the fix, app.gd fed the CYCLED authored id straight into
## EnemyModel.is_boss_stage()/boss_for_stage(); because
## WorldCatalog.authored_level_id() does `(localLevel-1) % pool.size()`,
## every local level that is a multiple of 10 mapped to an authored id that
## is a multiple of 10 -> `is_boss` true, and for Celestial Haven / the
## un-banded islands that boss resolved to Jinn. So Jinn (and every chapter
## boss) showed up on local levels 10, 20, 30, ... instead of the finale.

const CHAPTER_BOSS := ["poison_beast", "ice_wraith", "dark_knight", "chaos_sorcerer", "jinn"]
const CHAPTER_MINOR := ["poison_beast", "ice_wraith", "dark_knight", "chaos_sorcerer", "stone_golem"]

# ---- EnemyModel.island_villain: the island-aware selector ---------------

func test_ordinary_levels_never_return_a_boss_or_jinn() -> void:
	for isl in 5:
		var v: Dictionary = EnemyModel.island_villain(isl, false)
		check("island %d ordinary level is NOT a boss" % isl, not bool(v["is_boss"]))
		check_eq("island %d ordinary villain is its minor villain" % isl,
			String(v["id"]), CHAPTER_MINOR[isl])
		check("island %d ordinary villain is NEVER Jinn" % isl, String(v["id"]) != "jinn")

func test_finale_returns_the_islands_own_chapter_boss() -> void:
	for isl in 5:
		var v: Dictionary = EnemyModel.island_villain(isl, true)
		check("island %d finale IS a boss" % isl, bool(v["is_boss"]))
		check_eq("island %d finale boss id" % isl, String(v["id"]), CHAPTER_BOSS[isl])

func test_jinn_appears_only_at_the_celestial_finale() -> void:
	for isl in 10:
		for fi in 2:
			var finale: bool = fi == 1
			var id := String(EnemyModel.island_villain(isl, finale)["id"])
			var jinn_allowed: bool = (isl == 4 and finale)
			if id == "jinn":
				check("Jinn only at island 4 finale (got island=%d finale=%s)" % [isl, finale], jinn_allowed)
			if isl == 4 and finale:
				check_eq("island 4 finale IS Jinn", id, "jinn")

func test_unauthored_islands_get_no_boss_no_jinn() -> void:
	for isl in [5, 6, 7, 8, 9]:
		var vf: Dictionary = EnemyModel.island_villain(isl, true)
		var vn: Dictionary = EnemyModel.island_villain(isl, false)
		check("island %d (unauthored) finale has no boss" % isl, not bool(vf["is_boss"]))
		check("island %d (unauthored) finale id is not Jinn" % isl, String(vf["id"]) != "jinn")
		check("island %d (unauthored) ordinary id is not Jinn" % isl, String(vn["id"]) != "jinn")

# ---- CombatDirector: island-aware vs flat authored-campaign path -------

func test_combat_director_island_path_gates_the_boss_to_the_finale() -> void:
	# authored id 10 is what Evergreen local levels 10/20/.../100 all reuse.
	# The BUG: CombatDirector.new(10) alone flags is_boss on every one of them.
	var mid := CombatDirector.new(10, 0, false)     # island 0, NOT the finale
	check("Evergreen ordinary level: is_boss is FALSE", not mid.is_boss)
	check_eq("Evergreen ordinary level: no boss id", String(mid.boss_id), "")
	check("Evergreen ordinary level: not the final boss", not mid.is_final_boss())

	var fin := CombatDirector.new(10, 0, true)      # island 0 finale
	check("Evergreen finale: is_boss is TRUE", fin.is_boss)
	check_eq("Evergreen finale: chapter boss", String(fin.boss_id), "poison_beast")

	# Celestial Haven (island 4): Jinn only on the finale.
	var cel_mid := CombatDirector.new(50, 4, false)
	check("Celestial ordinary level: is_boss FALSE", not cel_mid.is_boss)
	check("Celestial ordinary level: Jinn is NOT selected", not cel_mid.is_final_boss())
	var cel_fin := CombatDirector.new(50, 4, true)
	check("Celestial finale: is_boss TRUE", cel_fin.is_boss)
	check("Celestial finale: IS the final boss (Jinn)", cel_fin.is_final_boss())

func test_combat_director_flat_authored_path_is_unchanged() -> void:
	# island_index < 0 -> the direct authored-campaign callers (unit tests,
	# _debug_start_authored_level) keep the every-10th-stage semantics.
	check("flat: stage 10 is a finale", CombatDirector.new(10).is_boss)
	check("flat: stage 50 is a finale", CombatDirector.new(50).is_boss)
	check_eq("flat: stage 50 boss is Jinn", String(CombatDirector.new(50).boss_id), "jinn")
	check("flat: stage 7 is not a finale", not CombatDirector.new(7).is_boss)
	check("flat: stage 3 is not a finale", not CombatDirector.new(3).is_boss)

# ---- the actual routing: every world x every local-level position -------

func test_full_routing_no_early_boss_on_any_island() -> void:
	if not Engine.get_main_loop().root.has_node("GameData"):
		check("GameData autoload present", false, "needed for routing check")
		return
	var lpi: int = IslandProgress.LEVELS_PER_ISLAND
	var probe_locals := [1, 2, 5, 9, 10, 11, 20, 30, 40, 50, 60, 90, lpi - 1, lpi]
	for wi in WorldCatalog.count():
		var world_id := WorldCatalog.world_id_at(wi)
		var island_index := int(WorldCatalog.world(world_id).get("order", 1)) - 1
		for lv in probe_locals:
			var local_level: int = lv
			var authored: int = WorldCatalog.authored_level_id(world_id, local_level)
			var is_finale: bool = local_level >= lpi
			var cd := CombatDirector.new(authored, island_index, is_finale)
			# a boss/finale presentation may ONLY happen on the island finale
			check("world %d local %d: is_boss iff finale" % [wi, local_level],
				cd.is_boss == is_finale or (is_finale and island_index >= 5))
			if not is_finale:
				check("world %d local %d: NOT the main boss (Jinn)" % [wi, local_level],
					not cd.is_final_boss())
			# Jinn may surface only at Celestial Haven's (island index 4) finale
			if cd.is_final_boss():
				check("world %d local %d: Jinn only at island 4 finale" % [wi, local_level],
					island_index == 4 and is_finale)
