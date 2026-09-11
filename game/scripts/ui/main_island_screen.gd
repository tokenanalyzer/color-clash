class_name MainIslandScreen
extends Control
## The world / map selection screen: PLAY opens this. The ten supplied
## main-island artworks are laid out vertically in an inertial drag-scroll
## over the shared, fixed SEA CLIP video (owned by app.gd, behind this
## Control — this screen is transparent). Tapping a playable world opens its
## internal level map; worlds 6-10 are COMING SOON.
##
## Uses the same hand-rolled touch scroller as InfiniteLevelScroller (a plain
## Control + drag/inertia + tap hit-test) rather than a ScrollContainer, so a
## fling that starts on a big world card can never be mistaken for a tap and
## the scroll always responds on a real device.
##
## Concerns kept separate: WORLD DATA is WorldCatalog, the video is
## SeaClipBackground, this file is only card layout + navigation.

signal world_selected(world_id: StringName)
signal back_pressed()

const _TOP_PAD := 24.0
const _CARD_GAP := 34.0
const _BOTTOM_PAD := 160.0
const _TAP_SLOP := 18.0
const _FLING_SCALE := 46.0
const _FRICTION := 0.90

var _viewport: Control                 # clips + owns the drag input
var _canvas: Control                   # holds the cards, moved by _scroll_y
var _cards: Array[WorldCard] = []
var _back_btn: Button
var _title: Label
var _top_h := 132.0
var _scroll_y := 0.0
var _max_scroll := 0.0
var _vel := 0.0
var _dragging := false
var _press_pos := Vector2.ZERO
var _press_moved := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	_viewport = _DragArea.new()
	_viewport.owner_screen = self
	_viewport.clip_contents = true
	_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_viewport)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_canvas)

	for w in WorldCatalog.worlds():
		var card := WorldCard.new()
		var wid := StringName(String(w.get("id", "")))
		card.setup(wid)
		_canvas.add_child(card)
		_cards.append(card)

	_title = VisualTheme.label("CHOOSE YOUR WORLD", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_back_btn = UiKit.back_button()
	_back_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		back_pressed.emit())
	_back_btn.z_index = 5
	add_child(_back_btn)

	set_process(true)
	_relayout()
	get_viewport().size_changed.connect(_relayout)

func refresh() -> void:
	for card in _cards:
		card.refresh()

func _relayout() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	var si := VisualTheme.safe_insets(self)
	_top_h = si.position.y + 116.0
	_viewport.position = Vector2(0, _top_h)
	_viewport.size = Vector2(vp.x, vp.y - _top_h)
	_back_btn.position = Vector2(maxf(si.position.x + 14.0, 14.0), si.position.y + 12.0)
	_title.position = Vector2(0, si.position.y + 26.0)
	_title.size = Vector2(vp.x, 52)

	var card_w: float = clampf(vp.x - 40.0, 260.0, 620.0)
	var cx: float = (vp.x - card_w) * 0.5
	var y := _TOP_PAD
	for card in _cards:
		var h := card.layout(card_w)
		card.set_meta("y0", y)
		card.set_meta("h", h)
		card.position = Vector2(cx, y)
		y += h + _CARD_GAP
	_max_scroll = maxf(y + _BOTTOM_PAD - _viewport.size.y, 0.0)
	_scroll_y = clampf(_scroll_y, 0.0, _max_scroll)
	_apply_scroll()

func _apply_scroll() -> void:
	_canvas.position = Vector2(0, -_scroll_y)

func _process(delta: float) -> void:
	if _dragging or absf(_vel) < 4.0:
		return
	var before := _scroll_y
	_scroll_y = clampf(_scroll_y + _vel * delta, 0.0, _max_scroll)
	if is_equal_approx(before, _scroll_y):
		_vel = 0.0
	_vel *= _FRICTION
	_apply_scroll()

## Called by the inner _DragArea with viewport-local events.
func _handle_drag_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed:
				_vel = 0.0
				_scroll_y = clampf(_scroll_y
					+ (-140.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 140.0), 0.0, _max_scroll)
				_apply_scroll()
			return
		if event.pressed:
			_dragging = true
			_vel = 0.0
			_press_pos = event.position
			_press_moved = false
		else:
			_dragging = false
			if not _press_moved:
				_try_tap_at(event.position)
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		if event.position.distance_to(_press_pos) > _TAP_SLOP:
			_press_moved = true
		_scroll_y = clampf(_scroll_y - event.relative.y, 0.0, _max_scroll)
		_vel = lerpf(_vel, -event.relative.y * _FLING_SCALE, 0.5)
		_apply_scroll()

func _try_tap_at(view_local: Vector2) -> void:
	var canvas_pt := view_local - _canvas.position
	for card in _cards:
		if Rect2(card.position, card.size).has_point(canvas_pt):
			if WorldCatalog.is_island_unlocked(card.world_id):
				world_selected.emit(card.world_id)
			else:
				var pre := WorldCatalog.prerequisite_name(card.world_id)
				UiKit.show_toast(self, "Locked — finish %s first" % pre if pre != "" else "This island is locked")
			return

# ---- inner drag surface: forwards its gui input up to the screen ----
class _DragArea extends Control:
	var owner_screen: MainIslandScreen
	func _gui_input(event: InputEvent) -> void:
		if owner_screen != null:
			owner_screen._handle_drag_input(event)


