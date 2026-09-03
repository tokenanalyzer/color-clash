extends TestCase
## Inventory autoload — power upgrades (spend Economy coins), equipment
## grant/equip, collectibles, boss reward. Persists via SaveService; no
## second save/currency system.

func test_powers_start_at_level_one() -> void:
	var lv := Inventory.power_levels()
	for p in JamiePowers.ORDER:
		check("%s level >= 1" % p, int(lv[p]) >= 1)
	check_eq("first upgrade of fire_sword costs 150", Inventory.power_upgrade_cost(&"fire_sword") if Inventory.power_level(&"fire_sword") == 1 else 150, 150 if Inventory.power_level(&"fire_sword") == 1 else Inventory.power_upgrade_cost(&"fire_sword"))

func test_upgrade_spends_coins_and_raises_the_level() -> void:
	Economy.grant(5000)
	var id := &"lightning_boots"
	var before_lv := Inventory.power_level(id)
	if before_lv >= Inventory.MAX_POWER_LEVEL:
		check("already maxed — upgrade refused", not Inventory.upgrade_power(id))
		return
	var cost := Inventory.power_upgrade_cost(id)
	var before_coins := Economy.coins
	var ok := Inventory.upgrade_power(id)
	check("upgrade succeeded", ok)
	check_eq("level went up by one", Inventory.power_level(id), before_lv + 1)
	check_eq("coins dropped by the cost", Economy.coins, before_coins - cost)

func test_starter_equipment_is_owned_and_equipped() -> void:
	check("a sword is owned", Inventory.is_owned(&"iron_sword"))
	check("a sword slot is equipped", String(Inventory.equipped_in(&"sword")) != "")
	check("a boots slot is equipped", String(Inventory.equipped_in(&"boots")) != "")

func test_grant_and_equip_new_gear() -> void:
	Inventory.grant_equipment(&"flame_brand")
	check("flame_brand now owned", Inventory.is_owned(&"flame_brand"))
	Inventory.equip(&"flame_brand")
	check_eq("flame_brand equipped in the sword slot", Inventory.equipped_in(&"sword"), &"flame_brand")
	# cannot equip something not owned
	Inventory.equip(&"aurora_striders")
	check("unowned gear cannot be equipped",
		Inventory.equipped_in(&"boots") != &"aurora_striders" or Inventory.is_owned(&"aurora_striders"))

func test_boss_reward_grants_the_staged_drop_and_a_shard() -> void:
	var before := int(Inventory.collectibles().get("kingdom_shard", 0))
	Inventory.grant_boss_reward(30)   # storm_greaves is the stage-30 drop
	check("stage-30 boss drop granted", Inventory.is_owned(&"storm_greaves"))
	check_eq("a kingdom shard was collected", int(Inventory.collectibles().get("kingdom_shard", 0)), before + 1)

func test_combat_director_reads_power_levels_from_inventory() -> void:
	var c := CombatDirector.new(3)
	check_eq("CombatDirector powers match Inventory levels",
		c.powers.level[&"fire_sword"], Inventory.power_level(&"fire_sword"))
