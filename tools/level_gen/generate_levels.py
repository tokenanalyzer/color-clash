#!/usr/bin/env python3
"""Deterministic level-data generator for Color Clash — 50-level campaign.

Design-time tool only; levels are consumed at runtime purely as data
(game/scripts/levels/level_database.gd). Re-run after editing to regenerate
game/data/levels.json.

    python tools/level_gen/generate_levels.py

Curve (matches the product brief):

  L1-5   Onboarding. Small board, 3 colours, generous moves, ONE simple
         goal, no obstacles. Teach connect -> release -> blast.
  L6-15  Strategy. 4 colours, first ice then locks, power-creation goals,
         bigger targets, still comfortable move budgets.
  L16-30 Meaningful difficulty. 5 colours, stone, tighter moves, two-goal
         mixed objectives, real score targets.
  L31-50 Advanced. 6 colours (Orange), time bombs, mixed obstacle fields,
         three-goal objectives, demanding (but fair) move budgets.

Nothing here creates an unfair or hidden loss — move budgets are sized so a
skilled clear always has margin; the board is never secretly manipulated.
"""
import json
import os

LEVEL_COUNT = 50
COLOR_ORDER = ["red", "blue", "yellow", "green", "purple", "orange"]
OUT_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "game", "data", "levels.json")


def color_count(lid):
    if lid <= 5:   return 3
    if lid <= 15:  return 4
    if lid <= 30:  return 5
    return 6


def board_size(lid):
    w = 7 + (1 if lid > 10 else 0) + (1 if lid > 26 else 0)   # 7 -> 9
    h = 8 + (1 if lid > 6 else 0) + (1 if lid > 16 else 0) + (1 if lid > 34 else 0)  # 8 -> 11
    return w, h


