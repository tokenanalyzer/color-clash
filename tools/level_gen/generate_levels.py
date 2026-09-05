#!/usr/bin/env python3
"""Deterministic level-data generator for War of Love — 50-level campaign.

Design-time tool only; levels are consumed at runtime purely as data
(game/scripts/levels/level_database.gd -> LevelConfig). Re-run after editing
to regenerate game/data/levels.json:

    python tools/level_gen/generate_levels.py

------------------------------------------------------------------------
DIFFICULTY MODEL (Phase A of the gameplay overhaul brief)
------------------------------------------------------------------------
The campaign is 5 islands x 10 stages. Difficulty rises CONTINUOUSLY, but
the ramp is carried by OBJECTIVES and BLOCKERS, not by starving the player
of moves:

  * `starting_moves` is GENEROUS everywhere and only tapers gently.
      - Island 1 (1-10):   flat 30 moves (teaching space).
      - Islands 2-5:        29 -> 24 band, easing down ~1 move every 3 stages.
      - Boss stages (10/20/30/40/50): 28-32 moves (endurance headroom).
      - Hard floor: 23 moves. NEVER below. No level is ever a move-starve.
  * `difficulty_rank` is a plain 1..10 integer that climbs monotonically
     across the 50 stages (consumed later for enemy-strength / reward
     scaling; already surfaced on LevelConfig).
  * Objectives go SINGLE (island 1) -> DOUBLE (island 2-3) -> TRIPLE
     (island 3-5), and targets grow each chapter.
  * Obstacle fields get denser and more mixed each island (ice -> +lock ->
     +stone -> +timebomb).

FAIRNESS INVARIANTS (asserted at generation time, see _validate):
  * Every `break_obstacles` objective's target is <= the number of that
    obstacle actually placed on the board (obstacles never respawn).
  * Every `reach_score` objective's target is <= the level's own 1-star
    threshold, so completing the score goal can never require 2-star play.
  * `create_powers` targets stay modest (<= 6) and every board is >= 5 wide
    or tall so a Lightning (5-match) is always physically formable.
  * `starting_moves` is always >= _MOVE_FLOOR.
  * The board is never secretly manipulated; a skilled clear always has
    margin. Obstacles sit inside a safe band (never the bottom two rows or
    the top refill row) so gravity/refill always has room.
"""
import json
import os

LEVEL_COUNT = 50
COLOR_ORDER = ["red", "blue", "yellow", "green", "purple", "orange"]
OUT_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "game", "data", "levels.json")

_MOVE_FLOOR = 23
BOSS_STAGES = (10, 20, 30, 40, 50)

# Named enemy per island boss stage (mirrors data/enemies.json; used only for
# the human-readable level name so the map/HUD reads as a rescue journey).
_BOSS_NAME = {10: "Poison Beast", 20: "Ice Wraith", 30: "Dark Knight",
              40: "Chaos Sorcerer", 50: "Jinn"}


# --------------------------------------------------------------- shape --

def chapter(lid):
    """0-based island index for a stage."""
    return (lid - 1) // 10


def pos_in_chapter(lid):
    """0..9 position of a stage within its island."""
    return (lid - 1) % 10


def is_boss(lid):
    return lid in BOSS_STAGES


def color_count(lid):
    if lid <= 5:
        return 3
    if lid <= 15:
        return 4
    if lid <= 30:
        return 5
    return 6


def board_size(lid):
    w = 7 + (1 if lid > 10 else 0) + (1 if lid > 26 else 0)          # 7 -> 9
    h = 8 + (1 if lid > 6 else 0) + (1 if lid > 16 else 0) + (1 if lid > 34 else 0)  # 8 -> 11
    return w, h


def starting_moves(lid):
    """Generous, gently tapering. See module docstring."""
    ch = chapter(lid)
    if is_boss(lid):
        return max(_MOVE_FLOOR, 32 - ch)          # 32,31,30,29,28
    if ch == 0:
        return 30                                  # whole first island flat
    base = 30 - ch                                 # 29,28,27,26  (islands 2-5)
    taper = pos_in_chapter(lid) // 3               # 0..2 across the island
    return max(_MOVE_FLOOR, base - taper)


