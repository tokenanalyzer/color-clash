class_name CharacterView
extends Control
## Placeholder Color Clash mascot. Listens to CharacterDirector.react and
## plays a pose + a short speech bubble. Everything is code-drawn for now:
## a rounded silhouette whose face changes per pose. When real artwork is
## supplied it registers under AssetLibrary ids `char_<pose>` and this view
## blits the sprite instead — same graceful-fallback pattern every other
## renderer uses, so dropping the art in needs no code change here.
##
## Deliberately cheap: no per-frame processing, one short Tween per reaction,
## a SceneTreeTimer to retract the bubble. Never intercepts touch.

const _ACCENT := Color(0.42, 0.78, 1.0)
const _BODY := Color(0.16, 0.19, 0.32)
const _BODY_HI := Color(0.28, 0.34, 0.54)

var _pose: StringName = &"idle"
var _line: String = ""
var _show_bubble := false
var _pop: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(120, 150)
	pivot_offset = Vector2(60, 140)
	var dir := get_node_or_null("/root/CharacterDirector")
	if dir != null:
		dir.react.connect(play_reaction)

func play_reaction(pose: StringName, line: String) -> void:
	_pose = pose
	_line = line
	_show_bubble = line != ""
	queue_redraw()

	if _pop != null and _pop.is_valid():
		_pop.kill()
	scale = Vector2(0.86, 1.12)
	_pop = create_tween()
	_pop.tween_property(self, "scale", Vector2(1.06, 0.94), 0.12).set_trans(Tween.TRANS_BACK)
	_pop.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC)

	if _show_bubble:
		var want := _line
		get_tree().create_timer(1.7).timeout.connect(func():
			if _line == want:
				_show_bubble = false
				queue_redraw()
		)

func set_idle() -> void:
	_pose = &"idle"
	_show_bubble = false
	queue_redraw()

func _draw() -> void:
	# Real art path (none registered yet) — blit and stop.
	# real hero art (Jamie) — pose-specific char_* override first, then the
	# supplied Jamie portrait, then the code-drawn placeholder below.
	var tex := AssetLibrary.tex(StringName("char_" + String(_pose)))
	if tex == null:
		tex = Cast.portrait(Cast.WHO_JAMIE)
	if tex != null:
		var s := minf(size.x, size.y) * 1.9
		var m: float = maxf(float(tex.get_width()), float(tex.get_height()))
		var w := s * tex.get_width() / m
		var h := s * tex.get_height() / m
		draw_texture_rect(tex, Rect2(Vector2(size.x * 0.5 - w * 0.5, size.y - h * 0.98), Vector2(w, h)), false)
		_draw_bubble()
		return

	var cx := size.x * 0.5
	var feet := size.y - 6.0
	var body_r := 40.0
	var head_c := Vector2(cx, feet - body_r * 2.0 - 26.0)
	var head_r := 30.0
	var tilt := _pose_tilt()

	# soft ground shadow
	draw_circle(Vector2(cx, feet), body_r * 0.9, Color(0, 0, 0, 0.22))
	# body — a rounded blob
	draw_circle(Vector2(cx, feet - body_r), body_r, _BODY)
	draw_circle(Vector2(cx - body_r * 0.3, feet - body_r * 1.35), body_r * 0.62, _BODY_HI)
	# head
	var hc := head_c + Vector2(tilt * 10.0, 0.0)
	draw_circle(hc, head_r, _BODY)
	draw_circle(hc + Vector2(-head_r * 0.35, -head_r * 0.35), head_r * 0.45, _BODY_HI)
	draw_arc(hc, head_r, 0, TAU, 28, _ACCENT, 3.0, true)

	_draw_face(hc, head_r)
	_draw_arms(Vector2(cx, feet - body_r * 1.1), body_r)
	_draw_bubble()

func _pose_tilt() -> float:
	match _pose:
		&"hype", &"cheer", &"power_up", &"victory":
			return 0.6
		&"worried", &"sad":
			return -0.5
		&"point":
			return 0.3
		_:
			return 0.0

