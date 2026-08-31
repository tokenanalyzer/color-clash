class_name PieceView
extends Node2D
## Draws one board cell. The jewel body is a BAKED texture (see
## GemTextures) blitted as a single quad — sharp at any phone resolution
## and far cheaper than per-frame vector drawing — with a shared soft
## shadow beneath it. Power icons, obstacle overlays and the selection
## glow are drawn on top.
##
## Only power / time-bomb tiles run _process (an idle glow pulse); plain
## gems are fully static between board changes, so a full board costs one
## textured quad each and nothing per frame.

var color_id: StringName = CellData.COLOR_EMPTY
var power_id: StringName = CellData.POWER_NONE
var obstacle_id: StringName = CellData.OBSTACLE_NONE
var obstacle_hp: int = 0
var cell_size: float = 64.0
var selected: bool = false

var _base := Color(0.6, 0.6, 0.6)
var _deep := Color(0.35, 0.35, 0.35)
var _accent := Color(0.9, 0.9, 0.9)
var _rim := Color(1, 1, 1)
var _glow := Color(1, 1, 1)
var _phase := 0.0
var _palette: PieceColorPalette

const _SPECTRUM := [
	Color(0.96, 0.26, 0.38), Color(1.0, 0.6, 0.2), Color(1.0, 0.87, 0.28),
	Color(0.3, 0.82, 0.5), Color(0.28, 0.6, 0.98), Color(0.66, 0.36, 0.95),
]

## Fixed identity colour per power (Bomb=Red, Lightning=Yellow, Freeze=Blue,
## Rainbow=Purple, Chain=Green) — matches the reference's special-tile set.
const _POWER_BODY := {
	&"bomb": Color(0.85, 0.16, 0.24),
	&"lightning": Color(0.98, 0.72, 0.12),
	&"freeze": Color(0.24, 0.68, 0.98),
	&"rainbow": Color(0.62, 0.34, 0.94),
	&"chain": Color(0.18, 0.78, 0.44),
}
const _POWER_GLOW := {
	&"bomb": Color(1.0, 0.35, 0.3),
	&"lightning": Color(1.0, 0.9, 0.35),
	&"freeze": Color(0.6, 0.9, 1.0),
	&"rainbow": Color(0.9, 0.6, 1.0),
	&"chain": Color(0.4, 1.0, 0.6),
}

func configure(p_color_id: StringName, p_power_id: StringName, p_obstacle_id: StringName, p_obstacle_hp: int, p_cell_size: float, palette: PieceColorPalette) -> void:
	color_id = p_color_id
	power_id = p_power_id
	obstacle_id = p_obstacle_id
	obstacle_hp = p_obstacle_hp
	cell_size = p_cell_size
	_palette = palette
	if palette != null and palette.has(color_id):
		var d := palette.get_def(color_id)
		_base = d.base_color
		_deep = d.deep_color
		_accent = d.accent_color
		_rim = d.rim_color
		_glow = d.glow_color
	_update_processing()
	queue_redraw()

func _update_processing() -> void:
	set_process(power_id != CellData.POWER_NONE or obstacle_id == &"timebomb")

func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()

func set_selected(value: bool) -> void:
	if selected != value:
		selected = value
		queue_redraw()

# ------------------------------------------------------------------ draw --

## Texture is [RES + 2*PAD] square with the jewel filling RES; blit it so
## the jewel body is ~cell_size * 0.94 wide.
const _BLIT := 1.09

func _blit_rect() -> Rect2:
	var s := cell_size * _BLIT
	return Rect2(-s * 0.5, -s * 0.5, s, s)

func _blit_gem(tex: Texture2D) -> void:
	if tex == null:
		_draw_gem(_accent.lerp(_base, 0.15), _base, _base.lerp(_deep, 0.55), _rim, _glow)
		return
	var r := _blit_rect()
	# soft contact shadow
	var sh := GemTextures.shadow()
	if sh != null:
		var sc := cell_size * 1.02
		draw_texture_rect(sh, Rect2(-sc * 0.5, -sc * 0.5 + cell_size * 0.12, sc, sc), false, Color(0, 0, 0, 0.5))
	draw_texture_rect(tex, r, false)

