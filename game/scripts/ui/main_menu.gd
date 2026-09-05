class_name MainMenu
extends Control
## Home screen, reference-matched: the Color Clash wordmark (real PNG when
## supplied, else the tinted code wordmark) high on the screen, a large
## prominent PLAY button just above centre, DAILY REWARD + SETTINGS beneath
## it, and a frosted-glass currency bar under the status bar (no opaque
## strip). Built in code over the shared Backdrop; fully safe-area aware.

signal play_pressed()
signal daily_pressed()
signal inventory_pressed()

const VERSION_TEXT := "v0.5  •  offline"
## How far the logo (and, to preserve its tuned gap, the PLAY/action column
## below it) shift down from their original position (2026-09-05 UI pass —
## more breathing room under the taller currency chips).
const LOGO_DROP := 130.0

var _coins_label: Label
var _gems_label: Label
var _settings: SettingsPanel
var _daily_btn: Button
var _daily_dot: Control
var _top_bar: PanelContainer
var _top_bar_margin: MarginContainer
var _action_col: VBoxContainer
var _play_btn: Button
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

	# --- currency chips, no outer bar -------------------------------
	# 2026-09-05 UI pass: the chips already carry their own frosted-glass
	# pill (UiKit.currency_chip's glass(26)) — wrapping them in a SECOND,
	# bigger glass pill stacked the translucency into a flat, muddy dark
	# strip. Dropping the outer panel and just laying the two chips out
	# side by side reads far cleaner.
	_top_bar = PanelContainer.new()
	_top_bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_top_bar)
	_top_bar_margin = MarginContainer.new()
	_top_bar_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_top_bar.add_child(_top_bar_margin)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 20)
	_top_bar_margin.add_child(top)
	var coin := UiKit.currency_chip(&"coin", VisualTheme.TEXT_GOLD, true)
	_coins_label = coin["value"]
	(coin["plus"] as Button).pressed.connect(func(): UiKit.show_toast(self, "Shop coming soon"))
	top.add_child(coin["root"])
	var gem := UiKit.currency_chip(&"crystal", Color(0.82, 0.72, 1.0), true)
	_gems_label = gem["value"]
	(gem["plus"] as Button).pressed.connect(func(): UiKit.show_toast(self, "Shop coming soon"))
	top.add_child(gem["root"])

	# --- action column: PLAY (large) then DAILY + SETTINGS ----------
	_action_col = VBoxContainer.new()
	_action_col.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_action_col.add_theme_constant_override("separation", 18)
	add_child(_action_col)

	_play_btn = _make_play_button()
	_play_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		_bounce(_play_btn)
		play_pressed.emit()
	)
	_action_col.add_child(_play_btn)

	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 16)
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_col.add_child(sub)

	_daily_btn = UiKit.button("DAILY REWARD", &"secondary", VisualTheme.FS_BUTTON)
	_daily_btn.custom_minimum_size = Vector2(0, 82)
	_daily_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_daily_btn.clip_contents = false
	_daily_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		daily_pressed.emit()
	)
	sub.add_child(_daily_btn)
	_daily_dot = ClaimDot.new()
	_daily_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_daily_dot.position = Vector2(-18, 6)
	_daily_dot.custom_minimum_size = Vector2(22, 22)
	_daily_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_daily_btn.add_child(_daily_dot)

	var inv_btn := UiKit.button("INVENTORY", &"secondary", VisualTheme.FS_BUTTON)
	inv_btn.custom_minimum_size = Vector2(0, 82)
	inv_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		inventory_pressed.emit()
	)
	sub.add_child(inv_btn)

	var opt := UiKit.button("SETTINGS", &"tertiary", VisualTheme.FS_BUTTON)
	opt.custom_minimum_size = Vector2(0, 82)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.pressed.connect(func():
		Audio.play(&"button_tap")
		_settings.open()
	)
	sub.add_child(opt)

	_version = VisualTheme.label(VERSION_TEXT, VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0)
	_version.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_version)

	_settings = SettingsPanel.new()
	add_child(_settings)

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
	var vp := get_viewport_rect().size
	var bar_w: float = clampf(vp.x - 48.0, 280.0, 720.0)
	_top_bar.position = Vector2((vp.x - bar_w) * 0.5, si.position.y + 16.0)
	_top_bar.size = Vector2(bar_w, 76.0)
	_top_bar.custom_minimum_size = _top_bar.size
	_top_bar_margin.add_theme_constant_override("margin_left", 14)
	_top_bar_margin.add_theme_constant_override("margin_right", 14)

	var btn_w: float = clampf(vp.x - 90.0, 280.0, 560.0)
	_action_col.offset_left = (vp.x - btn_w) * 0.5
	_action_col.offset_right = -(vp.x - btn_w) * 0.5
	# PLAY centred around ~46% of the screen height — clearly the focus,
	# well clear of the bottom stone platform in the backdrop art. Shifted
	# down by LOGO_DROP to follow the logo and keep their gap unchanged.
	_action_col.offset_top = clampf(vp.y * 0.40, si.position.y + 220.0, vp.y - 340.0) + LOGO_DROP

	_version.offset_top = -(si.size.y + 32.0)
	_version.offset_bottom = -(si.size.y + 10.0)

