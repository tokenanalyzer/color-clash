class_name InfiniteLevelScroller
extends Control
## VISUAL + INPUT layer of one island's vertical level map. Owns a BOUNDED
## pool of IslandLevelNode children (never grows) and drives it from the pure
## InfiniteScrollModel: scrolling only moves a float offset, and every frame
## the model says which world-local level indices belong on screen and where.
## A node that scrolls out is not freed — it is re-assigned to the next
## logical level (new number, new cycled part, new position, new state).
##
## The island exposes WorldCatalog.levels_per_world() levels (100); the pool
## stays == POOL_SIZE no matter how far you scroll. Progression + lock state
## come from IslandProgress via WorldCatalog.

signal level_chosen(world_id: StringName, local_level: int)
signal inert_level_tapped(local_level: int)   # a locked node

const POOL_SIZE := 9
const _FLING_SCALE := 46.0
const _FRICTION := 0.90
## Pointer travel (px) past which a touch is a scroll, not a level tap.
const _TAP_SLOP := 18.0

var _world_id: StringName = &""
var _model: InfiniteScrollModel
var _nodes: Array[IslandLevelNode] = []
var _part_cache: Array = []                  # 5 Texture2D (or null), by part_index
var _scroll_offset := 0.0
var _vel := 0.0
var _dragging := false
var _part_w := 300.0
var _press_pos := Vector2.ZERO
var _press_moved := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_model = InfiniteScrollModel.new()
	for i in POOL_SIZE:
		var n := IslandLevelNode.new()
		add_child(n)
		_nodes.append(n)
	set_process(true)
	get_viewport().size_changed.connect(_on_resized)

## Point the pool at a world. Resolves + caches that world's five reusable
## part textures once (no per-scroll texture load/unload), sizes the layout to
## the viewport, and jumps to the player's current level in this world.
func setup(world_id: StringName) -> void:
	_world_id = world_id
	_part_cache.clear()
	var max_aspect := 1.0
	for pi in WorldCatalog.PARTS_PER_WORLD:
		var t := WorldCatalog.part_texture(world_id, pi + 1)   # +1 -> local level, part_index = pi
		_part_cache.append(t)
		if t != null and t.get_width() > 0:
			max_aspect = maxf(max_aspect, float(t.get_height()) / float(t.get_width()))
	_recompute_metrics(max_aspect)
	_scroll_offset = _model.offset_to_focus(WorldCatalog.focus_local_level(world_id), _view_h(), 0.35)
	_vel = 0.0
	_refresh_pool()

func _view_h() -> float:
	return maxf(size.y, get_viewport_rect().size.y)

func _recompute_metrics(max_part_aspect: float) -> void:
	var vw := maxf(size.x, get_viewport_rect().size.x)
	_part_w = clampf(vw * 0.52, 220.0, 460.0)
	# Row spacing must clear the tallest part + a real gap so consecutive
	# islands never collide (the zig-zag also pulls them apart sideways).
	_model.row_spacing = _part_w * max_part_aspect * 0.92 + _part_w * 0.30
	_model.pool_size = POOL_SIZE
	_model.buffer_rows = 2
	_model.min_index = 1
	_model.max_index = WorldCatalog.levels_per_world()
	_model.top_margin = clampf(_view_h() * 0.12, 120.0, 260.0)
	_model.bottom_margin = _model.row_spacing * 0.8

func _on_resized() -> void:
	if _world_id == &"":
		return
	var max_aspect := 1.0
	for t in _part_cache:
		if t != null and t.get_width() > 0:
			max_aspect = maxf(max_aspect, float(t.get_height()) / float(t.get_width()))
	var focus_idx := _model.first_index(_scroll_offset, _view_h()) + _model.buffer_rows + 1
	_recompute_metrics(max_aspect)
	_scroll_offset = _model.offset_to_focus(focus_idx, _view_h(), 0.35)
	_refresh_pool()

