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

## Implementation decisions (Phase 1 core)

These clarify ambiguities in the design above, made while implementing the
first playable core. They are product decisions, not incidental code
details — revisit them here if they need to change.

- **Grid & adjacency.** The board is an orthogonal (4-directional) grid,
  not a hex grid or a swap-based match-3 grid. Color Clash's identity is
  "connect," not "swap," so a free-form connect grid differentiates it
  from Candy Crush-likes without borrowing the reference mockup's hex
  layout. Diagonal connections are not allowed.
- **Power creation & auto-detonation.** A power tile is created at the
  path's release cell and **immediately detonates as part of the same
  move** — it never sits on the board waiting to be matched again. If its
  blast catches another power tile, that one detonates too, and so on
  until nothing new triggers. This is what makes the documented
  Match → Power → Explosion → Chain → Combo ladder happen within a single
  swipe, matching the "CHAIN REACTION" reference panel. "Combo" (the
  x2/x4/x7 counter) is the resulting chain depth of one move, not a
  cross-move streak.
- **Obstacles shipped now: Ice, Lock, Stone.** Ice takes 2 hits to clear
  fully (each hit still clears the piece underneath immediately — only the
  ice *layer* persists across hits). Lock has no piece and unlocks when an
  orthogonally adjacent cell clears. Stone holds no color and can only be
  removed by a power's area effect, never a plain connect. Portal,
  Crystal, and Timer are intentionally deferred — the obstacle system
  (BoardModel + ChainResolver) is built to add them without touching
  match/chain logic.
- **Boosters are usable both before and during a level.** The reference
  mockup's "BOOSTERS (USE BEFORE LEVEL)" section and its always-visible
  in-gameplay booster bar aren't fully consistent; mid-level use is more
  standard mobile-puzzle UX and better demonstrates the booster
  architecture. Bomb/Lightning/Rainbow apply their power at a random
  eligible cell; Shuffle regenerates the board; Extra Moves adds moves
  directly. None of this grants premium currency — see docs/SECURITY.md.

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