func _draw_face(c: Vector2, r: float) -> void:
	var eye_dx := r * 0.42
	var eye_y := c.y - r * 0.1
	var happy := _pose in [&"cheer", &"hype", &"victory", &"power_up", &"wave"]
	var sad := _pose in [&"sad", &"worried"]

	if _pose == &"hype" or _pose == &"power_up":
		# star-ish sparkle eyes
		for sx in [-1.0, 1.0]:
			var e := Vector2(c.x + sx * eye_dx, eye_y)
			draw_line(e + Vector2(-5, 0), e + Vector2(5, 0), Color.WHITE, 3.0)
			draw_line(e + Vector2(0, -5), e + Vector2(0, 5), Color.WHITE, 3.0)
	else:
		for sx in [-1.0, 1.0]:
			var e := Vector2(c.x + sx * eye_dx, eye_y)
			draw_circle(e, 4.5, Color.WHITE)
			var look := Vector2(0, 1.5) if sad else Vector2(0, 0)
			draw_circle(e + look, 2.2, Color(0.05, 0.06, 0.12))

	var mc := Vector2(c.x, c.y + r * 0.42)
	if happy:
		draw_arc(mc, 8.0, 0.15 * PI, 0.85 * PI, 16, Color.WHITE, 3.0, true)
	elif sad:
		draw_arc(mc + Vector2(0, 8), 8.0, 1.15 * PI, 1.85 * PI, 16, Color.WHITE, 3.0, true)
	else:
		draw_line(mc + Vector2(-6, 0), mc + Vector2(6, 0), Color.WHITE, 3.0)

func _draw_arms(shoulder: Vector2, body_r: float) -> void:
	var up := _pose in [&"cheer", &"hype", &"victory", &"power_up", &"wave"]
	var left_end: Vector2
	var right_end: Vector2
	if up:
		left_end = shoulder + Vector2(-body_r * 1.1, -body_r * 0.9)
		right_end = shoulder + Vector2(body_r * 1.1, -body_r * 0.9)
	elif _pose == &"point":
		left_end = shoulder + Vector2(-body_r * 0.6, body_r * 0.4)
		right_end = shoulder + Vector2(body_r * 1.3, -body_r * 0.2)
	else:
		left_end = shoulder + Vector2(-body_r * 0.9, body_r * 0.2)
		right_end = shoulder + Vector2(body_r * 0.9, body_r * 0.2)
	draw_line(shoulder + Vector2(-body_r * 0.5, 0), left_end, _BODY_HI, 8.0, true)
	draw_line(shoulder + Vector2(body_r * 0.5, 0), right_end, _BODY_HI, 8.0, true)
	draw_circle(left_end, 6.0, _ACCENT)
	draw_circle(right_end, 6.0, _ACCENT)

func _draw_bubble() -> void:
	if not _show_bubble or _line == "":
		return
	var font := ThemeDB.fallback_font
	var fs := 20
	var tw: float = font.get_string_size(_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := 12.0
	var bw := tw + pad * 2.0
	var bh := 38.0
	var bx := clampf(size.x * 0.5 - bw * 0.5, -bw * 0.25, size.x - bw * 0.75)
	var by := -bh - 6.0
	var rect := Rect2(bx, by, bw, bh)
	_round(rect, 12.0, Color(0.98, 0.98, 1.0, 0.97))
	var tail := PackedVector2Array([
		Vector2(bx + bw * 0.4, by + bh - 1),
		Vector2(bx + bw * 0.55, by + bh - 1),
		Vector2(bx + bw * 0.42, by + bh + 12),
	])
	draw_colored_polygon(tail, Color(0.98, 0.98, 1.0, 0.97))
	draw_string(font, Vector2(bx + pad, by + bh * 0.5 + fs * 0.34), _line,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.09, 0.16))

func _round(r: Rect2, radius: float, col: Color) -> void:
	var pts := ShapeDrawUtils.rounded_rect_points(r.size, radius, 5)
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(p + r.position + r.size * 0.5)
	draw_colored_polygon(moved, col)
