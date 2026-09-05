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

const _TAB_INACTIVE_FACE := Color(0.16, 0.19, 0.30)
const _TAB_INACTIVE_DEEP := Color(0.07, 0.09, 0.17)

## Colour pair for a button "kind".
static func _kind_colors(kind: StringName) -> Array:
	match kind:
		&"primary": return [GREEN_FACE, GREEN_DEEP]
		&"secondary": return [PURPLE_FACE, PURPLE_DEEP]
		&"tertiary": return [BLUE_FACE, BLUE_DEEP]
		&"danger": return [RED_FACE, RED_DEEP]
		# A real selected/unselected pair for segmented tab rows (2026-09-05
		# UI pass) — the active tab is gold-filled (matches the app's gold
		# "premium" accent), the inactive ones sit on the same quiet glass
		# tone as everything else, replacing the old alpha-dim hack.
		&"tab_active": return [GOLD, GOLD_DEEP]
		&"tab_inactive": return [_TAB_INACTIVE_FACE, _TAB_INACTIVE_DEEP]
		_: return [GREEN_FACE, GREEN_DEEP]

# --------------------------------------------------------------- widgets --

## The premium campaign button. `kind`: primary | secondary | tertiary | danger.
## `radius` lets a caller ask for a fuller pill shape (e.g. Settings' link
## rows, which read as stadium-shaped in the reference) without touching the
## default chunky-bevel look everywhere else.
static func button(text: String, kind: StringName = &"primary", font_size: int = -1, radius: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = false
	b.add_theme_font_size_override("font_size", font_size if font_size > 0 else VisualTheme.FS_BUTTON)
	set_button_kind(b, kind, radius)
	attach_press_feedback(b)
	return b

## Re-applies a button's face/font colors for `kind` in place — lets a tab
## row (or any button whose "selected" state changes at runtime) swap looks
## without rebuilding the Button node, so press-feedback/signal connections
## survive the switch.
static func set_button_kind(b: Button, kind: StringName, radius: int = 20) -> void:
	var cols := _kind_colors(kind)
	var face: Color = cols[0]
	var deep: Color = cols[1]
	# The gold-faced tab kind is bright enough that white text reads poorly —
	# everything else keeps the existing white-on-saturated-color look.
	var light_face := kind == &"tab_active"
	var font_col := Color(0.22, 0.14, 0.02) if light_face else Color(1, 1, 1)
	b.add_theme_color_override("font_color", font_col)
	b.add_theme_color_override("font_hover_color", font_col)
	b.add_theme_color_override("font_pressed_color", font_col)
	b.add_theme_constant_override("outline_size", 6 if not light_face else 2)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65) if not light_face else Color(1, 1, 0.85, 0.4))
	b.add_theme_stylebox_override("normal", button_face(face, deep, radius))
	b.add_theme_stylebox_override("hover", button_face(face.lightened(0.08), deep, radius))
	var pressed_sb := button_face(face.darkened(0.14), deep, radius)
	pressed_sb.border_width_bottom = 3
	pressed_sb.content_margin_top = 17
	pressed_sb.content_margin_bottom = 13
	b.add_theme_stylebox_override("pressed", pressed_sb)
	var dis := button_face(face.darkened(0.4), deep.darkened(0.2), radius)
	dis.bg_color.a = 0.7
	b.add_theme_stylebox_override("disabled", dis)

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
	root.add_theme_stylebox_override("panel", glass(26))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)

	# Sized up (2026-09-05 UI pass) — the coin/gem icons read as too small
	# for a "premium fantasy" top bar at their old 30px.
	var icon := HUD.GemIcon.new()
	icon.kind = icon_kind
	icon.tint = VisualTheme.GEM
	icon.custom_minimum_size = Vector2(42, 42)
	row.add_child(icon)

	var value := VisualTheme.label("0", VisualTheme.FS_HEADING, text_color)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)

	var plus: Button = null
	if with_plus:
		plus = Button.new()
		plus.custom_minimum_size = Vector2(38, 38)
		plus.focus_mode = Control.FOCUS_NONE
		plus.text = "+"
		plus.add_theme_font_size_override("font_size", 26)
		plus.add_theme_color_override("font_color", Color(1, 1, 1))
		plus.add_theme_constant_override("outline_size", 4)
		plus.add_theme_color_override("font_outline_color", Color(0, 0.25, 0.05, 0.8))
		var psb := button_face(GREEN_FACE, GREEN_DEEP, 19)
		psb.content_margin_left = 0
		psb.content_margin_right = 0
		psb.content_margin_top = 0
		psb.content_margin_bottom = 2
		psb.border_width_bottom = 4
		plus.add_theme_stylebox_override("normal", psb)
		plus.add_theme_stylebox_override("hover", psb)
		plus.add_theme_stylebox_override("pressed", button_face(GREEN_FACE.darkened(0.15), GREEN_DEEP, 19))
		row.add_child(plus)
		attach_press_feedback(plus)

	return {"root": root, "value": value, "plus": plus}

