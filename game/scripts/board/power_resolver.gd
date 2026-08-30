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
		&"chain":
			return _color_cells(board, source_color)
		&"rainbow":
			return _color_cells(board, source_color)
		_:
			return []

static func _bomb_cells(board: BoardModel, pos: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var p := pos + Vector2i(dx, dy)
			if board.in_bounds(p):
				cells.append(p)
	return cells

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
