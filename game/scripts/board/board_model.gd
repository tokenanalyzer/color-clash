class_name BoardModel
extends RefCounted
## Pure, engine-light board grid logic: layout, adjacency, path validation,
## clearing, gravity and refill. No Node/scene dependencies so this class is
## fully unit-testable headlessly (see game/tests/).
##
## Coordinate system: Vector2i(x, y) with x = column, y = row, y = 0 is the
## top row. Adjacency is orthogonal (4-directional) — Color Clash is a
## free-form "connect" game, not a swap-based match-3.

## Sentinel color id for Rainbow wildcard pieces: matches any color in a path.
const RAINBOW_COLOR_ID: StringName = &"rainbow"

var width: int
var height: int
var min_group_size: int
var _grid: Array = [] # _grid[x][y] = CellData

func _init(p_width: int, p_height: int, p_min_group_size: int = 3) -> void:
	width = p_width
	height = p_height
	min_group_size = p_min_group_size
	_grid.resize(width)
	for x in width:
		var column: Array = []
		column.resize(height)
		for y in height:
			column[y] = CellData.new()
		_grid[x] = column

func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

func get_cell(pos: Vector2i) -> CellData:
	if not in_bounds(pos):
		return null
	return _grid[pos.x][pos.y]

## HONEYCOMB adjacency (odd-r offset layout: odd rows are shifted +½ cell
## right when drawn). Every cell has up to 6 neighbours — E, W and two on
## each of the rows above and below. Straight left/right still works, so a
## "row" is a clean horizontal line; a "column" zig-zags by half a cell.
const _HEX_EVEN: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(0, 1), Vector2i(-1, 1),
]
const _HEX_ODD: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(0, 1),
]

func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var offsets := _HEX_ODD if (pos.y & 1) == 1 else _HEX_EVEN
	for offset in offsets:
		var n: Vector2i = pos + offset
		if in_bounds(n):
			result.append(n)
	return result

## Kept as an alias — callers that predate the hex grid still work, they
## just get 6 neighbours now instead of 4.
func get_orthogonal_neighbors(pos: Vector2i) -> Array[Vector2i]:
	return get_neighbors(pos)

func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return get_neighbors(a).has(b)

## Applies an obstacle definition to a cell before the board is generated.
func set_obstacle(pos: Vector2i, obstacle_id: StringName, hp: int) -> void:
	var cell := get_cell(pos)
	if cell == null:
		return
	cell.obstacle_id = obstacle_id
	cell.obstacle_hp = hp
	if CellData.family_of(obstacle_id) == &"lock":
		cell.locked_empty = true

## Seats an escort special (the Love Crystal, &"relic") on a cell before the
## board is generated. The cell then holds no colour, is not selectable, and
## only ever falls with gravity toward delivery at the bottom row.
func set_special(pos: Vector2i, special_id: StringName) -> void:
	var cell := get_cell(pos)
	if cell == null:
		return
	cell.special_id = special_id
	cell.color_id = CellData.COLOR_EMPTY
	cell.power_id = CellData.POWER_NONE

## Every board position currently carrying an escort special.
func special_positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in width:
		for y in height:
			if _grid[x][y].has_special():
				out.append(Vector2i(x, y))
	return out

## Fills every fillable empty cell with a random color from available_colors.
## Stone and still-locked cells are skipped (they hold no piece).
func generate(rng: RandomNumberGenerator, available_colors: Array[StringName]) -> void:
	for x in width:
		for y in height:
			var cell: CellData = _grid[x][y]
			if cell.is_stone() or cell.locked_empty or cell.has_special():
				continue
			cell.color_id = available_colors[rng.randi_range(0, available_colors.size() - 1)]

## True if any cell on the path already holds a power tile — such a path is
## an "activation" (thread the power(s) into a connection), not a plain
## match, so it only needs 2 cells and power tiles count as any colour.
func path_has_power(path: Array[Vector2i]) -> bool:
	for pos in path:
		var cell := get_cell(pos)
		if cell != null and cell.has_power():
			return true
	return false

## Resolves the effective match colour of a path — the colour every plain
## cell must share. Rainbow wildcards and power tiles are skipped (they
## connect to anything).
func get_path_target_color(path: Array[Vector2i]) -> StringName:
	for pos in path:
		var cell := get_cell(pos)
		if cell != null and cell.color_id != RAINBOW_COLOR_ID and not cell.has_power():
			return cell.color_id
	return RAINBOW_COLOR_ID

