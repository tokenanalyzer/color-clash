extends Node
## Autoload "Ads" — centralized AdMob monetization for War of Love.
##
## Backend-agnostic. When a native AdMob plugin singleton is present (a real
## Android build with the plugin installed) this drives it; otherwise it
## runs in UNAVAILABLE mode where every request fails gracefully and the
## game proceeds with its normal, non-ad behaviour. The game is always
## fully playable with no ads.
##
## ALL policy lives here and is headless-testable:
##   * rewarded reward is granted ONLY on the "user earned reward" callback,
##     exactly once (double-reward guard);
##   * a failed / unavailable / dismissed-without-reward ad grants nothing;
##   * interstitials only at explicit transition points, never mid-gameplay,
##     never in the first few seconds of a session, never before the player
##     has cleared `min_levels_cleared` levels (covers first launch + the
##     tutorial), with a cooldown, a per-session cap, and a guard that never
##     shows two ads back-to-back.
##
## Config: data/ads.json. Test ad unit ids are Google's OFFICIAL test ids
## (safe to ship in a debug/internal build); production ids are empty
## placeholders to be filled from the AdMob console. Ad unit ids are not
## secrets. See docs/MONETIZATION.md.
##
## UMP consent (EEA/UK/Switzerland): the native plugin runs Google's User
## Messaging Platform flow on every `initialize()` call (i.e. every launch)
## BEFORE ever calling MobileAds.initialize — see
## `game/android_plugin/admob/src/.../ColorClashAdMob.kt`. `_native_initialized`
## (and therefore every ad request) only ever becomes true once UMP allows it;
## no separate gating is needed here. `can_request_ads()` / `consent_status()`
## / `privacy_options_required()` / `show_privacy_options()` expose that state
## for UI. See docs/MONETIZATION.md's "Consent (UMP)" section.

signal rewarded_completed(placement: String)              ## reward EARNED (fires at the earn moment)
signal rewarded_closed(placement: String, earned: bool)   ## a shown ad finished (earned or not)
signal rewarded_failed(placement: String, reason: String) ## ad never showed
## The ONE terminal signal callers should use for control flow: fires
## EXACTLY ONCE per show_rewarded(), with earned=true only when the reward
## was actually granted. Connect it CONNECT_ONE_SHOT.
signal rewarded_result(placement: String, earned: bool)
signal interstitial_shown(placement: String)
signal interstitial_skipped(placement: String, reason: String)
## UMP consent (EEA/UK/Switzerland) outcome changed — `can_request_ads()` /
## `privacy_options_required()` have fresh values. Optional to listen to;
## nothing currently needs it, ad gating already reads the state directly.
signal consent_updated()

## Native plugin singletons we know how to talk to, in priority order.
const _CANDIDATE_SINGLETONS: Array[String] = [
	"AdMob", "PoingGodotAdMob", "GodotAdMob", "AdMobPlugin",
]
const _MIN_SESSION_AGE_MS := 30_000     ## no interstitial in the first 30 s of a session

var available := false                  ## a usable ad backend is present
var config: Dictionary = {}
var _test := true
var _plugin: Object = null

# --- UMP consent (EEA/UK/Switzerland) ---
## "unknown" | "not_required" | "required" | "obtained" — the UMP
## ConsentStatus as of the last `consent_info_updated` event. Informational;
## `can_request_ads()` is the one value gating actually reads.
var _consent_status := "unknown"
## Mirrors native `ConsentInformation.canRequestAds()`. Ad requests
## (`_preload_rewarded` / `_preload_interstitial`) never happen before this
## is true — `_native_initialized` itself only ever flips true once the
## native side has confirmed it, see `_on_native_ad_event("initialized")`.
var _ads_allowed := false
var _privacy_options_required := false

# --- session / frequency state (in-memory, per run) ---
var _session_start_ms := 0
var _interstitials_this_session := 0
var _last_interstitial_ms := -10_000_000
var _last_any_ad_ms := -10_000_000

# --- rewarded reward-once guard ---
var _rewarded_in_flight := false
var _rewarded_placement := ""
var _rewarded_earned := false
var _rewarded_cb: Callable = Callable()

# --- test hooks (only used by tests / never by shipping code) ---
var _debug_backend := false             ## true = a fake backend simulated by tests