# ======================================================================
#  One world card — supplied main-island PNG (aspect-fit, undistorted) with
#  its name + progress, and a padlock OVERLAY when the island is still locked.
#  Passive (no input of its own). The supplied PNG is never modified — the
#  lock, dim and "LOCKED" tag are all drawn on top.
# ======================================================================
class WorldCard extends Control:
	var world_id: StringName = &""
	var _art: TextureRect
	var _name_lbl: Label
	var _state_lbl: Label
	var _lock: _LockOverlay
	var _state: StringName = &"locked"
	var _art_aspect := 0.62
	var _name_top := 2.0

	func setup(id: StringName) -> void:
		world_id = id
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = false

		_art = TextureRect.new()
		_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art.texture = WorldCatalog.main_island_texture(id)
		if _art.texture != null and _art.texture.get_width() > 0:
			_art_aspect = float(_art.texture.get_height()) / float(_art.texture.get_width())
		add_child(_art)

		_name_lbl = VisualTheme.label(String(WorldCatalog.world(id).get("display_name", "")).to_upper(),
			VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
		_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_name_lbl)

		_state_lbl = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.STAR, 3)
		_state_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_state_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_state_lbl)

		# padlock overlay — added LAST so it draws ON TOP of the island art
		# (a parent Control's own _draw() renders behind its children).
		_lock = _LockOverlay.new()
		_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lock)
		refresh()

	func refresh() -> void:
		_state = WorldCatalog.world_state(world_id)
		_state_lbl.text = WorldCatalog.world_progress_text(world_id)
		match _state:
			&"locked":
				_art.modulate = Color(0.55, 0.58, 0.68, 0.92)
				_name_lbl.add_theme_color_override("font_color", VisualTheme.TEXT_DIM)
				_state_lbl.add_theme_color_override("font_color", Color(0.80, 0.72, 0.62))
			&"complete":
				_art.modulate = Color(1, 1, 1, 1)
				_name_lbl.add_theme_color_override("font_color", VisualTheme.TEXT_GOLD)
				_state_lbl.add_theme_color_override("font_color", VisualTheme.GOOD)
			_:  # current
				_art.modulate = Color(1, 1, 1, 1)
				_name_lbl.add_theme_color_override("font_color", VisualTheme.TEXT_GOLD)
				_state_lbl.add_theme_color_override("font_color", VisualTheme.STAR)
		if _lock != null:
			_lock.visible = _state == &"locked"
			_lock.queue_redraw()
		queue_redraw()

	func layout(w: float) -> float:
		var art_h: float = w * _art_aspect
		var total_h: float = art_h + 96.0
		custom_minimum_size = Vector2(w, total_h)
		size = Vector2(w, total_h)
		_name_top = 4.0
		_art.position = Vector2(0, 52.0)
		_art.size = Vector2(w, art_h)
		_name_lbl.position = Vector2(0, _name_top)
		_name_lbl.size = Vector2(w, 46.0)
		_state_lbl.position = Vector2(0, art_h + 54.0)
		_state_lbl.size = Vector2(w, 30.0)
		if _lock != null:
			_lock.position = _art.position
			_lock.size = _art.size
		return total_h


	## Padlock + medallion drawn over a locked island's art. Own node so it
	## sits ON TOP of the parent card's island TextureRect.
	class _LockOverlay extends Control:
		func _draw() -> void:
			var c := size * 0.5
			var r: float = clampf(minf(size.x, size.y) * 0.20, 52.0, 160.0)
			for k in range(4, 0, -1):
				var kt := float(k) / 4.0
				draw_circle(c, r * (0.95 + 0.5 * kt), Color(0.04, 0.05, 0.12, 0.16 * (1.0 - kt) + 0.16))
			draw_circle(c, r * 1.05, Color(0.05, 0.06, 0.14, 0.86))
			draw_arc(c, r * 1.05, 0.0, TAU, 44, VisualTheme.TEXT_GOLD, 4.0, true)
			var lock_tex := AssetLibrary.tex(&"obstacle_lock")
			if lock_tex != null and lock_tex.get_width() > 0:
				var s := r * 1.5
				var lh := s * float(lock_tex.get_height()) / float(lock_tex.get_width())
				draw_texture_rect(lock_tex, Rect2(c - Vector2(s, lh) * 0.5, Vector2(s, lh)), false)
			else:
				var bw := r * 1.0
				var bh := r * 0.82
				draw_arc(c + Vector2(0, -bh * 0.36), r * 0.44, PI, TAU, 24, Color(0.92, 0.94, 0.99), maxf(r * 0.17, 5.0), true)
				var body := Rect2(c + Vector2(-bw * 0.5, -bh * 0.10), Vector2(bw, bh))
				draw_rect(body, Color(0.92, 0.94, 0.99))
				draw_rect(body.grow(-maxf(r * 0.11, 4.0)), Color(0.13, 0.15, 0.25))
				draw_circle(c + Vector2(0, bh * 0.14), r * 0.14, Color(0.92, 0.94, 0.99))
			var font := ThemeDB.fallback_font
			var fs := int(clampf(r * 0.44, 24.0, 44.0))
			var tag := "LOCKED"
			var ts := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			var tp := Vector2(c.x - ts.x * 0.5, c.y + r * 1.45 + fs * 0.8)
			draw_string_outline(font, tp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.88))
			draw_string(font, tp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.87, 0.56))
