class_name UiKit
extends RefCounted
## Shared premium-UI toolkit for the reference-matched Color Clash skin:
## frosted-glass panels, ornate gold-frame dialogs, chunky beveled buttons,
## glass currency chips, and lightweight entrance / press animations.
##
## Everything is code-drawn or StyleBoxFlat-based — no new art assets — so it
## scales to any Android portrait resolution on the gl_compatibility
## renderer. Where a supplied PNG exists (logo / wordmark) the caller pulls
## it from AssetLibrary and falls back to these primitives.

# ------------------------------------------------------------- palette --
const GLASS_BG := Color(0.09, 0.12, 0.22, 0.52)      # translucent — backdrop shows through
const GLASS_BG_DEEP := Color(0.06, 0.08, 0.16, 0.68) # for panels that need more contrast
const GLASS_BORDER := Color(0.78, 0.88, 1.0, 0.28)
const GLASS_HILITE := Color(1.0, 1.0, 1.0, 0.16)
const GOLD := Color(1.0, 0.82, 0.36)
const GOLD_DEEP := Color(0.66, 0.46, 0.15)
const GOLD_LITE := Color(1.0, 0.94, 0.72)
const GREEN_FACE := Color(0.44, 0.80, 0.30)
const GREEN_DEEP := Color(0.16, 0.42, 0.12)
const PURPLE_FACE := Color(0.52, 0.36, 0.86)
const PURPLE_DEEP := Color(0.26, 0.16, 0.50)
const BLUE_FACE := Color(0.28, 0.56, 0.95)
const BLUE_DEEP := Color(0.10, 0.26, 0.56)
const RED_FACE := Color(0.90, 0.30, 0.32)
const RED_DEEP := Color(0.48, 0.10, 0.12)

# ------------------------------------------------------------ styleboxes --

## Frosted-glass card: low-alpha fill so the fantasy background reads through,
## a soft light hairline (brighter on top = "lit from above"), rounded
## corners and a diffuse drop shadow. This replaces every opaque black strip.
static func glass(radius: int = 24, deep: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS_BG_DEEP if deep else GLASS_BG
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.border_color = GLASS_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.34)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.anti_aliasing = true
	return sb

## A beveled button face (chunky 3D look from the reference): saturated top
## bevel, dark thick bottom bevel, gold-deep outline, drop shadow.
static func button_face(face: Color, deep: Color, radius: int = 20) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = face
	sb.set_corner_radius_all(radius)
	sb.border_color = deep
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 2
	sb.border_width_bottom = 7
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	sb.shadow_color = Color(0, 0, 0, 0.42)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	sb.anti_aliasing = true
	return sb

## Colour pair for a button "kind".
static func _kind_colors(kind: StringName) -> Array:
	match kind:
		&"primary": return [GREEN_FACE, GREEN_DEEP]
		&"secondary": return [PURPLE_FACE, PURPLE_DEEP]
		&"tertiary": return [BLUE_FACE, BLUE_DEEP]
		&"danger": return [RED_FACE, RED_DEEP]
		_: return [GREEN_FACE, GREEN_DEEP]

# --------------------------------------------------------------- widgets --

## The premium campaign button. `kind`: primary | secondary | tertiary | danger.
static func button(text: String, kind: StringName = &"primary", font_size: int = -1) -> Button:
	var cols := _kind_colors(kind)
	var face: Color = cols[0]
	var deep: Color = cols[1]
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = false
	b.add_theme_font_size_override("font_size", font_size if font_size > 0 else VisualTheme.FS_BUTTON)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.94, 0.98, 1.0))
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	b.add_theme_stylebox_override("normal", button_face(face, deep))
	b.add_theme_stylebox_override("hover", button_face(face.lightened(0.08), deep))
	var pressed_sb := button_face(face.darkened(0.14), deep)
	pressed_sb.border_width_bottom = 3
	pressed_sb.content_margin_top = 17
	pressed_sb.content_margin_bottom = 13
	b.add_theme_stylebox_override("pressed", pressed_sb)
	var dis := button_face(face.darkened(0.4), deep.darkened(0.2))
	dis.bg_color.a = 0.7
	b.add_theme_stylebox_override("disabled", dis)
	attach_press_feedback(b)
	return b