func _draw() -> void:
	var has_piece := color_id != CellData.COLOR_EMPTY
	if not has_piece and obstacle_id == CellData.OBSTACLE_NONE:
		return

	if obstacle_id == &"stone":
		_draw_stone()
		return
	if obstacle_id == &"lock" and not has_piece:
		_draw_lock()
		return

	if power_id != CellData.POWER_NONE:
		_draw_power_gem()
	elif color_id == BoardModel.RAINBOW_COLOR_ID:
		_draw_rainbow_gem()
	elif has_piece:
		_blit_gem(GemTextures.gem(color_id, _palette))

	if obstacle_id == &"ice":
		_draw_ice_overlay()
	elif obstacle_id == &"timebomb":
		_draw_timebomb_overlay()

	if selected:
		_draw_selection()

## The core faceted-gem body used by every coloured piece.
func _draw_gem(c_top: Color, c_mid: Color, c_deep: Color, c_rim: Color, c_glow: Color, glow_boost := 1.0) -> void:
	var body := ShapeDrawUtils.gem_points(cell_size)

	# soft contact shadow (two offset layers for a cheap blur)
	var s1 := _translated(body, Vector2(0, cell_size * 0.11))
	var s2 := _translated(body, Vector2(0, cell_size * 0.06))
	draw_colored_polygon(s1, Color(0, 0, 0, 0.20))
	draw_colored_polygon(s2, Color(0, 0, 0, 0.28))

	# body gradient, lit from above
	draw_polygon(body, ShapeDrawUtils.vertical_shade(body, c_top, c_deep))

	# faceted cuts: alternating light / dark wedges from the centre
	var n := 6
	var outer := ShapeDrawUtils.regular_polygon(n, cell_size * 0.42, PI / 6.0)
	for i in n:
		var a: Vector2 = outer[i]
		var b: Vector2 = outer[(i + 1) % n]
		var wedge := PackedVector2Array([Vector2.ZERO, a, b])
		var lit := (i == 4 or i == 5) # upper-left facets catch the light
		var shade := Color(1, 1, 1, 0.14) if lit else Color(0, 0, 0, 0.07)
		draw_colored_polygon(wedge, shade)

	# inner colour bloom
	VisualTheme.draw_glow(self, Vector2(0, cell_size * 0.02), cell_size * 0.24, Color(c_glow.r, c_glow.g, c_glow.b, 0.22 * glow_boost), 4)

	# top gloss highlight
	var gloss := ShapeDrawUtils.regular_polygon(14, 1.0, 0.0, Vector2(-cell_size * 0.08, -cell_size * 0.2))
	var scaled := PackedVector2Array()
	for p in gloss:
		scaled.append(Vector2((p.x + cell_size * 0.08) * cell_size * 0.24 - cell_size * 0.08,
			(p.y + cell_size * 0.2) * cell_size * 0.12 - cell_size * 0.2))
	draw_colored_polygon(scaled, Color(c_rim.r, c_rim.g, c_rim.b, 0.55))
	draw_circle(Vector2(-cell_size * 0.14, -cell_size * 0.24), cell_size * 0.05, Color(1, 1, 1, 0.85))

	# crisp rim
	var ring := body.duplicate()
	ring.append(body[0])
	draw_polyline(ring, Color(c_rim.r, c_rim.g, c_rim.b, 0.5), max(cell_size * 0.028, 1.5), true)

func _draw_rainbow_gem() -> void:
	_blit_gem(GemTextures.gem(BoardModel.RAINBOW_COLOR_ID, _palette))
	var spin := _phase * 0.6
	for i in _SPECTRUM.size():
		var r := cell_size * (0.30 - float(i) * 0.028)
		var col: Color = _SPECTRUM[i]
		col.a = 0.85
		draw_arc(Vector2.ZERO, r, spin + TAU * float(i) / 6.0, spin + TAU * float(i) / 6.0 + 2.2, 14, col, max(cell_size * 0.05, 2.0), true)

