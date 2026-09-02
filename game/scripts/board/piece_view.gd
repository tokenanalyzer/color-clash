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

## Texture is [RES + 2*PAD] square with the jewel filling RES. Blit clearly
## INSIDE the cell so every jewel keeps a visible ring of socket around it —
## the honeycomb should read as separated gems seated in cups, not one
## merged blob. (1.09 overlapped neighbours; 0.99 still touched.)
const _BLIT := 0.9

func _blit_rect() -> Rect2:
	var s := cell_size * _BLIT
	return Rect2(-s * 0.5, -s * 0.5, s, s)

func _blit_gem(tex: Texture2D) -> void:
	if tex == null:
		_draw_gem(_accent.lerp(_base, 0.15), _base, _base.lerp(_deep, 0.55), _rim, _glow)
		return
	# soft contact shadow — sized to the jewel (blit 0.9) and dropped low so
	# each one pools into its socket without spilling onto its neighbours.
	var sh := GemTextures.shadow()
	if sh != null:
		var sc := cell_size * 0.98
		draw_texture_rect(sh, Rect2(-sc * 0.5, -sc * 0.5 + cell_size * 0.13, sc, sc), false, Color(0, 0, 0, 0.55))
	_blit_tex(tex, _BLIT)

## Blit an arbitrary prepared sprite centred in the cell, preserving its aspect
## ratio (never stretched), scaled so its longer side ~= cell_size * k. `y_off`
## nudges it up/down; `tint` modulates (kept opaque-white by default so the
## artwork's own colour/lighting is untouched).
func _blit_tex(tex: Texture2D, k: float = 0.92, y_off: float = 0.0, tint: Color = Color(1, 1, 1)) -> void:
	if tex == null:
		return
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var m: float = maxf(tw, th)
	var w := cell_size * k * (tw / m)
	var h := cell_size * k * (th / m)
	draw_texture_rect(tex, Rect2(-w * 0.5, -h * 0.5 + y_off, w, h), false, tint)

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

