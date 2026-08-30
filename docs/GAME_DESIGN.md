# Color Clash — Game Design Document

## Product goal

Build a globally understandable, highly polished 2D puzzle game with a satisfying color-connection core, escalating chain reactions, strategic power-ups, fair difficulty, and a strong reward loop.

## Core interaction

1. Player selects/connects 3+ adjacent matching-color nodes by touch.
2. On release, the connected group resolves.
3. Larger groups create special powers.
4. Powers can trigger chain reactions.
5. The board resolves completely before the next input is accepted.
6. Player earns score, coins, and level progress.

## Core powers

- 3 colors: standard clear.
- 4 colors: Bomb.
- 5 colors: Lightning.
- 6+ colors: stronger chain power.
- Rainbow: wildcard / color conversion power.

These values are design starting points and must be data-driven for balancing.

## Adrenaline / satisfaction design

The game should create excitement through skillful anticipation, escalating audiovisual feedback, combo milestones, and meaningful choices. It must not rely on deceptive outcomes, fake near-misses, or hidden manipulation.

Feedback ladder:

Match → Pop → Power → Chain → Combo → Fever → Reward

## Level objectives

Examples:

- Clear a target number of a color.
- Break obstacles.
- Create a target number of powers.
- Reach a score target.
- Finish within a move limit.
- Complete a mixed objective.

## Obstacles

Introduce gradually and teach each mechanic before combining it with others.

- Ice: requires additional interaction.
- Lock: requires nearby clears.
- Stone: vulnerable to selected powers.
- Portal: changes board topology.
- Crystal: multi-hit reward object.
- Timer: optional high-pressure objective.

## Modes

- Campaign: primary progression.
- Daily Rush: short timed score challenge.
- Future event modes should reuse the same core systems.

## Monetization

### Rewarded ads

Optional rewards only, such as continue, double level reward, bonus booster, or chest enhancement.

### Interstitial ads

Use conservative frequency and never interrupt an active chain or important reward moment.

### In-app purchases

Low-price optional products can include starter packs, coin packs, booster packs, and remove-ads. Purchases must be validated server-side where applicable and must not be required to progress.

## Economy principles

- Coins are soft currency.
- Boosters are gameplay inventory.
- No real-money redemption.
- Economy values are remotely configurable.
- Reward tables are versioned.
- Client cannot be the sole authority for premium purchase entitlement.

## Difficulty targets

Initial balancing targets, not promises:

- Early onboarding: very high success rate.
- Normal levels: generally achievable with planning.
- Hard levels: clearly communicated and fair.
- Special levels: optional challenge, not forced monetization walls.

Actual difficulty will be measured from analytics and tuned through Remote Config.

## Accessibility

- Do not rely on color alone; use shapes/patterns or subtle symbols where useful.
- Support haptics toggle.
- Support sound/music toggles.
- Avoid excessive flashing.
- Maintain readable contrast and touch targets.
