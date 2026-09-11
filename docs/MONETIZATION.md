# War of Love — Monetization (AdMob)

Centralized in **`scripts/services/ads_service.gd`** (autoload **`Ads`**),
config in **`data/ads.json`**. The game is **fully playable with no ads** —
every placement degrades to its normal non-ad behaviour when ads are
unavailable / offline / not yet integrated.

## Backend model

`AdsService` is backend-agnostic. On `_ready()` it looks for the native
plugin singleton **`ColorClashAdMob`** (then, as a fallback, `AdMob`,
`PoingGodotAdMob`, …). If found → `available = true`, it calls
`initialize()` and drives the plugin. `initialize()` now runs the **UMP
consent flow** (see "Consent (UMP)" below) before ever requesting an ad —
`initialized` only ever fires, and `can_show_rewarded()` only ever becomes
`true`, once consent allows it. If no plugin is found (desktop, headless,
an iOS/other build, or the plugin failed to load) → `available = false`,
every `show_rewarded` fails gracefully, `maybe_show_interstitial` no-ops,
banners no-op. Until the plugin reports `initialized`, `can_show_rewarded()`
is `false` and interstitials are blocked (`not_initialized`).

### Native plugin — `ColorClashAdMob`

A minimal in-tree Godot 4 Android plugin (Kotlin `GodotPlugin`) that wraps
the **Google Mobile Ads SDK**
(`com.google.android.gms:play-services-ads:23.6.0`) and **Google's User
Messaging Platform (UMP) SDK**
(`com.google.android.ump:user-messaging-platform:4.0.0`). It only **loads /
shows** a rewarded ad and an interstitial ad, drives the UMP consent flow,
and reports every lifecycle step back over one generic signal,
`ad_event(event, message)`. **No policy lives in the plugin** — reward-once
guarding, frequency caps, cooldowns, failure-safe fallback, and what a
consent outcome means for gameplay are all in `ads_service.gd`.

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

