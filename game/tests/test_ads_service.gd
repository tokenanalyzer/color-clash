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

func test_interstitial_session_cap() -> void:
	Ads.debug_enable_fake_backend(true)
	Ads.debug_reset_session()
	# jump the session state to "cap already reached, cooldown elapsed":
	Ads._interstitials_this_session = int(Ads.config.get("interstitial", {}).get("max_per_session", 4))
	Ads._last_interstitial_ms = -10_000_000
	Ads._last_any_ad_ms = -10_000_000
	check("interstitial blocked once the per-session cap is hit",
		not Ads.maybe_show_interstitial("cap", {"levels_cleared": 20}))
	Ads.debug_disable_fake_backend()

# ---- native plugin glue (GDScript stand-in for the .kt bridge) ----------

class _NativeStub extends RefCounted:
	signal ad_event(event: String, message: String)
	var rewarded_ready := false
	var interstitial_ready := false
	var auto_init := true
	var privacy_options_required_value := false
	var can_request_ads_value := true
	var calls: Array[String] = []
	func initialize(_test_devices: bool) -> void:
		calls.append("initialize")
		if auto_init:
			ad_event.emit("initialized", "")
	func isInitialized() -> bool: return true
	func canRequestAds() -> bool: return can_request_ads_value
	func isPrivacyOptionsRequired() -> bool: return privacy_options_required_value
	func showPrivacyOptionsForm() -> void:
		calls.append("showPrivacyOptionsForm")
		ad_event.emit("privacy_options_dismissed", "")
	func loadRewarded(_id: String) -> void: calls.append("loadRewarded")
	func isRewardedReady() -> bool: return rewarded_ready
	func showRewarded() -> bool:
		calls.append("showRewarded")
		return rewarded_ready
	func loadInterstitial(_id: String) -> void: calls.append("loadInterstitial")
	func isInterstitialReady() -> bool: return interstitial_ready
	func showInterstitial() -> bool:
		calls.append("showInterstitial")
		return interstitial_ready

func test_native_glue_present_but_uninitialised_blocks_show() -> void:
	var stub := _NativeStub.new()
	stub.auto_init = false          # MobileAds.initialize never completes
	Ads.debug_install_native_stub(stub)
	check("plugin present but not initialised -> can_show_rewarded false", not Ads.can_show_rewarded())
	var res := {"earned": -1, "cb": 0}
	Ads.rewarded_result.connect(func(_p, e): res["earned"] = 1 if e else 0)
	Ads.show_rewarded("continue_moves", func(): res["cb"] += 1)
	check_eq("uninitialised -> earned=false", res["earned"], 0)
	check_eq("uninitialised -> no reward", res["cb"], 0)
	check("uninitialised -> not stuck in flight", not Ads.is_rewarded_in_flight())
	check("uninitialised -> interstitial also blocked",
		not Ads.maybe_show_interstitial("t", {"levels_cleared": 99}))
	Ads.debug_disable_fake_backend()

func test_native_rewarded_preloaded_shows_and_grants_once() -> void:
	var stub := _NativeStub.new()
	stub.rewarded_ready = true
	Ads.debug_install_native_stub(stub)
	var res := {"earned": -1, "cb": 0}
	Ads.rewarded_result.connect(func(_p, e): res["earned"] = 1 if e else 0)
	Ads.show_rewarded("continue_moves", func(): res["cb"] += 1)
	check("showRewarded called on the native stub", stub.calls.has("showRewarded"))
	# native reports the reward, then the dismiss
	Ads.debug_feed_native_event("rewarded_earned", "coins:5")
	Ads.debug_feed_native_event("rewarded_dismissed")
	# a stray duplicate earn afterwards must not re-grant
	Ads.debug_feed_native_event("rewarded_earned", "coins:5")
	check_eq("reward callback fired exactly once", res["cb"], 1)
	check_eq("terminal result earned=true", res["earned"], 1)
	check("not stuck in flight", not Ads.is_rewarded_in_flight())
	Ads.debug_disable_fake_backend()

func test_native_rewarded_not_preloaded_loads_then_shows() -> void:
	var stub := _NativeStub.new()
	stub.rewarded_ready = false          # nothing preloaded
	Ads.debug_install_native_stub(stub)
	Ads.show_rewarded("free_booster")
	check("loadRewarded requested when not ready", stub.calls.has("loadRewarded"))
	check("show deferred until load", not stub.calls.has("showRewarded"))
	stub.rewarded_ready = true
	Ads.debug_feed_native_event("rewarded_loaded")
	check("showRewarded called after rewarded_loaded", stub.calls.has("showRewarded"))
	Ads.debug_feed_native_event("rewarded_earned", "coins:1")
	Ads.debug_feed_native_event("rewarded_dismissed")
	check("cleared after the flow", not Ads.is_rewarded_in_flight())
	Ads.debug_disable_fake_backend()

