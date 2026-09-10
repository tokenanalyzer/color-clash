class_name PowerMeters
extends Control
## Jamie's three power meters (Fire Sword / Blue Lightning / Lightning Boots)
## as a compact HUD strip. Fills are driven by JamiePowers via CombatDirector;
## a meter flashes when it fires. Code-drawn glyphs keep it cheap — the
## supplied Jamie action art can replace them later without touching this.

const _POWERS: Array[StringName] = [&"fire_sword", &"lightning_hand", &"lightning_boots"]
const _TINT := {
	&"fire_sword": Color(1.0, 0.5, 0.16),
	&"lightning_hand": Color(0.32, 0.62, 1.0),
	&"lightning_boots": Color(0.7, 0.42, 1.0),
}

var _ratio := {&"fire_sword": 0.0, &"lightning_hand": 0.0, &"lightning_boots": 0.0}
var _shown := {&"fire_sword": 0.0, &"lightning_hand": 0.0, &"lightning_boots": 0.0}
var _flash := {&"fire_sword": 0.0, &"lightning_hand": 0.0, &"lightning_boots": 0.0}
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 46)
	set_process(true)

func set_meters(meters: Dictionary) -> void:
	for p in _POWERS:
		_ratio[p] = clampf(float(meters.get(p, 0.0)) / 100.0, 0.0, 1.0)

func flash_power(power: StringName) -> void:
	if power == &"ultimate":
		for p in _POWERS:
			_flash[p] = 1.0
	elif _flash.has(power):
		_flash[power] = 1.0

func _process(delta: float) -> void:
	var dirty := false
	for p in _POWERS:
		if absf(_shown[p] - _ratio[p]) > 0.001:
			_shown[p] = lerpf(_shown[p], _ratio[p], clampf(delta * 10.0, 0.0, 1.0))
			dirty = true
		if _flash[p] > 0.001:
			_flash[p] = maxf(_flash[p] - delta * 2.5, 0.0)
			dirty = true
	_t += delta
	if dirty:
		queue_redraw()

func _draw() -> void:
	# Three fully-rounded meter pills, each with a tinted icon chip riding the
	# left end and a coloured fill that grows from the left INSIDE the track —
	# matches the reference row above the board. Code-drawn (no art supplied
	# for these meters); only the presentation is tuned here.
	var n := _POWERS.size()
	var gap := 14.0
	var cw := (size.x - gap * float(n - 1)) / float(n)
	var ch := size.y
	var rad := ch * 0.5
	for i in n:
		var p: StringName = _POWERS[i]
		var x := float(i) * (cw + gap)
		var r := Rect2(x, 0.0, cw, ch)
		var tint: Color = _TINT[p]
		var ready: bool = float(_ratio[p]) >= 0.999
		# drop shadow + near-opaque dark track pill so it reads over the
		# starfield background, then a lit rim for definition
		_round(Rect2(x - 2.0, 2.0, cw + 4.0, ch + 2.0), rad + 2.0, Color(0, 0, 0, 0.35))
		_round(r, rad, Color(0.07, 0.09, 0.16, 0.985))
		_round(Rect2(x + 3.0, 3.0, cw - 6.0, ch * 0.34), rad, Color(1, 1, 1, 0.05))
		# coloured fill, inset so it never reaches the pill edge
		var inset := 3.5
		var maxw := cw - inset * 2.0
		var fw: float = maxw * float(_shown[p])
		var fp: float = float(_flash[p])
		if fw > 4.0:
			var fc: Color = tint if fp <= 0.0 else tint.lerp(Color(1, 1, 1), fp)
			_round(Rect2(x + inset, inset, fw, ch - inset * 2.0), rad - inset, fc)
			_round(Rect2(x + inset, inset, fw, (ch - inset * 2.0) * 0.42), rad - inset,
				Color(1, 1, 1, 0.20))
		# icon chip (rounded square) at the left end
		var chip := ch * 0.9
		var cr := Rect2(x + (ch - chip) * 0.5, (ch - chip) * 0.5, chip, chip)
		_round(cr, chip * 0.3, Color(tint.r, tint.g, tint.b, 1.0 if (_shown[p] > 0.02 or ready) else 0.62))
		_round(Rect2(cr.position.x, cr.position.y, cr.size.x, cr.size.y * 0.45), chip * 0.3, Color(1, 1, 1, 0.16))
		_round_outline(cr, chip * 0.3, Color(1, 1, 1, 0.35), 1.5)
		_glyph(p, cr.position + cr.size * 0.5, chip * 0.3, Color(1, 1, 1, 0.97))
		# rim: a lit pulse when full, a visible hairline otherwise
		if ready:
			var pulse := 0.55 + 0.45 * sin(_t * 8.0)
			_round_outline(r.grow(-1.0), rad - 1.0, Color(tint.r, tint.g, tint.b, pulse), 2.5)
		else:
			_round_outline(r.grow(-0.75), rad - 0.75, Color(0.62, 0.70, 0.9, 0.4), 1.5)

func _glyph(power: StringName, c: Vector2, r: float, col: Color) -> void:
	match power:
		&"fire_sword":
			draw_line(c + Vector2(-r * 0.2, r), c + Vector2(r * 0.2, -r), col, 3.0, true)
			draw_line(c + Vector2(-r * 0.6, r * 0.3), c + Vector2(r * 0.6, r * 0.3), col, 3.0, true)
		&"lightning_hand":
			draw_polyline(PackedVector2Array([
				c + Vector2(-r * 0.3, -r), c + Vector2(r * 0.2, -r * 0.1),
				c + Vector2(-r * 0.15, 0), c + Vector2(r * 0.3, r)]), col, 3.0, true)
		&"lightning_boots":
			draw_line(c + Vector2(-r * 0.6, r * 0.6), c + Vector2(r * 0.2, r * 0.6), col, 3.0, true)
			draw_line(c + Vector2(-r * 0.6, r * 0.6), c + Vector2(-r * 0.3, -r * 0.2), col, 3.0, true)
			draw_line(c + Vector2(-r * 0.3, -r * 0.2), c + Vector2(r * 0.4, -r * 0.2), col, 3.0, true)

func _round(r: Rect2, rad: float, col: Color) -> void:
	var pts := ShapeDrawUtils.rounded_rect_points(r.size, minf(rad, r.size.y * 0.5), 5)
	var m := PackedVector2Array()
	for p in pts:
		m.append(p + r.position + r.size * 0.5)
	draw_colored_polygon(m, col)

func _round_outline(r: Rect2, rad: float, col: Color, wd: float) -> void:
	var pts := ShapeDrawUtils.rounded_rect_points(r.size, minf(rad, r.size.y * 0.5), 6)
	var m := PackedVector2Array()
	for p in pts:
		m.append(p + r.position + r.size * 0.5)
	m.append(m[0])
	draw_polyline(m, col, wd, true)
