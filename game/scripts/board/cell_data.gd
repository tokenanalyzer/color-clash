class_name CellData
extends RefCounted
## A single board cell: the piece occupying it (if any), its power type,
## and any obstacle layered on top. Pure data, no engine dependencies.

const COLOR_EMPTY: StringName = &""
const POWER_NONE: StringName = &"none"
const OBSTACLE_NONE: StringName = &"none"
const SPECIAL_NONE: StringName = &""

var color_id: StringName = COLOR_EMPTY
var power_id: StringName = POWER_NONE
var obstacle_id: StringName = OBSTACLE_NONE
var obstacle_hp: int = 0
## An escort object riding this cell (currently only &"relic" — the Love
## Crystal the player must bring safely to the bottom of the board). A
## special holds NO colour piece, is never selectable for a connection, and
## is never destroyed by a clear/blast — it only ever moves: it falls with
## gravity like a piece, and is DELIVERED (removed, counts toward a
## `deliver` objective) once it reaches the bottom row. See BoardModel.
var special_id: StringName = SPECIAL_NONE
## True once a lock obstacle has been fully unlocked and can be refilled.
var locked_empty: bool = false

func is_empty() -> bool:
	return color_id == COLOR_EMPTY

func has_power() -> bool:
	return power_id != POWER_NONE

func has_obstacle() -> bool:
	return obstacle_id != OBSTACLE_NONE

func has_special() -> bool:
	return special_id != SPECIAL_NONE

## Anything gravity should carry down a column: a colour piece OR an escort
## special. (A special cell reports is_empty() == true because it holds no
## colour, so gravity code must ask this, not is_empty().)
func has_movable_content() -> bool:
	return not is_empty() or has_special()

## Obstacle "family" — the underlying mechanic a themed obstacle id reuses.
## The 2026-09-05 difficulty pass introduced new named blockers for variety
## (Wooden Crate, Reinforced Crate, Frozen Crystal, Magic Chain, Cursed
## Stone, Shadow Barrier, Dark Rune) without inventing new mechanics — each
## maps onto one of the 4 proven families below, so every existing engine
## code path (selectability, gravity, refill, damage, unlock) keeps working
## unchanged. Any id not listed maps to itself (so `stone`/`ice`/`lock`/
## `timebomb` still work directly).
const _FAMILY := {
	&"stone": &"stone", &"cursed_stone": &"stone", &"shadow_barrier": &"stone",
	&"ice": &"ice", &"wooden_crate": &"ice", &"reinforced_crate": &"ice", &"frozen_crystal": &"ice",
	&"lock": &"lock", &"magic_chain": &"lock",
	&"timebomb": &"timebomb", &"dark_rune": &"timebomb",
}

static func family_of(obstacle_id: StringName) -> StringName:
	return _FAMILY.get(obstacle_id, obstacle_id)

## "Stone family" blocks connect-selection, holds no piece, and only breaks
## via a power's blast area (see BoardModel.damage_stone). Shadow Barrier is
## the one id in this family with a real hp (2) instead of always 1-hit.
func is_stone() -> bool:
	return family_of(obstacle_id) == &"stone"

## "Ice family" holds a normal piece underneath and is damaged by ANY clear
## or blast that reaches it (see BoardModel.damage_ice) — hp tiers this
## family from a 1-hit Wooden Crate up to a 3-hit Reinforced Crate.
func is_ice() -> bool:
	return family_of(obstacle_id) == &"ice"

## "Lock family" holds no piece; only chips down when an adjacent cell
## clears (see BoardModel.unlock_neighbors) — never damaged directly.
func is_lock() -> bool:
	return family_of(obstacle_id) == &"lock"

## "Timebomb family" holds a normal piece AND a countdown (stored in
## obstacle_hp). Clearing the piece defuses it; letting the countdown reach
## zero detonates it. See BoardModel.tick_timebomb / defuse_timebomb.
func is_timebomb() -> bool:
	return family_of(obstacle_id) == &"timebomb"

## A stone cell blocks connect-selection and holds no piece.
func is_selectable() -> bool:
	if is_empty():
		return false
	if is_stone():
		return false
	if has_special():
		return false
	if locked_empty:
		return false
	return true

func clear_piece() -> void:
	color_id = COLOR_EMPTY
	power_id = POWER_NONE

func clear_special() -> void:
	special_id = SPECIAL_NONE

func duplicate_cell() -> CellData:
	var c := CellData.new()
	c.color_id = color_id
	c.power_id = power_id
	c.obstacle_id = obstacle_id
	c.obstacle_hp = obstacle_hp
	c.special_id = special_id
	c.locked_empty = locked_empty
	return c
