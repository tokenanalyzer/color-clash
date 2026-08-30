extends TestCase
## Exercises the Economy/Boosters autoload singletons directly. These are
## Node autoloads (not pure RefCounted logic) but stay deterministic and
## safe to test headlessly since SaveService/GameData load synchronously.

func test_economy_spend_and_grant() -> void:
	var start := Economy.coins
	Economy.grant(100)
	check_eq("grant_increases_balance", Economy.coins, start + 100)
	var spent_ok := Economy.spend(50)
	check("spend_succeeds_when_affordable", spent_ok)
	check_eq("balance_after_spend", Economy.coins, start + 50)
	var over := Economy.spend(999999999)
	check("spend_fails_when_insufficient", not over)

func test_booster_purchase_uses_economy() -> void:
	Economy.grant(1000)
	var before := Boosters.get_count(&"bomb")
	var purchase_ok := Boosters.purchase(&"bomb")
	check("purchase_succeeds_when_affordable", purchase_ok)
	check_eq("inventory_increases_after_purchase", Boosters.get_count(&"bomb"), before + 1)

func test_booster_use_decrements_inventory() -> void:
	Boosters.add(&"lightning", 3)
	var before := Boosters.get_count(&"lightning")
	var used := Boosters.use(&"lightning")
	check("use_succeeds_when_available", used)
	check_eq("count_decrements_on_use", Boosters.get_count(&"lightning"), before - 1)

func test_booster_purchase_fails_for_unknown_id() -> void:
	var ok := Boosters.purchase(&"not_a_real_booster")
	check("unknown_booster_purchase_fails", not ok)
