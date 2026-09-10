extends TestCase
## Match-3 -> character combat: JamiePowers meters + CombatDirector boss HP.
## Pure logic; no board, no save state.

func _move(cleared: int, powers_activated: int, chain_depth: int) -> ChainResolver.MoveResult:
	var r := ChainResolver.MoveResult.new()
	r.valid = true
	r.chain_depth = chain_depth
	for i in cleared:
		r.cleared_cells.append(Vector2i(i, 0))
	for i in powers_activated:
		r.powers_activated.append({"pos": Vector2i.ZERO, "power_id": &"bomb"})
	return r

func test_power_meters_fill_from_the_right_sources() -> void:
	var jp := JamiePowers.new()
	jp.feed(_move(10, 0, 1), 1, 10)
	check("fire_sword fills from cleared gems", jp.ratio(JamiePowers.FIRE_SWORD) > 0.0)
	check("lightning_hand stays empty with no power activations", jp.ratio(JamiePowers.LIGHTNING_HAND) == 0.0)
	jp.feed(_move(2, 1, 1), 1, 2)
	check("lightning_hand fills from power activations", jp.ratio(JamiePowers.LIGHTNING_HAND) > 0.0)
	jp.feed(_move(2, 0, 2), 2, 2)
	check("lightning_boots fills from cascade depth", jp.ratio(JamiePowers.LIGHTNING_BOOTS) > 0.0)

func test_full_meter_auto_fires_and_resets() -> void:
	var jp := JamiePowers.new()
	var ev := {}
	for i in 6:
		ev = jp.feed(_move(20, 0, 1), 1, 20)   # dump lots of fire energy
	check("fire_sword fired once it filled", (ev["fired"] as Array).has(JamiePowers.FIRE_SWORD))
	check("meter reset after firing", jp.ratio(JamiePowers.FIRE_SWORD) < 1.0)

func test_combo_and_ultimate_naming() -> void:
	check_eq("sword + hand", JamiePowers.combo_name(&"fire_sword", &"lightning_hand"), &"lightning_sword")
	check_eq("sword + boots", JamiePowers.combo_name(&"fire_sword", &"lightning_boots"), &"dash_slash")
	check_eq("hand + boots", JamiePowers.combo_name(&"lightning_hand", &"lightning_boots"), &"lightning_dash")
	check("ultimate does more than a single power",
		JamiePowers.new().attack_damage(&"ultimate") > JamiePowers.new().attack_damage(&"fire_sword"))

func test_combat_director_flags_finale_stages() -> void:
	# 2026-09-07: `is_boss` now means "chapter finale" (every 10th stage) —
	# it drives the villain-defeat presentation + boss music, NOT a health
	# bar. There is no boss HP any more.
	var c10 := CombatDirector.new(10)
	check("stage 10 is a chapter finale", c10.is_boss)
	check_eq("stage 10 villain is the Poison Beast", c10.boss_id, &"poison_beast")
	check("CombatDirector no longer tracks boss HP", not ("boss_hp" in c10))
	var c50 := CombatDirector.new(50)
	check("stage 50 is the final chapter (Jinn)", c50.is_final_boss())
	var c3 := CombatDirector.new(3)
	check("a normal stage is not a finale", not c3.is_boss)

func test_feed_move_builds_energy_without_any_hp_side_effect() -> void:
	# A finale stage's feed_move builds power-meter energy + emits jamie_attack
	# exactly like a normal stage — and never emits the (now-dead) HP signals.
	var c := CombatDirector.new(10)
	var hp_signal := [false]
	c.boss_damaged.connect(func(_a, _hp, _mx): hp_signal[0] = true)
	c.boss_defeated.connect(func(): hp_signal[0] = true)
	c.boss_attacked.connect(func(): hp_signal[0] = true)
	var attacks := [0]
	c.jamie_attack.connect(func(_k, _d, _b): attacks[0] += 1)
	for i in 8:
		c.feed_move(_move(12, 1, 3), 3, 12, true, 2)   # low moves_left too
	check("feed_move drives Jamie attacks", attacks[0] == 8)
	check("no boss-HP signal ever fires on a finale stage", not hp_signal[0])
