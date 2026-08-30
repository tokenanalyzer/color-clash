# Color Clash — Production Architecture

## Client

Godot 4.x + GDScript is the primary game runtime.

Suggested modules:

- Core: app lifecycle, state machine, configuration, save orchestration.
- Board: grid generation, cells, matching, resolution, cascades.
- Powers: bomb, lightning, rainbow, future powers.
- Levels: level definitions, objectives, progression.
- Economy: coins, boosters, rewards, inventory.
- UX: menus, HUD, onboarding, settings, accessibility.
- Audio/VFX: reusable feedback pipeline.
- Services: Firebase, ads, billing, analytics, crash reporting.
- Security: entitlement and economy validation boundaries.

## Offline-first rule

Core puzzle play must not require an internet connection. Network-dependent features should fail gracefully and never corrupt local progress.

## Persistence

Local save is the immediate gameplay source for offline continuity. Cloud save synchronizes when authenticated/connected. Conflicts must be handled deterministically.

## Firebase

Firebase is used for:

- Authentication / anonymous identity.
- Firestore for cloud profile and synchronized progression where appropriate.
- Cloud Functions for trusted server-side operations.
- Remote Config for tunable economy, difficulty, and live parameters.
- Analytics for gameplay funnels and retention metrics.
- Crashlytics for crash monitoring.
- App Check where supported.

Do not write every gameplay action to Firestore. Batch or checkpoint meaningful state changes.

## Monetization boundary

Google Play Billing and AdMob are client integrations, but purchase entitlement and sensitive economy operations must have a trusted validation path. Never ship secrets in the client.

## Data-driven design

Levels, objectives, colors, power definitions, reward tables, and balance constants should be data-driven so content and balancing can evolve without rewriting core systems.

## Performance goals

- Target 60 FPS on supported Android devices.
- Avoid allocations inside hot board-resolution loops where practical.
- Pool repeated VFX objects.
- Keep textures/audio appropriately compressed.
- Measure before optimizing.

## Current implementation (Phase 1 core)

```
game/
  data/                   colors, powers, fever, boosters, levels, sfx,
                           music (JSON)
  scripts/
    board/                BoardModel, CellData, PowerResolver, ChainResolver
                           (pure logic, no Node dependency) + BoardView/
                           PieceView (presentation + touch input)
    combo/                ComboSystem, FeverSystem
    levels/                LevelConfig, LevelDatabase, ObjectiveTracker
    economy/               ScoreCalculator (pure), EconomyService,
                           BoosterInventory (autoloads)
    core/                  JsonLoader, GameData (autoload — boot-time
                           config loader)
    save/                  SaveService (autoload — local JSON save)
    vfx/                   particle pool, screen shake, combo popups,
                           haptics, ShapeDrawUtils (piece rendering)
    audio/                 Synth (DSP primitives), SfxBuilder/
                           MusicLayerBuilder (pure, data -> PCM buffer),
                           AudioSettings/Audio/Music (autoloads — bus
                           control, SFX playback, adaptive music director)
    services/              IapService, AdsService, FirebaseService —
                           interface stubs only, not wired into gameplay
    ui/                    HUD (built in code, not a hand-authored scene)
    app.gd                 top-level GameController (level flow, session
                           state, signal wiring)
  scenes/main.tscn         entry scene; everything else is built in code
  tests/                   headless unit tests + manual smoke scripts
tools/level_gen/           level-data authoring script (regenerates
                           data/levels.json)
```

The gameplay-critical logic (BoardModel, PowerResolver, ChainResolver,
ScoreCalculator, ComboSystem/FeverSystem, ObjectiveTracker) is written as
plain `RefCounted` classes with no scene-tree dependency, specifically so
it can be unit tested headlessly and reasoned about independently of
rendering. BoardView/PieceView/HUD are the only layer that touches nodes,
tweens, or input.

### Testing & validation

No GUT dependency — a small reflection-based `TestCase` base
(`game/tests/test_case.gd`) plus `game/tests/test_runner.gd` cover
matching, path validation, obstacle interactions, power area effects,
chain cascades, scoring, objectives, the economy/booster autoloads, and
the audio DSP/builders (Synth/SfxBuilder/MusicLayerBuilder — buffer
length, no NaN/clipping, intensity actually changes pitch, every
data/sfx.json id builds, every data/music.json layer renders the same
loop length). Run headlessly:

```
godot4 --headless --path game --script res://tests/test_runner.gd
```

Manual (non-CI) smoke scripts boot the real main scene end to end —
useful after any board/level/audio change:
- `game/tests/smoke_main_e2e.gd` drives an actual move + booster through
  it.
- `game/tests/smoke_all_levels.gd` generates every campaign level's board
  to catch layout/obstacle crashes.
- `game/tests/smoke_audio_chain.gd` drives the full connect -> match ->
  power -> blast -> cascade -> combo -> Fever -> level-completion chain
  through a real drag gesture and boosters, asserting each stage actually
  played its sound and (for Fever) that the music state reached it.

## Release pipeline

Local development → automated validation → Android debug build → device playtest → release candidate → internal testing → production AAB.

The project must remain buildable throughout development.
