class_name SplashScreen
extends Control
## First screen shown on launch: the Color Clash wordmark rising in over the
## shared premium Backdrop with a short loading sweep, then it fades and
## emits `finished`. Everything is code-drawn and boots instantly — the
## ~1.3s beat is a deliberate "settle" so the launch doesn't feel abrupt,
## and is where real async warm-up (audio bus, save read, later Firebase
## init) will be awaited. Safe-area aware so nothing rides the notch.

signal finished()

const _DURATION := 1.35

var _t := 0.0
var _running := true
var _fx: Control
var _img: TextureRect
var _ground: ColorRect

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# This Control is parented to a CanvasLayer, which does NOT drive its rect
	# from anchors — so we size it (and every full-rect child) to the viewport
	# ourselves, exactly like HUD/MainMenu. Without this the poster TextureRect
	# has a zero-size rect and renders nothing (the "blank splash" bug).
	_ground = ColorRect.new()
	_ground.color = Color(0.02, 0.03, 0.07, 1.0)   # matches boot_splash/bg_color
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ground)

	# WAR OF LOVE poster splash when the composed PNG is present
	# (assets/branding/splash.png); otherwise the code-drawn wordmark.
	var poster := AssetLibrary.tex(&"brand_splash")
	if poster != null:
		_img = TextureRect.new()
		_img.texture = poster
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# KEEP_ASPECT_CENTERED (fit, never crop) rather than COVERED: real
		# devices vary in aspect ratio (many are taller than the poster's
		# 9:16), and COVERED would crop the top/bottom of the supplied
		# artwork to fill them. The dark _ground colour letterboxes cleanly.
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_img)
	else:
		var bg := Backdrop.new()
		bg.accent = VisualTheme.ACCENT
		bg.scene_id = &"env_main_background"
		add_child(bg)

	_fx = SplashFX.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.poster_mode = poster != null
	add_child(_fx)

	_track_size()
	get_viewport().size_changed.connect(_track_size)

func _track_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 1.0:
		vp = Vector2(get_viewport().size)
	size = vp
	custom_minimum_size = vp
	position = Vector2.ZERO
	for c in [_ground, _img, _fx]:
		if c != null:
			c.position = Vector2.ZERO
			c.size = vp
			c.custom_minimum_size = vp

func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	if _fx != null:
		_fx.t = _t
		_fx.queue_redraw()
	if _t >= _DURATION:
		_running = false
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(func():
			finished.emit()
			queue_free()
		)


## All splash vector work on its own layer so it sits above the Backdrop.
class SplashFX extends Control:
	var t := 0.0
	var poster_mode := false

	func _draw() -> void:
		var s := size
		if s.x < 1.0:
			return
		var si := VisualTheme.safe_insets(self)
		var cx := s.x * 0.5
		var cy: float = s.y * 0.42

		# poster splash carries its own title — only draw the loading sweep,
		# styled to match the new crest's gold/crimson palette rather than a
		# generic white progress bar.
		if poster_mode:
			var font := ThemeDB.fallback_font
			var bar_w := s.x * 0.5
			var bx := cx - bar_w * 0.5
			var by: float = s.y - si.size.y - 64.0
			var pr: float = clampf(t / _splash_duration(), 0.0, 1.0)
			var lead := Vector2(bx + bar_w * pr, by)
			# soft crimson-gold glow breathing behind the leading edge
			var pulse: float = 0.7 + 0.3 * sin(t * 5.0)
			VisualTheme.draw_glow(self, lead, 15.0 * pulse, Color(VisualTheme.ACCENT_HOT.r, VisualTheme.ACCENT_HOT.g, VisualTheme.ACCENT_HOT.b, 0.5), 4)
			draw_line(Vector2(bx, by), Vector2(bx + bar_w, by), Color(1, 1, 1, 0.14), 6.0, true)
			draw_line(Vector2(bx, by), lead, VisualTheme.STAR, 6.0, true)
			# a small gold-rimmed crimson gem instead of a flat dot
			draw_circle(lead, 8.0, VisualTheme.ACCENT_HOT)
			draw_circle(lead, 8.0, Color(VisualTheme.TEXT_GOLD.r, VisualTheme.TEXT_GOLD.g, VisualTheme.TEXT_GOLD.b, 0.9), false, 1.6)
			draw_circle(lead + Vector2(-2.4, -2.4), 2.2, Color(1, 1, 1, 0.85))
			return

		var appear: float = clampf(t / 0.55, 0.0, 1.0)
		var ease := 1.0 - pow(1.0 - appear, 3.0)

		# a ring of faint hex gems blooming outward behind the wordmark
		var ring_r: float = s.x * (0.10 + 0.22 * ease)
		for i in 6:
			var a := TAU * float(i) / 6.0 - t * 0.4
			var p := Vector2(cx, cy) + Vector2(cos(a), sin(a)) * ring_r
			var col: Color = _HUES[i]
			var gr: float = s.x * 0.05 * (0.6 + 0.4 * sin(t * 3.0 + float(i)))
			for k in range(3, 0, -1):
				var kt := float(k) / 3.0
				draw_circle(p, gr * (1.6 * kt), Color(col.r, col.g, col.b, 0.10 * (1.0 - kt) * ease))
			var hx := PackedVector2Array()
			for j in 6:
				var ha := PI / 6.0 + TAU * float(j) / 6.0
				hx.append(p + Vector2(cos(ha), sin(ha)) * gr)
			draw_colored_polygon(hx, Color(col.r, col.g, col.b, 0.35 * ease))

		VisualTheme.draw_glow(self, Vector2(cx, cy), s.x * 0.6, Color(0.45, 0.6, 1.0, 0.16 * ease), 6)
		var wy := cy + (1.0 - ease) * 44.0
		var fs: float = clampf(s.x * 0.12, 48.0, 82.0)
		VisualTheme.draw_wordmark(self, Vector2(cx, wy), fs, ease)

		var font := ThemeDB.fallback_font
		var tag := "CONNECT   BLAST   COMBO"
		var tfs := int(clampf(s.x * 0.03, 18.0, 28.0))
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		draw_string_outline(font, Vector2(cx - tw * 0.5, wy + fs * 0.95), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 4, Color(0, 0, 0, 0.6 * ease))
		draw_string(font, Vector2(cx - tw * 0.5, wy + fs * 0.95), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0.74, 0.84, 0.98, ease))

		# loading sweep, comfortably above the gesture bar
		var bar_w := s.x * 0.5
		var bx := cx - bar_w * 0.5
		var by: float = s.y - si.size.y - 90.0
		draw_line(Vector2(bx, by), Vector2(bx + bar_w, by), Color(1, 1, 1, 0.10), 6.0, true)
		var p: float = clampf(t / _splash_duration(), 0.0, 1.0)
		draw_line(Vector2(bx, by), Vector2(bx + bar_w * p, by), VisualTheme.ACCENT, 6.0, true)
		draw_circle(Vector2(bx + bar_w * p, by), 7.0, Color(1, 1, 1, 0.95))
		var lfs := int(clampf(s.x * 0.026, 15.0, 22.0))
		var lt := "LOADING"
		var ltw := font.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		draw_string(font, Vector2(cx - ltw * 0.5, by - 22.0), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(0.6, 0.68, 0.85))

	func _splash_duration() -> float:
		return 1.35

	const _HUES := [
		Color(0.95, 0.30, 0.42), Color(1.0, 0.62, 0.24), Color(1.0, 0.85, 0.30),
		Color(0.36, 0.82, 0.52), Color(0.34, 0.62, 1.0), Color(0.64, 0.40, 0.96),
	]
