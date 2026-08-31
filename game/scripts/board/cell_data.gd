class_name CellData
extends RefCounted
## A single board cell: the piece occupying it (if any), its power type,
## and any obstacle layered on top. Pure data, no engine dependencies.

const COLOR_EMPTY: StringName = &""
const POWER_NONE: StringName = &"none"
const OBSTACLE_NONE: StringName = &"none"

var color_id: StringName = COLOR_EMPTY
var power_id: StringName = POWER_NONE
var obstacle_id: StringName = OBSTACLE_NONE
var obstacle_hp: int = 0
## True once a lock obstacle has been fully unlocked and can be refilled.
var locked_empty: bool = false

func is_empty() -> bool:
	return color_id == COLOR_EMPTY

func has_power() -> bool:
	return power_id != POWER_NONE

func has_obstacle() -> bool:
	return obstacle_id != OBSTACLE_NONE

func is_stone() -> bool:
	return obstacle_id == &"stone"

func is_ice() -> bool:
	return obstacle_id == &"ice"

func is_lock() -> bool:
	return obstacle_id == &"lock"

## A time-bomb cell holds a normal piece AND a countdown (stored in
## obstacle_hp). Clearing the piece defuses it; letting the countdown reach
## zero detonates it. See BoardModel.tick_timebomb / defuse_timebomb.
func is_timebomb() -> bool:
	return obstacle_id == &"timebomb"

## A stone cell blocks connect-selection and holds no piece.
func is_selectable() -> bool:
	if is_empty():
		return false
	if is_stone():
		return false
	if locked_empty:
		return false
	return true

func clear_piece() -> void:
	color_id = COLOR_EMPTY
	power_id = POWER_NONE

func duplicate_cell() -> CellData:
	var c := CellData.new()
	c.color_id = color_id
	c.power_id = power_id
	c.obstacle_id = obstacle_id
	c.obstacle_hp = obstacle_hp
	c.locked_empty = locked_empty
	return c
