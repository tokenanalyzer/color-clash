extends TestCase
## 2026-09-07 gameplay overhaul — the CAMPAIGN must actually deliver
## progression + variety, not "collect X of a colour with a bigger X".
## Reads the real campaign through GameData.levels (LevelConfig), plus the
## finale-stage / background wiring.

func _lc(id: int) -> LevelConfig:
	return GameData.levels.get_level(id)

func _family(kind: String) -> String:
	return {
		"wooden_crate": "ice", "reinforced_crate": "ice", "frozen_crystal": "ice", "ice": "ice",
		"magic_chain": "lock", "lock": "lock",
		"cursed_stone": "stone", "shadow_barrier": "stone", "stone": "stone",
		"dark_rune": "timebomb", "timebomb": "timebomb",
	}.get(kind, kind)

# ------------------------------------------------------- difficulty ramp --

func test_difficulty_rank_climbs_1_to_10_monotonically() -> void:
	check_eq("50 stages", GameData.levels.count(), 50)
	var prev := 0
	for id in range(1, 51):
		var lc := _lc(id)
		check("L%d rank never regresses" % id, lc.difficulty_rank >= prev)
		prev = lc.difficulty_rank
	check_eq("first stage rank 1", _lc(1).difficulty_rank, 1)
	check_eq("last stage rank 10", _lc(50).difficulty_rank, 10)

func test_moves_are_generous_and_data_driven_never_a_move_starve() -> void:
	var seen := {}
	for id in range(1, 51):
		var lc := _lc(id)
		check("L%d moves >= fair floor 23" % id, lc.starting_moves >= 23)
		check("L%d starting_moves == move_limit alias" % id, lc.starting_moves == lc.move_limit)
		seen[lc.starting_moves] = true
	check("move budgets are level-data driven (>=3 distinct)", seen.size() >= 3)

func test_objective_and_blocker_load_grows_across_the_campaign() -> void:
	var early_obj := 0
	var late_obj := 0
	var early_obs := 0
	var late_obs := 0
	for id in range(1, 51):
		var lc := _lc(id)
		var isl := (id - 1) / 10
		if isl <= 1:
			early_obj += lc.objectives.size()
			early_obs += lc.obstacles.size()
		elif isl >= 3:
			late_obj += lc.objectives.size()
			late_obs += lc.obstacles.size()
	check("later islands run more simultaneous objectives", late_obj > early_obj)
	check("later islands carry denser blocker fields", late_obs > early_obs)

# --------------------------------------------------- objective variety --

func test_clear_color_does_not_dominate_the_objective_design() -> void:
	var lead_cc := 0
	var types := {}
	for id in range(1, 51):
		var lc := _lc(id)
		if String(lc.objectives[0].get("type", "")) == "clear_color":
			lead_cc += 1
		for o in lc.objectives:
			types[String(o.get("type", ""))] = true
	check("clear_color leads <= 55%% of stages, got %d/50" % lead_cc, lead_cc <= 27)
	for t: String in ["clear_color", "reach_score", "create_powers", "break_obstacles", "deliver"]:
		check("campaign uses objective type '%s'" % t, types.has(t))

func test_tutorial_stages_1_to_3_teach_one_idea_with_no_blockers() -> void:
	for id: int in [1, 2, 3]:
		var lc := _lc(id)
		check("tutorial L%d has no blockers" % id, lc.obstacles.is_empty())
		check("tutorial L%d has exactly one objective" % id, lc.objectives.size() == 1)
		check("tutorial L%d has no escort yet" % id, lc.specials.is_empty())

func test_blocker_families_are_introduced_in_order() -> void:
	var first_seen := {}
	for id in range(1, 51):
		for o in _lc(id).obstacles:
			var fam := _family(String(o.get("type", "")))
			if not first_seen.has(fam):
				first_seen[fam] = id
	check("ice family taught before stone family",
		int(first_seen.get("ice", 99)) < int(first_seen.get("stone", 99)))
	check("stone family taught before timebomb family",
		int(first_seen.get("stone", 99)) < int(first_seen.get("timebomb", 99)))
	var earliest := 99
	for v: int in first_seen.values():
		earliest = mini(earliest, int(v))
	check("no blocker at all before stage 4", earliest >= 4)

