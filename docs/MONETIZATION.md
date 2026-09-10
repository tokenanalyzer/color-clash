# War of Love — Monetization (AdMob)

Centralized in **`scripts/services/ads_service.gd`** (autoload **`Ads`**),
config in **`data/ads.json`**. The game is **fully playable with no ads** —
every placement degrades to its normal non-ad behaviour when ads are
unavailable / offline / not yet integrated.

## Backend model

`AdsService` is backend-agnostic. On `_ready()` it looks for the native
plugin singleton **`ColorClashAdMob`** (then, as a fallback, `AdMob`,
`PoingGodotAdMob`, …). If found → `available = true`, it calls
`initialize()` and drives the plugin. If not (desktop, headless, an
iOS/other build, or the plugin failed to load) → `available = false`, every
`show_rewarded` fails gracefully, `maybe_show_interstitial` no-ops, banners
no-op. Until the plugin reports `initialized`, `can_show_rewarded()` is
`false` and interstitials are blocked (`not_initialized`).

### Native plugin — `ColorClashAdMob`

A minimal in-tree Godot 4 Android plugin (Kotlin `GodotPlugin`) that wraps
the **Google Mobile Ads SDK**
(`com.google.android.gms:play-services-ads:23.6.0`). It only **loads /
shows** a rewarded ad and an interstitial ad and reports every lifecycle
step back over one generic signal, `ad_event(event, message)`. **No policy
lives in the plugin** — reward-once guarding, frequency caps, cooldowns and
failure-safe fallback are all in `ads_service.gd`.

- **Canonical source + template patches + re-apply script:**
  `game/android_plugin/admob/` (see its `README.md`). The Godot Android
  build template `game/android/` is regenerable and **not** vendored, so
  the plugin's real home is the tracked `android_plugin/admob/` directory;
  `install.sh` re-applies it onto a freshly generated template.
- **Registration:** `AndroidManifest.xml` meta-data
  `org.godotengine.plugin.v1.ColorClashAdMob` →
  `com.colorclash.admob.ColorClashAdMob`.
- **App ID:** `AndroidManifest.xml` meta-data
  `com.google.android.gms.ads.APPLICATION_ID` → `@string/admob_app_id`, a
  `resValue` emitted by `build.gradle` from the `ADMOB_APP_ID` env var,
  defaulting to Google's **test** App ID. Not a secret; no real value
  committed.
- **Build requirement:** a custom `GodotPlugin` compiles only under the
  Gradle build, so `export_presets.cfg` sets
  `gradle_build/use_gradle_build=true` on **both** the debug (`preset.0`)
  and release (`preset.1`) presets.
- **Permissions:** the Ads SDK needs network, so both presets now request
  `INTERNET` and `ACCESS_NETWORK_STATE` (see `docs/PRIVACY_POLICY.md`).
  `arm64-v8a`-only, `target_sdk=35`, package `com.colorclash.game` and the
  release AAB format are unchanged.

### GDScript ⇄ native flow

`show_rewarded()` → if `isRewardedReady()` show immediately, else
`loadRewarded(unit_id)` and show on the `rewarded_loaded` event. A 12 s
watchdog (`_LOAD_TIMEOUT_MS`, driven by `_process`) turns a load that never
returns into a normal `rewarded_failed` so a caller can never hang.
`rewarded_earned` grants once; `rewarded_dismissed` clears the in-flight
flag and preloads the next ad. Interstitial is analogous but fire-and-forget
(no reward). Every native failure event (`*_load_failed`, `*_show_failed`,
`init_failed`) degrades to the normal non-ad path.

**To go to production:** fill the `prod` unit ids in `data/ads.json`, set
`use_test_ads=false`, and export with `ADMOB_APP_ID` set to the real AdMob
App ID.

## Placements (integrated only into flows that already exist)