## Small round icon button (gear / close / plus) drawn as a glass disc.
static func icon_button(glyph: StringName, diameter: int = 64) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.focus_mode = Control.FOCUS_NONE
	var sb := glass(diameter / 2, true)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", glass(diameter / 2, true))
	var psb := glass(diameter / 2, true)
	psb.bg_color = psb.bg_color.darkened(0.15)
	b.add_theme_stylebox_override("pressed", psb)
	var g := _Glyph.new()
	g.glyph = glyph
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(g)
	attach_press_feedback(b)
	return b

## Glass currency chip: [icon] [value] (+). Returns a dict:
##   {root: PanelContainer, value: Label, plus: Button|null}
static func currency_chip(icon_kind: StringName, text_color: Color, with_plus: bool = true) -> Dictionary:
	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", glass(22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)

	var icon := HUD.GemIcon.new()
	icon.kind = icon_kind
	icon.tint = VisualTheme.GEM
	icon.custom_minimum_size = Vector2(30, 30)
	row.add_child(icon)

	var value := VisualTheme.label("0", VisualTheme.FS_LABEL, text_color)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)

	var plus: Button = null
	if with_plus:
		plus = Button.new()
		plus.custom_minimum_size = Vector2(30, 30)
		plus.focus_mode = Control.FOCUS_NONE
		plus.text = "+"
		plus.add_theme_font_size_override("font_size", 22)
		plus.add_theme_color_override("font_color", Color(1, 1, 1))
		plus.add_theme_constant_override("outline_size", 4)
		plus.add_theme_color_override("font_outline_color", Color(0, 0.25, 0.05, 0.8))
		var psb := button_face(GREEN_FACE, GREEN_DEEP, 15)
		psb.content_margin_left = 0
		psb.content_margin_right = 0
		psb.content_margin_top = 0
		psb.content_margin_bottom = 2
		psb.border_width_bottom = 4
		plus.add_theme_stylebox_override("normal", psb)
		plus.add_theme_stylebox_override("hover", psb)
		plus.add_theme_stylebox_override("pressed", button_face(GREEN_FACE.darkened(0.15), GREEN_DEEP, 15))
		row.add_child(plus)
		attach_press_feedback(plus)

	return {"root": root, "value": value, "plus": plus}

# ------------------------------------------------------------ animations --

## Scale-punch on press for any BaseButton — cheap, mobile-safe.
static func attach_press_feedback(b: BaseButton) -> void:
	b.button_down.connect(func():
		b.pivot_offset = b.size * 0.5
		var t := b.create_tween()
		t.tween_property(b, "scale", Vector2(0.94, 0.94), 0.06).set_trans(Tween.TRANS_SINE)
	)
	b.button_up.connect(func():
		b.pivot_offset = b.size * 0.5
		var t := b.create_tween()
		t.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	)

## Panel entrance: scale-up from 0.86 + fade. Call after the node has a size.
static func pop_in(node: CanvasItem, dur: float = 0.26) -> void:
	if node is Control:
		(node as Control).pivot_offset = (node as Control).size * 0.5
	node.scale = Vector2(0.86, 0.86)
	node.modulate.a = 0.0
	var t := node.create_tween()
	t.set_parallel(true)
	t.tween_property(node, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, dur * 0.8)

## Panel exit — returns the tween so the caller can await it.
static func pop_out(node: CanvasItem, dur: float = 0.18) -> Tween:
	if node is Control:
		(node as Control).pivot_offset = (node as Control).size * 0.5
	var t := node.create_tween()
	t.set_parallel(true)
	t.tween_property(node, "scale", Vector2(0.9, 0.9), dur).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "modulate:a", 0.0, dur)
	return t

## Animated integer count-up on a Label.
static func count_to(label: Label, from_val: int, to_val: int, dur: float = 0.4, thousands: bool = false) -> void:
	var t := label.create_tween()
	t.tween_method(func(v: float):
		var n := int(round(v))
		label.text = _commas(n) if thousands else str(n)
	, float(from_val), float(to_val), dur)