# ----------------------------------------------- escort (Love Crystal) --

func test_escort_recurs_and_scales_and_is_always_solvable() -> void:
	var escort_stages := 0
	var max_crystals := 0
	for id in range(1, 51):
		var lc := _lc(id)
		if lc.specials.is_empty():
			continue
		escort_stages += 1
		max_crystals = maxi(max_crystals, lc.specials.size())
		var obstacle_cells := {}
		for o in lc.obstacles:
			obstacle_cells[Vector2i(int(o.get("x", 0)), int(o.get("y", 0)))] = String(o.get("type", ""))
		var cols := {}
		for s in lc.specials:
			var sx := int(s.get("x", 0))
			var sy := int(s.get("y", 0))
			check("L%d crystal is a relic" % id, String(s.get("type", "")) == "relic")
			check("L%d crystal in the upper half with room to fall" % id, sy >= 1 and sy <= lc.height - 4)
			check("L%d crystal inside the play columns" % id, sx >= 1 and sx <= lc.width - 2)
			check("L%d crystal not on a blocker" % id, not obstacle_cells.has(Vector2i(sx, sy)))
			check("L%d one crystal per column" % id, not cols.has(sx))
			cols[sx] = true
			var stones_below := 0
			for o in lc.obstacles:
				if int(o.get("x", 0)) == sx and int(o.get("y", 0)) > sy \
						and String(o.get("type", "")) in ["cursed_stone", "shadow_barrier"]:
					stones_below += 1
			check("L%d crystal not stone-walled below" % id, stones_below <= 1)
		for o in lc.objectives:
			if String(o.get("type", "")) == "deliver":
				check("L%d deliver target <= crystals placed" % id, int(o.get("target", 0)) <= lc.specials.size())
	check("escort mechanic recurs (>= 8 stages)", escort_stages >= 8)
	check("crystal count scales into the endgame (>= 3 somewhere)", max_crystals >= 3)

# --------------------------------------------------- finale / villain --

func test_finale_stages_have_no_hp_win_condition() -> void:
	var supported := ["clear_color", "reach_score", "create_powers", "break_obstacles", "deliver"]
	for sid: int in [10, 20, 30, 40, 50]:
		var lc := _lc(sid)
		check("finale L%d has >= 2 objectives" % sid, lc.objectives.size() >= 2)
		for o in lc.objectives:
			check("finale L%d goal '%s' is a real objective, not HP" % [sid, o.get("type", "")],
				supported.has(String(o.get("type", ""))))

func test_combat_director_carries_no_boss_hp() -> void:
	var c10 := CombatDirector.new(10)
	check("stage 10 flagged as a chapter finale", c10.is_boss)
	check("CombatDirector has NO boss_hp field", not ("boss_hp" in c10))
	check("CombatDirector has NO boss_hp_max field", not ("boss_hp_max" in c10))
	check("a normal stage is not a finale", not CombatDirector.new(7).is_boss)

# ------------------------------------------------------ backgrounds --

func test_every_level_names_its_island_backdrop() -> void:
	var island_env: Array[StringName] = [
		&"env_floating_islands", &"env_crystal_formations", &"env_large_structures",
		&"env_clouds_mists", &"env_aurora_energy_bands",
	]
	for id in range(1, 51):
		var lc := _lc(id)
		var isl := (id - 1) / 10
		check("L%d declares an env backdrop" % id, lc.env != &"")
		check_eq("L%d env matches its island theme" % id, lc.env, island_env[isl])

func test_island_theme_backdrops_resolve_to_real_art() -> void:
	for isl in 5:
		var theme := IslandModel.island_theme(isl)
		check("island %d theme is set" % isl, theme != &"")
		check("island %d backdrop '%s' loads" % [isl, theme], AssetLibrary.tex(theme) != null)