## Fantasy toggle switch (2026-09-05 UI pass) — a glass capsule track (dim
## slate when off, warm gold glow when on) with a sliding gold-rimmed knob.
## Replaces the stock, unthemed `CheckButton` Settings used previously.
class ToggleSwitch extends Button:
	signal toggled_value(v: bool)
	var _knob_t := 0.0   # 0=off .. 1=on, animated

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(96, 44)
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(state, empty)
		toggled.connect(func(v: bool):
			_animate_knob(v)
			toggled_value.emit(v))

	## Sets the visual/logical state without an animated slide or emitting
	## `toggled_value` — for initializing from a saved setting at open time.
	func set_state(v: bool) -> void:
		set_pressed_no_signal(v)
		_knob_t = 1.0 if v else 0.0
		queue_redraw()

	func _animate_knob(v: bool) -> void:
		if not is_inside_tree():
			_knob_t = 1.0 if v else 0.0
			queue_redraw()
			return
		var t := create_tween()
		t.tween_method(func(x: float): _knob_t = x; queue_redraw(),
			_knob_t, 1.0 if v else 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Reference toggle is a solid green pill when on, dim slate when off —
		# richer/more saturated than a subtle glow lerp.
		var track_col: Color = Color(0.16, 0.18, 0.26, 0.95).lerp(UiKit.GREEN_FACE, _knob_t)
		var pts := ShapeDrawUtils.rounded_rect_points(Vector2(w, h), h * 0.5, 5)
		var poly := PackedVector2Array()
		for p in pts:
			poly.append(p + Vector2(w, h) * 0.5)
		draw_colored_polygon(poly, track_col)
		var closed := poly.duplicate()
		closed.append(closed[0])
		draw_polyline(closed, UiKit.GREEN_DEEP.lerp(UiKit.GOLD, 1.0 - _knob_t), 2.0, true)
		var r := h * 0.5 - 4.0
		var kx: float = lerpf(r + 4.0, w - r - 4.0, _knob_t)
		var font := ThemeDB.fallback_font
		var fs := int(h * 0.36)
		var label := "ON" if _knob_t > 0.5 else "OFF"
		var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# Keep the label clear of the knob's left/right edge, whichever side it
		# sits on, instead of a fixed offset that can clip under the knob.
		var text_x: float = 10.0 if _knob_t > 0.5 else maxf(w - 10.0 - text_w, kx + r + 6.0)
		draw_string(font, Vector2(text_x, h * 0.5 + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 1, 1, 0.9) if _knob_t > 0.5 else Color(1, 1, 1, 0.55))
		var knob_center := Vector2(kx, h * 0.5)
		draw_circle(knob_center, r + 2.5, Color(0, 0, 0, 0.35))
		draw_circle(knob_center, r, Color(0.97, 0.96, 0.93))
		draw_arc(knob_center, r - 1.0, 0, TAU, 20, UiKit.GOLD_DEEP.lerp(UiKit.GOLD, _knob_t), 2.0, true)

static func toggle(value: bool = false) -> ToggleSwitch:
	var t := ToggleSwitch.new()
	t.set_state(value)
	attach_press_feedback(t)
	return t

## Fantasy volume slider (2026-09-05 UI pass, Settings reference match) — a
## thin recessed track with a solid green fill and a cream gold-rimmed knob,
## replacing the unthemed stock `HSlider`. Range 0..1 like the old slider.
class VolumeSlider extends Range:
	signal value_changed_by_user(v: float)
	var _dragging := false

	func _init() -> void:
		min_value = 0.0
		max_value = 1.0
		step = 0.01
		custom_minimum_size = Vector2(130, 34)
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				_set_from_x(event.position.x)
		elif event is InputEventScreenTouch:
			_dragging = event.pressed
			if event.pressed:
				_set_from_x(event.position.x)
		elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _dragging:
			_set_from_x(event.position.x)

	func _set_from_x(x: float) -> void:
		var r := size.y * 0.5
		var t := clampf((x - r) / maxf(size.x - r * 2.0, 1.0), 0.0, 1.0)
		value = lerpf(min_value, max_value, t)
		value_changed_by_user.emit(value)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := h * 0.5
		var track := Rect2(Vector2(0, h * 0.5 - 4.0), Vector2(w, 8.0))
		_rrect(track, 4.0, Color(0.12, 0.13, 0.20, 0.9))
		var t: float = (value - min_value) / maxf(max_value - min_value, 0.0001)
		var fill_w: float = maxf(lerpf(0.0, w, t), 8.0)
		_rrect(Rect2(Vector2(0, h * 0.5 - 4.0), Vector2(fill_w, 8.0)), 4.0, UiKit.GREEN_FACE)
		var kx: float = lerpf(r, w - r, t)
		var kc := Vector2(kx, h * 0.5)
		draw_circle(kc, r, Color(0, 0, 0, 0.30))
		draw_circle(kc, r - 2.0, Color(0.97, 0.96, 0.93))
		draw_arc(kc, r - 3.0, 0, TAU, 16, UiKit.GOLD_DEEP, 2.0, true)

	func _rrect(r: Rect2, radius: float, col: Color) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, radius, 4)
		var poly := PackedVector2Array()
		for p in pts:
			poly.append(p + r.position + r.size * 0.5)
		draw_colored_polygon(poly, col)

