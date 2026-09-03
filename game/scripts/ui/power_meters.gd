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
	custom_minimum_size = Vector2(0, 34)
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
	var n := _POWERS.size()
	var gap := 10.0
	var cw := (size.x - gap * float(n - 1)) / float(n)
	var ch := size.y
	for i in n:
		var p: StringName = _POWERS[i]
		var x := float(i) * (cw + gap)
		var r := Rect2(x, 0, cw, ch)
		var tint: Color = _TINT[p]
		var ready: bool = float(_ratio[p]) >= 0.999
		# track
		_round(r, 9.0, Color(0.05, 0.06, 0.12, 0.9))
		# fill
		var fw: float = cw * float(_shown[p])
		var fp: float = float(_flash[p])
		if fw > 6.0:
			var fc: Color = tint if fp <= 0.0 else tint.lerp(Color(1, 1, 1), fp)
			_round(Rect2(x, 0, fw, ch), 9.0, fc)
		# icon glyph at the left
		var gc := Vector2(x + ch * 0.5, ch * 0.5)
		_glyph(p, gc, ch * 0.32, Color(1, 1, 1, 0.92) if _shown[p] > 0.1 or ready else Color(1, 1, 1, 0.4))
		# ready pip
		if ready:
			var pulse := 0.6 + 0.4 * sin(_t * 8.0)
			_round_outline(r.grow(-1.0), 8.0, Color(tint.r, tint.g, tint.b, pulse), 2.0)
		else:
			_round_outline(r.grow(-0.5), 8.5, Color(1, 1, 1, 0.12), 1.0)

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