## A path is valid when it is long enough (min_group_size for a plain match,
## just 2 when it threads a power tile), has no repeated cells, every step is
## orthogonally adjacent to the previous one, every cell is selectable, and
## every plain non-wildcard cell shares one colour. Power tiles and Rainbow
## wildcards match any colour.
func validate_path(path: Array[Vector2i]) -> bool:
	var min_size := 2 if path_has_power(path) else min_group_size
	if path.size() < min_size:
		return false
	var seen := {}
	for i in path.size():
		var pos: Vector2i = path[i]
		if not in_bounds(pos):
			return false
		if seen.has(pos):
			return false
		seen[pos] = true
		var cell := get_cell(pos)
		if cell == null or not cell.is_selectable():
			return false
		if i > 0 and not is_adjacent(path[i - 1], pos):
			return false
	var target := get_path_target_color(path)
	if target == RAINBOW_COLOR_ID:
		return true
	for pos in path:
		var cell := get_cell(pos)
		if cell.has_power() or cell.color_id == RAINBOW_COLOR_ID:
			continue
		if cell.color_id != target:
			return false
	return true

## Clears the pieces at the given cells (color + power only; obstacles stay).
func clear_cells(cells: Array[Vector2i]) -> void:
	for pos in cells:
		var cell := get_cell(pos)
		if cell != null:
			cell.clear_piece()

## Cracks an ice obstacle by one hit. Returns true if it fully broke.
func damage_ice(pos: Vector2i) -> bool:
	var cell := get_cell(pos)
	if cell == null or not cell.is_ice():
		return false
	cell.obstacle_hp -= 1
	if cell.obstacle_hp <= 0:
		cell.obstacle_id = CellData.OBSTACLE_NONE
		cell.obstacle_hp = 0
		return true
	return false

## Stone-family can only be removed by a power's area effect, never a plain
## clear. Most of the family (stone/cursed_stone) has no hp (defaults to 0)
## and always breaks in one hit; Shadow Barrier is placed with hp 2 and
## needs two separate power blasts (returns false, still blocking, after the
## first). Returns true only once it's actually gone.
func damage_stone(pos: Vector2i) -> bool:
	var cell := get_cell(pos)
	if cell == null or not cell.is_stone():
		return false
	cell.obstacle_hp -= 1
	if cell.obstacle_hp <= 0:
		cell.obstacle_id = CellData.OBSTACLE_NONE
		cell.obstacle_hp = 0
		cell.color_id = CellData.COLOR_EMPTY
		return true
	return false

## Encases a plain colored piece in ice (Freeze power's ring effect). No-op
## on empty / stone / powered / already-obstructed / locked cells. Returns
## true if a piece was frozen.
func freeze_cell(pos: Vector2i, hp: int = 2) -> bool:
	var cell := get_cell(pos)
	if cell == null or cell.is_empty() or cell.is_stone() or cell.has_power() or cell.has_obstacle() or cell.locked_empty:
		return false
	cell.obstacle_id = &"ice"
	cell.obstacle_hp = hp
	return true

## Clears a time-bomb's countdown without detonating it — used when the
## piece occupying the time-bomb cell is cleared by a match or blast.
func defuse_timebomb(pos: Vector2i) -> bool:
	var cell := get_cell(pos)
	if cell == null or not cell.is_timebomb():
		return false
	cell.obstacle_id = CellData.OBSTACLE_NONE
	cell.obstacle_hp = 0
	return true

## Decrements one time-bomb's countdown by a turn. Returns true if it just
## reached zero (the caller detonates it).
func tick_timebomb(pos: Vector2i) -> bool:
	var cell := get_cell(pos)
	if cell == null or not cell.is_timebomb():
		return false
	cell.obstacle_hp -= 1
	return cell.obstacle_hp <= 0

func timebomb_positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in width:
		for y in height:
			if _grid[x][y].is_timebomb():
				out.append(Vector2i(x, y))
	return out

