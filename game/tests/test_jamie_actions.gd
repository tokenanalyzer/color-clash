extends TestCase
## Phase C — Jamie combat animation system. The controller is pure logic and
## fully deterministic; the rig/Cast checks are light. CombatDirector still
## owns damage — these tests only prove the PRESENTATION state machine is
## correct, never skips a `strike` beat, and never duplicates one.

const _ACTIONS_PATH := "res://data/jamie_actions.json"

func _cfg() -> Dictionary:
	return JsonLoader.load_json(_ACTIONS_PATH)

func _controller() -> JamieActionController:
	return JamieActionController.from_dict(_cfg())

func _events_of(list: Array) -> Array:
	return list.map(func(e): return String(e["event"]))

func _run(c: JamieActionController, dt: float, steps: int) -> Array:
	var all: Array = []
	for i in steps:
		all.append_array(c.tick(dt))
	return all

## Capture EVERY phase_changed emission (including the windup_start fired
## synchronously inside request()), as {event, action, meta} dicts.
func _capture(c: JamieActionController) -> Array:
	var log: Array = []
	c.phase_changed.connect(func(ev, act, meta): log.append({"event": ev, "action": act, "meta": meta}))
	return log

# ------------------------------------------------------ data integrity --

func test_all_required_actions_exist() -> void:
	var a: Dictionary = _cfg().get("actions", {})
	for id in ["attack_sword", "attack_lightning", "attack_dash", "attack_bomb",
			"attack_blast", "attack_mega_blast", "fever_ultimate", "hurt", "victory"]:
		check("action '%s' defined" % id, a.has(id))

func test_action_timings_are_within_the_brief_ranges() -> void:
	var c := _controller()
	# normal attack 0.4-0.9, power 0.7-1.3, heavy 0.9-1.5, ultimate 1.5-3.0
	check("sword total in normal range", c.action_duration(&"attack_sword") >= 0.4 and c.action_duration(&"attack_sword") <= 1.0)
	check("lightning total in power range", c.action_duration(&"attack_lightning") <= 1.3)
	check("mega blast is a heavy attack", c.action_duration(&"attack_mega_blast") >= 0.9 and c.action_duration(&"attack_mega_blast") <= 1.6)
	var ult := c.action_duration(&"fever_ultimate")
	check("fever ultimate 1.5-3.0s", ult >= 1.5 and ult <= 3.0, "ult=%.2f" % ult)

func test_projectile_and_impact_vfx_ids_resolve() -> void:
	var a: Dictionary = _cfg().get("actions", {})
	for id in a:
		var d: Dictionary = a[id]
		for key in ["projectile", "impact"]:
			if d.has(key):
				var vid := StringName(String(d[key]))
				check("%s.%s '%s' resolves" % [id, key, vid], AssetLibrary.tex(vid) != null)

# ---------------------------------------------------- state machine --

func test_request_when_idle_begins_a_windup() -> void:
	var c := _controller()
	check_eq("starts idle", c.state, JamieActionController.IDLE)
	check("known action accepted", c.request(&"attack_sword"))
	check_eq("now in windup", c.state, JamieActionController.WINDUP)
	check("busy", c.is_busy())

func test_unknown_action_is_ignored() -> void:
	var c := _controller()
	check("unknown id rejected", not c.request(&"attack_banana"))
	check_eq("still idle", c.state, JamieActionController.IDLE)

func test_full_phase_cycle_emits_each_beat_once_then_returns_to_idle() -> void:
	var c := _controller()
	var log := _capture(c)
	c.request(&"attack_sword")
	_run(c, 0.05, 60)
	var evs := _events_of(log)
	check_eq("one windup_start", evs.count("windup_start"), 1)
	check_eq("exactly one strike", evs.count("strike"), 1)
	check_eq("exactly one recover", evs.count("recover"), 1)
	check_eq("exactly one action_done", evs.count("action_done"), 1)
	check("strike precedes recover", evs.find("strike") < evs.find("recover"))
	check_eq("back to idle", c.state, JamieActionController.IDLE)

