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

## Release pipeline

Local development → automated validation → Android debug build → device playtest → release candidate → internal testing → production AAB.

The project must remain buildable throughout development.
