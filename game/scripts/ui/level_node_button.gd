class_name LevelNodeButton
extends Button
## One tappable campaign node. Fully code-drawn to match Color Clash's
## glossy-gem language: a shadowed, gradient-lit disc whose colour, ring and
## icon read locked / unlocked / current / completed at a glance, with a
## star arc above a cleared level and a crowned, rotating-ring treatment on
## the current one. Every Nth node is flagged `is_chest` for a reward beat.

const NODE_RADIUS := 50.0
const _TOP_PADDING := 38.0
const FACE_W := 102.0          # drawn width of a stage-diorama face
const FACE_ASPECT := 1.0       # height / width of the diorama region

var level_id: int = 0
var state: StringName = &"locked" # locked | unlocked | current | completed
var stars: int = 0
var is_chest: bool = false
## Optional per-stage diorama art (an AtlasTexture region of the island's
## stage sheet — see IslandModel.stage_face). When set it becomes the node
## face; all state chrome (lock veil, star arc, current glow/crown, number)
## is still drawn on top. null -> the generic map_*_node sprite / vector disc.
var face_texture: Texture2D = null
var _spin := 0.0
var _bob := 0.0

func configure(id: int, p_state: StringName, p_stars: int, p_is_chest: bool = false) -> void:
	level_id = id
	state = p_state
	stars = p_stars
	is_chest = p_is_chest
	disabled = state == &"locked"
	focus_mode = Control.FOCUS_NONE
	if face_texture != null:
		custom_minimum_size = Vector2(FACE_W + 26.0, FACE_W * FACE_ASPECT + _TOP_PADDING + 30.0)
	else:
		custom_minimum_size = Vector2(NODE_RADIUS * 2.0 + 24.0, NODE_RADIUS * 2.0 + _TOP_PADDING + 16.0)
	size = custom_minimum_size
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, empty)
	set_process(state == &"current")
	if state == &"current":
		_start_pulse()
	queue_redraw()

func _process(delta: float) -> void:
	_spin += delta * 1.4
	_bob += delta
	queue_redraw()

