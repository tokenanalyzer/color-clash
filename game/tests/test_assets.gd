extends TestCase
## Guards the prepared art integration (assets 1-74): every logical id in
## AssetLibrary must resolve to a real, non-empty Texture2D, and a few
## representative ids from each group are asserted by name so a rename or a
## missing import fails CI loudly rather than silently falling back to the
## procedural draw.

func test_every_registered_texture_loads() -> void:
	var a: Dictionary = Assets.audit()
	check("all 74 asset ids resolve to a texture",
		a["missing"].is_empty(), "missing: %s" % str(a["missing"]))
	check_eq("registry size", int(a["total"]), 74)

func test_group_representatives_present() -> void:
	for id in [
		&"gem_red", &"gem_purple",                        # 1-6 gems
		&"power_bomb", &"power_rainbow", &"power_combo_core",  # 7-12 powers
		&"obstacle_ice_block", &"obstacle_time_bomb_fuse",     # 13-18 obstacles
		&"vfx_explosion_core", &"vfx_energy_trail_head",       # 19-30 vfx
		&"eco_gold_coin", &"eco_reward_chest", &"eco_coin_burst",  # 31-39 economy
		&"map_current_node", &"map_portal", &"map_destination_structure",  # 40-48 map
		&"ui_coin_icon", &"ui_power_energy_container", &"ui_level_badge",   # 49-57 ui
		&"env_main_background", &"env_map_landmarks", &"env_aurora_energy_bands",  # 58-67 env
		&"cel_victory_crown", &"cel_fever_activation_emblem",  # 68-74 celebration
	]:
		var t: Texture2D = Assets.tex(id)
		check("%s loads" % id, t != null and t.get_width() > 0 and t.get_height() > 0,
			"texture for %s did not load" % id)

func test_convenience_lookups() -> void:
	check("Assets.gem(&\"blue\") resolves", Assets.gem(&"blue") != null)
	check("Assets.power(&\"lightning\") resolves", Assets.power(&"lightning") != null)
	check("world_for_level cycles", Assets.world_for_level(1) != null and Assets.world_for_level(25) != null)
	check("unknown id returns null", Assets.tex(&"does_not_exist") == null)