func _ready() -> void:
	_session_start_ms = Time.get_ticks_msec()
	config = JsonLoader.load_json("res://data/ads.json")
	if config.is_empty():
		config = _default_config()
	# `use_test_ads=false` (the shipped release config) only ever takes effect
	# on a non-debug export. Any debug build — including running the editor
	# and a debug APK export used for on-device testing — forces test ads
	# regardless of the config value, so production ids can never show up
	# outside a real release build.
	_test = bool(config.get("use_test_ads", true)) or OS.is_debug_build()
	_detect_plugin()
	if _plugin != null:
		available = true
		_wire_plugin()
		_dbg("native AdMob backend detected (%s), test_ads=%s" % [_plugin.get_class(), _test])
	else:
		_dbg("no native AdMob backend — ads UNAVAILABLE, game runs ad-free")

# =====================================================================
#  REWARDED
# =====================================================================

## Show a rewarded ad for `placement`. `on_reward` (optional) is invoked
## EXACTLY ONCE, and only if the user actually earns the reward. On any
## other outcome `rewarded_failed` fires and `on_reward` is never called —
## the caller must keep its normal non-ad path working.
func show_rewarded(placement: String, on_reward: Callable = Callable()) -> void:
	if _rewarded_in_flight:
		rewarded_failed.emit(placement, "busy")
		rewarded_result.emit(placement, false)
		return
	if not can_show_rewarded():
		# no backend / offline — fail immediately; the caller connected its
		# result handler before calling us and keeps its normal non-ad path.
		rewarded_failed.emit(placement, "unavailable")
		rewarded_result.emit(placement, false)
		return
	_rewarded_in_flight = true
	_rewarded_placement = placement
	_rewarded_earned = false
	_rewarded_cb = on_reward
	_last_any_ad_ms = Time.get_ticks_msec()
	if _debug_backend:
		return   # a test will call debug_finish_rewarded(...)
	_plugin_show_rewarded()

func can_show_rewarded() -> bool:
	return available and not _rewarded_in_flight and (_debug_backend or _native_initialized)

func is_rewarded_in_flight() -> bool:
	return _rewarded_in_flight

## Native callback: the user earned the reward. Grants once.
func _on_native_rewarded_earned(_data = null) -> void:
	if not _rewarded_in_flight or _rewarded_earned:
		return
	_rewarded_earned = true
	rewarded_completed.emit(_rewarded_placement)
	if _rewarded_cb.is_valid():
		_rewarded_cb.call()

## Native callback: the rewarded ad closed (earned or not).
func _on_native_rewarded_closed(_data = null) -> void:
	if not _rewarded_in_flight:
		return
	var placement := _rewarded_placement
	var earned := _rewarded_earned
	_clear_rewarded()
	rewarded_closed.emit(placement, earned)
	rewarded_result.emit(placement, earned)

## Native callback: the rewarded ad failed to load or show.
func _on_native_rewarded_failed(reason = "load_failed") -> void:
	if not _rewarded_in_flight:
		return
	var placement := _rewarded_placement
	var was_earned := _rewarded_earned
	_clear_rewarded()
	if was_earned:
		rewarded_closed.emit(placement, true)
		rewarded_result.emit(placement, true)
	else:
		rewarded_failed.emit(placement, str(reason))
		rewarded_result.emit(placement, false)

func _clear_rewarded() -> void:
	_rewarded_in_flight = false
	_rewarded_placement = ""
	_rewarded_earned = false
	_rewarded_cb = Callable()

# =====================================================================
#  INTERSTITIAL
# =====================================================================

## Try to show an interstitial at a transition point. Returns true only if
## one was actually shown. Never shows during gameplay (callers must only
## call this between screens). Self-gates on every frequency rule.
func maybe_show_interstitial(placement: String, context: Dictionary = {}) -> bool:
	var reason := _interstitial_block_reason(context)
	if reason != "":
		interstitial_skipped.emit(placement, reason)
		_dbg("interstitial skipped @ %s: %s" % [placement, reason])
		return false
	var now := Time.get_ticks_msec()
	_last_interstitial_ms = now
	_last_any_ad_ms = now
	_interstitials_this_session += 1
	interstitial_shown.emit(placement)
	if not _debug_backend:
		_plugin_show_interstitial()
	_dbg("interstitial shown @ %s (#%d this session)" % [placement, _interstitials_this_session])
	return true

