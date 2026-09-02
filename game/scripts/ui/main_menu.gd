class_name MainMenu
extends Control
## Home screen: the Color Clash wordmark over the shared premium Backdrop, a
## slow-drifting gem-cluster motif filling the middle, a big PLAY button into
## the campaign map, Daily Reward + Settings, a currency readout under the
## status bar and a single version line above the gesture bar. Built in code,
## no scene/assets. Fully safe-area aware and anchor-driven.

signal play_pressed()
signal daily_pressed()

const VERSION_TEXT := "v0.5  •  offline"

var _coins_label: Label
var _gems_label: Label
var _options: CenterContainer
var _daily_btn: Button
var _daily_dot: Control
var _top_bar: MarginContainer
var _button_col: VBoxContainer
var _version: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	var bg := Backdrop.new()
	bg.accent = VisualTheme.ACCENT
	bg.scene_id = &"env_floating_particles"
	add_child(bg)

	var motif := GemClusterMotif.new()
	motif.set_anchors_preset(Control.PRESET_FULL_RECT)
	motif.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(motif)

	var title := TitleBlock.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# --- currency row, pinned under the status bar ----------------------
	_top_bar = MarginContainer.new()
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(_top_bar)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 18)
	_top_bar.add_child(top)
	_coins_label = _pill(top, &"coin", VisualTheme.TEXT_GOLD)
	_gems_label = _pill(top, &"crystal", Color(0.82, 0.72, 1.0))

	# --- button column, anchored to the lower third --------------------
	_button_col = VBoxContainer.new()
	_button_col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_button_col.alignment = BoxContainer.ALIGNMENT_END
	_button_col.add_theme_constant_override("separation", 16)
	add_child(_button_col)

	var play: BaseButton
	var play_tex := AssetLibrary.tex(&"ui_play_button")
	if play_tex != null:
		var tb := TextureButton.new()
		tb.texture_normal = play_tex
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.custom_minimum_size = Vector2(0, 156)
		tb.focus_mode = Control.FOCUS_NONE
		play = tb
	else:
		play = _big_button("PLAY", VisualTheme.GOOD, VisualTheme.FS_HEADING)
		play.custom_minimum_size = Vector2(0, 88)
	play.pressed.connect(func():
		Audio.play(&"button_tap")
		_bounce(play)
		play_pressed.emit()
	)
	_button_col.add_child(play)

	_daily_btn = _big_button("DAILY REWARD", VisualTheme.STAR.darkened(0.05), VisualTheme.FS_BUTTON)
	_daily_btn.custom_minimum_size = Vector2(0, 72)
	_daily_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		daily_pressed.emit()
	)
	_button_col.add_child(_daily_btn)
	_daily_dot = ClaimDot.new()
	_daily_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_daily_dot.position = Vector2(-26, 8)
	_daily_dot.custom_minimum_size = Vector2(22, 22)
	_daily_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_daily_btn.add_child(_daily_dot)

	var opt := _big_button("SETTINGS", VisualTheme.ACCENT, VisualTheme.FS_BUTTON)
	opt.custom_minimum_size = Vector2(0, 72)
	opt.pressed.connect(func():
		Audio.play(&"button_tap")
		_options.visible = true
		_bounce(_options.get_child(0))
	)
	_button_col.add_child(opt)

	# --- single version line, above the gesture bar -------------------
	_version = VisualTheme.label(VERSION_TEXT, VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0)
	_version.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_version)

	_build_options()
	_apply_safe_area()
	refresh()

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	_apply_safe_area()

