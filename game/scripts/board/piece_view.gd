class_name PieceView
extends Node2D
## Draws one board cell: the colored gem piece (if any), its power icon,
## and any obstacle overlay (ice/lock/stone). Pure vector drawing — no
## texture assets required, so it stays lightweight and easy to reskin.

var color_id: StringName = CellData.COLOR_EMPTY
var power_id: StringName = CellData.POWER_NONE
var obstacle_id: StringName = CellData.OBSTACLE_NONE
var obstacle_hp: int = 0
var cell_size: float = 64.0
var selected: bool = false

var _base_color: Color = Color(0.6, 0.6, 0.6)
var _accent_color: Color = Color(0.9, 0.9, 0.9)
var _glow_color: Color = Color(1.0, 1.0, 1.0)

const _RAINBOW_ARC_COLORS := [
	Color(0.9, 0.25, 0.35), Color(0.95, 0.6, 0.15), Color(0.95, 0.85, 0.2),
	Color(0.25, 0.7, 0.4), Color(0.25, 0.5, 0.9), Color(0.55, 0.3, 0.85),
]

func configure(p_color_id: StringName, p_power_id: StringName, p_obstacle_id: StringName, p_obstacle_hp: int, p_cell_size: float, palette: PieceColorPalette) -> void:
	color_id = p_color_id
	power_id = p_power_id
	obstacle_id = p_obstacle_id
	obstacle_hp = p_obstacle_hp
	cell_size = p_cell_size
	if palette != null and palette.has(color_id):
		var def := palette.get_def(color_id)
		_base_color = def.base_color
		_accent_color = def.accent_color
		_glow_color = def.glow_color
	queue_redraw()

func set_selected(value: bool) -> void:
	if selected != value:
		selected = value
		queue_redraw()

func _draw() -> void:
	if color_id == CellData.COLOR_EMPTY and obstacle_id == CellData.OBSTACLE_NONE:
		return

	var size := Vector2(cell_size, cell_size) * 0.86
	var shifted := ShapeDrawUtils.rounded_rect_points(size, size.x * 0.28)

	if color_id == CellData.COLOR_EMPTY:
		_draw_obstacle_only(shifted, size)
		return

	var shadow := PackedVector2Array()
	for p in shifted:
		shadow.append(p + Vector2(0, size.y * 0.07))
	var shadow_color := _base_color.darkened(0.5)
	shadow_color.a = 0.45
	draw_colored_polygon(shadow, shadow_color)

	if color_id == BoardModel.RAINBOW_COLOR_ID:
		_draw_rainbow_body(shifted, size)
	else:
		draw_colored_polygon(shifted, _base_color)

	var gloss_color := _accent_color
	gloss_color.a = 0.4
	draw_circle(Vector2(-size.x * 0.16, -size.y * 0.22), size.x * 0.22, gloss_color)

	if obstacle_id == &"ice":
		_draw_ice_overlay(shifted, size)

	if power_id != CellData.POWER_NONE:
		_draw_power_icon(size)

	if selected:
		var ring := shifted.duplicate()
		ring.append(shifted[0])
		draw_polyline(ring, _glow_color, size.x * 0.06, true)

func _draw_rainbow_body(shifted: PackedVector2Array, size: Vector2) -> void:
	draw_colored_polygon(shifted, Color(0.95, 0.95, 0.98))
	var band_count := _RAINBOW_ARC_COLORS.size()
	for i in band_count:
		var r := size.x * 0.44 * (1.0 - float(i) / float(band_count) * 0.75)
		var col: Color = _RAINBOW_ARC_COLORS[i]
		col.a = 0.85
		draw_arc(Vector2(0, size.y * 0.12), r, PI, TAU, 20, col, size.x * 0.06, true)

func _draw_obstacle_only(shifted: PackedVector2Array, size: Vector2) -> void:
	if obstacle_id == &"stone":
		draw_colored_polygon(shifted, Color(0.42, 0.44, 0.5))
		var crack := Color(0.25, 0.27, 0.32, 0.85)
		draw_line(Vector2(-size.x * 0.2, -size.y * 0.12), Vector2(size.x * 0.08, size.y * 0.18), crack, 3.0)
		draw_line(Vector2(size.x * 0.04, -size.y * 0.24), Vector2(-size.x * 0.14, size.y * 0.04), crack, 3.0)
	elif obstacle_id == &"lock":
		draw_colored_polygon(shifted, Color(0.32, 0.34, 0.4))
		draw_arc(Vector2(0, -size.y * 0.1), size.x * 0.16, PI, TAU, 16, Color(0.85, 0.85, 0.92), 3.0, true)
		var body_size := Vector2(size.x * 0.32, size.y * 0.24)
		draw_rect(Rect2(-body_size * 0.5 + Vector2(0, size.y * 0.06), body_size), Color(0.85, 0.85, 0.92))

func _draw_ice_overlay(shifted: PackedVector2Array, size: Vector2) -> void:
	var alpha := 0.55 if obstacle_hp >= 2 else 0.28
	var ice_color := Color(0.75, 0.9, 1.0, alpha)
	draw_colored_polygon(shifted, ice_color)
	var crack_color := Color(1, 1, 1, 0.7)
	draw_line(Vector2(-size.x * 0.15, -size.y * 0.2), Vector2(size.x * 0.05, size.y * 0.05), crack_color, 2.0)
	if obstacle_hp >= 2:
		draw_line(Vector2(size.x * 0.1, -size.y * 0.05), Vector2(-size.x * 0.05, size.y * 0.22), crack_color, 2.0)

func _draw_power_icon(size: Vector2) -> void:
	match power_id:
		&"bomb":
			draw_circle(Vector2.ZERO, size.x * 0.22, Color(0.12, 0.12, 0.15, 0.92))
			draw_line(Vector2(0, -size.y * 0.22), Vector2(size.x * 0.12, -size.y * 0.36), Color(1, 0.6, 0.1), 3.0)
			draw_circle(Vector2(size.x * 0.12, -size.y * 0.38), size.x * 0.05, Color(1, 0.82, 0.25))
		&"lightning":
			var pts := PackedVector2Array([
				Vector2(-size.x * 0.05, -size.y * 0.32), Vector2(size.x * 0.1, -size.y * 0.02),
				Vector2(-size.x * 0.01, -size.y * 0.02), Vector2(size.x * 0.06, size.y * 0.32),
				Vector2(-size.x * 0.12, size.y * 0.02), Vector2(size.x * 0.0, size.y * 0.02),
			])
			draw_colored_polygon(pts, Color(1, 0.92, 0.3))
		&"chain":
			draw_arc(Vector2(-size.x * 0.1, 0), size.x * 0.16, 0, TAU, 16, Color(1, 1, 1, 0.95), size.x * 0.045, true)
			draw_arc(Vector2(size.x * 0.1, 0), size.x * 0.16, 0, TAU, 16, Color(1, 1, 1, 0.95), size.x * 0.045, true)
		_:
			pass
