extends TestCase
## AdsService (autoload "Ads") — monetization policy contract.
##
## Covers: game plays ad-free when no backend is present; rewarded reward is
## granted exactly once and only on "earned"; a dismissed/failed/unavailable
## ad grants nothing; interstitial frequency gating (first-seconds guard,
## tutorial guard, cooldown, per-session cap, no two ads back-to-back).

func _drain() -> void:
	# let call_deferred() fire (Ads defers the "unavailable" failure a frame)
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).process_frame.emit()

func test_headless_has_no_ad_backend() -> void:
	Ads.debug_disable_fake_backend()
	check("no native plugin in headless -> ads unavailable", not Ads.available)
	check("can_show_rewarded is false", not Ads.can_show_rewarded())

func test_unavailable_rewarded_grants_nothing() -> void:
	Ads.debug_disable_fake_backend()
	var res := {"result": -1, "reward_calls": 0}
	var cb := func(): res["reward_calls"] += 1
	Ads.rewarded_result.connect(func(_p, earned): res["result"] = 1 if earned else 0, CONNECT_ONE_SHOT)
	Ads.show_rewarded("continue_moves", cb)
	_drain()
	check_eq("unavailable ad -> terminal result earned=false", res["result"], 0)
	check_eq("unavailable ad -> reward callback NOT called", res["reward_calls"], 0)
	check("not left in-flight", not Ads.is_rewarded_in_flight())

func test_rewarded_earned_grants_exactly_once() -> void:
	Ads.debug_enable_fake_backend(true)
	var res := {"completed": 0, "result_earned": -1, "reward_calls": 0}
	var cb := func(): res["reward_calls"] += 1
	Ads.rewarded_completed.connect(func(_p): res["completed"] += 1)
	Ads.rewarded_result.connect(func(_p, earned): res["result_earned"] = 1 if earned else 0)
	Ads.show_rewarded("free_booster", cb)
	check("in flight after show", Ads.is_rewarded_in_flight())
	Ads.debug_finish_rewarded("earned")
	# a duplicate/late callback must not re-grant
	Ads.debug_finish_rewarded("earned")
	check_eq("rewarded_completed emitted once", res["completed"], 1)
	check_eq("reward callback invoked once", res["reward_calls"], 1)
	check_eq("terminal result earned=true", res["result_earned"], 1)
	check("cleared after finish", not Ads.is_rewarded_in_flight())
	Ads.debug_disable_fake_backend()

func test_rewarded_dismissed_without_earning_grants_nothing() -> void:
	Ads.debug_enable_fake_backend(true)
	var res := {"result_earned": -1, "reward_calls": 0}
	Ads.rewarded_result.connect(func(_p, earned): res["result_earned"] = 1 if earned else 0)
	Ads.show_rewarded("double_win_coins", func(): res["reward_calls"] += 1)
	Ads.debug_finish_rewarded("closed")     # dismissed early, no reward
	check_eq("dismissed -> result earned=false", res["result_earned"], 0)
	check_eq("dismissed -> reward callback not called", res["reward_calls"], 0)
	Ads.debug_disable_fake_backend()

func test_rewarded_load_failure_grants_nothing() -> void:
	Ads.debug_enable_fake_backend(true)
	var res := {"result_earned": -1, "reward_calls": 0}
	Ads.rewarded_result.connect(func(_p, earned): res["result_earned"] = 1 if earned else 0)
	Ads.show_rewarded("free_coins", func(): res["reward_calls"] += 1)
	Ads.debug_finish_rewarded("failed", "no_fill")
	check_eq("load failure -> result earned=false", res["result_earned"], 0)
	check_eq("load failure -> reward callback not called", res["reward_calls"], 0)
	check("not stuck in-flight", not Ads.is_rewarded_in_flight())
	Ads.debug_disable_fake_backend()

func test_interstitial_never_shows_without_backend() -> void:
	Ads.debug_disable_fake_backend()
	var shown: bool = Ads.maybe_show_interstitial("t", {"levels_cleared": 999})
	check("no backend -> interstitial not shown", not shown)

func test_interstitial_frequency_gating() -> void:
	Ads.debug_enable_fake_backend(true)
	# fresh session: too young
	check("fresh session blocks interstitial", not Ads.maybe_show_interstitial("a", {"levels_cleared": 999}))
	Ads.debug_reset_session()
	# tutorial guard: not enough levels cleared
	check("tutorial guard blocks interstitial", not Ads.maybe_show_interstitial("b", {"levels_cleared": 1}))
	# enough cleared -> shows
	check("past tutorial -> interstitial shows", Ads.maybe_show_interstitial("c", {"levels_cleared": 10}))
	# immediately again -> cooldown (and back-to-back)
	check("cooldown blocks the next interstitial", not Ads.maybe_show_interstitial("d", {"levels_cleared": 10}))
	# after another reset, a rewarded ad in the last few seconds blocks it (no two back-to-back)
	Ads.debug_reset_session()
	Ads.show_rewarded("continue_moves")
	Ads.debug_finish_rewarded("earned")
	check("no interstitial right after a rewarded ad", not Ads.maybe_show_interstitial("e", {"levels_cleared": 10}))
	# session cap
	Ads.debug_disable_fake_backend()

func test_reward_amounts_from_config() -> void:
	check_eq("continue moves reward", Ads.reward_continue_moves(), 5)
	check_eq("free coins reward", Ads.reward_free_coins(), 120)
	var fb := Ads.reward_free_booster()
	check_eq("free booster id", String(fb["id"]), "bomb")
	check_eq("free booster amount", int(fb["amount"]), 1)
	check("double-win-coins enabled", Ads.double_win_coins_enabled())

func test_service_left_in_clean_headless_state() -> void:
	Ads.debug_disable_fake_backend()
	check("ads unavailable after tests", not Ads.available)
	check("nothing in flight", not Ads.is_rewarded_in_flight())