func _draw_power_gem() -> void:
	var body_col: Color = _POWER_BODY.get(power_id, _base)
	var glow_col: Color = _POWER_GLOW.get(power_id, _glow)
	var pulse := 0.7 + 0.3 * sin(_phase * 4.5)
	var slow := 0.5 + 0.5 * sin(_phase * 1.8)

	# double aura — a wide breathing halo + a tighter bright core glow
	var g := GemTextures.glow()
	if g != null:
		var gs1 := cell_size * (2.2 + 0.35 * slow)
		draw_texture_rect(g, Rect2(-gs1 * 0.5, -gs1 * 0.5, gs1, gs1), false,
			Color(glow_col.r, glow_col.g, glow_col.b, 0.22 + 0.12 * slow))
		var gs2 := cell_size * (1.35 + 0.2 * pulse)
		draw_texture_rect(g, Rect2(-gs2 * 0.5, -gs2 * 0.5, gs2, gs2), false,
			Color(glow_col.r, glow_col.g, glow_col.b, 0.35 * pulse))

	# a light "lift" so power tiles read as raised above the plain jewels
	var lift := Vector2(0, -cell_size * 0.03 * pulse)
	draw_set_transform(lift, 0.0, Vector2.ONE)
	_blit_gem(GemTextures.solid_gem(StringName("__pow_" + String(power_id)), body_col))

	match power_id:
		&"bomb": _icon_bomb(pulse)
		&"lightning": _icon_lightning(pulse)
		&"freeze": _icon_freeze()
		&"rainbow": _icon_rainbow()
		&"chain": _icon_chain(pulse)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# orbiting energy sparks
	for i in 3:
		var a := _phase * 3.0 + TAU * float(i) / 3.0
		var orb := Vector2(cos(a), sin(a * 1.1)) * cell_size * (0.52 + 0.06 * pulse)
		draw_circle(orb + lift, cell_size * 0.06 * (0.7 + 0.5 * pulse), Color(glow_col.r, glow_col.g, glow_col.b, 0.9))
		draw_circle(orb + lift, cell_size * 0.03, Color(1, 1, 1, 0.9))

	# charged rim
	var body := ShapeDrawUtils.gem_points(cell_size)
	body.append(body[0])
	draw_polyline(body, Color(glow_col.r, glow_col.g, glow_col.b, 0.5 + 0.4 * pulse), max(cell_size * 0.04, 2.0), true)

# ------------------------------------------------------------ power icons --

func _icon_bomb(pulse: float) -> void:
	draw_circle(Vector2(0, cell_size * 0.03), cell_size * 0.24, Color(0.08, 0.08, 0.11))
	draw_circle(Vector2(-cell_size * 0.08, cell_size * -0.05), cell_size * 0.08, Color(1, 1, 1, 0.5))
	var fuse_top := Vector2(cell_size * 0.14, -cell_size * 0.22)
	draw_line(Vector2(cell_size * 0.06, -cell_size * 0.12), fuse_top, Color(0.9, 0.7, 0.4), max(cell_size * 0.035, 2.0))
	var spark := cell_size * (0.05 + 0.03 * pulse)
	draw_circle(fuse_top, spark, Color(1, 0.9, 0.4))
	draw_circle(fuse_top, spark * 0.5, Color(1, 1, 0.85))

func _icon_lightning(pulse: float) -> void:
	var top := PackedVector2Array([
		Vector2(cell_size * 0.06, -cell_size * 0.30), Vector2(cell_size * 0.16, -cell_size * 0.02),
		Vector2(-cell_size * 0.02, -cell_size * 0.02),
	])
	var bottom := PackedVector2Array([
		Vector2(-cell_size * 0.06, cell_size * 0.30), Vector2(-cell_size * 0.16, cell_size * 0.02),
		Vector2(cell_size * 0.02, cell_size * 0.02),
	])
	var c := Color(1, 0.97, 0.7).lerp(Color(1, 1, 1), pulse)
	draw_colored_polygon(top, c)
	draw_colored_polygon(bottom, c)