func test_native_rewarded_load_failure_is_failure_safe() -> void:
	var stub := _NativeStub.new()
	Ads.debug_install_native_stub(stub)
	var res := {"earned": -1, "cb": 0}
	Ads.rewarded_result.connect(func(_p, e): res["earned"] = 1 if e else 0)
	Ads.show_rewarded("double_win_coins", func(): res["cb"] += 1)
	Ads.debug_feed_native_event("rewarded_load_failed", "no_fill")
	check_eq("load-failed -> earned=false", res["earned"], 0)
	check_eq("load-failed -> no reward callback", res["cb"], 0)
	check("not stuck in flight after native load failure", not Ads.is_rewarded_in_flight())
	Ads.debug_disable_fake_backend()

func test_native_interstitial_uses_preloaded_ad() -> void:
	var stub := _NativeStub.new()
	stub.interstitial_ready = true
	Ads.debug_install_native_stub(stub)
	Ads.debug_reset_session()
	var shown: bool = Ads.maybe_show_interstitial("t", {"levels_cleared": 20})
	check("interstitial reported shown", shown)
	check("showInterstitial called on the native stub", stub.calls.has("showInterstitial"))
	Ads.debug_disable_fake_backend()

# ---- UMP consent (EEA/UK/Switzerland) --------------------------------
# `initialize()` on the real plugin now runs the UMP flow before ever
# calling MobileAds.initialize(); here that's simulated entirely by feeding
# synthetic `ad_event`s (never a live consent UI or network — see
# `_NativeStub` above), exactly like the native-glue tests above it.

func test_consent_not_required_allows_ads() -> void:
	var stub := _NativeStub.new()
	stub.auto_init = false          # full control over the event sequence
	Ads.debug_install_native_stub(stub)
	check("ads not allowed before consent settles", not Ads.can_request_ads())
	Ads.debug_feed_native_event("consent_info_updated", "NOT_REQUIRED")
	check_eq("consent status reflects NOT_REQUIRED", Ads.consent_status(), "not_required")
	Ads.debug_feed_native_event("consent_form_dismissed", "")
	check("no loadRewarded before ads are allowed",
		not stub.calls.has("loadRewarded") and not stub.calls.has("loadInterstitial"))
	Ads.debug_feed_native_event("initialized", "")
	check("ads allowed once initialized fires", Ads.can_request_ads())
	check("no privacy options entry point needed", not Ads.privacy_options_required())
	Ads.debug_disable_fake_backend()

func test_consent_required_then_granted_allows_ads() -> void:
	var stub := _NativeStub.new()
	stub.auto_init = false
	stub.privacy_options_required_value = true
	Ads.debug_install_native_stub(stub)
	Ads.debug_feed_native_event("consent_info_updated", "REQUIRED")
	check_eq("consent status reflects REQUIRED", Ads.consent_status(), "required")
	check("ads not yet allowed while consent is pending", not Ads.can_request_ads())
	check("nothing preloaded while consent is pending",
		not stub.calls.has("loadRewarded") and not stub.calls.has("loadInterstitial"))
	Ads.debug_feed_native_event("consent_form_dismissed", "")   # user completed the form
	Ads.debug_feed_native_event("initialized", "")              # canRequestAds() was true
	check("ads allowed once consent is granted", Ads.can_request_ads())
	check_eq("consent status still queryable", Ads.consent_status(), "required")
	check("privacy-options entry point available for a REQUIRED-region user",
		Ads.privacy_options_required())
	Ads.debug_disable_fake_backend()

func test_consent_required_but_denied_blocks_ads() -> void:
	var stub := _NativeStub.new()
	stub.auto_init = false
	Ads.debug_install_native_stub(stub)
	Ads.debug_feed_native_event("consent_info_updated", "REQUIRED")
	Ads.debug_feed_native_event("consent_form_dismissed", "")
	# consent flow completed but doesn't permit ad requests (denied/restricted)
	Ads.debug_feed_native_event("ads_blocked", "consent_not_obtained")
	check("can_request_ads false when consent denies ad requests", not Ads.can_request_ads())
	check("can_show_rewarded false while blocked", not Ads.can_show_rewarded())
	check("interstitial also blocked while consent denies ads",
		not Ads.maybe_show_interstitial("t", {"levels_cleared": 99}))
	check("no ad was ever loaded while blocked",
		not stub.calls.has("loadRewarded") and not stub.calls.has("loadInterstitial"))
	Ads.debug_disable_fake_backend()