| # | Type | Where | Trigger | Reward |
|---|---|---|---|---|
| 1 | **Rewarded** | "NEED MORE MOVES?" continue modal (`extra_moves_prompt.gd`) — shown on out-of-moves / after a fail. Button **"▶ WATCH AD  +5 MOVES (FREE)"** above GIVE UP. | player taps it | **+5 moves** to the running board (same resume path as buying moves — level is not restarted) |
| 2 | **Rewarded** | WIN panel (`hud.gd` → `app.gd`) — button **"▶ DOUBLE COINS (+N)"** | player taps it on a win | **+N coins** again (N = that level's `reward_coins`), granted via `Economy.grant` |
| 3 | **Rewarded** | In-level Booster Shop (`booster_shop.gd`) — button **"▶ WATCH AD — FREE BOMB x1"** | player taps it | **1 booster** (`bomb` by default) via `Boosters.add` |
| 4 | **Interstitial** | `app.gd` at level→level / level→map **transitions only** (`_on_next_level_pressed`, `_on_retry_pressed`, `_on_map_pressed`), and only when `_level_ended`. | automatic, self-gated | — |
| — | **Banner** | Capability built (`Ads.show_banner/hide_banner`) but **not placed** — Home / island / level map are full-bleed supplied artwork with no safe non-gameplay strip. Skipped rather than damage the UI. | — | — |

No **"extra life"** placement: the game has **no lives / hearts / energy
system**, and per the brief no new game system was added for it.

## Reward-once / graceful-degrade guarantees

- A rewarded reward is granted **only** when `Ads.rewarded_result` fires
  with `earned == true`. That signal fires **exactly once** per
  `show_rewarded()` — for earned, dismissed-without-reward, load failure,
  and unavailable alike — so callers connect one handler, disconnect it in
  the handler, and cannot double-grant. A `_ad_pending` / in-flight flag
  blocks a second tap.
- Unavailable / offline / failed / dismissed-early → nothing is granted,
  the coin options / normal flow still work, the game continues.

## Interstitial frequency policy (`data/ads.json` → `interstitial`)

| rule | default | key |
|---|---|---|
| never in the first N seconds of a session | 30 s | `_MIN_SESSION_AGE_MS` (code) |
| never before the player has cleared N levels (covers first launch + tutorial) | 4 | `min_levels_cleared` |
| min gap between interstitials | 150 s | `cooldown_seconds` |
| max interstitials per session | 4 | `max_per_session` |
| never two ads back-to-back (rewarded or interstitial) | 20 s | `back_to_back_guard_seconds` |
| only at explicit transitions, never during gameplay | — | call sites gate on `_level_ended` |

## Test-ad configuration

`data/ads.json` ships with `use_test_ads: true` and Google's **official
test ad unit ids** (safe in a debug / internal-testing build). `prod`
fields are empty placeholders. Ad unit ids are not secrets; no keys or
secrets are committed. **Never** run with production ids in testing, and
**never** ship with `use_test_ads: true`.

| unit | test id | where it is read |
|---|---|---|
| app id | `ca-app-pub-3940256099942544~3347511713` | `build.gradle` `resValue admob_app_id` (env `ADMOB_APP_ID` overrides); **not** read from `ads.json` at runtime |
| rewarded | `ca-app-pub-3940256099942544/5224354917` | `ads.json` → `unit_ids.rewarded.test` |
| interstitial | `ca-app-pub-3940256099942544/1033173712` | `ads.json` → `unit_ids.interstitial.test` |
| banner | `ca-app-pub-3940256099942544/6300978111` | unused (no banner placement) |

The native plugin also registers `AdRequest.DEVICE_ID_EMULATOR` as a test
device when `initialize(true)` is called (debug builds), so an emulator
shows test ads even if a `prod` id were ever set.

### Production IDs still to be supplied

| item | how |
|---|---|
| `unit_ids.rewarded.prod` | AdMob console → fill in `data/ads.json` |
| `unit_ids.interstitial.prod` | AdMob console → fill in `data/ads.json` |
| `use_test_ads` | set to `false` in `data/ads.json` for a real release |
| AdMob App ID | export with `ADMOB_APP_ID=ca-app-pub-XXXX~YYYY` |

## Tests

`tests/test_ads_service.gd` (in `test_runner`): ad-free when no backend;
reward granted exactly once and only on "earned"; dismissed / failed /
unavailable grant nothing and don't get stuck in-flight; interstitial
gating (session age, tutorial guard, cooldown, **session cap**, no
back-to-back). Native-plugin glue is exercised headlessly with a GDScript
stand-in (`_NativeStub` + `Ads.debug_install_native_stub` /
`debug_feed_native_event`): plugin present but not yet `initialized` blocks
every show; a preloaded rewarded shows and grants exactly once (a stray
duplicate `rewarded_earned` does not re-grant); a not-preloaded rewarded
loads then shows on `rewarded_loaded`; a native `rewarded_load_failed` is
failure-safe (no reward, not stuck in-flight); a preloaded interstitial is
shown via the native `showInterstitial()`.
