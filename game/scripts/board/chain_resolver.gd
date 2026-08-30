class_name ChainResolver
extends RefCounted
## Orchestrates one player move: validates the path, clears it, creates a
## power if the group is large enough, and auto-detonates that power as
## part of the same move — any further power tiles caught in its area
## detonate too, cascading until nothing new triggers. This is the
## "Match -> Power -> Explosion -> Another power triggered -> Chain -> Combo"
## feedback ladder described in docs/GAME_DESIGN.md, entirely deterministic
## and independent of the view layer so it can be unit tested headlessly.

const _NO_SKIP := Vector2i(-999, -999)
const _CHAIN_SAFETY_LIMIT := 200

class MoveResult:
	extends RefCounted
	var valid: bool = false
	var cleared_cells: Array[Vector2i] = []
	var colors_cleared: Dictionary = {} # StringName -> int
	var powers_created: Array[Dictionary] = [] # [{pos, power_id}]
	var powers_activated: Array[Dictionary] = [] # [{pos, power_id}]
	var obstacles_broken: Array[Dictionary] = [] # [{pos, obstacle_id}]
	var chain_depth: int = 0
	var score_events: Array[Dictionary] = [] # [{cells, power_bonus}] one per wave
	var wave_cells: Array = [] # Array[Array[Vector2i]] — cells touched per wave, parallel to score_events
	var gravity_moves: Array[Dictionary] = []
	var refilled_cells: Array[Vector2i] = []

static func resolve_move(board: BoardModel, path: Array[Vector2i], power_config: PowerConfig, rng: RandomNumberGenerator, available_colors: Array[StringName], rainbow_chance: float = 0.0) -> MoveResult:
	var result := MoveResult.new()
	if not board.validate_path(path):
		return result
	result.valid = true

	var group_size := path.size()
	var target_color := board.get_path_target_color(path)
	var power_to_create := power_config.power_for_group_size(group_size)
	var release_pos: Vector2i = path[path.size() - 1]
	var horizontal := _path_is_horizontal(path)

	var skip_pos := _NO_SKIP
	if power_to_create != &"none":
		skip_pos = release_pos

	_apply_initial_clear(board, result, path, skip_pos)
	result.chain_depth = 1

	if power_to_create != &"none":
		var cell := board.get_cell(release_pos)
		var placed_color := target_color
		if placed_color == BoardModel.RAINBOW_COLOR_ID:
			placed_color = available_colors[rng.randi_range(0, available_colors.size() - 1)]
		cell.color_id = placed_color
		cell.power_id = power_to_create
		result.powers_created.append({"pos": release_pos, "power_id": power_to_create})
		_process_power_chain(board, result, power_config, release_pos, horizontal)

	result.gravity_moves = board.apply_gravity()
	result.refilled_cells = board.refill(rng, available_colors, rainbow_chance)
	return result

## Detonates a power directly at `pos` without a player-drawn path — used by
## boosters (Bomb/Lightning/Rainbow) which grant an instant activation
## rather than requiring a match. Shares the same cascade, obstacle and
## gravity/refill rules as a normal move so behavior stays consistent.
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
	_process_power_chain(board, result, power_config, pos, horizontal)
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

static func _apply_initial_clear(board: BoardModel, result: MoveResult, path: Array[Vector2i], skip_pos: Vector2i) -> void:
	var touched: Array[Vector2i] = []
	for pos in path:
		if pos == skip_pos:
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
	var cleared_color := cell.color_id
	result.cleared_cells.append(pos)
	if cleared_color != BoardModel.RAINBOW_COLOR_ID and cleared_color != CellData.COLOR_EMPTY:
		result.colors_cleared[cleared_color] = int(result.colors_cleared.get(cleared_color, 0)) + 1
	for unlocked_pos in board.unlock_neighbors(pos):
		result.obstacles_broken.append({"pos": unlocked_pos, "obstacle_id": &"lock"})
	cell.clear_piece()

static func _process_power_chain(board: BoardModel, result: MoveResult, power_config: PowerConfig, origin: Vector2i, initial_horizontal: bool) -> void:
	var visited := {}
	var queue: Array[Vector2i] = [origin]
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
		var horizontal := initial_horizontal if pos == origin else true
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
				chained.append(apos)
				continue
			var was_occupied := not acell.is_empty() or acell.is_stone()
			_clear_or_damage(board, result, apos)
			touched.append(apos)
			if was_occupied:
				wave_new_cells += 1

		result.score_events.append({"cells": wave_new_cells, "power_bonus": int(definition.get("activation_bonus", 0))})
		result.wave_cells.append(touched)
		for chained_pos in chained:
			queue.append(chained_pos)