# ------------------------------------------------------------- input --

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed:
				_vel = 0.0
				_scroll_offset = _model.clamp_offset(_scroll_offset
					+ (-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * _model.row_spacing * 0.5, _view_h())
				_refresh_pool()
			return
		if event.pressed:
			_dragging = true
			_vel = 0.0
			_press_pos = event.position
			_press_moved = false
		else:
			_dragging = false
			# A touch that never travelled past the slop is a level tap.
			if not _press_moved:
				_try_tap_at(event.position)
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		if event.position.distance_to(_press_pos) > _TAP_SLOP:
			_press_moved = true
		_scroll_offset = _model.clamp_offset(_scroll_offset - event.relative.y, _view_h())
		_vel = lerpf(_vel, -event.relative.y * _FLING_SCALE, 0.5)
		_refresh_pool()

func _process(delta: float) -> void:
	if _dragging or absf(_vel) < 4.0:
		return
	var before := _scroll_offset
	_scroll_offset = _model.clamp_offset(_scroll_offset + _vel * delta, _view_h())
	if is_equal_approx(before, _scroll_offset):
		_vel = 0.0
	_vel *= _FRICTION
	_refresh_pool()

# --------------------------------------------------------- pool sync --

func _refresh_pool() -> void:
	if _model == null or _nodes.is_empty():
		return
	var vw := maxf(size.x, get_viewport_rect().size.x)
	var plan := _model.layout(_scroll_offset, _view_h())
	var x_off := clampf(vw * 0.16, 40.0, 132.0)
	var i := 0
	for entry in plan:
		if i >= _nodes.size():
			break
		var idx := int(entry["index"])
		var node := _nodes[i]
		var part_tex: Texture2D = _part_cache[WorldCatalog.part_index(idx)] if not _part_cache.is_empty() else null
		var st := WorldCatalog.node_state(_world_id, idx)
		var stars := WorldCatalog.node_stars(_world_id, idx)
		var routable := WorldCatalog.is_level_unlocked(_world_id, idx)
		var aspect := 1.0
		if part_tex != null and part_tex.get_width() > 0:
			aspect = float(part_tex.get_height()) / float(part_tex.get_width())
		var box := Vector2(_part_w, _part_w * aspect)
		node.assign(idx, part_tex, st, stars, routable, box)
		# zig-zag: 1 -> LEFT, 2 -> RIGHT, ... anchored on the viewport centre.
		var side := float(WorldCatalog.zigzag_side(idx))
		var cx := vw * 0.5 + side * x_off
		var px := clampf(cx - box.x * 0.5, 12.0, maxf(vw - box.x - 12.0, 12.0))
		node.position = Vector2(px, float(entry["y"]) - box.y * 0.5)
		node.visible = true
		i += 1
	while i < _nodes.size():
		_nodes[i].visible = false
		i += 1

## Route a settled tap at `local_pos` (scroller space) to whichever visible
## pooled node it landed on (island art + board rect). Water taps are ignored.
func _try_tap_at(local_pos: Vector2) -> void:
	for node in _nodes:
		if node.visible and Rect2(node.position, node.hit_rect().size).has_point(local_pos):
			_on_node_clicked(node.local_level)
			return

func _on_node_clicked(local_level: int) -> void:
	Audio.play(&"button_tap")
	if WorldCatalog.is_level_unlocked(_world_id, local_level):
		level_chosen.emit(_world_id, local_level)
	else:
		inert_level_tapped.emit(local_level)

# ---------------------------------------------------- test / introspection --

## Number of pooled visual objects that currently exist (always POOL_SIZE
## once ready — used by the far-scroll performance test).
func live_node_count() -> int:
	return _nodes.size()

func visible_node_count() -> int:
	var n := 0
	for node in _nodes:
		if node.visible:
			n += 1
	return n

## The logical level indices currently mounted on the pool, in view order.
func visible_indices() -> Array[int]:
	var out: Array[int] = []
	for node in _nodes:
		if node.visible:
			out.append(node.local_level)
	return out

func scroll_offset() -> float:
	return _scroll_offset

## Test hook: jump straight to a world-local level and re-sync the pool.
func debug_scroll_to_local_level(local_level: int) -> void:
	_scroll_offset = _model.offset_to_focus(local_level, _view_h(), 0.35)
	_refresh_pool()
