class_name ChainResolver
extends RefCounted
## Orchestrates one player move: validates the path, clears it, creates
## power(s) if the group is large enough, and auto-detonates them as part
## of the same move. Two independent, fully deterministic mechanisms let a
## single strong move produce a real multi-stage cascade (never a faked
## counter — every extra wave traces back to an actual board interaction):
##
## 1. MULTIPLE POWERS FROM ONE MOVE. A big enough connected group creates
##    more than one power tile, spread across the path (see
##    PowerConfig.powers_for_group_size / data/powers.json's `count`).
##    Several powers detonating from one move can legitimately catch each
##    other in their own blast areas — POWER + POWER INTERACTION — handled
##    by the existing "is this affected cell itself a live power" check
##    below, which now has more than one power to ever find.
## 2. SECONDARY POWER GENERATION FROM EXPOSED CLUSTERS. After any clear
##    (the player's initial match or a power's blast), the cells newly
##    adjacent to what just cleared are checked for a same-color connected
##    group big enough to match on its own (BoardModel.find_connected_group).
##    If the board state exposed one, it auto-clears as a genuine bonus
##    wave — and, exactly like a player match, a big enough exposed group
##    creates its own power(s), which re-enter the same queue and can keep
##    the cascade going. This is what makes chain depth reflect the real
##    board, not a scripted number.
##
## This is the "Match -> Power -> Explosion -> Another power triggered ->
## Chain -> Combo" feedback ladder from docs/GAME_DESIGN.md, entirely
## deterministic and independent of the view layer so it can be unit
## tested headlessly.

const _CHAIN_SAFETY_LIMIT := 400
## Caps how many board-exposed secondary waves one move can trigger. Without
## this, a fortunate blast on a low-color-count board could theoretically
## domino through a large fraction of the board every time, making outcomes
## feel more like luck than skill. Six still allows a real, escalating,
## multi-stage cascade — it just can't run away with the whole board.
const _MAX_SECONDARY_TRIGGERS := 6
## Moves a player loses when a time bomb they left on the board detonates —
## it doesn't end the level outright, but it burns turns and wrecks the
## local board, so ignoring one is genuinely costly.
const TIMEBOMB_MOVE_PENALTY := 2

class MoveResult:
	extends RefCounted
	var valid: bool = false
	var cleared_cells: Array[Vector2i] = []
	var colors_cleared: Dictionary = {} # StringName -> int
	var powers_created: Array[Dictionary] = [] # [{pos, power_id}]
	var powers_activated: Array[Dictionary] = [] # [{pos, power_id}]
	var obstacles_broken: Array[Dictionary] = [] # [{pos, obstacle_id}]
	## Cells the Freeze power encased in ice this move (not cleared — a
	## deliberate side effect the view renders and tests assert on).
	var frozen_cells: Array[Vector2i] = []
	## Board positions where a time bomb hit zero and detonated this move.
	var timebomb_explosions: Array[Vector2i] = []
	## Extra moves deducted this resolve (currently only time-bomb blasts).
	var move_penalty: int = 0
	var chain_depth: int = 0
	## How many waves were triggered purely by exposed board state (not by
	## the player's path or by one power directly catching another) — proof
	## a cascade is real, useful for tests/analytics.
	var secondary_triggers: int = 0
	var score_events: Array[Dictionary] = [] # [{cells, power_bonus, [power_id, power_pos]}] one per wave — power_id/power_pos are only present for a wave that IS a power detonation (not wave0 or a plain auto-chain clear wave)
	var wave_cells: Array = [] # Array[Array[Vector2i]] -- cells touched per wave, parallel to score_events
	var gravity_moves: Array[Dictionary] = []
	var refilled_cells: Array[Vector2i] = []