func _apply_safe_area() -> void:
	if _top_bar == null:
		return
	var si := VisualTheme.safe_insets(self)
	_top_bar.add_theme_constant_override("margin_top", int(si.position.y + 18.0))
	_top_bar.add_theme_constant_override("margin_left", 24)
	_top_bar.add_theme_constant_override("margin_right", 24)
	var vpw := get_viewport_rect().size.x
	var btn_w: float = clampf(vpw - 96.0, 280.0, 620.0)
	_button_col.offset_left = (vpw - btn_w) * 0.5
	_button_col.offset_right = -(vpw - btn_w) * 0.5
	_button_col.offset_bottom = -(si.size.y + 76.0)
	_button_col.offset_top = -(si.size.y + 76.0 + 280.0)
	_version.offset_top = -(si.size.y + 34.0)
	_version.offset_bottom = -(si.size.y + 10.0)

func refresh() -> void:
	_coins_label.text = str(Economy.coins)
	_gems_label.text = str(SaveService.get_int("gems", 0))
	if _daily_dot != null:
		_daily_dot.visible = DailyRewardsScreen.has_claimable()

func _pill(parent: Control, kind: StringName, tc: Color) -> Label:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", VisualTheme.panel(VisualTheme.PANEL, 20, VisualTheme.PANEL_BORDER, 2))
	parent.add_child(pc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pc.add_child(row)
	var icon := HUD.GemIcon.new()
	icon.kind = kind
	icon.tint = VisualTheme.GEM
	icon.custom_minimum_size = Vector2(26, 26)
	row.add_child(icon)
	var lbl := VisualTheme.label("0", VisualTheme.FS_LABEL, tc)
	row.add_child(lbl)
	return lbl

func _big_button(text: String, tint: Color, fs: int) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", VisualTheme.TEXT)
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_color_override("font_outline_color", VisualTheme.OUTLINE)
	b.add_theme_stylebox_override("normal", VisualTheme.button_face(tint.darkened(0.1)))
	b.add_theme_stylebox_override("hover", VisualTheme.button_face(tint))
	b.add_theme_stylebox_override("pressed", VisualTheme.button_face(tint.darkened(0.3)))
	b.focus_mode = Control.FOCUS_NONE
	return b

func _build_options() -> void:
	_options = CenterContainer.new()
	_options.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options.visible = false
	_options.z_index = 50
	add_child(_options)

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_options.add_child(scrim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 360)
	panel.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.09, 0.10, 0.19, 0.98), 28, VisualTheme.PANEL_BORDER_BRIGHT, 2))
	_options.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var t := VisualTheme.label("SETTINGS", VisualTheme.FS_TITLE, VisualTheme.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_toggle("Music", AudioSettings.music_enabled, func(x): AudioSettings.set_music_enabled(x)))
	v.add_child(_toggle("Sound Effects", AudioSettings.sfx_enabled, func(x): AudioSettings.set_sfx_enabled(x)))
	v.add_child(_toggle("Haptics", AudioSettings.haptics_enabled, func(x): AudioSettings.set_haptics_enabled(x)))
	var close := _big_button("CLOSE", VisualTheme.ACCENT, VisualTheme.FS_BUTTON)
	close.custom_minimum_size = Vector2(220, 64)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		Audio.play(&"button_tap")
		_options.visible = false
	)
	v.add_child(close)

func _toggle(text: String, initial: bool, fn: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := VisualTheme.label(text, VisualTheme.FS_BODY, VisualTheme.TEXT_DIM, 0)
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	var cb := CheckButton.new()
	cb.button_pressed = initial
	cb.toggled.connect(func(x):
		Audio.play(&"button_tap")
		fn.call(x)
	)
	row.add_child(cb)
	return row

func _bounce(node: Control) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2(1.05, 1.05), 0.08)
	t.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Pulsing "you have something" badge on the Daily Reward button.
class ClaimDot extends Control:
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var p := 0.6 + 0.4 * sin(_t * 6.0)
		draw_circle(c, 12.0 * p, Color(1, 0.3, 0.3, 0.4))
		draw_circle(c, 8.0, Color(1, 0.35, 0.35))
		draw_circle(c + Vector2(-2, -2), 3.0, Color(1, 0.8, 0.8))