func _make_play_button() -> Button:
	var b := UiKit.button("PLAY", &"primary", 44)
	b.custom_minimum_size = Vector2(0, 132)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = false
	b.add_theme_font_size_override("font_size", 46)
	# subtle idle breathing so the primary action draws the eye
	var t := b.create_tween().set_loops()
	t.tween_property(b, "scale", Vector2(1.02, 1.02), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(b, "scale", Vector2.ONE, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return b

func refresh() -> void:
	_coins_label.text = str(Economy.coins)
	_gems_label.text = str(SaveService.get_int("gems", 0))
	if _daily_dot != null:
		_daily_dot.visible = DailyRewardsScreen.has_claimable()

func _bounce(node: Control) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2(1.06, 1.06), 0.08)
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


## Wordmark + tagline, gently bobbing, in the upper quarter. Uses the real
## logo PNG (AssetLibrary &"brand_wordmark") when present, else the tinted
## code wordmark — so dropping the supplied logo in needs no code change.
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
		# Pushed down a fixed amount (2026-09-05 UI pass, see
		# MainMenu.LOGO_DROP) so the crest clears the now-taller currency
		# chips with real breathing room — _apply_safe_area() shifts the
		# PLAY/action column down by the same amount so the logo-to-button
		# gap this was already tuned against doesn't change.
		var cy: float = maxf(s.y * 0.20, si.position.y + 150.0) + MainMenu.LOGO_DROP + sin(_t * 1.4) * 5.0

		var logo := AssetLibrary.tex(&"brand_wordmark")
		if logo != null:
			var lw: float = minf(s.x * 0.78, 720.0)
			var lh := lw * float(logo.get_height()) / float(logo.get_width())
			VisualTheme.draw_glow(self, Vector2(cx, cy), s.x * 0.5, Color(0.5, 0.6, 1.0, 0.14), 6)
			draw_texture_rect(logo, Rect2(cx - lw * 0.5, cy - lh * 0.5, lw, lh), false)
			return

		var fs: float = clampf(s.x * 0.115, 46.0, 78.0)
		VisualTheme.draw_glow(self, Vector2(cx, cy), s.x * 0.55, Color(0.5, 0.6, 1.0, 0.14), 6)
		VisualTheme.draw_wordmark(self, Vector2(cx, cy), fs, 1.0)
		var font := ThemeDB.fallback_font
		var tag := "CONNECT   BLAST   COMBO"
		var tfs := int(clampf(s.x * 0.028, 18.0, 26.0))
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		draw_string_outline(font, Vector2(cx - tw * 0.5, cy + fs * 0.95), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 4, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(cx - tw * 0.5, cy + fs * 0.95), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0.74, 0.84, 0.98))


## A calm arc of six glossy hex gems drifting behind the middle of the menu.
class GemClusterMotif extends Control:
	var _t := 0.0
	const _HUES := [
		Color(0.95, 0.30, 0.42), Color(1.0, 0.62, 0.24), Color(1.0, 0.85, 0.30),
		Color(0.36, 0.82, 0.52), Color(0.34, 0.62, 1.0), Color(0.64, 0.40, 0.96),
	]
	const _GEM_KEYS := [&"gem_red", &"gem_orange", &"gem_yellow", &"gem_green", &"gem_blue", &"gem_purple"]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x < 1.0:
			return
		var center := Vector2(s.x * 0.5, s.y * 0.52)
		var ring_r := s.x * 0.30
		for i in 6:
			var base_a := TAU * float(i) / 6.0 - PI * 0.5 + _t * 0.06
			var p := center + Vector2(cos(base_a), sin(base_a) * 0.72) * ring_r
			p.y += sin(_t * 0.8 + float(i) * 1.3) * 12.0
			var r: float = (46.0 + 6.0 * sin(_t * 0.6 + float(i))) * (1.0 if s.x > 700.0 else 0.8)
			var col: Color = _HUES[i]
			var tex := AssetLibrary.tex(_GEM_KEYS[i])
			if tex != null:
				var d := r * 2.4
				for k in range(3, 0, -1):
					var kt := float(k) / 3.0
					draw_circle(p, r * 1.4 * kt, Color(col.r, col.g, col.b, 0.045 * (1.0 - kt)))
				draw_texture_rect(tex, Rect2(p - Vector2(d, d) * 0.5, Vector2(d, d)), false, Color(1, 1, 1, 0.42))
				continue
			for k in range(4, 0, -1):
				var kt := float(k) / 4.0
				draw_circle(p, r * 1.5 * kt, Color(col.r, col.g, col.b, 0.03 * (1.0 - kt)))
			var pts := PackedVector2Array()
			for j in 6:
				var a := PI / 6.0 + TAU * float(j) / 6.0
				pts.append(p + Vector2(cos(a), sin(a)) * r)
			draw_polygon(pts, ShapeDrawUtils.vertical_shade(pts,
				Color(col.r, col.g, col.b, 0.15), Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 0.12)))
			pts.append(pts[0])
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.20), 2.0, true)