static func resolve_move(board: BoardModel, path: Array[Vector2i], power_config: PowerConfig, rng: RandomNumberGenerator, available_colors: Array[StringName], rainbow_chance: float = 0.0) -> MoveResult:
	var result := MoveResult.new()
	if not board.validate_path(path):
		return result
	result.valid = true

	var group_size := path.size()
	var target_color := board.get_path_target_color(path)
	if target_color == BoardModel.RAINBOW_COLOR_ID:
		target_color = available_colors[rng.randi_range(0, available_colors.size() - 1)]
	var power_plan := power_config.powers_for_group_size(group_size)
	var horizontal := _path_is_horizontal(path)

	var power_positions := _pick_positions_from_list(path, power_plan.size())
	var skip_set := {}
	for p in power_positions:
		skip_set[p] = true

	_apply_initial_clear(board, result, path, skip_set)
	result.chain_depth = 1

	var queue: Array = []
	var path_oriented := {}
	for i in power_plan.size():
		var pos: Vector2i = power_positions[i]
		var power_id: StringName = power_plan[i]
		var cell := board.get_cell(pos)
		cell.color_id = target_color
		cell.power_id = power_id
		result.powers_created.append({"pos": pos, "power_id": power_id})
		queue.append(pos)
		path_oriented[pos] = true

	# Secondary generation only triggers "during cascades" (a power's blast),
	# not off the player's own plain match — that keeps a common 3/4-length
	# connect exactly as predictable as before, while a move that actually
	# creates a power can still snowball into something bigger if the board
	# state allows it.
	_process_chain_queue(board, result, power_config, queue, horizontal, path_oriented)

	# A player move ticks every time bomb still on the board; any that reach
	# zero detonate now, before gravity, as their own blast wave(s).
	_tick_timebombs(board, result)

	result.gravity_moves = board.apply_gravity()
	result.refilled_cells = board.refill(rng, available_colors, rainbow_chance)
	return result

## Detonates a power directly at `pos` without a player-drawn path — used by
## boosters (Bomb/Lightning/Rainbow) which grant an instant activation
## rather than requiring a match. Shares the same cascade (including
## secondary/power-interaction cascading), obstacle and gravity/refill
## rules as a normal move so behavior stays consistent.
static func detonate_power_at(board: BoardModel, pos: Vector2i, power_id: StringName, power_config: PowerConfig, rng: RandomNumberGenerator, available_colors: Array[StringName], rainbow_chance: float = 0.0, horizontal: bool = true) -> MoveResult:
	var result := MoveResult.new()
	var cell := board.get_cell(pos)
	if cell == null or cell.is_stone() or cell.locked_empty:
		return result
	result.valid = true
	var source_color := cell.color_id
	if source_color == CellData.COLOR_EMPTY or source_color == BoardModel.RAINBOW_COLOR_ID:
		source_color = available_colors[rng.randi_range(0, available_colors.size() - 1)]
	cell.color_id = source_color
	cell.power_id = power_id
	result.powers_created.append({"pos": pos, "power_id": power_id})
	# Baseline of 1 mirrors resolve_move's wave0, so a booster-triggered
	# detonation scores/feels identical to a player match that created and
	# auto-detonated the same power (both are "one wave, one activation" ->
	# chain_depth 2) instead of being under-counted as a plain no-power clear.
	result.chain_depth = 1

	var queue: Array = [pos]
	var path_oriented := {pos: true}
	_process_chain_queue(board, result, power_config, queue, horizontal, path_oriented)

	result.gravity_moves = board.apply_gravity()
	result.refilled_cells = board.refill(rng, available_colors, rainbow_chance)
	return result

static func _path_is_horizontal(path: Array[Vector2i]) -> bool:
	var min_x: int = path[0].x
	var max_x: int = path[0].x
	var min_y: int = path[0].y
	var max_y: int = path[0].y
	for p in path:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)
	return (max_x - min_x) >= (max_y - min_y)