## Whenever a cell clears, orthogonal Lock neighbors take one hit and may
## unlock. Returns the list of newly-unlocked positions.
func unlock_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var unlocked: Array[Vector2i] = []
	for n in get_orthogonal_neighbors(pos):
		var cell := get_cell(n)
		if cell != null and cell.is_lock():
			cell.obstacle_hp -= 1
			if cell.obstacle_hp <= 0:
				cell.obstacle_id = CellData.OBSTACLE_NONE
				cell.obstacle_hp = 0
				cell.locked_empty = false
				unlocked.append(n)
	return unlocked

## Compacts pieces downward per column, stopping at stone/locked blockers.
## Escort specials (&"relic") fall the same way; any special that ends up in
## the bottom row is DELIVERED (removed) on this same pass.
##
## Returns the list of moves for the view layer to animate. A plain piece
## move is `{from, to}`; a special that moved carries `special`; a special
## that was delivered carries `{from, to, special, delivered = true}` with
## `to` == the bottom-row cell it left from.
func apply_gravity() -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for x in width:
		var write_y := height - 1
		for y in range(height - 1, -1, -1):
			var cell: CellData = _grid[x][y]
			if cell.is_stone() or cell.locked_empty:
				write_y = y - 1
				continue
			if not cell.has_movable_content():
				continue
			if y != write_y:
				var target: CellData = _grid[x][write_y]
				target.color_id = cell.color_id
				target.power_id = cell.power_id
				target.special_id = cell.special_id
				var was_special := cell.has_special()
				cell.color_id = CellData.COLOR_EMPTY
				cell.power_id = CellData.POWER_NONE
				cell.special_id = CellData.SPECIAL_NONE
				var m := {"from": Vector2i(x, y), "to": Vector2i(x, write_y)}
				if was_special:
					m["special"] = target.special_id
				moves.append(m)
			write_y -= 1
		# deliver any special that has come to rest in the bottom row
		var bottom: CellData = _grid[x][height - 1]
		if bottom.has_special():
			var sid := bottom.special_id
			bottom.special_id = CellData.SPECIAL_NONE
			moves.append({
				"from": Vector2i(x, height - 1), "to": Vector2i(x, height - 1),
				"special": sid, "delivered": true,
			})
	return moves

## Fills empty, fillable cells (top rows after gravity) with new pieces.
func refill(rng: RandomNumberGenerator, available_colors: Array[StringName], rainbow_chance: float = 0.0) -> Array[Vector2i]:
	var filled: Array[Vector2i] = []
	for x in width:
		for y in height:
			var cell: CellData = _grid[x][y]
			if cell.is_empty() and not cell.is_stone() and not cell.locked_empty and not cell.has_special():
				if rainbow_chance > 0.0 and rng.randf() < rainbow_chance:
					cell.color_id = RAINBOW_COLOR_ID
				else:
					cell.color_id = available_colors[rng.randi_range(0, available_colors.size() - 1)]
				filled.append(Vector2i(x, y))
	return filled

## Flood-fills the same-color (Rainbow-wildcard-aware) connected group
## containing `start`, via orthogonal steps. Cells currently holding a
## power (has_power()) are treated as boundaries, not members — a power
## tile is always resolved through its own detonation, never swept into a
## plain clear. Returns [] if `start` itself isn't a plain selectable
## colored piece. Used both for move-availability checks and for
## ChainResolver's "does this blast expose a fresh cluster" auto-chain scan.
func find_connected_group(start: Vector2i) -> Array[Vector2i]:
	var start_cell := get_cell(start)
	if start_cell == null or not start_cell.is_selectable() or start_cell.has_power():
		return []
	var target := start_cell.color_id
	var visited := {start: true}
	var stack: Array[Vector2i] = [start]
	var members: Array[Vector2i] = [start]
	while not stack.is_empty():
		var pos: Vector2i = stack.pop_back()
		for n in get_orthogonal_neighbors(pos):
			if visited.has(n):
				continue
			var ncell := get_cell(n)
			if ncell == null or not ncell.is_selectable() or ncell.has_power():
				continue
			if ncell.color_id != target and ncell.color_id != RAINBOW_COLOR_ID and target != RAINBOW_COLOR_ID:
				continue
			visited[n] = true
			stack.append(n)
			members.append(n)
	return members

## True if no valid connect-3 move currently exists anywhere on the board.
## Used to trigger an automatic reshuffle rather than stranding the player.
func has_any_valid_move() -> bool:
	for x in width:
		for y in height:
			if find_connected_group(Vector2i(x, y)).size() >= min_group_size:
				return true
	return false
