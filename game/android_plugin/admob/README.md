# War of Love — native AdMob plugin (`ColorClashAdMob`)

A minimal in-tree Godot 4 Android plugin that bridges the **Google Mobile
Ads SDK** (`com.google.android.gms:play-services-ads:23.6.0`) to
`scripts/services/ads_service.gd` (autoload **`Ads`**).

The plugin is deliberately *thin*: it only **loads / shows** a rewarded ad
and an interstitial ad and reports every lifecycle step back over one
generic signal, `ad_event(event, message)`. **All** monetization policy —
reward-once guarding, interstitial frequency caps / cooldowns, failure-safe
fallback — lives in GDScript, never in the plugin. See
`docs/MONETIZATION.md`.

## Why this directory exists

The Godot Android build template (`game/android/`) is **regenerable and not
vendored** (`.gitignore` → `/game/android/`). Regenerating it with
`--install-android-build-template` overwrites `AndroidManifest.xml` and
`build.gradle` and knows nothing about our plugin. This directory holds the
**canonical, version-controlled** copy of everything the integration adds,
plus a script to re-apply it.

```
android_plugin/admob/
├── src/com/colorclash/admob/ColorClashAdMob.kt   canonical plugin source
├── patches/AndroidManifest.xml.patch             +2 <meta-data> (App ID + plugin id)
├── patches/build.gradle.patch                    +play-services-ads dep, +admob_app_id resValue
├── install.sh                                    re-apply onto a fresh template (idempotent)
└── README.md
```

## Rebuilding the Android template from scratch

```sh
# 1. regenerate the template (overwrites game/android/)
godot4 --headless --path game --install-android-build-template

# 2. re-apply this plugin
game/android_plugin/admob/install.sh

# 3. build (debug APK shown; gradle build must be enabled in export_presets.cfg)
godot4 --headless --path game --export-debug "Android" build/war-of-love-debug.apk
```

`export_presets.cfg` already sets `gradle_build/use_gradle_build=true` on
both the debug (`preset.0`) and release (`preset.1`) presets — a custom
GodotPlugin can only be compiled by the Gradle build, not the prebuilt
template.

## AdMob App ID

Not a secret, not committed as a real value. `build.gradle` emits it as a
string resource:

```gradle
resValue "string", "admob_app_id",
    (System.getenv("ADMOB_APP_ID") ?: "ca-app-pub-3940256099942544~3347511713")
```

Default = Google's **test** App ID. For a production build set the
`ADMOB_APP_ID` environment variable before exporting. `AndroidManifest.xml`
references it as `@string/admob_app_id`.

## Ad unit IDs

Read at runtime from `data/ads.json` (`unit_ids.rewarded` /
`unit_ids.interstitial`, `test` vs `prod` chosen by `use_test_ads`) and
passed to `loadRewarded()` / `loadInterstitial()`. Ships with
`use_test_ads: true` and Google's official test unit ids; `prod` fields are
empty placeholders. **Never** ship with test ids; **never** test with prod
ids.

## Plugin API (consumed only by `ads_service.gd`)

| method (`@UsedByGodot`)     | purpose                                   |
|-----------------------------|-------------------------------------------|
| `initialize(useTestDevices)`| `MobileAds.initialize`; emits `initialized`|
| `isInitialized()`           | bool                                      |
| `loadRewarded(unitId)`      | preload; emits `rewarded_loaded` / `rewarded_load_failed` |
| `isRewardedReady()`         | bool                                      |
| `showRewarded()`            | show preloaded ad; emits `rewarded_shown` / `rewarded_earned` / `rewarded_dismissed` / `rewarded_show_failed` |
| `loadInterstitial(unitId)`  | preload; emits `interstitial_loaded` / `interstitial_load_failed` |
| `isInterstitialReady()`     | bool                                      |
| `showInterstitial()`        | show; emits `interstitial_shown` / `interstitial_dismissed` / `interstitial_show_failed` |

Signal: `ad_event(event: String, message: String)`.
