class_name SplashScreen
extends Control
## First screen shown on launch: the Color Clash wordmark rising in over a
## dark cosmic field with a short loading sweep, then it fades and emits
## `finished`. No real asset loading happens here yet (everything is code-
## drawn and boots instantly) — the bar is a deliberate ~1s "settle" beat
## so the launch doesn't feel abrupt, and is where real async warm-up
## (audio bus setup, save read, later Firebase init) will be awaited.

signal finished()

const _DURATION := 1.25

var _t := 0.0
var _running := true

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	queue_redraw()
	if _t >= _DURATION:
		_running = false
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(func():
			finished.emit()
			queue_free()
		)

func _draw() -> void:
	var s := size
	VisualTheme.draw_v_gradient(self, Rect2(Vector2.ZERO, s), VisualTheme.BG_TOP, VisualTheme.BG_BOTTOM, 20)
	VisualTheme.draw_glow(self, Vector2(s.x * 0.5, s.y * 0.42), s.x * 0.6, Color(0.4, 0.6, 1.0, 0.12), 6)

	var appear: float = clampf(_t / 0.5, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - appear, 3.0)
	var cx := s.x * 0.5
	var cy := s.y * 0.4 + (1.0 - ease) * 40.0
	VisualTheme.draw_wordmark(self, Vector2(cx, cy), 52.0, ease)

	var tag := "CONNECT   BLAST   COMBO"
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(cx - tw * 0.5, cy + 54.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.7, 0.8, 0.95, ease))

	# loading sweep
	var bar_w := s.x * 0.44
	var bx := cx - bar_w * 0.5
	var by := s.y * 0.72
	draw_rect(Rect2(bx, by, bar_w, 6), Color(1, 1, 1, 0.10), true)
	var p: float = clampf(_t / _DURATION, 0.0, 1.0)
	draw_rect(Rect2(bx, by, bar_w * p, 6), VisualTheme.ACCENT, true)
	draw_circle(Vector2(bx + bar_w * p, by + 3), 6.0, Color(1, 1, 1, 0.9))