func test_can_request_ads_gates_rewarded_show() -> void:
	var stub := _NativeStub.new()
	stub.auto_init = false
	Ads.debug_install_native_stub(stub)
	check("cannot show rewarded before consent settles", not Ads.can_show_rewarded())
	var res := {"earned": -1}
	Ads.rewarded_result.connect(func(_p, e): res["earned"] = 1 if e else 0)
	Ads.show_rewarded("continue_moves")
	check_eq("blocked by pending consent -> terminal result earned=false", res["earned"], 0)
	check("not left in-flight", not Ads.is_rewarded_in_flight())
	Ads.debug_disable_fake_backend()

func test_privacy_options_availability_and_entry_point() -> void:
	var stub := _NativeStub.new()
	stub.auto_init = false
	Ads.debug_install_native_stub(stub)
	stub.privacy_options_required_value = false
	Ads.debug_feed_native_event("consent_info_updated", "NOT_REQUIRED")
	Ads.debug_feed_native_event("consent_form_dismissed", "")
	check("privacy options not required for a NOT_REQUIRED consent status",
		not Ads.privacy_options_required())
	stub.privacy_options_required_value = true
	Ads.debug_feed_native_event("consent_info_updated", "OBTAINED")
	Ads.debug_feed_native_event("consent_form_dismissed", "")
	check("privacy options required once a REQUIRED-region choice is on record",
		Ads.privacy_options_required())
	Ads.show_privacy_options()
	check("show_privacy_options() reaches the native privacy-options form",
		stub.calls.has("showPrivacyOptionsForm"))
	Ads.debug_disable_fake_backend()

func test_show_privacy_options_safe_without_backend() -> void:
	Ads.debug_disable_fake_backend()
	Ads.show_privacy_options()   # must not error with no plugin present
	check("privacy options not required with no backend", not Ads.privacy_options_required())
	check("can_request_ads false with no backend", not Ads.can_request_ads())

func test_privacy_options_withdrawal_blocks_ads_again() -> void:
	var stub := _NativeStub.new()
	stub.auto_init = false
	Ads.debug_install_native_stub(stub)
	Ads.debug_feed_native_event("consent_info_updated", "OBTAINED")
	Ads.debug_feed_native_event("consent_form_dismissed", "")
	Ads.debug_feed_native_event("initialized", "")
	check("ads allowed after initial consent", Ads.can_request_ads())
	# user reopens privacy options (e.g. from Settings) and withdraws consent
	Ads.debug_feed_native_event("privacy_options_dismissed", "")
	Ads.debug_feed_native_event("ads_blocked", "consent_withdrawn")
	check("ads blocked again after withdrawal", not Ads.can_request_ads())
	check("rewarded now blocked too", not Ads.can_show_rewarded())
	Ads.debug_disable_fake_backend()

## Existing rewarded/interstitial behaviour must survive unchanged once it
## runs behind the new consent gate — same reward-once / gating guarantees
## as the pre-consent tests above, just reached through the consent flow.
func test_full_consent_then_rewarded_and_interstitial_flow_unchanged() -> void:
	var stub := _NativeStub.new()
	stub.auto_init = false
	stub.rewarded_ready = true
	Ads.debug_install_native_stub(stub)
	Ads.debug_feed_native_event("consent_info_updated", "NOT_REQUIRED")
	Ads.debug_feed_native_event("consent_form_dismissed", "")
	Ads.debug_feed_native_event("initialized", "")
	Ads.debug_reset_session()

	var res := {"earned": -1, "cb": 0}
	Ads.rewarded_result.connect(func(_p, e): res["earned"] = 1 if e else 0)
	Ads.show_rewarded("continue_moves", func(): res["cb"] += 1)
	check("showRewarded called through the normal (post-consent) path",
		stub.calls.has("showRewarded"))
	Ads.debug_feed_native_event("rewarded_earned", "coins:5")
	Ads.debug_feed_native_event("rewarded_dismissed")
	check_eq("reward still granted exactly once", res["cb"], 1)
	check_eq("terminal result earned=true", res["earned"], 1)

	Ads.debug_reset_session()   # else the back-to-back guard blocks the interstitial below
	stub.interstitial_ready = true
	check("interstitial still shows through the normal (post-consent) path",
		Ads.maybe_show_interstitial("t", {"levels_cleared": 20}))
	check("showInterstitial called on the native stub", stub.calls.has("showInterstitial"))
	Ads.debug_disable_fake_backend()

func test_service_left_in_clean_headless_state() -> void:
	Ads.debug_disable_fake_backend()
	check("ads unavailable after tests", not Ads.available)
	check("nothing in flight", not Ads.is_rewarded_in_flight())
	check("consent state reset", not Ads.can_request_ads() and not Ads.privacy_options_required())