## "" = clear to show; otherwise the reason it is blocked.
func _interstitial_block_reason(context: Dictionary) -> String:
	if not available:
		return "unavailable"
	if not (_debug_backend or _native_initialized):
		return "not_initialized"
	if _rewarded_in_flight:
		return "rewarded_in_flight"
	var i: Dictionary = config.get("interstitial", {})
	var now := Time.get_ticks_msec()
	if now - _session_start_ms < _MIN_SESSION_AGE_MS:
		return "session_too_young"
	var cleared: int = int(context.get("levels_cleared", _total_levels_cleared()))
	if cleared < int(i.get("min_levels_cleared", 4)):
		return "tutorial_guard"
	if now - _last_any_ad_ms < int(config.get("back_to_back_guard_seconds", 20)) * 1000:
		return "back_to_back"
	if now - _last_interstitial_ms < int(i.get("cooldown_seconds", 150)) * 1000:
		return "cooldown"
	if _interstitials_this_session >= int(i.get("max_per_session", 4)):
		return "session_cap"
	return ""

## Total world-local levels cleared, read straight from the save dict so
## this service stays decoupled from IslandProgress.
func _total_levels_cleared() -> int:
	var n := 0
	var ip = SaveService.get_value("island_progress", {})
	if typeof(ip) == TYPE_DICTIONARY:
		for wid in ip:
			var w = ip[wid]
			if typeof(w) == TYPE_DICTIONARY and typeof(w.get("levels", null)) == TYPE_DICTIONARY:
				n += (w["levels"] as Dictionary).size()
	return n

# =====================================================================
#  BANNER (capability only — see docs/MONETIZATION.md: no safe placement in
#  the full-bleed artwork UI, so nothing calls these yet)
# =====================================================================

func show_banner() -> void:
	if available and not _debug_backend:
		_plugin_show_banner()

func hide_banner() -> void:
	if available and not _debug_backend:
		_plugin_hide_banner()

# =====================================================================
#  reward amounts (data-driven)
# =====================================================================

func reward_continue_moves() -> int:
	return int(config.get("rewards", {}).get("continue_moves", 5))

func reward_free_coins() -> int:
	return int(config.get("rewards", {}).get("free_coins", 120))

func reward_free_booster() -> Dictionary:
	var b = config.get("rewards", {}).get("free_booster", {"id": "bomb", "amount": 1})
	return {"id": StringName(String(b.get("id", "bomb"))), "amount": int(b.get("amount", 1))}

func double_win_coins_enabled() -> bool:
	return bool(config.get("rewards", {}).get("double_win_coins", true))

func unit_id(kind: String) -> String:
	var u: Dictionary = config.get("unit_ids", {}).get(kind, {})
	return String(u.get("test" if _test else "prod", ""))

func using_test_ads() -> bool:
	return _test

# =====================================================================
#  UMP consent (EEA / UK / Switzerland)
# =====================================================================

## Whether ad requests are currently allowed by UMP consent state. False
## until the consent flow (requested fresh on every launch, see `_ready()`)
## has settled AND allows it. When there's no native backend at all this
## stays false too — moot, since `available` is already false and every
## public entry point (`can_show_rewarded()`, `maybe_show_interstitial()`)
## already gates on that.
func can_request_ads() -> bool:
	return _ads_allowed

## "unknown" | "not_required" | "required" | "obtained" (UMP ConsentStatus,
## lowercased). Informational — nothing gates on this directly.
func consent_status() -> String:
	return _consent_status

## True when the player must be given a way to revisit their consent choice
## (an EEA/UK/CH user who has made one). A Settings-style screen should only
## show its "Privacy Choices" entry when this is true.
func privacy_options_required() -> bool:
	return _privacy_options_required

## Shows Google's privacy-options form so the player can change or withdraw
## their consent choice. No-ops with no native backend (desktop/headless) —
## call sites don't need to guard on `available` themselves.
func show_privacy_options() -> void:
	if _plugin != null and not _debug_backend:
		_plugin.call("showPrivacyOptionsForm")

# =====================================================================
#  native plugin glue  (thin — the plugin API surface lives here only)
# =====================================================================