func _icon_freeze() -> void:
	var spin := _phase * 0.8
	var c := Color(0.92, 0.98, 1.0, 0.95)
	for i in 3:
		var a := spin + PI * float(i) / 3.0
		var tip := Vector2(cos(a), sin(a)) * cell_size * 0.3
		draw_line(-tip, tip, c, max(cell_size * 0.035, 2.0))
		# barbs
		for s in [-1.0, 1.0]:
			var mid := tip * 0.55
			var barb := Vector2(cos(a + s * 0.9), sin(a + s * 0.9)) * cell_size * 0.12
			draw_line(mid, mid + barb, c, max(cell_size * 0.025, 1.5))
	draw_circle(Vector2.ZERO, cell_size * 0.06, Color(1, 1, 1, 0.9))

func _icon_rainbow() -> void:
	var spin := _phase * 1.2
	for i in _SPECTRUM.size():
		var col: Color = _SPECTRUM[i]
		draw_arc(Vector2.ZERO, cell_size * 0.24, spin + TAU * float(i) / 6.0, spin + TAU * float(i) / 6.0 + 1.4, 10, col, max(cell_size * 0.06, 2.5), true)
	draw_circle(Vector2.ZERO, cell_size * 0.07, Color(1, 1, 1, 0.9))

func _icon_chain(pulse: float) -> void:
	var c := Color(0.9, 1.0, 0.92, 0.95)
	for off in [Vector2(-cell_size * 0.12, 0), Vector2(cell_size * 0.12, 0)]:
		var ring := ShapeDrawUtils.regular_polygon(6, cell_size * 0.15, PI / 6.0, off)
		ring.append(ring[0])
		draw_polyline(ring, c, max(cell_size * 0.045, 2.0) * (0.8 + 0.3 * pulse), true)
	draw_circle(Vector2.ZERO, cell_size * 0.05, Color(0.7, 1.0, 0.8))

# -------------------------------------------------------------- obstacles --

func _draw_stone() -> void:
	var body := ShapeDrawUtils.round_polygon(ShapeDrawUtils.regular_polygon(6, cell_size * 0.44, PI / 6.0), cell_size * 0.06, 2)
	draw_colored_polygon(_translated(body, Vector2(0, cell_size * 0.08)), Color(0, 0, 0, 0.3))
	draw_polygon(body, ShapeDrawUtils.vertical_shade(body, Color(0.5, 0.52, 0.58), Color(0.28, 0.29, 0.34)))
	var crack := Color(0.16, 0.17, 0.2, 0.9)
	draw_line(Vector2(-cell_size * 0.2, -cell_size * 0.12), Vector2(cell_size * 0.08, cell_size * 0.18), crack, max(cell_size * 0.03, 2.0))
	draw_line(Vector2(cell_size * 0.05, -cell_size * 0.22), Vector2(-cell_size * 0.12, cell_size * 0.05), crack, max(cell_size * 0.025, 1.5))
	draw_circle(Vector2(-cell_size * 0.14, -cell_size * 0.16), cell_size * 0.05, Color(1, 1, 1, 0.12))

func _draw_lock() -> void:
	var body := ShapeDrawUtils.gem_points(cell_size)
	draw_colored_polygon(_translated(body, Vector2(0, cell_size * 0.09)), Color(0, 0, 0, 0.28))
	draw_polygon(body, ShapeDrawUtils.vertical_shade(body, Color(0.34, 0.36, 0.44), Color(0.2, 0.21, 0.27)))
	_draw_padlock()

