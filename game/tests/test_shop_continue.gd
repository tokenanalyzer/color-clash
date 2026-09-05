extends TestCase
## Phase B — in-level booster shop + "Need More Moves?" continue.
## Pure-logic + lightweight widget checks. Everything goes through the
## EXISTING autoloads (Economy / Boosters / SaveService) — there is no
## second currency and no second inventory, so buying/using in the in-level
## shop and in the separate Inventory screen mutate the same counts.

func _root() -> Node:
	return Engine.get_main_loop().root

# --------------------------------------------------- ContinueOffers --

func test_continue_offers_parse_tiers_in_order() -> void:
	var co := ContinueOffers.from_dict({"extra_moves": [
		{"id": "extra_moves_10", "moves": 10, "cost": 240},
		{"id": "extra_moves_5", "moves": 5, "cost": 140},
	]})
	var tiers := co.tiers()
	check_eq("two tiers parsed", tiers.size(), 2)
	check_eq("sorted ascending by moves", int(tiers[0]["moves"]), 5)
	check_eq("tier lookup by id", co.moves_of(&"extra_moves_10"), 10)
	check_eq("cost lookup by id", co.cost_of(&"extra_moves_5"), 140)
	check_eq("unknown tier -> empty", co.tier(&"nope").size(), 0)

func test_game_data_loads_the_continue_offers() -> void:
	check("GameData.continue_offers loaded", GameData.continue_offers != null)
	check("has at least the +5 and +10 tiers", GameData.continue_offers.tiers().size() >= 2)
	check_eq("+5 tier grants 5 moves", GameData.continue_offers.moves_of(&"extra_moves_5"), 5)
	check_eq("+10 tier grants 10 moves", GameData.continue_offers.moves_of(&"extra_moves_10"), 10)

func test_buying_extra_moves_deducts_coins_and_returns_move_count() -> void:
	Economy.grant(1000)
	var before := Economy.coins
	var cost := GameData.continue_offers.cost_of(&"extra_moves_5")
	var moves := GameData.continue_offers.purchase(&"extra_moves_5")
	check_eq("returns the tier's move count", moves, 5)
	check_eq("coins deducted by exactly the cost", Economy.coins, before - cost)

func test_buying_the_bigger_tier_costs_more_and_grants_more() -> void:
	Economy.grant(1000)
	var c5 := GameData.continue_offers.cost_of(&"extra_moves_5")
	var c10 := GameData.continue_offers.cost_of(&"extra_moves_10")
	check("+10 costs more than +5", c10 > c5)
	var before := Economy.coins
	var moves := GameData.continue_offers.purchase(&"extra_moves_10")
	check_eq("grants 10", moves, 10)
	check_eq("charged the +10 price", Economy.coins, before - c10)

func test_extra_moves_purchase_fails_when_broke_and_never_goes_negative() -> void:
	# drain the wallet
	Economy.spend(Economy.coins)
	check_eq("wallet empty", Economy.coins, 0)
	var moves := GameData.continue_offers.purchase(&"extra_moves_5")
	check_eq("no moves granted when broke", moves, 0)
	check_eq("coins stay at zero (never negative)", Economy.coins, 0)
	check("balance never negative", Economy.coins >= 0)

func test_extra_moves_purchase_persists_through_saveservice() -> void:
	Economy.grant(1000)
	GameData.continue_offers.purchase(&"extra_moves_5")
	check_eq("coin balance persisted", int(SaveService.get_int("coins", -1)), Economy.coins)

# ------------------------------------------ booster economy (shared) --

func test_shop_buy_uses_the_same_boosters_autoload_as_inventory() -> void:
	Economy.grant(2000)
	var before := Boosters.get_count(&"bomb")
	var ok := Boosters.purchase(&"bomb")
	check("purchase succeeded", ok)
	check_eq("count went up by exactly one", Boosters.get_count(&"bomb"), before + 1)
	# the separate Inventory screen reads this very same value
	check_eq("Boosters is the single source of truth", Boosters.counts.get(&"bomb", 0), before + 1)

func test_two_buys_add_two_no_duplicate_or_lost_purchase() -> void:
	Economy.grant(2000)
	var before := Boosters.get_count(&"lightning")
	Boosters.purchase(&"lightning")
	Boosters.purchase(&"lightning")
	check_eq("exactly +2 after two buys", Boosters.get_count(&"lightning"), before + 2)

func test_booster_buy_fails_when_broke_no_negative_balance() -> void:
	Economy.spend(Economy.coins)
	var before := Boosters.get_count(&"rainbow")
	var ok := Boosters.purchase(&"rainbow")
	check("purchase refused when broke", not ok)
	check_eq("inventory unchanged", Boosters.get_count(&"rainbow"), before)
	check("coins not negative", Economy.coins >= 0)

func test_using_a_booster_decrements_the_shared_count_and_persists() -> void:
	Boosters.add(&"freeze", 2)
	var before := Boosters.get_count(&"freeze")
	var used := Boosters.use(&"freeze")
	check("use succeeded", used)
	check_eq("count down by one", Boosters.get_count(&"freeze"), before - 1)
	check_eq("persisted to save", int((SaveService.get_value("boosters", {}) as Dictionary).get("freeze", -1)),
		Boosters.get_count(&"freeze"))