## The native side (game/android/build/src/com/colorclash/admob/ColorClashAdMob.kt)
## exposes ONE generic signal — ad_event(event, message) — plus load/show
## methods. This block is the ONLY place that talks to it; everything above
## (policy, reward-once guard, interstitial gating, the public API) is
## backend-independent.
const _NATIVE_SINGLETON := "ColorClashAdMob"
const _LOAD_TIMEOUT_MS := 12_000     ## give up waiting for a rewarded load after this

var _native_initialized := false
var _rewarded_wants_show := false    ## a show_rewarded() is waiting on a load
var _rewarded_load_deadline_ms := 0
var _signal_wired := false           ## ad_event connected (JNISingleton has_signal() is unreliable)

func _detect_plugin() -> void:
	if _debug_backend:
		return
	if Engine.has_singleton(_NATIVE_SINGLETON):
		_plugin = Engine.get_singleton(_NATIVE_SINGLETON)
		return
	for name in _CANDIDATE_SINGLETONS:      # tolerate an alternative plugin name
		if Engine.has_singleton(name):
			_plugin = Engine.get_singleton(name)
			return

func _wire_plugin() -> void:
	if _plugin == null:
		return
	# GodotPlugin / JNISingleton singletons do NOT reliably answer
	# has_signal() / has_method(), so connect the signal and call initialize()
	# directly. The GDScript test stub (a RefCounted with a real `ad_event`
	# signal and the same methods) works exactly the same way.
	if not _signal_wired:
		_plugin.connect("ad_event", _on_native_ad_event)
		_signal_wired = true
	_plugin.call("initialize", OS.is_debug_build() or _test)
	set_process(true)   # drives the rewarded load-timeout watchdog

func _refresh_privacy_options_required() -> void:
	var was := _privacy_options_required
	_privacy_options_required = _plugin != null and not _debug_backend \
		and bool(_plugin.call("isPrivacyOptionsRequired"))
	if _privacy_options_required != was:
		consent_updated.emit()

## Single dispatcher for every native lifecycle event.
func _on_native_ad_event(event: String, message: String) -> void:
	_dbg("native ad_event: %s %s" % [event, message])
	match event:
		"consent_info_updated":
			_consent_status = message.to_lower()
			_refresh_privacy_options_required()
		"consent_info_update_failed", "consent_form_error":
			pass   # non-fatal — the definitive outcome is "initialized" or "ads_blocked"
		"consent_form_dismissed":
			_refresh_privacy_options_required()
		"ads_blocked":
			# UMP says ad requests are not (or no longer) allowed — matches
			# "init_failed"'s effect: no preload, every ad request fails safe.
			_native_initialized = false
			_ads_allowed = false
			consent_updated.emit()
		"privacy_options_dismissed":
			_refresh_privacy_options_required()
		"privacy_options_error":
			pass
		"initialized":
			_native_initialized = true
			_ads_allowed = true
			_refresh_privacy_options_required()
			consent_updated.emit()
			_preload_rewarded()
			_preload_interstitial()
		"init_failed":
			_native_initialized = false
			_ads_allowed = false
		"rewarded_loaded":
			if _rewarded_wants_show and _rewarded_in_flight:
				_rewarded_wants_show = false
				if not _plugin.call("showRewarded"):
					_on_native_rewarded_failed("show_returned_false")
		"rewarded_load_failed":
			if _rewarded_wants_show:
				_rewarded_wants_show = false
				_on_native_rewarded_failed("load_failed: " + message)
			_preload_rewarded()   # try to have one ready next time
		"rewarded_earned":
			_on_native_rewarded_earned(message)
		"rewarded_dismissed":
			_on_native_rewarded_closed()
			_preload_rewarded()
		"rewarded_show_failed":
			_on_native_rewarded_failed("show_failed: " + message)
			_preload_rewarded()
		"interstitial_loaded", "interstitial_shown":
			pass
		"interstitial_dismissed", "interstitial_show_failed", "interstitial_load_failed":
			_preload_interstitial()

func _process(_delta: float) -> void:
	# watchdog: a rewarded show that never got a load/fail event must not
	# leave the caller hanging — time it out into a normal failure.
	if _rewarded_in_flight and _rewarded_wants_show \
			and Time.get_ticks_msec() > _rewarded_load_deadline_ms:
		_rewarded_wants_show = false
		_on_native_rewarded_failed("load_timeout")