static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

# -------------------------------------------------------- gold-frame panel --

## Ornate double-line gold frame with diamond corner accents over a frosted
## fill — the reference dialog chrome for Settings / Daily Rewards. Add your
## content as children; it lays them out via an inner MarginContainer you get
## from `content()`.
class GoldFramePanel extends PanelContainer:
	var _inner: MarginContainer
	var _accent := UiKit.GOLD
	var _t := 0.0

	func _init(pad: int = 22) -> void:
		var sb := UiKit.glass(26, true)
		sb.bg_color = Color(0.08, 0.09, 0.19, 0.86)
		sb.border_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(0)
		sb.content_margin_left = pad + 8
		sb.content_margin_right = pad + 8
		sb.content_margin_top = pad + 8
		sb.content_margin_bottom = pad + 8
		add_theme_stylebox_override("panel", sb)
		_inner = MarginContainer.new()
		add_child(_inner)
		set_process(true)

	func content() -> MarginContainer:
		return _inner

	func set_accent(c: Color) -> void:
		_accent = c
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		var shimmer := 0.85 + 0.15 * sin(_t * 2.0)
		var g := Color(_accent.r, _accent.g, _accent.b, shimmer)
		# outer heavy line + inner hairline
		_frame(r, 22.0, g, 4.0)
		_frame(r.grow(-7.0), 18.0, Color(UiKit.GOLD_DEEP.r, UiKit.GOLD_DEEP.g, UiKit.GOLD_DEEP.b, 0.9), 2.0)
		# diamond corner accents
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			_diamond(corner, 9.0, g)

	func _frame(r: Rect2, radius: float, col: Color, w: float) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, radius, 6)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.position + r.size * 0.5)
		moved.append(moved[0])
		draw_polyline(moved, col, w, true)

	func _diamond(c: Vector2, rad: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -rad), c + Vector2(rad, 0), c + Vector2(0, rad), c + Vector2(-rad, 0),
		]), col)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -rad * 0.5), c + Vector2(rad * 0.5, 0),
			c + Vector2(0, rad * 0.5), c + Vector2(-rad * 0.5, 0),
		]), UiKit.GOLD_LITE)


## Code-drawn chrome glyph for icon buttons (gear / close / plus / chevron).
class _Glyph extends Control:
	var glyph: StringName = &"gear"

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.26
		match glyph:
			&"gear":
				var tex := AssetLibrary.tex(&"ui_setting_gear")
				if tex != null:
					var s := minf(size.x, size.y) * 0.92
					var m: float = maxf(float(tex.get_width()), float(tex.get_height()))
					draw_texture_rect(tex, Rect2(c - Vector2(s * tex.get_width() / m, s * tex.get_height() / m) * 0.5,
						Vector2(s * tex.get_width() / m, s * tex.get_height() / m)), false)
					return
				draw_arc(c, r, 0, TAU, 24, VisualTheme.TEXT, maxf(r * 0.42, 2.0), true)
				for i in 8:
					var a := TAU * float(i) / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * r * 0.9, c + Vector2(cos(a), sin(a)) * r * 1.5,
						VisualTheme.TEXT, maxf(r * 0.3, 2.0), true)
				draw_circle(c, r * 0.4, Color(0.13, 0.16, 0.26))
			&"close":
				draw_line(c + Vector2(-r, -r), c + Vector2(r, r), Color(1, 1, 1), 5.0, true)
				draw_line(c + Vector2(-r, r), c + Vector2(r, -r), Color(1, 1, 1), 5.0, true)
			&"chevron":
				draw_line(c + Vector2(-r * 0.4, -r), c + Vector2(r * 0.5, 0), Color(1, 1, 1), 5.0, true)
				draw_line(c + Vector2(r * 0.5, 0), c + Vector2(-r * 0.4, r), Color(1, 1, 1), 5.0, true)
			&"pause":
				var w := r * 0.5
				draw_rect(Rect2(c + Vector2(-r, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
				draw_rect(Rect2(c + Vector2(r - w, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
			_:
				draw_circle(c, r, VisualTheme.TEXT)