func test_a_large_dt_spike_never_skips_the_strike() -> void:
	var c := _controller()
	c.request(&"attack_bomb")
	var evs := _events_of(c.tick(10.0))   # one monster frame past the whole action
	check("strike still emitted", evs.has("strike"))
	check("recover still emitted", evs.has("recover"))
	check("action_done still emitted", evs.has("action_done"))
	check_eq("ended idle", c.state, JamieActionController.IDLE)

func test_rapid_requests_queue_and_run_in_order() -> void:
	var c := _controller()
	var log := _capture(c)
	c.request(&"attack_sword")
	c.request(&"attack_lightning")
	check_eq("second one queued", c.queue_size(), 1)
	_run(c, 0.05, 120)
	var evs := _events_of(log)
	check_eq("both windups happened", evs.count("windup_start"), 2)
	check_eq("both strikes happened", evs.count("strike"), 2)
	check_eq("idle when the queue drains", c.state, JamieActionController.IDLE)

func test_queue_is_bounded_and_drops_the_oldest() -> void:
	var c := _controller()
	c.request(&"attack_sword")                 # in-flight
	for i in 8:
		c.request(&"attack_dash")              # spam
	check("queue capped", c.queue_size() <= JamieActionController.QUEUE_MAX)
	check("overflow counted", c.dropped > 0)

func test_reset_forces_idle_and_clears_the_queue() -> void:
	var c := _controller()
	c.request(&"attack_sword")
	c.request(&"attack_dash")
	c.reset()
	check_eq("idle after reset", c.state, JamieActionController.IDLE)
	check_eq("queue cleared", c.queue_size(), 0)

func test_fever_ultimate_strikes_once_per_sub_power() -> void:
	var c := _controller()
	var log := _capture(c)
	c.request(&"fever_ultimate")
	_run(c, 0.03, 200)
	var strikes := log.filter(func(e): return String(e["event"]) == "strike")
	check_eq("three sub-strikes (sword + lightning + dash)", strikes.size(), 3)
	var subs := strikes.map(func(e): return String(e["meta"].get("sub_action", "")))
	check("sub-actions are the three signature powers",
		subs.has("attack_sword") and subs.has("attack_lightning") and subs.has("attack_dash"))
	check_eq("still resolves to idle", c.state, JamieActionController.IDLE)

func test_controller_never_touches_damage_state() -> void:
	# it has no reference to CombatDirector / boss HP at all
	var c := _controller()
	check("no combat coupling", not ("boss_hp" in c) and not ("damage" in c))

# ----------------------------------------------------- Cast / clean art --

func test_jamie_and_jinn_pose_resolve_to_the_clean_portrait() -> void:
	# cast_atlas_transparent.png is RGB with a baked checkerboard, so every
	# Jamie/Jinn "pose" resolves to the clean RGBA portrait cut-out.
	check("jamie_pose returns a texture", Cast.jamie_pose(&"attack_sword") != null)
	check_eq("jamie_pose == the clean portrait", Cast.jamie_pose(&"whatever"),
		Cast.portrait(Cast.WHO_JAMIE))
	check_eq("Cast.pose(JAMIE) == portrait", Cast.pose(Cast.WHO_JAMIE, &"attack_lightning"),
		Cast.portrait(Cast.WHO_JAMIE))
	check_eq("jinn_pose == jinn portrait", Cast.jinn_pose(&"idle"), Cast.portrait(Cast.WHO_JINN))
	check("no AtlasTexture from the checkered collage", not (Cast.jamie_pose(&"x") is AtlasTexture))

func test_enemy_face_uses_the_keyed_sheet() -> void:
	# shadow_ghost has no dedicated art (data/enemies.json), so it still
	# slices the shared keyed sheet, source PNG untouched.
	var t := EnemyModel.enemy_face(&"shadow_ghost")
	check("enemy face exists", t != null)
	check("it is an AtlasTexture (source PNG untouched)", t is AtlasTexture)