func _preload_rewarded() -> void:
	if _plugin == null or not _native_initialized:
		return
	if not bool(_plugin.call("isRewardedReady")):
		_plugin.call("loadRewarded", unit_id("rewarded"))

func _preload_interstitial() -> void:
	if _plugin == null or not _native_initialized:
		return
	if not bool(_plugin.call("isInterstitialReady")):
		_plugin.call("loadInterstitial", unit_id("interstitial"))

func _plugin_show_rewarded() -> void:
	if _plugin == null:
		_on_native_rewarded_failed("no_plugin"); return
	if bool(_plugin.call("isRewardedReady")):
		if not _plugin.call("showRewarded"):
			_on_native_rewarded_failed("show_returned_false")
		return
	# not preloaded — load now and show on the "rewarded_loaded" event
	_rewarded_wants_show = true
	_rewarded_load_deadline_ms = Time.get_ticks_msec() + _LOAD_TIMEOUT_MS
	_plugin.call("loadRewarded", unit_id("rewarded"))

func _plugin_show_interstitial() -> void:
	if _plugin == null:
		return
	if bool(_plugin.call("isInterstitialReady")):
		_plugin.call("showInterstitial")
	else:
		_plugin.call("loadInterstitial", unit_id("interstitial"))   # ready next time

func _plugin_show_banner() -> void:
	pass   # no banner placement (see docs/MONETIZATION.md); native side has none

func _plugin_hide_banner() -> void:
	pass

# =====================================================================
#  test hooks
# =====================================================================

## Make the service behave as if a backend is present, WITHOUT a plugin —
## a test then drives outcomes with debug_finish_rewarded / the simulated
## interstitial path. No shipping code calls this.
func debug_enable_fake_backend(now_available: bool = true) -> void:
	_debug_backend = true
	available = now_available
	_native_initialized = now_available
	_ads_allowed = now_available
	_plugin = null

## Restore the real (no-plugin) headless state after a test.
func debug_disable_fake_backend() -> void:
	_debug_backend = false
	_plugin = null
	available = false
	_native_initialized = false
	_ads_allowed = false
	_consent_status = "unknown"
	_privacy_options_required = false
	_rewarded_wants_show = false
	_signal_wired = false
	_clear_rewarded()

## Simulate the end of an in-flight rewarded ad: "earned" | "closed" | "failed".
func debug_finish_rewarded(outcome: String, reason: String = "load_failed") -> void:
	match outcome:
		"earned":
			_on_native_rewarded_earned()
			_on_native_rewarded_closed()
		"closed":
			_on_native_rewarded_closed()
		"failed":
			_on_native_rewarded_failed(reason)

## Test hook: install a GDScript stand-in for the native plugin so the
## load -> show -> ad_event glue can be exercised headlessly. The stub must
## expose isRewardedReady/showRewarded/loadRewarded/isInterstitialReady/
## showInterstitial/loadInterstitial/initialize and an `ad_event` signal.
func debug_install_native_stub(stub: Object) -> void:
	_debug_backend = false
	_native_initialized = false
	_ads_allowed = false
	_consent_status = "unknown"
	_privacy_options_required = false
	_rewarded_wants_show = false
	_signal_wired = false
	_clear_rewarded()
	_plugin = stub
	available = stub != null
	if stub != null:
		_wire_plugin()

func debug_feed_native_event(event: String, message: String = "") -> void:
	_on_native_ad_event(event, message)

func debug_reset_session() -> void:
	_session_start_ms = Time.get_ticks_msec() - _MIN_SESSION_AGE_MS - 1
	_interstitials_this_session = 0
	_last_interstitial_ms = -10_000_000
	_last_any_ad_ms = -10_000_000
	_clear_rewarded()

# =====================================================================

func _default_config() -> Dictionary:
	return {
		"use_test_ads": true,
		"unit_ids": {},
		"interstitial": {"cooldown_seconds": 150, "max_per_session": 4, "min_levels_cleared": 4},
		"back_to_back_guard_seconds": 20,
		"rewards": {"continue_moves": 5, "double_win_coins": true, "free_coins": 120,
			"free_booster": {"id": "bomb", "amount": 1}},
	}

func _dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[Ads] %s" % msg)
