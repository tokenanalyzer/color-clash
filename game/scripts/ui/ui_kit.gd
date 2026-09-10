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

## Fantasy BACK button for the island screens: a wide glass pill with a big
## left-pointing gold chevron (the chevron glyph mirrored, per the brief — a
## flip transform, not a new arrow) + a readable "BACK" label. Comfortably
## tappable; nothing clips.
static func back_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(176, 88)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = false
	var sb := glass(24, true)
	sb.border_color = GOLD
	sb.set_border_width_all(3)
	for pad in ["content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		sb.set(pad, 0)
	b.add_theme_stylebox_override("normal", sb)
	var hsb := glass(24, true)
	hsb.border_color = GOLD
	hsb.set_border_width_all(3)
	b.add_theme_stylebox_override("hover", hsb)
	var psb := glass(24, true)
	psb.bg_color = psb.bg_color.darkened(0.15)
	b.add_theme_stylebox_override("pressed", psb)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var g := _Glyph.new()
	g.glyph = &"chevron_left"
	g.custom_minimum_size = Vector2(48, 48)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(g)
	var lbl := VisualTheme.label("BACK", VisualTheme.FS_HEADING, VisualTheme.TEXT_GOLD)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
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
			&"chevron_left":
				# the back arrow: the chevron mirrored on X, drawn bigger + bolder
				var rr := minf(size.x, size.y) * 0.40
				var w := maxf(rr * 0.34, 6.0)
				draw_line(c + Vector2(rr * 0.55, -rr), c + Vector2(-rr * 0.55, 0), VisualTheme.TEXT_GOLD, w, true)
				draw_line(c + Vector2(-rr * 0.55, 0), c + Vector2(rr * 0.55, rr), VisualTheme.TEXT_GOLD, w, true)
			&"pause":
				var w := r * 0.5
				draw_rect(Rect2(c + Vector2(-r, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
				draw_rect(Rect2(c + Vector2(r - w, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
			_:
				draw_circle(c, r, VisualTheme.TEXT)


# ============================================================ supplied UI art ==
## 2026-09-06 UI asset integration. These wrap the artist-supplied UI sheets
## (via AssetLibrary.ui_slice / ui_texture) as interactive Control nodes. The
## artwork is rendered VERBATIM — only uniform aspect scaling, a hit area,
## and a non-destructive press squash; nothing is redrawn. Every helper
## returns null / reports `available() == false` when its asset is missing,
## so a caller can fall back to the procedural widgets above.

## A plain TextureRect for one supplied slice (icon / banner / day-tile /
## value pill / divider). Aspect-locked, never stretched, sized to native px
## by default. Returns null if the slice is missing.
static func asset_rect(id: StringName, mouse_ignore: bool = true) -> TextureRect:
	var t := AssetLibrary.ui_slice(id)
	if t == null:
		return null
	var tr := TextureRect.new()
	tr.texture = t
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(t.get_width(), t.get_height())
	if mouse_ignore:
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## A button whose whole face is a supplied texture (a full PNG via
## AssetLibrary.ui_texture, or an atlas slice). Aspect-locked, press-squash
## feedback only — the art is never recoloured or redrawn. Returns null if
## `tex` is null.
static func asset_button(tex: Texture2D) -> TextureButton:
	if tex == null:
		return null
	var b := TextureButton.new()
	b.texture_normal = tex
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(tex.get_width(), tex.get_height())
	attach_press_feedback(b)
	return b


## The group AssetFramePanel.layout() scans to size aspect-locked children:
## it sets each member's custom_minimum_size to (interior_w * wfrac) wide and
## that / aspect tall, so a wide banner scales to the panel with no
## distortion. AspectRatioContainer can't do this inside a VBox (it reports
## no useful minimum height), hence the explicit pass.
const ASPECT_FIT_GROUP := "ui_aspect_fit"

static func _tag_aspect_fit(n: Control, tex: Texture2D, wfrac: float) -> void:
	if tex == null or tex.get_height() <= 0:
		return
	tag_aspect_fit(n, float(tex.get_width()) / float(tex.get_height()), wfrac)

## Register any Control so AssetFramePanel.layout() sizes it to
## (interior_width * wfrac) wide and that / aspect tall — used for the day
## tiles so both calendar rows come out the exact same size.
static func tag_aspect_fit(n: Control, aspect: float, wfrac: float) -> void:
	n.set_meta("aspect", maxf(aspect, 0.05))
	n.set_meta("wfrac", clampf(wfrac, 0.02, 1.0))
	n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not n.is_in_group(ASPECT_FIT_GROUP):
		n.add_to_group(ASPECT_FIT_GROUP)

## A supplied-texture button that AssetFramePanel scales to `wfrac` of the
## panel's interior width, aspect-locked. Press-squash feedback only; the
## art is never redrawn. Returns null if `tex` is null.
static func asset_button_fw(tex: Texture2D, wfrac: float = 1.0) -> TextureButton:
	var b := asset_button(tex)
	if b == null:
		return null
	_tag_aspect_fit(b, tex, wfrac)
	return b

## Non-interactive equivalent (banner / day tile / value pill / divider).
static func asset_rect_fw(id: StringName, wfrac: float = 1.0) -> TextureRect:
	var tr := asset_rect(id)
	if tr == null:
		return null
	_tag_aspect_fit(tr, AssetLibrary.ui_slice(id), wfrac)
	return tr


## Full-screen dialog shell built on a supplied decorative frame slice. The
## frame is shown at (viewport_width - 2*side_margin) wide, aspect-locked,
## vertically centred — nearly the whole portrait width, ~side_margin px gap
## each edge, ornate border never stretched. Call `layout(viewport_size)`
## from the owner's viewport-resize handler. Content goes in `content()`, a
## MarginContainer inset to the frame's interior safe-area (plus `extra_pad`
## px of breathing room) so it clears the gold border and corner ornaments.
## A `set_banner()` slice straddles the top edge; a `set_close_x()` slice
## sits in the top-right corner — both owned here so every screen matches.
class AssetFramePanel extends Control:
	var _frame_id: StringName
	var _margin: float
	var _extra: float
	var _box: Control
	var _frame: TextureRect
	var _inner: MarginContainer
	var _banner: TextureRect
	var _banner_wfrac := 0.62
	var _close_x: TextureButton
	## Extra top content inset as a fraction of panel height, on top of the
	## frame safe-area — used to drop the first row clear of the header/banner
	## the way each reference mock does.
	var _content_top_frac := 0.0
	## ✕ centre as a fraction of panel width (the references put it ~0.87,
	## overlapping the top-right corner, NOT jammed against the edge).
	var _close_cx_frac := 0.87

	func _init(frame_id: StringName, side_margin: float = 10.0, extra_pad: float = 18.0) -> void:
		_frame_id = frame_id
		_margin = side_margin
		_extra = extra_pad
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		_box = Control.new()
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_box)

		_frame = TextureRect.new()
		_frame.texture = AssetLibrary.ui_slice(_frame_id)
		_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame.mouse_filter = Control.MOUSE_FILTER_STOP   # blocks taps falling through the panel
		_box.add_child(_frame)

		_inner = MarginContainer.new()
		_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(_inner)

	func has_art() -> bool:
		return AssetLibrary.ui_slice(_frame_id) != null

	## Extra top inset (fraction of panel height) so the first content row
	## drops clear of the header/banner, matching the reference mock.
	func set_content_top(frac: float) -> void:
		_content_top_frac = maxf(frac, 0.0)

	func content() -> MarginContainer:
		return _inner

	## The node to run pop_in / pop_out on (so the scrim isn't scaled).
	func visual() -> Control:
		return _box

	## A title slice hung across the frame's top edge (baked text). `wfrac`
	## is its width as a fraction of the panel width.
	func set_banner(slice_id: StringName, wfrac: float = 0.62) -> void:
		_banner_wfrac = wfrac
		var t := AssetLibrary.ui_slice(slice_id)
		if t == null:
			return
		_banner = TextureRect.new()
		_banner.texture = t
		_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.z_index = 4
		_box.add_child(_banner)

	## The red ✕, parked in the frame's top-right corner (fully inside).
	func set_close_x(slice_id: StringName, on_press: Callable) -> void:
		var t := AssetLibrary.ui_slice(slice_id)
		if t == null:
			return
		_close_x = UiKit.asset_button(t)
		_close_x.z_index = 6
		if on_press.is_valid():
			_close_x.pressed.connect(on_press)
		_box.add_child(_close_x)

	## True once the panel has a real size (safe to pop_in / read `visual()`).
	func is_laid_out() -> bool:
		return _box.size.x > 1.0

	func layout(viewport: Vector2) -> void:
		if viewport.x < 2.0 or viewport.y < 2.0:
			return
		var aspect: float = AssetLibrary.ui_aspect(_frame_id)
		var bleed: float = AssetLibrary.ui_bleed(_frame_id)
		# over-size by the slice's transparent outer margin so the *visible*
		# gold border lands at `_margin` px from the screen edge, not the
		# artwork's transparent bounding box.
		var w: float = (viewport.x - _margin * 2.0) / maxf(1.0 - 2.0 * bleed, 0.5)
		var h: float = w / maxf(aspect, 0.01)
		var max_h: float = viewport.y / maxf(1.0 - 2.0 * bleed, 0.5) - 12.0
		if h > max_h:
			h = max_h
			w = h * aspect
		_box.size = Vector2(w, h)
		_box.pivot_offset = Vector2(w, h) * 0.5
		_box.position = ((viewport - Vector2(w, h)) * 0.5).round()

		var s: Dictionary = AssetLibrary.ui_safe(_frame_id)
		var ml := int(round(w * s["left"] + _extra))
		var mr := int(round(w * s["right"] + _extra))
		var mt := int(round(h * s["top"] + _extra + h * _content_top_frac))
		var mb := int(round(h * s["bottom"] + _extra))
		# leave headroom for the banner if one straddles the top edge
		if _banner != null and _banner.texture != null:
			var bw := w * _banner_wfrac
			var bh := bw / maxf(float(_banner.texture.get_width()) / float(_banner.texture.get_height()), 0.01)
			mt = int(maxf(mt, bh * 0.62 + _extra + h * _content_top_frac))
			_banner.size = Vector2(bw, bh)
			_banner.position = Vector2((w - bw) * 0.5, -bh * 0.30 + h * s["top"] * 0.15)
		_inner.add_theme_constant_override("margin_left", ml)
		_inner.add_theme_constant_override("margin_right", mr)
		_inner.add_theme_constant_override("margin_top", mt)
		_inner.add_theme_constant_override("margin_bottom", mb)

		if _close_x != null and _close_x.texture_normal != null:
			var xs := clampf(w * 0.115, 88.0, 160.0)
			_close_x.size = Vector2(xs, xs)
			# reference position: centre ~0.87 of panel width, centre roughly
			# on the top border line — overlapping the corner, well inside the
			# screen so the whole hit area is tappable.
			_close_x.position = Vector2(w * _close_cx_frac - xs * 0.5, maxf(h * 0.028, 6.0))

		# size every aspect-locked child to the interior width
		_size_aspect_fit(_inner, w - ml - mr)

	func _size_aspect_fit(node: Node, iw: float) -> void:
		for c in node.get_children():
			if c is Control and (c as Control).is_in_group(UiKit.ASPECT_FIT_GROUP) and c.has_meta("aspect"):
				var wf: float = c.get_meta("wfrac", 1.0)
				var asp: float = c.get_meta("aspect", 1.0)
				var cw: float = iw * wf
				(c as Control).custom_minimum_size = Vector2(cw, cw / maxf(asp, 0.01))
			_size_aspect_fit(c, iw)


## Toggle rendered from the supplied ON / OFF switch slices. Same public API
## as UiKit.ToggleSwitch (`toggled_value` signal, `set_state()`) so screens
## can swap between them freely.
class AssetToggle extends Button:
	signal toggled_value(v: bool)
	var _on_tex: Texture2D
	var _off_tex: Texture2D
	var _tr: TextureRect

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		_on_tex = AssetLibrary.ui_slice(&"settings_toggle_on")
		_off_tex = AssetLibrary.ui_slice(&"settings_toggle_off")
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, empty)
		var ref: Texture2D = _on_tex if _on_tex != null else _off_tex
		if ref != null:
			custom_minimum_size = Vector2(ref.get_width(), ref.get_height())
		_tr = TextureRect.new()
		_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tr)
		toggled.connect(func(v: bool):
			_apply(v)
			toggled_value.emit(v))
		_apply(false)

	static func available() -> bool:
		return AssetLibrary.ui_slice(&"settings_toggle_on") != null \
			and AssetLibrary.ui_slice(&"settings_toggle_off") != null

	func set_state(v: bool) -> void:
		set_pressed_no_signal(v)
		_apply(v)

	func _apply(v: bool) -> void:
		_tr.texture = _on_tex if v else _off_tex


## Volume slider drawn from the supplied track + knob slices. Same public API
## as UiKit.VolumeSlider (`value_changed_by_user` signal, Range 0..1).
class AssetSlider extends Range:
	signal value_changed_by_user(v: float)
	var _bg: NinePatchRect
	var _fill: NinePatchRect
	var _knob: TextureRect
	var _dragging := false

	func _init() -> void:
		min_value = 0.0
		max_value = 1.0
		step = 0.01
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		var knob_tex := AssetLibrary.ui_slice(&"settings_slider_knob")
		var kh: float = 34.0
		if knob_tex != null:
			kh = float(knob_tex.get_height())
		custom_minimum_size = Vector2(160, kh)

		_bg = _np(&"settings_slider_bg")
		add_child(_bg)
		_fill = _np(&"settings_slider_fill")
		add_child(_fill)
		_knob = TextureRect.new()
		_knob.texture = knob_tex
		_knob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_knob.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if knob_tex != null:
			_knob.size = Vector2(knob_tex.get_width(), knob_tex.get_height())
		add_child(_knob)
		resized.connect(_relayout)
		value_changed.connect(func(_v: float): _relayout())

	static func available() -> bool:
		return AssetLibrary.ui_slice(&"settings_slider_fill") != null \
			and AssetLibrary.ui_slice(&"settings_slider_bg") != null

	func _np(id: StringName) -> NinePatchRect:
		var n := NinePatchRect.new()
		n.texture = AssetLibrary.ui_slice(id)
		var m: Array = AssetLibrary.ui_nine(id)
		if m.size() == 4:
			n.patch_margin_left = int(m[0])
			n.patch_margin_top = int(m[1])
			n.patch_margin_right = int(m[2])
			n.patch_margin_bottom = int(m[3])
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return n

	func _ready() -> void:
		_relayout()

	func _relayout() -> void:
		var w: float = size.x
		var h: float = size.y
		var frac: float = clampf((value - min_value) / maxf(max_value - min_value, 0.0001), 0.0, 1.0)
		var th: float = h
		if _bg.texture != null:
			th = minf(float(_bg.texture.get_height()), h)
		var ty: float = (h - th) * 0.5
		_bg.position = Vector2(0, ty)
		_bg.size = Vector2(w, th)
		var kr: float = h * 0.5
		var kx: float = lerpf(kr, w - kr, frac)
		_fill.position = Vector2(0, ty)
		_fill.size = Vector2(maxf(kx, kr * 2.0), th)
		if _knob != null:
			_knob.position = Vector2(kx - _knob.size.x * 0.5, (h - _knob.size.y) * 0.5)

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
		var kr: float = size.y * 0.5
		var t: float = clampf((x - kr) / maxf(size.x - kr * 2.0, 1.0), 0.0, 1.0)
		value = lerpf(min_value, max_value, t)
		value_changed_by_user.emit(value)


# ================================================== gameplay top bar art ==
## 2026-09-06 asset pass. Renders a number using the artist-supplied gold
## digit glyphs from `topbar_elements.png` (tb_d0..tb_d9) instead of a font,
## so MOVES / SCORE match the reference exactly. Duck-types `Label`: it has
## a `text` String property (assigning re-lays the glyphs) and silently
## accepts `add_theme_color_override` so the existing HUD setters keep
## working. `digit_h` (or custom_minimum_size.y) is the glyph height.
class GlyphNum extends Control:
	var digit_h: float = 44.0:
		set(v):
			if is_equal_approx(v, digit_h):
				return
			digit_h = v
			if _ready_done:
				_rebuild()
	var kerning: float = -6.0
	var align_center := true
	var warn := false:
		set(v):
			warn = v
			modulate = Color(1.0, 0.55, 0.5) if v else Color(1, 1, 1)
	var text: String = "0":
		set(v):
			if v == text and _ready_done and not _glyphs.is_empty():
				return
			text = v
			if _ready_done:
				_rebuild()

	var _glyphs: Array[TextureRect] = []
	var _ready_done := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if custom_minimum_size.y > 1.0 and digit_h == 44.0:
			digit_h = custom_minimum_size.y
		_ready_done = true
		_rebuild()

	func _rebuild() -> void:
		for c in get_children():
			remove_child(c)
			c.free()
		_glyphs.clear()
		var run := ""
		for ch in text:
			if ch >= "0" and ch <= "9":
				run += ch
		if run.is_empty():
			run = "0"
		var x := 0.0
		var h := digit_h
		for ch in run:
			var tex := AssetLibrary.ui_slice(StringName("tb_d%s" % ch))
			var g := TextureRect.new()
			g.texture = tex
			g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			g.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var gw := h
			if tex != null and tex.get_height() > 0:
				gw = h * float(tex.get_width()) / float(tex.get_height())
			g.size = Vector2(gw, h)
			g.position = Vector2(x, 0)
			add_child(g)
			_glyphs.append(g)
			x += gw + kerning
		var total := maxf(x - kerning, 1.0)
		custom_minimum_size = Vector2(total, h)
		if align_center:
			# lay the run centred on this Control's own position, both axes —
			# callers put GlyphNum where they want the number's centre.
			for g in _glyphs:
				g.position.x -= total * 0.5
				g.position.y -= h * 0.5


## The gameplay FEVER bar drawn from the supplied standalone art
## (`tbn_fever_bar` frame — "FEVER" tab + end diamonds baked in — plus the
## `tbn_fever_crown` riding it near the left) with a gold fill clipped to
## `ratio`. Same public surface as the old procedural FeverArt (`ratio`,
## `active`, `flash`, `mult_text`) so `HUD.set_fever` / `flash_fever` keep
## working untouched. The bar art is aspect-fit to width and bottom-aligned
## in the wrap; the crown gets the headroom above it.
class FeverBarArt extends Control:
	var ratio: float = 0.0:
		set(v): ratio = clampf(v, 0.0, 1.0); _redraw_fill()
	var active := false:
		set(v): active = v; _redraw_fill()
	var flash: float = 0.0:
		set(v): flash = v; _redraw_fill()
	var mult_text := "x1.5"

	func _redraw_fill() -> void:
		if _fill != null:
			_fill.queue_redraw()

	var _frame: TextureRect
	var _crown: TextureRect
	var _fill: Control
	var _bar_rect := Rect2()
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = false
		_frame = TextureRect.new()
		_frame.texture = AssetLibrary.ui_texture(&"tbn_fever_bar")
		_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_frame.stretch_mode = TextureRect.STRETCH_SCALE
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_frame)
		_fill = _FeverFill.new()
		_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fill.owner_bar = self
		add_child(_fill)
		# 2026-09-07: the crown power-up is intentionally NOT placed on the
		# FEVER bar — there is no room to seat the supplied `tbn_fever_crown`
		# cleanly outside the meter (centred, clear of the track / fill / gold
		# frame, not touching the GOAL panel above) without disturbing the rest
		# of the top section, so per the brief it is left off for a clean UI.
		# `_crown` stays null; the asset remains registered for later use.
		_crown = null
		set_process(true)
		resized.connect(_relayout)
		_relayout()

	func _relayout() -> void:
		if _frame == null:
			return
		var aspect := 6.56
		var ft := _frame.texture
		if ft != null and ft.get_height() > 0:
			aspect = float(ft.get_width()) / float(ft.get_height())
		var bw := size.x
		var bhh := bw / aspect
		if bhh > size.y:
			bhh = size.y
			bw = bhh * aspect
		_bar_rect = Rect2((size.x - bw) * 0.5, size.y - bhh, bw, bhh)
		_frame.position = _bar_rect.position
		_frame.size = _bar_rect.size
		_fill.position = _bar_rect.position
		_fill.size = _bar_rect.size
		_fill.queue_redraw()
		if _crown != null:
			var ct := _crown.texture
			var cw := _bar_rect.size.x * 0.145
			var chh := cw * 0.816
			if ct != null and ct.get_width() > 0:
				chh = cw * float(ct.get_height()) / float(ct.get_width())
			_crown.size = Vector2(cw, chh)
			# rides the START of the meter, overlapping the right edge of the
			# "FEVER" tab: base on the track bottom rail, top poking above the
			# top rail (matches the reference composition).
			_crown.position = Vector2(
				_bar_rect.position.x + _bar_rect.size.x * 0.275 - cw * 0.5,
				_bar_rect.position.y + _bar_rect.size.y * 0.86 - chh)

	func _process(dt: float) -> void:
		_t += dt
		if flash > 0.0:
			flash = maxf(flash - dt * 3.0, 0.0)
		if active:
			_fill.queue_redraw()

	## Inner node that paints the energy fill EMBEDDED in the supplied bar's
	## dark inner groove. The groove is the recessed dark channel BETWEEN the
	## two gold rails of `tbn_fever_bar` (fever_bar.png, 1700x259), measured
	## row-by-row from its luma: it runs y≈93..193 (yfrac 0.359..0.745),
	## vertical centre 0.552, height 0.386 of the bar; horizontally x
	## 0.1118..0.8876. The fill is a THIN capsule — ~half the groove height —
	## centred in the groove with ~9.6% (of bar height) clearance above and
	## below and a small horizontal inset, so it never reaches the gold frame.
	## It grows left→right with `ratio`; geometry is bounded to the groove so
	## it is strictly clipped to the track. Colour is the bar art's gold
	## (#faad01) deepened, so it reads as contained energy rather than a
	## rectangle laid over the artwork.
	class _FeverFill extends Control:
		var owner_bar: UiKit.FeverBarArt
		const TRACK_L := 0.1118
		const TRACK_R := 0.8876
		const TRACK_CY := 0.552
		const TRACK_H := 0.386
		func _draw() -> void:
			if owner_bar == null:
				return
			var fl := size.x * (TRACK_L + 0.014)
			var fr := size.x * (TRACK_R - 0.014)
			var fh := size.y * TRACK_H * 0.5
			var cy := size.y * TRACK_CY
			var w := (fr - fl) * clampf(owner_bar.ratio, 0.0, 1.0)
			if w < 3.0:
				return
			var col := Color(0.85, 0.54, 0.07)
			if owner_bar.active:
				col = Color(0.96, 0.66, 0.12)
			if owner_bar.flash > 0.0:
				col = col.lerp(Color(1.0, 0.88, 0.52), clampf(owner_bar.flash, 0.0, 0.85))
			var rad := fh * 0.5
			var pts := ShapeDrawUtils.rounded_rect_points(Vector2(w, fh), minf(rad, w * 0.5), 4)
			var poly := PackedVector2Array()
			var origin := Vector2(fl, cy - fh * 0.5)
			for p in pts:
				poly.append(p + origin + Vector2(w, fh) * 0.5)
			draw_colored_polygon(poly, col)
			# soft top sheen so it catches light like the rest of the art
			var sh := ShapeDrawUtils.rounded_rect_points(Vector2(w, fh * 0.42), minf(rad, w * 0.5), 4)
			var spoly := PackedVector2Array()
			var sorigin := Vector2(fl, cy - fh * 0.5 + fh * 0.06)
			for p in sh:
				spoly.append(p + sorigin + Vector2(w, fh * 0.42) * 0.5)
			draw_colored_polygon(spoly, Color(1.0, 0.82, 0.38, 0.4))
			if owner_bar.active:
				var g := 0.35 + 0.25 * sin(owner_bar._t * 7.0)
				draw_colored_polygon(poly, Color(1.0, 0.9, 0.6, 0.12 * g))