def difficulty_rank(lid):
    """Monotonic 1..10 across the campaign."""
    return 1 + (lid - 1) * 9 // (LEVEL_COUNT - 1)


def difficulty(lid):
    if lid <= 5:
        return "tutorial"
    if lid <= 12:
        return "easy"
    if lid <= 24:
        return "medium"
    if lid <= 38:
        return "hard"
    return "expert"


# ----------------------------------------------------------- obstacles --

def _obstacle_specs(lid):
    """(type, count, hp) tuples for a stage. hp 0 => omit the field.
    Densities climb each island; bosses carry a thematic-but-fair field.

    Themed ids (2026-09-05 gameplay-depth pass) are original War of Love
    blockers, but each reuses one of the 4 proven mechanic families instead
    of inventing new ones (see game/scripts/board/cell_data.gd's _FAMILY
    table):
      ice family      (any clear/blast damages; hp tiers the challenge)
        -> wooden_crate (hp1, gentle), frozen_crystal (hp2), reinforced_crate (hp3)
      lock family      (only chips from an ADJACENT clear, never a direct hit)
        -> magic_chain
      stone family     (power-blast only, never a plain match)
        -> cursed_stone (1 hit, like plain stone), shadow_barrier (hp2, needs
           2 separate power blasts)
      timebomb family  (counts down each move, detonates if ignored)
        -> dark_rune
    """
    ch = chapter(lid)
    p = pos_in_chapter(lid)
    specs = []

    if ch == 0:                                    # 1-10  teach: crates, then chains
        if lid <= 3:
            return []
        if lid <= 5:
            specs = [("wooden_crate", 3, 1)]
        elif lid <= 7:
            specs = [("wooden_crate", 4, 1)]
        elif lid <= 9:
            specs = [("wooden_crate", 2, 1), ("magic_chain", 2, 1)]
        else:                                      # 10 boss (Poison Beast)
            specs = [("frozen_crystal", 2, 2), ("magic_chain", 1, 1)]

    elif ch == 1:                                  # 11-20  frozen crystal + chains, denser
        if p <= 2:
            specs = [("magic_chain", 3, 1), ("frozen_crystal", 2, 2)]
        elif p <= 5:
            specs = [("frozen_crystal", 3, 2), ("magic_chain", 2, 1)]
        elif p <= 8:
            specs = [("reinforced_crate", 2, 3), ("frozen_crystal", 3, 2), ("magic_chain", 1, 1)]
        else:                                      # 20 boss (Ice Wraith)
            specs = [("frozen_crystal", 3, 2), ("reinforced_crate", 2, 3)]

    elif ch == 2:                                  # 21-30  cursed stone joins in
        if p <= 2:
            specs = [("cursed_stone", 3, 0), ("frozen_crystal", 2, 2)]
        elif p <= 5:
            specs = [("cursed_stone", 3, 0), ("reinforced_crate", 2, 3)]
        elif p <= 8:
            specs = [("cursed_stone", 3, 0), ("frozen_crystal", 3, 2), ("magic_chain", 2, 1)]
        else:                                      # 30 boss (Dark Knight)
            specs = [("cursed_stone", 3, 0), ("reinforced_crate", 2, 3)]

    elif ch == 3:                                  # 31-40  dark runes + shadow barriers join in
        fuse = max(6, 10 - ch)                     # 7
        if p <= 2:
            specs = [("reinforced_crate", 2, 3), ("cursed_stone", 2, 0), ("dark_rune", 1, fuse)]
        elif p <= 5:
            specs = [("cursed_stone", 3, 0), ("frozen_crystal", 2, 2), ("magic_chain", 1, 1), ("dark_rune", 1, fuse)]
        elif p <= 8:
            specs = [("cursed_stone", 3, 0), ("shadow_barrier", 1, 2), ("reinforced_crate", 2, 3), ("dark_rune", 1, fuse)]
        else:                                      # 40 boss (Chaos Sorcerer)
            specs = [("cursed_stone", 2, 0), ("shadow_barrier", 1, 2), ("reinforced_crate", 2, 3), ("dark_rune", 1, fuse)]

    else:                                          # 41-50  dense endgame mix, every family present
        fuse = max(6, 10 - ch)                     # 6
        if p <= 2:
            specs = [("cursed_stone", 2, 0), ("shadow_barrier", 1, 2), ("frozen_crystal", 3, 2),
                     ("magic_chain", 1, 1), ("dark_rune", 1, fuse)]
        elif p <= 5:
            specs = [("cursed_stone", 3, 0), ("shadow_barrier", 1, 2), ("reinforced_crate", 2, 3),
                     ("magic_chain", 2, 1), ("dark_rune", 1, fuse)]
        elif p <= 8:
            specs = [("cursed_stone", 3, 0), ("shadow_barrier", 2, 2), ("reinforced_crate", 2, 3),
                     ("magic_chain", 2, 1), ("dark_rune", 1, fuse)]
        else:                                      # 50 (Jinn) — fair boss race
            specs = [("cursed_stone", 2, 0), ("shadow_barrier", 1, 2), ("reinforced_crate", 2, 3), ("dark_rune", 1, fuse)]

    return specs


