# War of Love — Monetization (AdMob)

Centralized in **`scripts/services/ads_service.gd`** (autoload **`Ads`**),
config in **`data/ads.json`**. The game is **fully playable with no ads** —
every placement degrades to its normal non-ad behaviour when ads are
unavailable / offline / not yet integrated.

## Backend model

`AdsService` is backend-agnostic. On `_ready()` it looks for a native
AdMob plugin singleton (`AdMob`, `PoingGodotAdMob`, …). If found →
`available = true` and it drives the plugin. If not (desktop, headless, or
the plugin not installed yet) → `available = false`, every `show_rewarded`
fails gracefully, `maybe_show_interstitial` no-ops, banners no-op.

**No native AdMob plugin is bundled yet.** To go live: add a Godot 4
Android AdMob plugin (e.g. `poing-studios/godot-admob-android`) under
`game/addons/` + `game/android/plugins/`, put the AdMob **App ID** in the
Android manifest metadata, and fill the `prod` unit ids in `data/ads.json`
+ set `use_test_ads=false`. The GDScript side already targets a generic
plugin method/signal surface (`_plugin_show_rewarded`, `_wire_plugin`).

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

| unit | test id |
|---|---|
| app id | `ca-app-pub-3940256099942544~3347511713` |
| rewarded | `ca-app-pub-3940256099942544/5224354917` |
| interstitial | `ca-app-pub-3940256099942544/1033173712` |
| banner | `ca-app-pub-3940256099942544/6300978111` |

## Tests

`tests/test_ads_service.gd` (in `test_runner`): ad-free when no backend;
reward granted exactly once and only on "earned"; dismissed / failed /
unavailable grant nothing and don't get stuck in-flight; interstitial
gating (session age, tutorial guard, cooldown, session cap, no
back-to-back); reward amounts read from config.
