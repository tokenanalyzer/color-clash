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

func test_combat_director_flags_boss_stages() -> void:
	var c10 := CombatDirector.new(10)
	check("stage 10 is a boss fight", c10.is_boss)
	check_eq("stage 10 boss is the Poison Beast", c10.boss_id, &"poison_beast")
	check_eq("boss starts at full HP", c10.boss_hp, c10.boss_hp_max)
	check("boss has real HP", c10.boss_hp_max > 0)
	var c50 := CombatDirector.new(50)
	check("stage 50 is the final boss", c50.is_final_boss())
	var c3 := CombatDirector.new(3)
	check("a normal stage has no boss", not c3.is_boss)
	check_eq("normal stage boss HP is 0", c3.boss_hp_max, 0)

func test_matching_damages_and_eventually_defeats_the_boss() -> void:
	var c := CombatDirector.new(10)
	var damaged := [0]
	var defeated := [false]
	c.boss_damaged.connect(func(_a, _hp, _mx): damaged[0] += 1)
	c.boss_defeated.connect(func(): defeated[0] = true)
	var guard := 0
	while c.boss_hp > 0 and guard < 60:
		c.feed_move(_move(12, 1, 3), 3, 12, true, 20)
		guard += 1
	check("boss took damage from matches", damaged[0] > 0)
	check("boss was defeated by matching", defeated[0])
	check_eq("boss HP floored at 0", c.boss_hp, 0)

func test_boss_attacks_when_moves_run_low() -> void:
	var c := CombatDirector.new(20)
	var hit := [false]
	c.boss_attacked.connect(func(): hit[0] = true)
	c.feed_move(_move(4, 0, 1), 1, 4, true, 2)   # moves_left <= 3, boss still alive
	check("boss counter-attacks near fail", hit[0])
