class_name PowerResolver
extends RefCounted
## Pure computation of which cells a power activation affects. Does not
## mutate the board — callers apply the resulting cell list. Keeping this
## separate from ChainResolver makes each power's area effect independently
## testable and easy to extend with new power types.

static func affected_cells(board: BoardModel, pos: Vector2i, power_id: StringName, horizontal: bool, source_color: StringName, definition: Dictionary) -> Array[Vector2i]:
	match power_id:
		&"bomb":
			return _bomb_cells(board, pos, int(definition.get("radius", 1)))
		&"lightning":
			return _line_cells(board, pos, horizontal)
		&"freeze":
			return _diamond_cells(board, pos, int(definition.get("radius", 1)))
		&"chain":
			return _color_cells(board, source_color)
		&"rainbow":
			return _color_cells(board, source_color)
		_:
			return []

## The hex ring at exactly `distance` steps from `pos` (BFS on the honeycomb
## neighbour graph). distance 0 = just `pos`.
static func hex_ring(board: BoardModel, pos: Vector2i, distance: int) -> Array[Vector2i]:
	var dist := {pos: 0}
	var frontier: Array[Vector2i] = [pos]
	for step in distance:
		var next: Array[Vector2i] = []
		for p in frontier:
			for n in board.get_neighbors(p):
				if not dist.has(n):
					dist[n] = step + 1
					next.append(n)
		frontier = next
	var out: Array[Vector2i] = []
	for k in dist.keys():
		if dist[k] == distance:
			out.append(k)
	return out

## Every cell within `radius` hex steps of `pos` (inclusive).
static func hex_disc(board: BoardModel, pos: Vector2i, radius: int) -> Array[Vector2i]:
	var dist := {pos: 0}
	var frontier: Array[Vector2i] = [pos]
	var out: Array[Vector2i] = [pos]
	for step in radius:
		var next: Array[Vector2i] = []
		for p in frontier:
			for n in board.get_neighbors(p):
				if not dist.has(n):
					dist[n] = step + 1
					next.append(n)
					out.append(n)
		frontier = next
	return out

## Freeze shatters a small hex disc, then encases the ring one step further
## out — see ChainResolver, which applies the ring.
static func freeze_ring_cells(board: BoardModel, pos: Vector2i, radius: int = 1) -> Array[Vector2i]:
	return hex_ring(board, pos, radius + 1)

static func _diamond_cells(board: BoardModel, pos: Vector2i, radius: int) -> Array[Vector2i]:
	return hex_disc(board, pos, radius)

static func _bomb_cells(board: BoardModel, pos: Vector2i, radius: int) -> Array[Vector2i]:
	return hex_disc(board, pos, radius)

static func _line_cells(board: BoardModel, pos: Vector2i, horizontal: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if horizontal:
		for x in board.width:
			cells.append(Vector2i(x, pos.y))
	else:
		for y in board.height:
			cells.append(Vector2i(pos.x, y))
	return cells

static func _color_cells(board: BoardModel, color_id: StringName) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if color_id == BoardModel.RAINBOW_COLOR_ID or color_id == CellData.COLOR_EMPTY:
		return cells
	for x in board.width:
		for y in board.height:
			var cell := board.get_cell(Vector2i(x, y))
			if cell != null and cell.color_id == color_id:
				cells.append(Vector2i(x, y))
	return cells