def move_limit(lid):
    # Generous in onboarding, then a gentle squeeze. Floor keeps it fair.
    if lid <= 5:
        return 30
    if lid <= 15:
        return 28 - (lid - 6)              # 28 -> 19
    if lid <= 30:
        return 24 - (lid - 16) // 2        # 24 -> 17
    return max(16, 22 - (lid - 31) // 3)   # 22 -> 16


def difficulty(lid):
    if lid <= 5:   return "tutorial"
    if lid <= 15:  return "easy"
    if lid <= 30:  return "medium"
    if lid <= 42:  return "hard"
    return "expert"


def obstacles(lid, w, h):
    obs = []
    if lid <= 5:
        return obs
    if 6 <= lid <= 9:                               # ice, 1..3
        for i in range(min(3, lid - 5)):
            obs.append({"type": "ice", "x": 2 + i, "y": 1, "hp": 2})
    elif 10 <= lid <= 15:                           # locks
        for i in range(min(3, lid - 9)):
            obs.append({"type": "lock", "x": 1 + i, "y": h - 2, "hp": 1})
    elif 16 <= lid <= 22:                           # stone
        for i in range(min(3, lid - 15)):
            obs.append({"type": "stone", "x": 3 + i, "y": 2})
    elif 23 <= lid <= 30:                           # ice + stone mix
        obs = [
            {"type": "ice", "x": 1, "y": 1, "hp": 2},
            {"type": "ice", "x": w - 2, "y": 1, "hp": 2},
            {"type": "stone", "x": w // 2, "y": h // 2},
        ]
        if lid >= 27:
            obs.append({"type": "lock", "x": w // 2, "y": h - 2, "hp": 1})
    else:                                           # 31-50: full mix + time bomb
        tier = 3 + (lid - 31) // 6                  # 3 -> 6
        picks = [
            {"type": "ice", "x": 1, "y": 1, "hp": 2},
            {"type": "stone", "x": w // 2, "y": h // 2},
            {"type": "lock", "x": w - 2, "y": h - 2, "hp": 1},
            {"type": "ice", "x": w - 2, "y": 1, "hp": 2},
            {"type": "stone", "x": 2, "y": h - 3},
        ]
        obs = picks[:min(tier, len(picks))]
        if lid >= 34:
            fuse = max(5, 9 - (lid - 34) // 5)      # 9 -> 5
            obs.append({"type": "timebomb", "x": w // 2, "y": 1, "hp": fuse})
    return obs


def objectives(lid, colors, w, h):
    obs_count = len(obstacles(lid, w, h))
    # ---- onboarding: one plain, well-signposted goal ----
    if lid == 1:
        return [{"type": "reach_score", "target": 2500}]
    if lid == 2:
        return [{"type": "clear_color", "color": colors[0], "target": 18}]
    if lid == 3:
        return [{"type": "reach_score", "target": 5000}]
    if lid == 4:
        return [{"type": "create_powers", "power": "any", "target": 2}]
    if lid == 5:
        return [{"type": "clear_color", "color": colors[1], "target": 24}]

    cycle = lid % 5
    if lid <= 15:                                   # single goals, growing
        if cycle == 0:
            return [{"type": "clear_color", "color": colors[lid % len(colors)], "target": 20 + lid}]
        if cycle == 1:
            return [{"type": "reach_score", "target": 6000 + lid * 700}]
        if cycle == 2:
            return [{"type": "create_powers", "power": "any", "target": min(3 + lid // 5, 7)}]
        if cycle == 3 and obs_count:
            return [{"type": "break_obstacles", "obstacle": "any", "target": obs_count}]
        return [{"type": "reach_score", "target": 7000 + lid * 650}]

    if lid <= 30:                                   # two-goal mixes
        base = 22 + lid
        goals = [
            {"type": "clear_color", "color": colors[0], "target": base},
            {"type": "reach_score", "target": 9000 + lid * 900},
        ]
        if cycle in (2, 4) and obs_count:
            goals[1] = {"type": "break_obstacles", "obstacle": "any", "target": obs_count}
        return goals

    # ---- advanced: three goals ----
    base = 26 + lid
    goals = [
        {"type": "clear_color", "color": colors[0], "target": base},
        {"type": "clear_color", "color": colors[3], "target": base - 8},
        {"type": "create_powers", "power": "any", "target": 4 + lid // 10},
    ]
    if obs_count and cycle in (1, 3):
        goals[2] = {"type": "break_obstacles", "obstacle": "any", "target": obs_count}
    return goals


def hint(lid):
    return {
        1: "Swipe across 3+ same-colour jewels, then release.",
        2: "Longer connections clear more — and score more.",
        4: "Connect 4+ to leave a POWER tile. Connect it again to fire it.",
        6: "Ice takes two hits. Blast it with a power.",
        10: "Locks open when you clear jewels right next to them.",
        16: "Stone only breaks inside a power blast.",
        34: "Time bombs count down every move — clear or blast them first!",
    }.get(lid, "")


def build_level(lid):
    w, h = board_size(lid)
    colors = COLOR_ORDER[:color_count(lid)]
    lvl = {
        "id": lid,
        "name": "Level %d" % lid,
        "width": w,
        "height": h,
        "colors": colors,
        "move_limit": move_limit(lid),
        "objectives": objectives(lid, colors, w, h),
        "obstacles": obstacles(lid, w, h),
        "reward": {"coins": 70 + lid * 16},
        "difficulty": difficulty(lid),
    }
    hnt = hint(lid)
    if hnt:
        lvl["hint"] = hnt
    return lvl


def main():
    levels = [build_level(i) for i in range(1, LEVEL_COUNT + 1)]
    payload = {
        "_comment": "Generated by tools/level_gen/generate_levels.py. Edit the generator, not this file.",
        "levels": levels,
    }
    out_path = os.path.abspath(OUT_PATH)
    with open(out_path, "w") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")
    print("Wrote %d levels to %s" % (len(levels), out_path))


if __name__ == "__main__":
    main()