def _safe_cells(w, h):
    """Obstacle-eligible cells: never the top refill row or the bottom two
    rows (keeps gravity/refill working), never the outer columns."""
    return [(x, y) for y in range(1, h - 2) for x in range(1, w - 1)]


def _scatter_order(lid, cells):
    """Deterministic LCG shuffle of `cells` keyed by stage id — stable across
    runs, and spreads obstacles so no column is ever walled off."""
    seed = (lid * 2654435761) & 0xFFFFFFFF
    pool = list(cells)
    out = []
    while pool:
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        out.append(pool.pop(seed % len(pool)))
    return out


def obstacles(lid):
    w, h = board_size(lid)
    specs = _obstacle_specs(lid)
    if not specs:
        return []
    order = _scatter_order(lid, _safe_cells(w, h))
    # keep the field well under half the safe band so the board stays open
    cap = max(1, len(order) * 4 // 10)
    out = []
    i = 0
    for (kind, count, hp) in specs:
        for _ in range(count):
            if i >= len(order) or len(out) >= cap:
                break
            x, y = order[i]
            i += 1
            cell = {"type": kind, "x": x, "y": y}
            if hp:
                cell["hp"] = hp
            out.append(cell)
    return out


def _count_obstacle(obs, kind):
    return sum(1 for o in obs if o["type"] == kind)


# ---------------------------------------------------------- objectives --

# Rough per-move score yield for a decent (not perfect) clear, by tier.
# Used ONLY to derive first-pass per-level star thresholds + score goals —
# the runtime rating is pure score vs. these numbers
# (game/scripts/economy/star_rating.gd). Re-tune from analytics later
# (docs/GAME_DESIGN.md "Difficulty targets").
_SCORE_YIELD = {
    "tutorial": 470,
    "easy": 680,
    "medium": 980,
    "hard": 1280,
    "expert": 1580,
}


def _expected_score(lid):
    return starting_moves(lid) * _SCORE_YIELD[difficulty(lid)]


def _snap(v):
    return int(round(v / 500.0)) * 500


def _score_goal(lid, frac):
    return max(500, _snap(_expected_score(lid) * frac))


def _clear_goal(lid, tier=0):
    """Colour-clear target. tier 0 = primary, 1 = secondary, 2 = tertiary."""
    ch = chapter(lid)
    base = [18, 26, 34, 44, 52][ch] + pos_in_chapter(lid)
    mult = (1.0, 0.72, 0.55)[tier]
    return int(round(base * mult))


def _power_goal(lid):
    return min(2 + lid // 8, 6)


def _pick_colors(colors, k):
    """k distinct colour names from the level's palette (palettes are 3-6)."""
    out = []
    idx = 0
    while len(out) < k and idx < len(colors):
        out.append(colors[idx])
        idx += 1
    # palettes are always >= 3 and k is always <= 3, so this never cycles;
    # the guard just keeps the generator total.
    while len(out) < k:
        out.append(colors[-1])
    return out


_OBSTACLE_OBJ_KIND = {  # which obstacle a stage's obstacle-goal should name
    0: "wooden_crate", 1: "magic_chain", 2: "cursed_stone", 3: "cursed_stone", 4: "shadow_barrier",
}


def objectives(lid, colors, obs):
    """Varied, chapter-scaled goals. Uses only the runtime-supported types
    (clear_color / reach_score / create_powers / break_obstacles)."""
    ch = chapter(lid)
    p = pos_in_chapter(lid)

    # ---- Island 1: pure teaching, one goal at a time ----
    if ch == 0:
        table = {
            1: [{"type": "reach_score", "target": _score_goal(1, 0.30)}],
            2: [{"type": "clear_color", "color": colors[0], "target": 15}],
            3: [{"type": "create_powers", "power": "any", "target": 2}],
            4: [{"type": "reach_score", "target": _score_goal(4, 0.38)}],
            5: [{"type": "clear_color", "color": colors[1], "target": 22}],
            6: [{"type": "break_obstacles", "obstacle": "wooden_crate",
                 "target": _count_obstacle(obs, "wooden_crate")}],
            7: [{"type": "clear_color", "color": colors[0], "target": 24},
                {"type": "reach_score", "target": _score_goal(7, 0.42)}],
            8: [{"type": "create_powers", "power": "any", "target": 3},
                {"type": "break_obstacles", "obstacle": "any", "target": len(obs)}],
            9: [{"type": "break_obstacles", "obstacle": "magic_chain",
                 "target": _count_obstacle(obs, "magic_chain")},
                {"type": "clear_color", "color": colors[2], "target": 20}],
            10: [{"type": "reach_score", "target": _score_goal(10, 0.95)},
                 {"type": "clear_color", "color": colors[0], "target": 20}],
        }
        return table[lid]

    # ---- Boss stages 20/30/40/50: score race + a colour goal (+ powers late) ----
    if is_boss(lid):
        goals = [
            {"type": "reach_score", "target": _score_goal(lid, 0.95)},
            {"type": "clear_color", "color": colors[0], "target": _clear_goal(lid, 1)},
        ]
        if ch >= 3:
            goals.append({"type": "create_powers", "power": "any",
                          "target": 4 + (ch - 3)})
        return goals

    # ---- Islands 2-5: doubles growing into triples ----
    cols = _pick_colors(colors, 3)
    obs_kind = _OBSTACLE_OBJ_KIND[ch]
    have_kind = _count_obstacle(obs, obs_kind) > 0
    obstacle_goal = (
        {"type": "break_obstacles", "obstacle": obs_kind,
         "target": _count_obstacle(obs, obs_kind)}
        if have_kind else
        {"type": "break_obstacles", "obstacle": "any", "target": len(obs)}
    )
    score_goal = {"type": "reach_score", "target": _score_goal(lid, 0.45)}
    power_goal = {"type": "create_powers", "power": "any", "target": _power_goal(lid)}

    shapes = {
        0: [{"type": "clear_color", "color": cols[0], "target": _clear_goal(lid, 0)}, score_goal],
        1: [{"type": "clear_color", "color": cols[1], "target": _clear_goal(lid, 0)}, obstacle_goal],
        2: [power_goal, score_goal],
        3: [{"type": "clear_color", "color": cols[0], "target": _clear_goal(lid, 0)},
            {"type": "clear_color", "color": cols[2], "target": _clear_goal(lid, 1)}],
        4: [{"type": "clear_color", "color": cols[1], "target": _clear_goal(lid, 0)}, obstacle_goal],
        5: [{"type": "clear_color", "color": cols[0], "target": _clear_goal(lid, 0)},
            {"type": "clear_color", "color": cols[2], "target": _clear_goal(lid, 1)}, power_goal],
        6: [{"type": "clear_color", "color": cols[1], "target": _clear_goal(lid, 0)}, score_goal, obstacle_goal],
        7: [{"type": "clear_color", "color": cols[0], "target": _clear_goal(lid, 0)},
            {"type": "clear_color", "color": cols[2], "target": _clear_goal(lid, 1)}, obstacle_goal],
        8: [{"type": "clear_color", "color": cols[1], "target": _clear_goal(lid, 0)},
            {"type": "clear_color", "color": cols[2], "target": _clear_goal(lid, 1)}, power_goal],
    }
    goals = list(shapes[p])

    # Cap objective count by island: island 2 stays mostly double (triples
    # only from the mid-chapter on); island 3 mixes double/triple.
    if ch == 1 and p <= 5:
        goals = goals[:2]
    elif ch == 2 and p <= 2:
        goals = goals[:2]

    # Islands 4-5 (stages 31-50): "multiple simultaneous objectives" /
    # "longer objective chains" — every non-boss stage runs three goals.
    if ch >= 3 and len(goals) < 3:
        present = {g["type"] for g in goals}
        for extra in (obstacle_goal, power_goal, score_goal):
            if extra["type"] not in present:
                goals.append(extra)
                break

    return goals


# --------------------------------------------------------- star scores --

def star_scores(lid, objs):
    expected = _expected_score(lid)
    for o in objs:
        if o.get("type") == "reach_score":
            expected = max(expected, int(o["target"] * 1.25))
    s1 = _snap(expected * 0.50)
    s2 = max(_snap(expected * 0.80), s1 + 500)
    s3 = max(_snap(expected * 1.20), s2 + 500)
    return [s1, s2, s3]


# --------------------------------------------------------------- hints --

def hint(lid):
    return {
        1: "Swipe across 3+ same-colour jewels, then release.",
        2: "Longer connections clear more — and score more.",
        3: "Connect 4+ to leave a POWER tile. Connect it again to fire it.",
        6: "Wooden Crates break in one hit — clear a jewel on top of one.",
        9: "Magic Chains open when you clear jewels right next to them.",
        10: "Boss ahead — every match powers Jamie's attack.",
        16: "Cursed Stone only breaks inside a power blast.",
        21: "Line up 5 to leave a Lightning — it clears a whole row and column.",
        31: "Dark Runes count down every move — clear or blast them first!",
        41: "Endgame: chain powers together for the score you need.",
        50: "Jinn. Everything you've learned. Rescue Jasmine.",
    }.get(lid, "")


# ------------------------------------------------------------ assemble --

def build_level(lid):
    w, h = board_size(lid)
    colors = COLOR_ORDER[:color_count(lid)]
    obs = obstacles(lid)
    objs = objectives(lid, colors, obs)
    sscores = star_scores(lid, objs)

    # Fairness clamp: a score goal must never exceed the 1-star threshold.
    for o in objs:
        if o.get("type") == "reach_score":
            o["target"] = min(o["target"], sscores[0])

    moves = starting_moves(lid)
    name = "Level %d" % lid
    if lid in _BOSS_NAME:
        name = "Stage %d — %s" % (lid, _BOSS_NAME[lid])

    lvl = {
        "id": lid,
        "name": name,
        "width": w,
        "height": h,
        "colors": colors,
        # `starting_moves` is the canonical key; `move_limit` is kept as an
        # alias so older consumers / saved data keep working unchanged.
        "starting_moves": moves,
        "move_limit": moves,
        "difficulty": difficulty(lid),
        "difficulty_rank": difficulty_rank(lid),
        "objectives": objs,
        "obstacles": obs,
        "star_scores": sscores,
        "reward": {"coins": 70 + lid * 16},
    }
    hnt = hint(lid)
    if hnt:
        lvl["hint"] = hnt
    return lvl


def _validate(levels):
    """Enforce the fairness invariants in the module docstring. Raises on
    any violation so a bad edit can never ship a broken campaign."""
    prev_rank = 0
    for lvl in levels:
        lid = lvl["id"]
        tag = "L%d" % lid

        assert lvl["starting_moves"] >= _MOVE_FLOOR, \
            "%s: %d moves is below the fair floor %d" % (tag, lvl["starting_moves"], _MOVE_FLOOR)
        assert lvl["starting_moves"] == lvl["move_limit"], \
            "%s: starting_moves / move_limit alias mismatch" % tag

        assert lvl["difficulty_rank"] >= prev_rank, \
            "%s: difficulty_rank regressed (%d < %d)" % (tag, lvl["difficulty_rank"], prev_rank)
        prev_rank = lvl["difficulty_rank"]

        # obstacles: in bounds, unique cells, inside the safe band
        w, h = lvl["width"], lvl["height"]
        seen = set()
        for o in lvl["obstacles"]:
            xy = (o["x"], o["y"])
            assert xy not in seen, "%s: two obstacles on %s" % (tag, xy)
            seen.add(xy)
            assert 1 <= o["x"] <= w - 2, "%s: obstacle x=%d out of band" % (tag, o["x"])
            assert 1 <= o["y"] <= h - 3, "%s: obstacle y=%d out of band" % (tag, o["y"])
        assert len(lvl["obstacles"]) <= (w * h) // 3, \
            "%s: obstacle field too dense (%d on %dx%d)" % (tag, len(lvl["obstacles"]), w, h)

        counts = {}
        for o in lvl["obstacles"]:
            counts[o["type"]] = counts.get(o["type"], 0) + 1

        assert 1 <= len(lvl["objectives"]) <= 3, \
            "%s: %d objectives (want 1-3)" % (tag, len(lvl["objectives"]))

        for ob in lvl["objectives"]:
            t = ob["type"]
            if t == "break_obstacles":
                kind = ob.get("obstacle", "any")
                avail = len(lvl["obstacles"]) if kind == "any" else counts.get(kind, 0)
                assert ob["target"] >= 1, "%s: break_obstacles target < 1" % tag
                assert ob["target"] <= avail, \
                    "%s: break %d %s but only %d on board" % (tag, ob["target"], kind, avail)
            elif t == "reach_score":
                assert ob["target"] <= lvl["star_scores"][0], \
                    "%s: score goal %d exceeds 1-star %d" % (tag, ob["target"], lvl["star_scores"][0])
                assert ob["target"] >= 500, "%s: score goal too small" % tag
            elif t == "clear_color":
                assert ob["color"] in lvl["colors"], \
                    "%s: clear_color %s not in palette" % (tag, ob["color"])
                assert ob["target"] >= 1
            elif t == "create_powers":
                assert 1 <= ob["target"] <= 6, "%s: create_powers target %d" % (tag, ob["target"])
                assert max(w, h) >= 5, "%s: board too small to form powers" % tag
            else:
                raise AssertionError("%s: unknown objective type %r" % (tag, t))

        if is_boss(lvl["id"]):
            assert len(lvl["objectives"]) >= 2, "%s: boss stage needs >= 2 goals" % tag

    # the ramp must actually move
    ranks = [l["difficulty_rank"] for l in levels]
    assert ranks[0] == 1 and ranks[-1] == 10, "difficulty_rank must span 1..10"
    moves = {l["starting_moves"] for l in levels}
    assert len(moves) >= 3, "move counts must be level-data driven, not fixed"


def main():
    levels = [build_level(i) for i in range(1, LEVEL_COUNT + 1)]
    _validate(levels)
    payload = {
        "_comment": ("Generated by tools/level_gen/generate_levels.py. Edit the "
                     "generator, not this file. `starting_moves` is canonical; "
                     "`move_limit` is a kept alias. See the generator docstring "
                     "for the difficulty model + fairness invariants."),
        "levels": levels,
    }
    out_path = os.path.abspath(OUT_PATH)
    with open(out_path, "w") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")
    print("Wrote %d levels to %s" % (len(levels), out_path))
    # quick human-readable curve summary
    for lid in (1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50):
        lv = levels[lid - 1]
        print("  L%-2d  moves=%-2d rank=%-2d  goals=%d  obstacles=%-2d  %s"
              % (lid, lv["starting_moves"], lv["difficulty_rank"],
                 len(lv["objectives"]), len(lv["obstacles"]), lv["difficulty"]))


if __name__ == "__main__":
    main()