func _draw_padlock() -> void:
	var col := Color(0.86, 0.88, 0.95)
	draw_arc(Vector2(0, -cell_size * 0.08), cell_size * 0.15, PI, TAU, 16, col, max(cell_size * 0.045, 2.5), true)
	var b := Vector2(cell_size * 0.34, cell_size * 0.26)
	draw_rect(Rect2(-b * 0.5 + Vector2(0, cell_size * 0.08), b), col)
	draw_circle(Vector2(0, cell_size * 0.16), cell_size * 0.045, Color(0.2, 0.2, 0.26))

func _draw_ice_overlay() -> void:
	var body := ShapeDrawUtils.gem_points(cell_size)
	var alpha := 0.62 if obstacle_hp >= 2 else 0.32
	draw_colored_polygon(body, Color(0.78, 0.92, 1.0, alpha))
	var edge := body.duplicate()
	edge.append(body[0])
	draw_polyline(edge, Color(0.9, 0.98, 1.0, 0.8), max(cell_size * 0.03, 1.5), true)
	var crack := Color(1, 1, 1, 0.75)
	draw_line(Vector2(-cell_size * 0.16, -cell_size * 0.2), Vector2(cell_size * 0.06, cell_size * 0.06), crack, 2.0)
	if obstacle_hp < 2:
		draw_line(Vector2(cell_size * 0.12, -cell_size * 0.06), Vector2(-cell_size * 0.06, cell_size * 0.22), crack, 2.0)
		draw_line(Vector2(-cell_size * 0.02, -cell_size * 0.22), Vector2(cell_size * 0.02, cell_size * 0.24), crack, 1.5)

func _draw_timebomb_overlay() -> void:
	# The closer the countdown gets to zero, the harder it pulses.
	var urgency: float = clampf(1.0 - float(max(obstacle_hp, 0)) / 5.0, 0.15, 1.0)
	var warn := 0.5 + 0.5 * sin(_phase * (5.0 + 8.0 * urgency))
	VisualTheme.draw_glow(self, Vector2.ZERO, cell_size * 0.55, Color(1.0, 0.3, 0.2, (0.25 + 0.35 * urgency) * warn), 4)
	draw_circle(Vector2.ZERO, cell_size * 0.34, Color(0.09, 0.09, 0.12, 0.96))
	draw_arc(Vector2.ZERO, cell_size * 0.34, 0, TAU, 26, Color(1.0, 0.42, 0.32, 0.65 + 0.35 * warn), max(cell_size * 0.045, 2.5), true)
	# countdown ring: fraction of the fuse left (assumes a 7-turn fuse)
	var frac: float = clampf(float(max(obstacle_hp, 0)) / 7.0, 0.0, 1.0)
	draw_arc(Vector2.ZERO, cell_size * 0.34, -PI / 2.0, -PI / 2.0 + TAU * frac, 26, Color(1, 0.85, 0.4, 0.9), max(cell_size * 0.05, 2.5), true)
	# big countdown number
	var font := ThemeDB.fallback_font
	var txt := str(max(obstacle_hp, 0))
	var fs := int(cell_size * 0.56)
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var col := Color(1, 0.96, 0.9).lerp(Color(1, 0.45, 0.35), urgency)
	draw_string_outline(font, -ts * 0.5 + Vector2(0, ts.y * 0.33), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, 5, Color(0, 0, 0, 0.85))
	draw_string(font, -ts * 0.5 + Vector2(0, ts.y * 0.33), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)

func _draw_selection() -> void:
	var g := GemTextures.glow()
	if g != null:
		var gs := cell_size * 1.7
		draw_texture_rect(g, Rect2(-gs * 0.5, -gs * 0.5, gs, gs), false,
			Color(_glow.r, _glow.g, _glow.b, 0.35))
	var body := ShapeDrawUtils.gem_points(cell_size * 1.13)
	body.append(body[0])
	draw_polyline(body, Color(1, 1, 1, 0.85), max(cell_size * 0.055, 2.5), true)

func _translated(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + by)
	return out