## Picks `count` items spread evenly across `items` (an ordered path or an
## unordered flood-filled group — either way index-spread is a deterministic,
## reasonable placement). Never returns duplicates.
static func _pick_positions_from_list(items: Array, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if count <= 0:
		return out
	var n := items.size()
	if count >= n:
		for i in n:
			out.append(items[i])
		return out
	var used := {}
	for i in count:
		var idx: int = (n - 1) if count == 1 else int(round(float(i) * float(n - 1) / float(count - 1)))
		while used.has(idx) and idx < n - 1:
			idx += 1
		used[idx] = true
		out.append(items[idx])
	return out

static func _apply_initial_clear(board: BoardModel, result: MoveResult, path: Array[Vector2i], skip_set: Dictionary) -> void:
	var touched: Array[Vector2i] = []
	for pos in path:
		if skip_set.has(pos):
			continue
		_clear_or_damage(board, result, pos)
		touched.append(pos)
	result.score_events.append({"cells": touched.size(), "power_bonus": 0})
	result.wave_cells.append(touched)

## Clears a piece (counting stats, ice/lock/stone side effects) or, for a
## stone cell, applies a power hit instead. Safe to call on an already-empty
## cell (idempotent) so overlapping power areas never double-count.
static func _clear_or_damage(board: BoardModel, result: MoveResult, pos: Vector2i) -> void:
	var cell := board.get_cell(pos)
	if cell == null:
		return
	if cell.is_stone():
		if board.damage_stone(pos):
			result.obstacles_broken.append({"pos": pos, "obstacle_id": &"stone"})
		return
	if cell.is_empty():
		return
	if cell.is_ice():
		if board.damage_ice(pos):
			result.obstacles_broken.append({"pos": pos, "obstacle_id": &"ice"})
	if cell.is_timebomb():
		if board.defuse_timebomb(pos):
			result.obstacles_broken.append({"pos": pos, "obstacle_id": &"timebomb"})
	var cleared_color := cell.color_id
	result.cleared_cells.append(pos)
	if cleared_color != BoardModel.RAINBOW_COLOR_ID and cleared_color != CellData.COLOR_EMPTY:
		result.colors_cleared[cleared_color] = int(result.colors_cleared.get(cleared_color, 0)) + 1
	for unlocked_pos in board.unlock_neighbors(pos):
		result.obstacles_broken.append({"pos": unlocked_pos, "obstacle_id": &"lock"})
	cell.clear_piece()

## Drains `queue` (which may already contain more than one origin — a big
## move's several created powers, or ones an earlier wave already found)
## until nothing new triggers. `path_oriented` marks which positions should
## use the player's swipe direction for Lightning; anything discovered
## mid-cascade (chained-into, or auto-chain-created) defaults to horizontal.
static func _process_chain_queue(board: BoardModel, result: MoveResult, power_config: PowerConfig, queue: Array, initial_horizontal: bool, path_oriented: Dictionary) -> void:
	var visited := {}
	var safety := 0
	while not queue.is_empty() and safety < _CHAIN_SAFETY_LIMIT:
		safety += 1
		var pos: Vector2i = queue.pop_front()
		if visited.has(pos):
			continue
		var cell := board.get_cell(pos)
		if cell == null or not cell.has_power():
			continue
		visited[pos] = true

		var power_id := cell.power_id
		var source_color := cell.color_id
		var definition := power_config.get_definition(power_id)
		var horizontal: bool = initial_horizontal if path_oriented.has(pos) else true
		var affected := PowerResolver.affected_cells(board, pos, power_id, horizontal, source_color, definition)

		result.powers_activated.append({"pos": pos, "power_id": power_id})
		result.chain_depth += 1
		_clear_or_damage(board, result, pos)

		var wave_new_cells := 0
		var touched: Array[Vector2i] = [pos]
		var chained: Array[Vector2i] = []
		for apos in affected:
			if apos == pos:
				continue
			var acell := board.get_cell(apos)
			if acell == null:
				continue
			if acell.has_power() and not visited.has(apos):
				# POWER + POWER INTERACTION: this blast reached a still-live
				# power tile (from a multi-power move, or one an earlier wave
				# created) -- let it detonate properly instead of just wiping it.
				chained.append(apos)
				touched.append(apos)
				continue
			var was_occupied := not acell.is_empty() or acell.is_stone()
			_clear_or_damage(board, result, apos)
			touched.append(apos)
			if was_occupied:
				wave_new_cells += 1

		# FREEZE: after shattering its small diamond, encase the plain pieces
		# on the ring one step further out in ice. Existing obstacles / powers
		# / gaps on the ring are left alone.
		if power_id == &"freeze":
			for rpos in PowerResolver.freeze_ring_cells(board, pos, int(definition.get("radius", 1))):
				if board.freeze_cell(rpos, int(definition.get("freeze_hp", 2))):
					result.frozen_cells.append(rpos)

		result.score_events.append({
			"cells": wave_new_cells,
			"power_bonus": int(definition.get("activation_bonus", 0)),
			"power_id": power_id,
			"power_pos": pos,
		})
		result.wave_cells.append(touched)
		for chained_pos in chained:
			queue.append(chained_pos)

		_append_auto_chain_groups(board, result, power_config, touched, queue)

## After a wave clears `touched`, checks every newly-adjacent cell for a
## same-color connected group big enough to match on its own. Each such
## exposed group auto-clears as its own wave and, if large enough, spawns
## its own power(s) fed back into `queue` — genuine secondary generation,
## driven entirely by the resulting board state.
static func _append_auto_chain_groups(board: BoardModel, result: MoveResult, power_config: PowerConfig, touched: Array, queue: Array) -> void:
	if result.secondary_triggers >= _MAX_SECONDARY_TRIGGERS:
		return
	for group in _find_auto_chain_groups(board, touched, power_config.min_group_size()):
		if result.secondary_triggers >= _MAX_SECONDARY_TRIGGERS:
			return
		_resolve_auto_chain_group(board, result, power_config, group, queue)

static func _find_auto_chain_groups(board: BoardModel, touched: Array, min_group_size: int) -> Array:
	var groups: Array = []
	var seen := {}
	for pos in touched:
		for n in board.get_orthogonal_neighbors(pos):
			if seen.has(n):
				continue
			var group := board.find_connected_group(n)
			if group.is_empty():
				seen[n] = true
				continue
			for m in group:
				seen[m] = true
			if group.size() >= min_group_size:
				groups.append(group)
	return groups

static func _resolve_auto_chain_group(board: BoardModel, result: MoveResult, power_config: PowerConfig, group: Array, queue: Array) -> void:
	var power_plan := power_config.powers_for_group_size(group.size())
	var anchor_positions := _pick_positions_from_list(group, power_plan.size())
	var anchor_set := {}
	for p in anchor_positions:
		anchor_set[p] = true

	var target_color: StringName = BoardModel.RAINBOW_COLOR_ID
	for pos in group:
		var c := board.get_cell(pos)
		if c != null and c.color_id != BoardModel.RAINBOW_COLOR_ID:
			target_color = c.color_id
			break

	var touched: Array[Vector2i] = []
	for pos in group:
		if anchor_set.has(pos):
			continue
		_clear_or_damage(board, result, pos)
		touched.append(pos)

	result.score_events.append({"cells": touched.size(), "power_bonus": 0})
	result.wave_cells.append(touched)
	result.chain_depth += 1
	result.secondary_triggers += 1

	for i in power_plan.size():
		var pos: Vector2i = anchor_positions[i]
		var power_id: StringName = power_plan[i]
		var cell := board.get_cell(pos)
		cell.color_id = target_color
		cell.power_id = power_id
		result.powers_created.append({"pos": pos, "power_id": power_id})
		queue.append(pos)

## Ticks every time bomb on the board down one turn (called once per player
## move, after the cascade so a bomb cleared this move doesn't also tick).
## Any that reach zero detonate in place as a 3x3 blast wave and add a move
## penalty. Deterministic and order-stable (top-left to bottom-right).
static func _tick_timebombs(board: BoardModel, result: MoveResult) -> void:
	for pos in board.timebomb_positions():
		if board.tick_timebomb(pos):
			_detonate_timebomb(board, result, pos)

static func _detonate_timebomb(board: BoardModel, result: MoveResult, pos: Vector2i) -> void:
	var cell := board.get_cell(pos)
	if cell != null:
		cell.obstacle_id = CellData.OBSTACLE_NONE
		cell.obstacle_hp = 0
	result.timebomb_explosions.append(pos)
	result.move_penalty += TIMEBOMB_MOVE_PENALTY
	result.obstacles_broken.append({"pos": pos, "obstacle_id": &"timebomb"})
	result.chain_depth += 1

	var touched: Array[Vector2i] = []
	var wave_new_cells := 0
	for apos in PowerResolver.affected_cells(board, pos, &"bomb", true, CellData.COLOR_EMPTY, {"radius": 1}):
		var acell := board.get_cell(apos)
		if acell == null:
			continue
		var was_occupied := not acell.is_empty() or acell.is_stone()
		_clear_or_damage(board, result, apos)
		touched.append(apos)
		if was_occupied:
			wave_new_cells += 1
	result.score_events.append({"cells": wave_new_cells, "power_bonus": 0, "timebomb": true, "power_pos": pos})
	result.wave_cells.append(touched)