## Power tiles are RENDERED AS DISTINCT OBJECTS. When the prepared power art
## (assets 7-11) is present it is blitted as its own sprite — a fused bomb,
## an electric crystal, a rimed ice shard, a prismatic orb, linked rings —
## floating above the plain jewels inside a breathing per-power aura. Missing
## art falls back to the original vector objects (`_draw_*_power`).
func _draw_power_gem() -> void:
	var glow_col: Color = _POWER_GLOW.get(power_id, _glow)
	var pulse := 0.7 + 0.3 * sin(_phase * 4.5)
	var slow := 0.5 + 0.5 * sin(_phase * 1.8)

	# wide breathing halo + tight bright core glow, tinted per power
	var g := GemTextures.glow()
	if g != null:
		var gs1 := cell_size * (2.35 + 0.4 * slow)
		draw_texture_rect(g, Rect2(-gs1 * 0.5, -gs1 * 0.5, gs1, gs1), false,
			Color(glow_col.r, glow_col.g, glow_col.b, 0.24 + 0.14 * slow))
		var gs2 := cell_size * (1.45 + 0.25 * pulse)
		draw_texture_rect(g, Rect2(-gs2 * 0.5, -gs2 * 0.5, gs2, gs2), false,
			Color(glow_col.r, glow_col.g, glow_col.b, 0.4 * pulse))

	# a "lift" so power tiles float above the plain jewels
	var lift := Vector2(0, -cell_size * 0.06 * (0.6 + 0.4 * pulse))
	draw_set_transform(lift, 0.0, Vector2.ONE)
	var art := AssetLibrary.power(power_id)
	if art != null:
		# a soft contact shadow keeps the object seated in its socket
		var sh := GemTextures.shadow()
		if sh != null:
			var sc := cell_size * 1.02
			draw_texture_rect(sh, Rect2(-sc * 0.5, -sc * 0.5 + cell_size * 0.16, sc, sc), false, Color(0, 0, 0, 0.55))
		if power_id == &"bomb":
			# expanding "arming" warning ring — reads as a live hazard
			var warn := fposmod(_phase * 0.9, 1.0)
			draw_arc(Vector2.ZERO, cell_size * 0.46 * (1.0 + warn * 1.1), 0, TAU, 28,
				Color(1.0, 0.3, 0.2, 0.5 * (1.0 - warn)), max(cell_size * 0.04, 2.0), true)
		_blit_tex(art, 1.02, -cell_size * 0.02)
	else:
		match power_id:
			&"bomb": _draw_bomb_power(pulse)
			&"lightning": _draw_lightning_power(pulse)
			&"freeze": _draw_freeze_power(pulse, slow)
			&"rainbow": _draw_rainbow_power(pulse)
			&"chain": _draw_chain_power(pulse)
			_: _blit_gem(GemTextures.solid_gem(StringName("__pow_" + String(power_id)), _POWER_BODY.get(power_id, _base)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --------------------------------------------------------- power objects --

func _draw_bomb_power(pulse: float) -> void:
	var r := cell_size * 0.46
	# danger aura + expanding warning ring (faster as it "arms")
	var warn := fposmod(_phase * 0.9, 1.0)
	draw_arc(Vector2.ZERO, r * (1.0 + warn * 1.1), 0, TAU, 28,
		Color(1.0, 0.3, 0.2, 0.5 * (1.0 - warn)), max(cell_size * 0.04, 2.0), true)
	# contact shadow
	var sh := GemTextures.shadow()
	if sh != null:
		var sc := cell_size * 1.05
		draw_texture_rect(sh, Rect2(-sc * 0.5, -sc * 0.5 + cell_size * 0.16, sc, sc), false, Color(0, 0, 0, 0.6))
	# iron sphere: dark base, up-left lit shoulder, tight specular
	draw_circle(Vector2.ZERO, r, Color(0.06, 0.06, 0.09))
	for i in range(6, 0, -1):
		var t := float(i) / 6.0
		draw_circle(Vector2(-r * 0.28, -r * 0.30) * (1.0 - t), r * t * 0.92,
			Color(0.20, 0.21, 0.27).lerp(Color(0.06, 0.06, 0.09), 1.0 - t))
	draw_circle(Vector2(-r * 0.34, -r * 0.36), r * 0.20, Color(1, 1, 1, 0.55))
	draw_circle(Vector2(-r * 0.30, -r * 0.32), r * 0.09, Color(1, 1, 1, 0.9))
	draw_arc(Vector2.ZERO, r, 0, TAU, 28, Color(0, 0, 0, 0.55), max(cell_size * 0.03, 2.0), true)
	# neck collar + fuse
	var neck := Vector2(cell_size * 0.10, -r * 0.86)
	draw_circle(neck, cell_size * 0.11, Color(0.16, 0.13, 0.10))
	var tip := Vector2(cell_size * 0.30, -cell_size * 0.52)
	var mid := Vector2(cell_size * 0.30, -r * 1.02)
	draw_polyline(PackedVector2Array([neck, mid, tip]), Color(0.55, 0.42, 0.28), max(cell_size * 0.06, 3.0), true)
	# crackling spark at the fuse tip
	var flick := 0.7 + 0.3 * sin(_phase * 22.0)
	draw_circle(tip, cell_size * (0.13 + 0.05 * flick), Color(1.0, 0.55, 0.12, 0.9))
	draw_circle(tip, cell_size * 0.08 * flick, Color(1.0, 0.92, 0.6))
	for i in 4:
		var a := _phase * 12.0 + TAU * float(i) / 4.0
		draw_line(tip, tip + Vector2(cos(a), sin(a)) * cell_size * (0.12 + 0.06 * flick),
			Color(1.0, 0.8, 0.3, 0.8), max(cell_size * 0.02, 1.5), true)

func _draw_lightning_power(pulse: float) -> void:
	_blit_gem(GemTextures.solid_gem(&"__pow_lightning", Color(0.16, 0.42, 0.95)))
	# electric core bloom
	VisualTheme.draw_glow(self, Vector2.ZERO, cell_size * 0.34, Color(0.7, 0.9, 1.0, 0.5 + 0.3 * pulse), 4)
	# jagged internal cracks that flicker
	var seedp := int(_phase * 8.0)
	for k in 3:
		var pts := PackedVector2Array()
		var a := TAU * (float(k) / 3.0) + float(seedp) * 0.7
		var start := Vector2(cos(a), sin(a)) * cell_size * 0.36
		var stepn := 4
		for s in stepn + 1:
			var f := float(s) / float(stepn)
			var jitter := sin((f * 9.0 + float(seedp) + k) * 3.0) * cell_size * 0.09
			var dir := (-start).normalized()
			var perp := Vector2(-dir.y, dir.x)
			pts.append(start.lerp(Vector2.ZERO, f) + perp * jitter * (1.0 - f))
		draw_polyline(pts, Color(1, 1, 1, 0.85), max(cell_size * 0.03, 1.5), true)
	# bold bolt glyph
	var bolt := PackedVector2Array([
		Vector2(cell_size * 0.10, -cell_size * 0.34), Vector2(-cell_size * 0.06, -cell_size * 0.02),
		Vector2(cell_size * 0.07, -cell_size * 0.02), Vector2(-cell_size * 0.10, cell_size * 0.34),
		Vector2(cell_size * 0.18, -cell_size * 0.04), Vector2(cell_size * 0.03, -cell_size * 0.04),
	])
	draw_colored_polygon(bolt, Color(1.0, 0.97, 0.75).lerp(Color(1, 1, 1), pulse))
	var edge := bolt.duplicate(); edge.append(bolt[0])
	draw_polyline(edge, Color(0.5, 0.8, 1.0, 0.9), max(cell_size * 0.02, 1.5), true)
	# perimeter arcs jumping around the crystal
	for i in 2:
		var a2 := _phase * 6.0 + PI * float(i)
		var o := Vector2(cos(a2), sin(a2)) * cell_size * 0.46
		draw_line(o, o + Vector2(cos(a2 + 1.4), sin(a2 + 1.4)) * cell_size * 0.16,
			Color(0.8, 0.95, 1.0, 0.8), max(cell_size * 0.025, 1.5), true)
	var body := ShapeDrawUtils.gem_points(cell_size); body.append(body[0])
	draw_polyline(body, Color(0.6, 0.85, 1.0, 0.6 + 0.4 * pulse), max(cell_size * 0.045, 2.0), true)

func _draw_freeze_power(pulse: float, slow: float) -> void:
	# translucent ice shard — a rotated faceted crystal, pale and cold
	var crystal := ShapeDrawUtils.regular_polygon(6, cell_size * 0.47, PI / 6.0 + slow * 0.15)
	draw_colored_polygon(_translated(crystal, Vector2(0, cell_size * 0.1)), Color(0.1, 0.2, 0.35, 0.4))
	draw_polygon(crystal, ShapeDrawUtils.vertical_shade(crystal, Color(0.86, 0.96, 1.0), Color(0.42, 0.66, 0.86)))
	# inner facets
	for i in 6:
		var v: Vector2 = crystal[i]
		draw_line(Vector2.ZERO, v, Color(1, 1, 1, 0.28), max(cell_size * 0.02, 1.5), true)
	# rime edge
	var edge := crystal.duplicate(); edge.append(crystal[0])
	draw_polyline(edge, Color(0.95, 1.0, 1.0, 0.9), max(cell_size * 0.035, 2.0), true)
	# slow-turning snowflake
	var spin := _phase * 0.7
	for i in 3:
		var a := spin + PI * float(i) / 3.0
		var tip := Vector2(cos(a), sin(a)) * cell_size * 0.32
		draw_line(-tip, tip, Color(1, 1, 1, 0.95), max(cell_size * 0.03, 2.0), true)
		for s in [-1.0, 1.0]:
			var m := tip * 0.55
			draw_line(m, m + Vector2(cos(a + s * 0.9), sin(a + s * 0.9)) * cell_size * 0.12,
				Color(1, 1, 1, 0.9), max(cell_size * 0.02, 1.5), true)
	draw_circle(Vector2.ZERO, cell_size * 0.06, Color(1, 1, 1))
	# drifting frost twinkles
	for i in 4:
		var a := _phase * (0.6 + 0.1 * i) + TAU * float(i) / 4.0
		var p := Vector2(cos(a), sin(a * 1.3)) * cell_size * (0.30 + 0.12 * sin(_phase + i))
		draw_circle(p, cell_size * 0.03 * (0.6 + 0.4 * sin(_phase * 4.0 + i)), Color(1, 1, 1, 0.8))

func _draw_rainbow_power(pulse: float) -> void:
	# pearlescent orb with rotating spectrum bands
	var r := cell_size * 0.46
	var spin := _phase * 0.9
	draw_circle(Vector2.ZERO, r, Color(0.98, 0.98, 1.0))
	for i in _SPECTRUM.size():
		var a0 := spin + TAU * float(i) / 6.0
		var wedge := PackedVector2Array([Vector2.ZERO])
		for s in 5:
			var aa := a0 + (TAU / 6.0) * float(s) / 4.0
			wedge.append(Vector2(cos(aa), sin(aa)) * r)
		var col: Color = _SPECTRUM[i]
		col.a = 0.55
		draw_colored_polygon(wedge, col)
	# glossy dome + rim
	draw_circle(Vector2(-r * 0.3, -r * 0.32), r * 0.28, Color(1, 1, 1, 0.7))
	draw_arc(Vector2.ZERO, r, 0, TAU, 30, Color(1, 1, 1, 0.85), max(cell_size * 0.03, 2.0), true)
	draw_circle(Vector2.ZERO, cell_size * 0.09, Color(1, 1, 1))
	# orbiting prism sparks
	for i in 6:
		var a := -_phase * 2.4 + TAU * float(i) / 6.0
		var o := Vector2(cos(a), sin(a)) * cell_size * (0.5 + 0.05 * pulse)
		var sc: Color = _SPECTRUM[i]
		draw_circle(o, cell_size * 0.05, sc)
		draw_circle(o, cell_size * 0.025, Color(1, 1, 1, 0.9))

func _draw_chain_power(pulse: float) -> void:
	_blit_gem(GemTextures.solid_gem(&"__pow_chain", Color(0.12, 0.62, 0.36)))
	VisualTheme.draw_glow(self, Vector2.ZERO, cell_size * 0.32, Color(0.4, 1.0, 0.6, 0.4 + 0.3 * pulse), 4)
	# three linked energy rings
	var offs := [Vector2(-cell_size * 0.16, -cell_size * 0.04), Vector2(0, cell_size * 0.14), Vector2(cell_size * 0.16, -cell_size * 0.04)]
	for oi in offs.size():
		var ring := ShapeDrawUtils.regular_polygon(6, cell_size * 0.15, PI / 6.0, offs[oi])
		ring.append(ring[0])
		draw_polyline(ring, Color(0.85, 1.0, 0.9, 0.95), max(cell_size * 0.04, 2.0) * (0.8 + 0.3 * pulse), true)
		# energy pulse travelling around each ring
		var t := fposmod(_phase * 1.5 + float(oi) * 0.33, 1.0)
		var pa := t * TAU
		draw_circle(offs[oi] + Vector2(cos(pa), sin(pa)) * cell_size * 0.15, cell_size * 0.045, Color(1, 1, 1))
	# radiating ticks
	for i in 6:
		var a := _phase * 3.0 + TAU * float(i) / 6.0
		var b := Vector2(cos(a), sin(a))
		draw_line(b * cell_size * 0.4, b * cell_size * (0.5 + 0.06 * pulse), Color(0.6, 1.0, 0.75, 0.7), max(cell_size * 0.02, 1.5), true)

# -------------------------------------------------------------- obstacles --

func _draw_stone() -> void:
	var art := AssetLibrary.tex(&"obstacle_stone_block")
	if art != null:
		var sh := GemTextures.shadow()
		if sh != null:
			var sc := cell_size * 1.0
			draw_texture_rect(sh, Rect2(-sc * 0.5, -sc * 0.5 + cell_size * 0.15, sc, sc), false, Color(0, 0, 0, 0.5))
		_blit_tex(art, 0.98)
		return
	var body := ShapeDrawUtils.round_polygon(ShapeDrawUtils.regular_polygon(6, cell_size * 0.44, PI / 6.0), cell_size * 0.06, 2)
	draw_colored_polygon(_translated(body, Vector2(0, cell_size * 0.08)), Color(0, 0, 0, 0.3))
	draw_polygon(body, ShapeDrawUtils.vertical_shade(body, Color(0.5, 0.52, 0.58), Color(0.28, 0.29, 0.34)))
	var crack := Color(0.16, 0.17, 0.2, 0.9)
	draw_line(Vector2(-cell_size * 0.2, -cell_size * 0.12), Vector2(cell_size * 0.08, cell_size * 0.18), crack, max(cell_size * 0.03, 2.0))
	draw_line(Vector2(cell_size * 0.05, -cell_size * 0.22), Vector2(-cell_size * 0.12, cell_size * 0.05), crack, max(cell_size * 0.025, 1.5))
	draw_circle(Vector2(-cell_size * 0.14, -cell_size * 0.16), cell_size * 0.05, Color(1, 1, 1, 0.12))

func _draw_lock() -> void:
	var art := AssetLibrary.tex(&"obstacle_lock")
	if art != null:
		var sh := GemTextures.shadow()
		if sh != null:
			var sc := cell_size * 1.0
			draw_texture_rect(sh, Rect2(-sc * 0.5, -sc * 0.5 + cell_size * 0.15, sc, sc), false, Color(0, 0, 0, 0.5))
		_blit_tex(art, 0.96)
		return
	var body := ShapeDrawUtils.gem_points(cell_size * _BLIT)
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
	var has_piece := color_id != CellData.COLOR_EMPTY
	var body := ShapeDrawUtils.gem_points(cell_size * _BLIT)

	# Prepared art: a solid frosted block when nothing is trapped, a
	# gem-frozen-in-ice sprite once fully encased (hp>=2). At hp<2 keep a thin
	# procedural glaze so the jewel's own colour reads through as it cracks.
	var block := AssetLibrary.tex(&"obstacle_ice_block")
	var frozen := AssetLibrary.tex(&"obstacle_frozen_gem")
	if not has_piece and block != null:
		_blit_tex(block, 1.0)
		return
	if has_piece and obstacle_hp >= 2 and frozen != null:
		_blit_tex(frozen, 1.0)
		return
	if has_piece:
		var alpha := 0.42 if obstacle_hp >= 2 else 0.22
		draw_colored_polygon(body, Color(0.7, 0.88, 1.0, alpha))
	else:
		draw_polygon(body, ShapeDrawUtils.vertical_shade(body,
			Color(0.82, 0.93, 1.0), Color(0.5, 0.72, 0.9)))
		draw_circle(Vector2(-cell_size * 0.16, -cell_size * 0.2), cell_size * 0.12, Color(1, 1, 1, 0.5))
	var edge := body.duplicate()
	edge.append(body[0])
	draw_polyline(edge, Color(0.92, 0.99, 1.0, 0.95), max(cell_size * 0.04, 2.0), true)
	var crack := Color(1, 1, 1, 0.72)
	draw_line(Vector2(-cell_size * 0.15, -cell_size * 0.18), Vector2(cell_size * 0.05, cell_size * 0.05), crack, max(cell_size * 0.022, 2.0), true)
	if obstacle_hp < 2:
		draw_line(Vector2(cell_size * 0.1, -cell_size * 0.05), Vector2(-cell_size * 0.05, cell_size * 0.2), crack, max(cell_size * 0.02, 1.5), true)
		draw_line(Vector2(-cell_size * 0.02, -cell_size * 0.2), Vector2(cell_size * 0.02, cell_size * 0.22), crack, max(cell_size * 0.015, 1.5), true)

func _draw_timebomb_overlay() -> void:
	# The closer the countdown gets to zero, the harder it pulses.
	var urgency: float = clampf(1.0 - float(max(obstacle_hp, 0)) / 5.0, 0.15, 1.0)
	var warn := 0.5 + 0.5 * sin(_phase * (5.0 + 8.0 * urgency))
	var frac: float = clampf(float(max(obstacle_hp, 0)) / 7.0, 0.0, 1.0)
	VisualTheme.draw_glow(self, Vector2.ZERO, cell_size * 0.55, Color(1.0, 0.3, 0.2, (0.25 + 0.35 * urgency) * warn), 4)

	var art := AssetLibrary.tex(&"obstacle_time_bomb")
	if art != null:
		_blit_tex(art, 0.98)
		var fuse := AssetLibrary.tex(&"obstacle_time_bomb_fuse")
		if fuse != null and frac > 0.05:
			# the fuse shortens / fades as the countdown burns down
			_blit_tex(fuse, 0.98 * (0.55 + 0.45 * frac), -cell_size * 0.18 * (1.0 - frac),
				Color(1, 1, 1, 0.55 + 0.45 * frac))
	else:
		draw_circle(Vector2.ZERO, cell_size * 0.34, Color(0.09, 0.09, 0.12, 0.96))
		draw_arc(Vector2.ZERO, cell_size * 0.34, 0, TAU, 26, Color(1.0, 0.42, 0.32, 0.65 + 0.35 * warn), max(cell_size * 0.045, 2.5), true)
	# countdown ring: fraction of the fuse left (assumes a 7-turn fuse)
	draw_arc(Vector2.ZERO, cell_size * 0.36, -PI / 2.0, -PI / 2.0 + TAU * frac, 26, Color(1, 0.85, 0.4, 0.95), max(cell_size * 0.05, 2.5), true)
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
	var body := ShapeDrawUtils.gem_points(cell_size * _BLIT * 1.14)
	body.append(body[0])
	draw_polyline(body, Color(1, 1, 1, 0.9), max(cell_size * 0.06, 2.5), true)

func _translated(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + by)
	return out