func test_enemy_face_dedicated_art_bypasses_the_sheet() -> void:
	# poison_beast (2026-09-05 polish pass) got its own single-character
	# art instead — a plain texture, not a sheet slice.
	var t := EnemyModel.enemy_face(&"poison_beast")
	check("enemy face exists", t != null)
	check("it is NOT an AtlasTexture (dedicated art, not the shared sheet)", not (t is AtlasTexture))
	if t is AtlasTexture:
		check("it slices the checkerboard-keyed sheet",
			(t as AtlasTexture).atlas == AssetLibrary.tex(&"story_enemies_keyed"))

# ------------------------------------------------------- JamieRig node --

func test_jamie_rig_runs_an_action_and_reports_an_enemy_reaction() -> void:
	var rig := JamieRig.new()
	Engine.get_main_loop().root.add_child(rig)
	rig.configure(14.0, 900.0, 320.0, Vector2(700.0, 760.0))
	var got := [StringName("")]
	rig.enemy_reaction.connect(func(kind, _p): got[0] = kind)
	rig.play(&"attack_sword")
	check("rig is busy after play()", rig.is_busy())
	rig._process(10.0)                          # force the whole action through
	check_eq("enemy reaction kind delivered", got[0], &"hit")
	check("rig returned to idle", not rig.is_busy())
	rig.queue_free()

func test_jamie_rig_sizes_from_the_real_portrait_aspect() -> void:
	var rig := JamieRig.new()
	Engine.get_main_loop().root.add_child(rig)
	rig.configure(14.0, 900.0, 320.0, Vector2(700.0, 760.0))
	check("rig height matches the requested char height", absf(rig.size.y - 320.0) < 1.0)
	check("rig is portrait-proportioned (taller than wide)", rig.size.x < rig.size.y)
	check("rig width is a sane fraction of its height", rig.size.x > 320.0 * 0.4 and rig.size.x < 320.0)
	rig.queue_free()

# ------------------------------------------------------ EnemyActor node --

func test_enemy_actor_picks_villain_vs_boss_by_stage() -> void:
	var ea := EnemyActor.new()
	Engine.get_main_loop().root.add_child(ea)
	var torso3 := ea.configure(3, 1000.0, 900.0, 260.0)
	check("normal stage -> minor villain", not ea.is_boss_actor())
	check("returns a torso point inside its rect", torso3.x > 0.0 and torso3.y > 0.0)
	check("enemy actor is visible with art", ea.visible)
	var _t10 := ea.configure(10, 1000.0, 900.0, 260.0)
	check("stage 10 -> boss takes over", ea.is_boss_actor())
	ea.play_hit(&"heavy_hit")       # must not crash
	ea.play_hit(&"stun")
	ea.play_defeat()
	check("still alive as a node after defeat anim starts", is_instance_valid(ea))
	ea.queue_free()

func test_enemy_actor_never_mirrors_dedicated_art() -> void:
	# 2026-09-05 correction: the 5 dedicated single-character pieces must
	# render at their exact supplied angle/facing — never horizontally
	# flipped (unlike the old shared sheet, which was always flipped).
	var ea := EnemyActor.new()
	Engine.get_main_loop().root.add_child(ea)
	ea.configure(1, 1000.0, 900.0, 260.0)          # stage 1 -> poison_beast (dedicated art)
	check_eq("dedicated-art villain is not mirrored", ea._facing, 1.0)
	check_eq("sprite scale.x matches (not flipped)", ea._sprite.scale.x, 1.0)
	ea.configure(50, 1000.0, 900.0, 260.0)         # stage 50 -> Jinn (pre-existing, unchanged path)
	check_eq("Jinn's portrait keeps its pre-existing mirrored presentation", ea._facing, -1.0)
	ea.queue_free()