func test_booster_prices_scale_with_impact() -> void:
	var bomb := int(GameData.boosters[&"bomb"].get("cost", 0))
	var rainbow := int(GameData.boosters[&"rainbow"].get("cost", 0))
	check("rainbow (clears a whole colour) costs more than bomb", rainbow > bomb)
	check("every booster has a positive price", bomb > 0 and rainbow > 0)

# ------------------------------------------------ BoosterShop widget --
# add_child() runs _ready() synchronously, so these need no frame stepping.
# The logical open/close/use/bought signals all fire synchronously (only the
# fade-out visuals are deferred), which keeps them safe for the sync runner.

func test_booster_shop_opens_and_closes() -> void:
	var shop := BoosterShop.new()
	_root().add_child(shop)
	check("starts hidden", not shop.is_open())
	shop.open()
	check("open() marks it open", shop.is_open())
	check("visible when open", shop.visible)
	var closed_fired := [false]
	shop.closed.connect(func(): closed_fired[0] = true)
	shop.close()
	check("close() clears the open flag", not shop.is_open())
	check("closed signal fired", closed_fired[0])
	shop.queue_free()

func test_booster_shop_buy_confirm_routes_through_economy_and_boosters() -> void:
	Economy.grant(2000)
	var shop := BoosterShop.new()
	_root().add_child(shop)
	shop.open()
	var coins_before := Economy.coins
	var owned_before := Boosters.get_count(&"bomb")
	shop.request_buy(&"bomb")
	var ok := shop.confirm_buy()
	check("confirm_buy reported success", ok)
	check_eq("one bomb added", Boosters.get_count(&"bomb"), owned_before + 1)
	check_eq("coins charged", Economy.coins, coins_before - int(GameData.boosters[&"bomb"].get("cost", 0)))
	shop.queue_free()

func test_booster_shop_use_emits_and_closes() -> void:
	Boosters.add(&"lightning", 1)
	var shop := BoosterShop.new()
	_root().add_child(shop)
	shop.open()
	var got := [StringName("")]
	shop.use_requested.connect(func(id): got[0] = id)
	shop.request_use(&"lightning")
	check_eq("use_requested carried the booster id", got[0], &"lightning")
	check("shop closed itself on USE", not shop.is_open())
	shop.queue_free()

func test_booster_shop_confirm_blocks_when_broke() -> void:
	Economy.spend(Economy.coins)
	var shop := BoosterShop.new()
	_root().add_child(shop)
	shop.open()
	var owned_before := Boosters.get_count(&"rainbow")
	shop.request_buy(&"rainbow")
	var ok := shop.confirm_buy()
	check("confirm refused with no coins", not ok)
	check_eq("nothing bought", Boosters.get_count(&"rainbow"), owned_before)
	check("still no negative balance", Economy.coins >= 0)
	shop.queue_free()

# ------------------------------------------- ExtraMovesPrompt widget --

func test_moves_prompt_opens_and_buys() -> void:
	Economy.grant(2000)
	var prompt := ExtraMovesPrompt.new()
	_root().add_child(prompt)
	prompt.open()
	check("prompt open", prompt.is_open())
	var bought := [0]
	prompt.bought.connect(func(m): bought[0] = m)
	var coins_before := Economy.coins
	prompt._buy(&"extra_moves_5")
	check_eq("bought signal reported +5 moves", bought[0], 5)
	check_eq("coins spent on the continue", Economy.coins,
		coins_before - GameData.continue_offers.cost_of(&"extra_moves_5"))
	check("prompt closed after buying", not prompt.is_open())
	prompt.queue_free()

func test_moves_prompt_give_up_emits_without_spending() -> void:
	Economy.grant(500)
	var prompt := ExtraMovesPrompt.new()
	_root().add_child(prompt)
	prompt.open()
	var gave_up := [false]
	var coins_before := Economy.coins
	prompt.gave_up.connect(func(): gave_up[0] = true)
	prompt._decline()
	check("gave_up signal fired", gave_up[0])
	check_eq("no coins spent on giving up", Economy.coins, coins_before)
	prompt.queue_free()

# ------------------------------------- overlay sizing (device clip bug) --

## Regression test for a physical-device bug: the booster shop / "Need More
## Moves?" panels are constructed inside HUD._ready() BEFORE HUD itself has
## a real size (a Control parented to a CanvasLayer starts at (0,0)). Their
## FULL_RECT anchors baked size/offsets against that zero-sized parent; when
## HUD grew to the real viewport a frame later, the anchor contribution and
## the stale offset both counted the full width, doubling the overlay's
## width and pushing "NEED MORE MOVES?" and the shop off the right edge.
## HUD._track_size() now re-tracks each overlay after sizing itself.
func test_overlay_children_are_not_double_sized_after_hud_settles() -> void:
	var hud := HUD.new()
	_root().add_child(hud)
	var vp := hud.get_viewport_rect().size
	check("HUD itself matches the viewport", hud.size.is_equal_approx(vp), "hud.size=%s vp=%s" % [hud.size, vp])
	check("booster shop is NOT double-wide", hud._booster_shop.size.is_equal_approx(vp),
		"shop.size=%s vp=%s" % [hud._booster_shop.size, vp])
	check("moves prompt is NOT double-wide", hud._moves_prompt.size.is_equal_approx(vp),
		"prompt.size=%s vp=%s" % [hud._moves_prompt.size, vp])
	check("settings dialog is NOT double-wide", hud._settings_dialog.size.is_equal_approx(vp),
		"settings.size=%s vp=%s" % [hud._settings_dialog.size, vp])
	hud.queue_free()