**Production wiring (done, 2026-09-11):** `data/ads.json` now carries the
real `prod` unit ids and `use_test_ads=false`. `AdsService._ready()` still
forces test ads on any `OS.is_debug_build()` build regardless of that flag
(editor runs, `--headless` tests, and debug APK exports all stay on
Google's test ids) — **only a real release export ever serves production
ads.** The AdMob App ID is still supplied at export time via `ADMOB_APP_ID`
(see below); it is not read from `ads.json`.

## Consent (UMP) — EEA / UK / Switzerland

**Done, 2026-09-11.** Google requires an IAB-TCF consent flow (via its User
Messaging Platform SDK) for users in the EEA, UK, and Switzerland before any
ad request; `ColorClashAdMob.initialize()` runs it on every launch, ahead of
`MobileAds.initialize()`, following
[Google's official UMP Android quick-start](https://developers.google.com/admob/ump/android/quick-start):

1. `UserMessagingPlatform.getConsentInformation(ctx).requestConsentInfoUpdate(...)`
   — fetches the current consent requirement for this user/region. Runs on
   **every app launch** (once per process, from `AdsService._ready()` →
   `initialize()`), as Google's docs require.
2. `UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity)` —
   shows Google's consent form **only if the SDK determines it's required**
   (EEA/UK/CH and no valid choice on record yet); a silent no-op everywhere
   else (most players, including the dev team's own India-based test
   device, never see a form).
3. `MobileAds.initialize()` is only ever called once
   `ConsentInformation.canRequestAds()` is `true` — both right after step 1
   (a previous session's cached consent may already allow it, so the player
   isn't made to wait on the network round trip) and again after step 2
   settles. Guarded so it only actually runs once
   (`mobileAdsInitializeCalled`).

**Event vocabulary** (all still over the one `ad_event(event, message)`
signal — the plugin's API surface didn't grow a second signal):
`consent_info_updated` (message = UMP `ConsentStatus`: `UNKNOWN` /
`NOT_REQUIRED` / `REQUIRED` / `OBTAINED`), `consent_info_update_failed`,
`consent_form_error`, `consent_form_dismissed`, `ads_blocked` (message
`consent_not_obtained` | `consent_withdrawn` — consent settled but doesn't
currently permit ad requests), plus the existing `initialized` / `init_failed`
(which now only ever fire post-consent).

**`AdsService` (GDScript) state**, additive — nothing existing changed:
- `can_request_ads() -> bool` — mirrors `canRequestAds()`; ad requests never
  happen while this is false, because `_native_initialized` (the existing
  gate every rewarded/interstitial call already checks) only flips `true`
  in the same event handler that sets this.
- `consent_status() -> String` — `"unknown" | "not_required" | "required" |
  "obtained"`, informational.
- `privacy_options_required() -> bool` — true when the player must be
  offered a way to revisit their choice (an EEA/UK/CH player who has made
  one).
- `show_privacy_options()` — calls the native `showPrivacyOptionsForm()`;
  safe no-op with no backend. Re-checks `canRequestAds()` after the form
  closes and fires `ads_blocked` again if the player withdrew consent —
  gameplay stops requesting new ads immediately, same as any other
  `ads_blocked`.
- `consent_updated` signal — fires when `can_request_ads()` /
  `privacy_options_required()` change; optional to listen to.

**Privacy-options entry point (UI):** `scripts/ui/settings_panel.gd` adds a
"Privacy Choices" row to the existing Settings links section, **only
visible when `Ads.privacy_options_required()` is true** (re-checked every
time the panel opens, since consent can settle after the panel is first
built). Tapping it calls `Ads.show_privacy_options()`. No new screen, no new
art asset — reuses the existing procedural secondary-button style; the
other three link rows (Privacy Policy / Terms / Restore Purchases) are
untouched placeholders.

**Why gameplay code didn't need to change:** the consent gate lives entirely
inside `_native_initialized` (which was already the one thing every
rewarded/interstitial call site checks, indirectly via `can_show_rewarded()`
/ `maybe_show_interstitial()`). Before consent settles, ad requests simply
degrade the same way they always have for "no backend" — the game stays
fully playable with no ads, exactly as designed.

**Manual AdMob dashboard step still required (code alone isn't enough):**
Google's UMP form is **configured in the AdMob console**, not in code — a
publisher must set up a GDPR (and, if desired, UK/US) message under
**AdMob → Privacy & messaging** for this app before
`loadAndShowConsentFormIfRequired` has anything to show. Without a
published message, EEA/UK/CH users hit `consent_form_error` /
`ConsentInformation` staying `REQUIRED` and never resolving — `canRequestAds()`
stays `false` for them forever, so they'd never see an ad (fail-safe, not a
crash, but also not the intended outcome). **This has not been done** — it
needs the AdMob account owner to log into the AdMob console and publish a
message for `ca-app-pub-9900197126922435~4709930379` before worldwide
release.

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

## Test / production ad-unit selection

`data/ads.json` now ships with `use_test_ads: false` and both Google's
**official test ad unit ids** and the **real production ids** side by
side. Which one is actually used is decided in code
(`AdsService._ready()`), not purely by the config flag:

```
_test = bool(config.get("use_test_ads", true)) or OS.is_debug_build()
```

So:
- **Editor runs, `--headless` test/smoke runs, and debug APK exports**
  (`OS.is_debug_build() == true`) **always** use the `test` ids, no matter
  what `use_test_ads` says — dev/testing can never accidentally serve real
  ads or trip production impression counters.
- **A real release export** (`preset.1` "Android Release", AAB,
  `OS.is_debug_build() == false`) uses `config.use_test_ads` as-is —
  currently `false` — so it serves the `prod` ids below.

Ad unit ids are not secrets; no keys or secrets are committed. **Never**
force-test with production ids by flipping `use_test_ads: true` in a debug
build config — it isn't necessary, debug builds already ignore the flag.

| unit | test id | prod id | where it is read |
|---|---|---|---|
| app id | `ca-app-pub-3940256099942544~3347511713` | `ca-app-pub-9900197126922435~4709930379` | `build.gradle` `resValue admob_app_id` (env `ADMOB_APP_ID` overrides); **not** read from `ads.json` at runtime — `ads.json`'s `unit_ids.app_id` is documentation-only |
| rewarded | `ca-app-pub-3940256099942544/5224354917` | `ca-app-pub-9900197126922435/9777941726` | `ads.json` → `unit_ids.rewarded.{test,prod}` |
| interstitial | `ca-app-pub-3940256099942544/1033173712` | `ca-app-pub-9900197126922435/9191618364` | `ads.json` → `unit_ids.interstitial.{test,prod}` |
| banner | `ca-app-pub-3940256099942544/6300978111` | (not created — no banner placement) | unused (no banner placement) |

The native plugin also registers `AdRequest.DEVICE_ID_EMULATOR` as a test
device when `initialize(true)` is called (debug builds), so an emulator
shows test ads even if a `prod` id were ever set.

### Still required for a real release export

| item | how |
|---|---|
| AdMob App ID at export time | `ADMOB_APP_ID=ca-app-pub-9900197126922435~4709930379 godot4 --headless --path game --export-release "Android Release" ...` (see `docs/ANDROID_RELEASE.md`) — the App ID is a build resource, not read from `ads.json` |
| UMP / consent (EEA / UK / Switzerland) | **code done** (see "Consent (UMP)" above) — but the AdMob-console consent message still needs to be published; see that section's last paragraph |
| Data safety section (Play Console) | declare ad-id/advertising data collection via Google Mobile Ads SDK before submitting for review |

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

**Consent tests** (same file, same stub — synthetic `ad_event`s only, never
a live consent UI or network): consent not required allows ads once
`initialized` fires and nothing preloads before then; consent required
blocks ads until granted, then allows them and requires the privacy-options
entry point; consent required-but-denied (`ads_blocked`) blocks rewarded,
interstitial, and every ad load; `can_request_ads()` gates a rewarded show
attempt; privacy-options visibility follows `isPrivacyOptionsRequired()`
and `show_privacy_options()` reaches the native form; safe no-op with no
backend; withdrawing consent via privacy options blocks ads again; a full
consent → rewarded → interstitial run behaves exactly like the
pre-consent-era tests above it.

## Worldwide release — outstanding

- **UMP consent message (AdMob console)** — the code is done (see "Consent
  (UMP)" above), but Google requires the actual GDPR/UK/US message to be
  **configured and published in the AdMob console** (Privacy & messaging)
  before it has anything to show EEA/UK/CH users. **Not done** — needs the
  AdMob account owner.
- **Google Play Data Safety section** — declare `AD_ID` / advertising data
  collection (Google Mobile Ads SDK) in Play Console before submitting.
- **Ads.txt / app-ads.txt** — not applicable (no owned web property serving
  ads for this app; N/A unless a promotional site is added later).
- **Play Console AdMob linking** — link the Play Console app to this AdMob
  app (`ca-app-pub-9900197126922435~4709930379`) once the Play Store
  listing exists, so Play's ad-related warnings/policy checks activate.
- Release signing (`docs/ANDROID_RELEASE.md`) — upload keystore still not
  created; unrelated to ads but also blocks a real release export.