func _start_pulse() -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(self, "scale", Vector2(1.07, 1.07), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _center() -> Vector2:
	var y_off := sin(_bob * 2.2) * 2.5 if state == &"current" else 0.0
	return Vector2(size.x * 0.5, _TOP_PADDING + NODE_RADIUS + y_off)

const _STATE_SPRITE := {
	&"locked": &"map_locked_node", &"unlocked": &"map_level_node",
	&"current": &"map_current_node", &"completed": &"map_completed_node",
}

func _draw() -> void:
	pivot_offset = size * 0.5
	var c := _center()
	var r := NODE_RADIUS
	var font := ThemeDB.fallback_font

	# --- per-stage diorama face (user-supplied stage art) ---------------
	if face_texture != null:
		_draw_diorama_face(c, r, font)
		return

	var sprite := AssetLibrary.tex(_STATE_SPRITE.get(state, &"map_level_node"))
	if sprite != null:
		if state == &"current":
			VisualTheme.draw_glow(self, c, r * 2.1, Color(1.0, 0.8, 0.3, 0.35), 5)
		# node disc art, fit to the button width (aspect kept), centred on c
		var dw := r * 2.5
		var dh := dw * float(sprite.get_height()) / float(sprite.get_width())
		draw_texture_rect(sprite, Rect2(c - Vector2(dw, dh) * 0.5, Vector2(dw, dh)), false)
		# rotating dashed ring + crown on the current node
		if state == &"current":
			for i in 12:
				var a := _spin + TAU * float(i) / 12.0
				draw_line(c + Vector2(cos(a), sin(a)) * (r + 8.0),
					c + Vector2(cos(a), sin(a)) * (r + 14.0), Color(1.0, 0.9, 0.5, 0.9), 3.0, true)
			var crown := AssetLibrary.tex(&"ui_crown_trophy")
			if crown != null:
				var cw := r * 1.5
				var chh := cw * float(crown.get_height()) / float(crown.get_width())
				draw_texture_rect(crown, Rect2(c + Vector2(-cw * 0.5, -r - chh * 0.8), Vector2(cw, chh)), false)
			else:
				_draw_crown(c + Vector2(0, -r - 16.0))
		# label / chest
		if is_chest and AssetLibrary.has(&"map_milestone_chest"):
			var chest := AssetLibrary.tex(&"map_milestone_chest")
			var kw := r * 1.7
			var kh := kw * float(chest.get_height()) / float(chest.get_width())
			draw_texture_rect(chest, Rect2(c - Vector2(kw, kh) * 0.5, Vector2(kw, kh)), false)
		elif is_chest:
			_draw_chest(c)
		elif state != &"locked":
			var label := str(level_id)
			var fs := 32
			var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			draw_string_outline(font, c - ts * 0.5 + Vector2(0, ts.y * 0.30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.7))
			draw_string(font, c - ts * 0.5 + Vector2(0, ts.y * 0.30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		# earned-star rating above a cleared node (player's real score)
		if state == &"completed":
			var star_tex := AssetLibrary.tex(&"eco_star")
			for i in 3:
				var a := deg_to_rad(-128.0 + float(i) * 38.0)
				var sc := c + Vector2(cos(a), sin(a)) * (r + 18.0)
				if star_tex != null:
					var ss := 26.0
					draw_texture_rect(star_tex, Rect2(sc - Vector2(ss, ss) * 0.5, Vector2(ss, ss)), false,
						Color(1, 1, 1) if i < stars else Color(0.32, 0.33, 0.4, 0.85))
				else:
					_draw_star(sc, 9.0, VisualTheme.STAR if i < stars else Color(0.3, 0.31, 0.38))
		return

	var base: Color
	var ring: Color
	match state:
		&"locked":
			base = Color(0.24, 0.25, 0.31); ring = Color(0.15, 0.16, 0.2)
		&"current":
			base = Color(1.0, 0.66, 0.16); ring = Color(1.0, 0.88, 0.5)
		&"completed":
			base = Color(0.26, 0.6, 0.96); ring = Color(0.6, 0.82, 1.0)
		_:
			base = Color(0.4, 0.78, 0.55); ring = Color(0.7, 0.96, 0.8)

	# aura for the current node
	if state == &"current":
		VisualTheme.draw_glow(self, c, r * 2.0, Color(1.0, 0.8, 0.3, 0.35), 5)

	# cast shadow + glossy domed disc + lit rim + rim-light highlight
	draw_circle(c + Vector2(0, 7), r * 1.03, Color(0, 0, 0, 0.42))
	var disc := ShapeDrawUtils.regular_polygon(32, r, 0.0, c)
	draw_polygon(disc, ShapeDrawUtils.vertical_shade(disc, base.lightened(0.42), base.darkened(0.42)))
	# inner bloom
	VisualTheme.draw_glow(self, c + Vector2(0, r * 0.05), r * 0.5, Color(base.lightened(0.2).r, base.lightened(0.2).g, base.lightened(0.2).b, 0.28), 4)
	draw_arc(c, r - 2.0, 0, TAU, 40, ring, 5.0, true)
	draw_arc(c, r - 2.0, PI * 0.15, PI * 0.85, 20, Color(0, 0, 0, 0.28), 5.0, true)
	# top gloss cap
	draw_circle(c + Vector2(-r * 0.28, -r * 0.34), r * 0.3, Color(1, 1, 1, 0.34))
	draw_circle(c + Vector2(-r * 0.18, -r * 0.22), r * 0.12, Color(1, 1, 1, 0.55))

	# rotating dashed ring on the current node
	if state == &"current":
		for i in 12:
			var a := _spin + TAU * float(i) / 12.0
			var p1 := c + Vector2(cos(a), sin(a)) * (r + 7.0)
			var p2 := c + Vector2(cos(a), sin(a)) * (r + 13.0)
			draw_line(p1, p2, Color(1.0, 0.9, 0.5, 0.9), 3.0, true)
		_draw_crown(c + Vector2(0, -r - 16.0))

	if state == &"locked":
		draw_arc(c + Vector2(0, -9), 13.0, PI, TAU, 16, Color(0.82, 0.85, 0.94), 4.0, true)
		draw_rect(Rect2(c + Vector2(-14, -6), Vector2(28, 20)), Color(0.82, 0.85, 0.94))
		draw_circle(c + Vector2(0, 2), 3.5, Color(0.2, 0.2, 0.26))
	elif is_chest:
		_draw_chest(c)
	else:
		var label := str(level_id)
		var fs := 36
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string_outline(font, c - ts * 0.5 + Vector2(0, ts.y * 0.32), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, 6, Color(0, 0, 0, 0.6))
		draw_string(font, c - ts * 0.5 + Vector2(0, ts.y * 0.32), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)

	if state == &"completed":
		var arc_r := r + 16.0
		for i in 3:
			var a := deg_to_rad(-130.0 + float(i) * 40.0)
			var sc := c + Vector2(cos(a), sin(a)) * arc_r
			_draw_star(sc, 9.0, VisualTheme.STAR if i < stars else Color(0.3, 0.31, 0.38))

## Draws a user-supplied stage diorama as the node face + all state chrome.
## Every state shows the SAME diorama on the SAME gold-framed medallion — the
## art is the star. State is a light overlay: a number/lock/chest disc in the
## corner, a star ribbon for a cleared stage, a pulsing gold ring + crown for
## the current stage, and a gentle darken for a locked one.
func _draw_diorama_face(c: Vector2, _r: float, font: Font) -> void:
	var fw := FACE_W
	var fh := FACE_W * FACE_ASPECT
	var bob := sin(_bob * 2.2) * 3.0 if state == &"current" else 0.0
	var face := Rect2(size.x * 0.5 - fw * 0.5, _TOP_PADDING + bob, fw, fh)
	var mid := face.position + face.size * 0.5

	# dark halo so every node pops off a same-colour island background
	for k in range(4, 0, -1):
		var kt := float(k) / 4.0
		draw_circle(mid + Vector2(0, 4), fw * 0.72 * kt, Color(0, 0, 0, 0.16 * (1.0 - kt) + 0.06))
	draw_circle(Vector2(mid.x, face.end.y + 2.0), fw * 0.40, Color(0, 0, 0, 0.34))
	if state == &"current":
		VisualTheme.draw_glow(self, mid, fw * 1.15, Color(1.0, 0.82, 0.32, 0.42), 5)

	# the diorama (always full art; a locked stage is only lightly dimmed)
	draw_texture_rect(face_texture, face, false, Color(1, 1, 1))
	if state == &"locked":
		_rounded(face.grow(-1.0), 12.0, Color(0.05, 0.06, 0.14, 0.44))

	# consistent gold medallion frame for every state
	var rim := UiKit.GOLD
	var rimw := 3.0
	match state:
		&"locked": rim = Color(0.60, 0.64, 0.76, 0.75); rimw = 2.5
		&"unlocked": rim = Color(1.0, 0.9, 0.55, 0.8); rimw = 3.0
		&"completed": rim = Color(1.0, 0.86, 0.4, 0.95); rimw = 3.0
	_rounded_outline(face.grow(1.0), 13.0, Color(0, 0, 0, 0.45), rimw + 3.0)
	_rounded_outline(face.grow(1.0), 13.0, rim, rimw)

	if state == &"current":
		for i in 12:
			var a := _spin + TAU * float(i) / 12.0
			var dir := Vector2(cos(a), sin(a) * 0.92)
			draw_line(mid + dir * (fw * 0.60), mid + dir * (fw * 0.70), Color(1.0, 0.9, 0.5, 0.9), 3.0, true)
		var crown := AssetLibrary.tex(&"ui_crown_trophy")
		if crown != null:
			var cw := fw * 0.5
			var chh := cw * float(crown.get_height()) / float(crown.get_width())
			draw_texture_rect(crown, Rect2(mid.x - cw * 0.5, face.position.y - chh * 0.62, cw, chh), false)
		else:
			_draw_crown(Vector2(mid.x, face.position.y - 6.0))

	# star ribbon hugging the top of a cleared stage
	if state == &"completed":
		var star_tex := AssetLibrary.tex(&"eco_star")
		for i in 3:
			var a := deg_to_rad(-116.0 + float(i) * 26.0)
			var sc := mid + Vector2(cos(a), sin(a) * 0.86) * (fw * 0.58)
			if star_tex != null:
				var ss := 24.0
				draw_texture_rect(star_tex, Rect2(sc - Vector2(ss, ss) * 0.5, Vector2(ss, ss)), false,
					Color(1, 1, 1) if i < stars else Color(0.32, 0.34, 0.42, 0.8))
			else:
				_draw_star(sc, 8.0, VisualTheme.STAR if i < stars else Color(0.3, 0.31, 0.38))

	# small state disc in the bottom-left corner of the medallion
	var badge_c := face.position + Vector2(fw * 0.16, fh - 6.0)
	var bcol := Color(0.86, 0.5, 0.12) if state == &"current" else Color(0.10, 0.12, 0.2)
	draw_circle(badge_c, 16.0, Color(0, 0, 0, 0.55))
	draw_circle(badge_c, 14.0, bcol.darkened(0.2) if state == &"current" else Color(0.08, 0.10, 0.18))
	_rounded_outline(Rect2(badge_c - Vector2(14, 14), Vector2(28, 28)), 14.0,
		rim if state != &"unlocked" else Color(1, 1, 1, 0.5), 2.0)
	if state == &"locked":
		draw_arc(badge_c + Vector2(0, -2.0), 4.5, PI, TAU, 10, Color(0.86, 0.89, 0.96), 2.0, true)
		draw_rect(Rect2(badge_c + Vector2(-5, -2), Vector2(10, 8)), Color(0.86, 0.89, 0.96))
	elif is_chest:
		_draw_chest(badge_c)
	else:
		var lbl := str(level_id)
		var fs := 20
		var ts := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string_outline(font, badge_c - ts * 0.5 + Vector2(0, ts.y * 0.34), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.8))
		draw_string(font, badge_c - ts * 0.5 + Vector2(0, ts.y * 0.34), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _rounded(r: Rect2, radius: float, col: Color) -> void:
	var pts := ShapeDrawUtils.rounded_rect_points(r.size, minf(radius, r.size.y * 0.5), 5)
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(p + r.position + r.size * 0.5)
	draw_colored_polygon(moved, col)

func _rounded_outline(r: Rect2, radius: float, col: Color, w: float) -> void:
	var pts := ShapeDrawUtils.rounded_rect_points(r.size, minf(radius, r.size.y * 0.5), 6)
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(p + r.position + r.size * 0.5)
	moved.append(moved[0])
	draw_polyline(moved, col, w, true)

func _draw_crown(p: Vector2) -> void:
	var w := 20.0
	var pts := PackedVector2Array([
		p + Vector2(-w, 6), p + Vector2(-w, -4), p + Vector2(-w * 0.4, 3),
		p + Vector2(0, -8), p + Vector2(w * 0.4, 3), p + Vector2(w, -4), p + Vector2(w, 6),
	])
	draw_colored_polygon(pts, VisualTheme.STAR)
	draw_polyline(pts, VisualTheme.STAR.darkened(0.3), 1.5, true)

func _draw_chest(c: Vector2) -> void:
	draw_rect(Rect2(c + Vector2(-18, -4), Vector2(36, 22)), Color(0.55, 0.36, 0.18))
	draw_rect(Rect2(c + Vector2(-18, -14), Vector2(36, 12)), Color(0.7, 0.47, 0.22))
	draw_rect(Rect2(c + Vector2(-3, -8), Vector2(6, 10)), VisualTheme.STAR)
	draw_line(c + Vector2(-18, -2), c + Vector2(18, -2), Color(1, 0.85, 0.4), 2.0)

func _draw_star(center: Vector2, rad: float, color: Color) -> void:
	draw_colored_polygon(ShapeDrawUtils.star_points(center, rad + 2.0), Color(0, 0, 0, 0.35))
	draw_colored_polygon(ShapeDrawUtils.star_points(center, rad), color)
