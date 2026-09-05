extends TestCase
## Jasmine's dynamic combat-arena presence (Phase C follow-up). Pure widget
## checks — the real wiring to gameplay events is exercised by
## smoke_combat_anim.gd (needs the full app + CombatDirector running).

func _root() -> Node:
	return Engine.get_main_loop().root

func test_every_declared_state_resolves_a_real_texture() -> void:
	for state in Cast.JASMINE_STATE_TABLE:
		check("state '%s' -> texture" % state, Cast.jasmine_state(state) != null)
	check("unknown state falls back to idle", Cast.jasmine_state(&"not_a_state") == Cast.jasmine_state(&"idle"))

func test_story_critical_states_use_the_dedicated_emotion_crops() -> void:
	# these must NOT fall back to the generic pose grid — they're the whole
	# point of using jasmine_expressions_ref.png.
	for state in [&"scared", &"worried", &"crying", &"captured", &"rescued", &"victory"]:
		check_eq("'%s' uses its emotion crop" % state, Cast.jasmine_state(state), Cast.jasmine_emotion(state))

func test_actor_changes_texture_with_state() -> void:
	var j := JasmineActor.new()
	_root().add_child(j)
	j.configure(500.0, 900.0, 240.0, 1000.0)
	check_eq("starts idle", j.state(), &"idle")
	var idle_tex := Cast.jasmine_state(&"idle")
	j.set_state(&"captured", false)
	check_eq("state updated", j.state(), &"captured")
	var captured_tex := Cast.jasmine_state(&"captured")
	check("texture actually changed", captured_tex != idle_tex)
	j.queue_free()

func test_actor_shifts_position_between_a_fearful_and_a_positive_state() -> void:
	var j := JasmineActor.new()
	_root().add_child(j)
	j.configure(500.0, 900.0, 240.0, 1000.0)
	j.set_state(&"captured", false)
	var captured_x := j.target_position().x
	j.set_state(&"rescued", false)
	var rescued_x := j.target_position().x
	check("rescued sits further right (toward Jamie) than captured",
		rescued_x > captured_x, "captured_x=%.1f rescued_x=%.1f" % [captured_x, rescued_x])
	j.queue_free()

func test_setting_the_same_state_twice_is_a_no_op() -> void:
	var j := JasmineActor.new()
	_root().add_child(j)
	j.configure(500.0, 900.0, 240.0, 1000.0)
	var fired := [0]
	j.changed.connect(func(_s): fired[0] += 1)
	j.set_state(&"hopeful")
	j.set_state(&"hopeful")
	check_eq("second identical set_state did not re-fire", fired[0], 1)
	j.queue_free()

# --------------------------------------------------- freeze / rainbow FX --

func test_freeze_and_rainbow_have_their_own_distinct_action_identity() -> void:
	var cfg := JsonLoader.load_json("res://data/jamie_actions.json")
	var actions: Dictionary = cfg.get("actions", {})
	check("attack_freeze is its own action (not a generic blast)", actions.has("attack_freeze"))
	check("attack_rainbow is its own action (not the generic mega blast)", actions.has("attack_rainbow"))
	check_eq("freeze uses the ice VFX", String(actions["attack_freeze"].get("impact", "")), "vfx_ice_burst")
	check_eq("rainbow uses the rainbow VFX", String(actions["attack_rainbow"].get("impact", "")), "vfx_rainbow_burst")
	check("freeze stuns rather than just knocking back",
		String(actions["attack_freeze"].get("enemy_reaction", "")) == "stun")
	check("freeze and rainbow use different sfx",
		actions["attack_freeze"]["sfx"] != actions["attack_rainbow"]["sfx"])