## Wordmark + tagline, gently bobbing, positioned in the upper quarter with
## a soft glow so it never collides with the status bar or the buttons.
class TitleBlock extends Control:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x < 1.0:
			return
		var si := VisualTheme.safe_insets(self)
		var cx := s.x * 0.5
		var cy: float = maxf(s.y * 0.24, si.position.y + 150.0) + sin(_t * 1.4) * 5.0
		var fs: float = clampf(s.x * 0.115, 46.0, 78.0)
		VisualTheme.draw_glow(self, Vector2(cx, cy), s.x * 0.55, Color(0.5, 0.6, 1.0, 0.14), 6)
		VisualTheme.draw_wordmark(self, Vector2(cx, cy), fs, 1.0)
		var font := ThemeDB.fallback_font
		var tag := "CONNECT   BLAST   COMBO"
		var tfs := int(clampf(s.x * 0.028, 18.0, 26.0))
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		draw_string_outline(font, Vector2(cx - tw * 0.5, cy + fs * 0.95), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 4, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(cx - tw * 0.5, cy + fs * 0.95), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0.74, 0.84, 0.98))


## A calm arc of six glossy hex gems drifting behind the middle of the menu —
## the game's own visual language filling what used to be dead space, kept
## faint and evenly spaced so the wordmark and buttons stay dominant.
class GemClusterMotif extends Control:
	var _t := 0.0
	const _HUES := [
		Color(0.95, 0.30, 0.42), Color(1.0, 0.62, 0.24), Color(1.0, 0.85, 0.30),
		Color(0.36, 0.82, 0.52), Color(0.34, 0.62, 1.0), Color(0.64, 0.40, 0.96),
	]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	const _GEM_KEYS := [&"gem_red", &"gem_orange", &"gem_yellow", &"gem_green", &"gem_blue", &"gem_purple"]

	func _draw() -> void:
		var s := size
		if s.x < 1.0:
			return
		var center := Vector2(s.x * 0.5, s.y * 0.46)
		var ring_r := s.x * 0.30
		for i in 6:
			var base_a := TAU * float(i) / 6.0 - PI * 0.5 + _t * 0.06
			var p := center + Vector2(cos(base_a), sin(base_a) * 0.72) * ring_r
			p.y += sin(_t * 0.8 + float(i) * 1.3) * 12.0
			var r: float = (52.0 + 7.0 * sin(_t * 0.6 + float(i))) * (1.0 if s.x > 700.0 else 0.8)
			var col: Color = _HUES[i]
			# real prepared gem art (#1-6), faint so the wordmark + buttons stay
			# dominant; procedural hex if the art is missing.
			var tex := AssetLibrary.tex(_GEM_KEYS[i])
			if tex != null:
				var d := r * 2.6
				for k in range(3, 0, -1):
					var kt := float(k) / 3.0
					draw_circle(p, r * 1.4 * kt, Color(col.r, col.g, col.b, 0.05 * (1.0 - kt)))
				draw_texture_rect(tex, Rect2(p - Vector2(d, d) * 0.5, Vector2(d, d)), false, Color(1, 1, 1, 0.5))
				continue
			for k in range(4, 0, -1):
				var kt := float(k) / 4.0
				draw_circle(p, r * 1.5 * kt, Color(col.r, col.g, col.b, 0.035 * (1.0 - kt)))
			var pts := PackedVector2Array()
			for j in 6:
				var a := PI / 6.0 + TAU * float(j) / 6.0
				pts.append(p + Vector2(cos(a), sin(a)) * r)
			draw_polygon(pts, ShapeDrawUtils.vertical_shade(pts,
				Color(col.r, col.g, col.b, 0.17), Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 0.14)))
			draw_circle(p + Vector2(-r * 0.28, -r * 0.3), r * 0.18, Color(1, 1, 1, 0.12))
			pts.append(pts[0])
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.22), 2.0, true)