static func volume_slider(value: float = 1.0) -> VolumeSlider:
	var s := VolumeSlider.new()
	s.value = value
	return s

# --------------------------------------------------------------- toasts --

## Consolidated toast/notification (2026-09-05 UI pass) — replaces 3
## near-identical copies that used to live in settings_panel.gd /
## main_menu.gd / level_map.gd, and is the base for the "OBJECTIVE
## COMPLETE" / "CHAPTER COMPLETE" / "NEW BOOSTER" / "NEW EQUIPMENT" moments
## (see app.gd / booster_shop.gd). Spawns its own throwaway Label so
## concurrent toasts stack instead of one call resetting another's
## animation. `parent` must be a Control already sized (it centers within
## it); `accent` tints the glass border so different moments can read as
## distinct without new art.
static func show_toast(parent: Control, text: String, accent: Color = GOLD) -> void:
	var toast := VisualTheme.label("  %s  " % text, VisualTheme.FS_BODY, VisualTheme.TEXT, 5)
	var sb := glass(16, true)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.border_width_top = 2
	toast.add_theme_stylebox_override("normal", sb)
	toast.modulate.a = 0.0
	toast.z_index = 200
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(toast)
	await parent.get_tree().process_frame
	toast.position = Vector2((parent.size.x - toast.size.x) * 0.5, parent.size.y * 0.72)
	var t := toast.create_tween()
	t.tween_property(toast, "modulate:a", 1.0, 0.14)
	t.tween_interval(1.2)
	t.tween_property(toast, "modulate:a", 0.0, 0.3)
	t.tween_callback(toast.queue_free)

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

	## Overrides the panel fill color in place — lets a specific dialog (e.g.
	## Settings' reference-matched deep violet) diverge from the default navy
	## fill without a whole new panel class.
	func set_bg_color(c: Color) -> void:
		var sb := (get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
		sb.bg_color = c
		add_theme_stylebox_override("panel", sb)

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
			&"bag":
				# a small shopping bag: rounded-top body + handle arc
				var bw := r * 1.7
				var bh := r * 1.9
				var body := Rect2(c + Vector2(-bw * 0.5, -bh * 0.28), Vector2(bw, bh))
				draw_rect(body, VisualTheme.TEXT_GOLD)
				draw_rect(body.grow(-3.0), Color(0.13, 0.16, 0.26))
				draw_arc(c + Vector2(0, -bh * 0.28), bw * 0.34, PI, TAU, 16, VisualTheme.TEXT_GOLD, 4.0, true)
				draw_rect(Rect2(c + Vector2(-bw * 0.5, -bh * 0.28), Vector2(bw, 4.0)), VisualTheme.TEXT_GOLD)
			&"chevron":
				draw_line(c + Vector2(-r * 0.4, -r), c + Vector2(r * 0.5, 0), Color(1, 1, 1), 5.0, true)
				draw_line(c + Vector2(r * 0.5, 0), c + Vector2(-r * 0.4, r), Color(1, 1, 1), 5.0, true)
			&"pause":
				var w := r * 0.5
				draw_rect(Rect2(c + Vector2(-r, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
				draw_rect(Rect2(c + Vector2(r - w, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
			_:
				draw_circle(c, r, VisualTheme.TEXT)
