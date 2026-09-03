class_name LevelMap
extends Control
## Campaign map — a genuinely vertically-scrollable, ISLAND-BASED world.
## Each island holds exactly IslandModel.LEVELS_PER_ISLAND (10) stages laid on
## a serpentine trail beneath an island header (name, x/10 progress, stars,
## lock). Islands stack down the scroll canvas; the whole thing scrolls with
## finger drag + inertia and auto-centres on the current island on open.
##
## Progression / unlock / star logic is UNTOUCHED — it all still comes from
## ProgressService (via IslandModel, which is a pure view of it). Public API
## (level_selected, home_pressed, refresh) is unchanged.

signal level_selected(level_id: int)
signal home_pressed()

const _TOP_PAD := 30.0
const _BOTTOM_PAD := 200.0
const _HEADER_H := 118.0
const _SECTION_GAP := 30.0
## The island-map art is 3:2 landscape; stretch it a little vertically so the
## 10 stage nodes get comfortable ( >110px ) spacing on a portrait screen.
const _MAP_ASPECT := 0.667      # 1024 / 1536
const _VSTRETCH := 1.06

static func _content_h_for(width: float) -> float:
	return width * _MAP_ASPECT * _VSTRETCH

static func _section_h_for(width: float) -> float:
	return _HEADER_H + _content_h_for(width)

var _top_bar: PanelContainer
var _top_bar_margin: MarginContainer
var _coins_label: Label
var _gems_label: Label
var _home_btn: Button
var _toast: Label
var _scroll: KineticScroll
var _canvas: Control
var _env: MapEnvironment
var _sections: Array = []            # [IslandSection]
var _node_buttons: Dictionary = {}   # level_id -> LevelNodeButton
var _top_h := 140.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_env = MapEnvironment.new()
	_env.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_env)
	_build_scroll_area()
	_build_top_bar()
	_build_toast()
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	refresh()
	call_deferred("_scroll_to_current")

# --------------------------------------------------------------- layout --

func _relayout() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	_env.size = vp
	var si := VisualTheme.safe_insets(self)
	_top_h = si.position.y + 128.0
	_scroll.position = Vector2.ZERO
	_scroll.size = vp
	_scroll.top_inset = _top_h
	_scroll.bottom_inset = si.size.y
	_top_bar.position = Vector2.ZERO
	_top_bar.size = Vector2(vp.x, _top_h)
	_top_bar_margin.add_theme_constant_override("margin_top", int(si.position.y + 14.0))
	_home_btn.position = Vector2(18, si.position.y + 16.0)
	_env.gesture_inset = si.size.y
	_layout_sections(vp.x)

func _layout_sections(width: float) -> void:
	if width <= 0.0:
		width = 1080.0
	var y := _top_h + _TOP_PAD
	var h := _section_h_for(width)
	for section in _sections:
		section.position = Vector2(0, y)
		section.custom_minimum_size = Vector2(width, h)
		section.size = Vector2(width, h)
		section.layout(width)
		y += h + _SECTION_GAP
	_canvas.custom_minimum_size = Vector2(width, y + _BOTTOM_PAD)
	_canvas.size = _canvas.custom_minimum_size

# ---------------------------------------------------------------- build --

func _build_scroll_area() -> void:
	_scroll = KineticScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.scroll_deadzone = 22
	_scroll.clip_contents = true
	add_child(_scroll)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_canvas)

	for island_idx in IslandModel.island_count():
		var section := IslandSection.new()
		section.setup(island_idx)
		for lid in section.level_ids:
			var btn := LevelNodeButton.new()
			btn.pressed.connect(_on_node_pressed.bind(lid))
			section.add_node(lid, btn)
			_node_buttons[lid] = btn
		_canvas.add_child(section)
		_sections.append(section)

func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	var sb := UiKit.glass(0, true)
	sb.bg_color = Color(0.06, 0.07, 0.14, 0.55)
	sb.set_corner_radius_all(0)
	sb.border_width_bottom = 1
	sb.border_width_top = 0
	sb.border_color = UiKit.GLASS_BORDER
	sb.shadow_size = 18
	_top_bar.add_theme_stylebox_override("panel", sb)
	add_child(_top_bar)

	_top_bar_margin = MarginContainer.new()
	_top_bar_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_top_bar_margin.add_theme_constant_override("margin_left", 78)
	_top_bar_margin.add_theme_constant_override("margin_right", 20)
	_top_bar.add_child(_top_bar_margin)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_top_bar_margin.add_child(row)

	var coin := UiKit.currency_chip(&"coin", VisualTheme.TEXT_GOLD, true)
	_coins_label = coin["value"]
	(coin["plus"] as Button).pressed.connect(func(): _show_toast("Shop coming soon"))
	row.add_child(coin["root"])

	var gem := UiKit.currency_chip(&"crystal", Color(0.82, 0.72, 1.0), true)
	_gems_label = gem["value"]
	(gem["plus"] as Button).pressed.connect(func(): _show_toast("Shop coming soon"))
	row.add_child(gem["root"])

	var gear := UiKit.icon_button(&"gear", 60)
	gear.pressed.connect(func():
		Audio.play(&"button_tap")
		_show_toast("Settings — use the pause menu in a level")
	)
	row.add_child(gear)

	_home_btn = UiKit.icon_button(&"chevron", 60)
	_home_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		home_pressed.emit()
	)
	_home_btn.z_index = 5
	add_child(_home_btn)

func _build_toast() -> void:
	_toast = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT, 5)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.add_theme_stylebox_override("normal", UiKit.glass(18, true))
	_toast.modulate.a = 0.0
	_toast.z_index = 40
	add_child(_toast)

func _show_toast(text: String) -> void:
	_toast.text = "  %s  " % text
	_toast.position = Vector2((size.x - _toast.size.x) * 0.5, size.y * 0.66)
	var t := _toast.create_tween()
	t.tween_property(_toast, "modulate:a", 1.0, 0.14)
	t.tween_interval(1.1)
	t.tween_property(_toast, "modulate:a", 0.0, 0.35)

# --------------------------------------------------------------- state --

## Re-reads Progress for every island + node — call whenever the map shows.
func refresh() -> void:
	_coins_label.text = str(Economy.coins)
	_gems_label.text = str(SaveService.get_int("gems", 0))
	for section in _sections:
		section.refresh()

func _scroll_to_current() -> void:
	var isl := IslandModel.current_island_index()
	if isl < 0 or isl >= _sections.size():
		return
	var section: IslandSection = _sections[isl]
	var focus_y: float = section.position.y + section.focus_offset()
	_scroll.set_scroll_target(int(clampf(focus_y - _scroll.size.y * 0.5, 0.0,
		maxf(_canvas.custom_minimum_size.y - _scroll.size.y, 0.0))))

func _on_node_pressed(level_id: int) -> void:
	if not Progress.is_unlocked(level_id):
		var isl := IslandModel.island_index_for_level(level_id)
		_show_toast("%s locks until you clear the island before it" % IslandModel.island_name(isl))
		return
	Audio.play(&"button_tap")
	level_selected.emit(level_id)


# ======================================================================
#  Island section — header + 10-node serpentine trail
# ======================================================================
class IslandSection extends Control:
	var island_idx := 0
	var level_ids: Array[int] = []
	var _nodes: Dictionary = {}          # level_id -> LevelNodeButton
	var _bg_fill: ColorRect              # dark ground behind the (letterboxed) art
	var _bg: TextureRect                 # the assembled island-map art
	var _art_rect := Rect2()             # where the art actually sits (nodes clamp to this)
	var _header: PanelContainer
	var _name_label: Label
	var _sub_label: Label
	var _progress_label: Label
	var _lock_badge: LockBadge
	var _positions: Dictionary = {}      # level_id -> Vector2 (section space)
	var _content_rect := Rect2()
	var _t := 0.0

	func setup(idx: int) -> void:
		island_idx = idx
		level_ids = IslandModel.level_ids_for_island(idx)
		mouse_filter = Control.MOUSE_FILTER_PASS
		clip_contents = true

		_bg_fill = ColorRect.new()
		_bg_fill.color = Color(0.05, 0.06, 0.13, 1.0)
		_bg_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg_fill)

		_bg = TextureRect.new()
		_bg.texture = IslandModel.island_map_art(idx)
		_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bg.clip_contents = true
		add_child(_bg)

		_header = PanelContainer.new()
		_header.add_theme_stylebox_override("panel", UiKit.glass(20, true))
		add_child(_header)
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", 12)
		_header.add_child(hrow)
		_lock_badge = LockBadge.new()
		_lock_badge.custom_minimum_size = Vector2(38, 38)
		hrow.add_child(_lock_badge)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		hrow.add_child(vb)
		_name_label = VisualTheme.label(IslandModel.island_name(idx).to_upper(), VisualTheme.FS_HEADING, VisualTheme.TEXT_GOLD)
		vb.add_child(_name_label)
		var subrow := HBoxContainer.new()
		subrow.add_theme_constant_override("separation", 10)
		_sub_label = VisualTheme.label(IslandModel.island_subtitle(idx).to_upper(), VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 2)
		subrow.add_child(_sub_label)
		_progress_label = VisualTheme.label("0 / %d" % level_ids.size(), VisualTheme.FS_CAPTION, VisualTheme.STAR, 3)
		subrow.add_child(_progress_label)
		vb.add_child(subrow)
		set_process(true)

	func add_node(level_id: int, btn: LevelNodeButton) -> void:
		_nodes[level_id] = btn
		add_child(btn)

	func focus_offset() -> float:
		var target := level_ids[0] if not level_ids.is_empty() else 0
		for lid in level_ids:
			if Progress.is_unlocked(lid) and not Progress.is_completed(lid):
				target = lid
				break
		return _positions.get(target, Vector2(0, LevelMap._HEADER_H)).y

	func layout(width: float) -> void:
		var content_h := LevelMap._content_h_for(width)
		_content_rect = Rect2(0, LevelMap._HEADER_H, width, content_h)
		_bg_fill.position = _content_rect.position
		_bg_fill.size = _content_rect.size
		_bg.position = _content_rect.position
		_bg.size = _content_rect.size

		# the art keeps its 3:2 aspect and is centred (no crop) — nodes clamp
		# to where it actually sits so they always land on the island scene.
		var art_h: float = width * LevelMap._MAP_ASPECT
		_art_rect = Rect2(0, LevelMap._HEADER_H + (content_h - art_h) * 0.5, width, art_h)

		var header_w: float = minf(width - 40.0, 460.0)
		_header.position = Vector2((width - header_w) * 0.5, 14.0)
		_header.size = Vector2(header_w, LevelMap._HEADER_H - 28.0)
		_header.custom_minimum_size = _header.size

		# stage 1 near the bottom, stage 10 near the top — every supplied map
		# reference flows this way. Positions map onto the art rect, inset a
		# little so nodes never clip the section edge.
		var count := level_ids.size()
		var inset := Vector2(art_h * 0.02, art_h * 0.04)
		var i := 0
		for lid in level_ids:
			var n := IslandModel.node_position_norm(island_idx, i, count)
			_positions[lid] = _art_rect.position + inset + Vector2(
				n.x * (width - inset.x * 2.0), n.y * (art_h - inset.y * 2.0))
			i += 1
		_position_nodes()

	func _position_nodes() -> void:
		for lid in level_ids:
			if _positions.has(lid):
				_nodes[lid].position = _positions[lid] - _nodes[lid].custom_minimum_size * 0.5

	func refresh() -> void:
		var st := IslandModel.island_state(island_idx)
		var done := IslandModel.island_completed_count(island_idx)
		_progress_label.text = "%d / %d" % [done, level_ids.size()]
		_lock_badge.state = st
		_lock_badge.queue_redraw()
		var locked := st == &"locked"
		_bg.modulate = Color(0.5, 0.55, 0.66, 0.9) if locked else Color(1, 1, 1, 1)
		_name_label.add_theme_color_override("font_color",
			VisualTheme.TEXT_DIM if locked else VisualTheme.TEXT_GOLD)

		var current_id := Progress.current_level_id()
		var idx := 0
		for lid in level_ids:
			var node_state: StringName
			if not Progress.is_unlocked(lid):
				node_state = &"locked"
			elif Progress.is_completed(lid):
				node_state = &"completed"
			elif lid == current_id:
				node_state = &"current"
			else:
				node_state = &"unlocked"
			var is_chest := (idx + 1) % 5 == 0
			var btn: LevelNodeButton = _nodes[lid]
			btn.face_texture = IslandModel.stage_face(island_idx, idx)
			btn.configure(lid, node_state, Progress.get_stars(lid), is_chest)
			idx += 1
		_position_nodes()
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		if IslandModel.island_state(island_idx) == &"current":
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		# subtle "traveled" trail: a soft dotted line through the cleared /
		# reachable nodes (the island art already carries the scenic path).
		var chain: Array = []
		for lid in level_ids:
			if _positions.has(lid) and Progress.is_unlocked(lid):
				chain.append(_positions[lid])
		for i in range(1, chain.size()):
			var a: Vector2 = chain[i - 1]
			var b: Vector2 = chain[i]
			draw_line(a, b, Color(0, 0, 0, 0.28), 12.0, true)
			draw_line(a, b, Color(1.0, 0.86, 0.45, 0.5), 5.0, true)
			var dir := (b - a)
			var L := dir.length()
			if L > 1.0:
				dir /= L
				var d := fposmod(_t * 40.0, 30.0)
				while d < L:
					draw_circle(a + dir * d, 3.0, Color(1, 1, 1, 0.8))
					d += 30.0
		# top divider veil so islands read as distinct chapters
		VisualTheme.draw_v_gradient(self, Rect2(0, 0, w, LevelMap._HEADER_H + 30.0),
			Color(0.04, 0.05, 0.11, 0.72), Color(0.04, 0.05, 0.11, 0.0), 16)
		if IslandModel.island_state(island_idx) == &"locked":
			draw_rect(Rect2(_content_rect.position, _content_rect.size), Color(0.04, 0.05, 0.12, 0.42))
			var lc := _content_rect.position + _content_rect.size * 0.5
			var lr := 46.0
			draw_arc(lc + Vector2(0, -lr * 0.35), lr * 0.55, PI, TAU, 20, Color(0.75, 0.78, 0.88, 0.6), 8.0, true)
			draw_rect(Rect2(lc + Vector2(-lr * 0.6, -lr * 0.35), Vector2(lr * 1.2, lr)), Color(0.75, 0.78, 0.88, 0.6))
		elif IslandModel.island_state(island_idx) == &"current":
			var pulse := 0.5 + 0.5 * sin(_t * 2.4)
			draw_rect(Rect2(0, 0, 4, size.y), Color(1.0, 0.82, 0.36, 0.3 + 0.3 * pulse))


	## The small round lock / check / play badge on an island header.
	class LockBadge extends Control:
		var state: StringName = &"locked"
		func _ready() -> void:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
		func _draw() -> void:
			var c := size * 0.5
			var r := minf(size.x, size.y) * 0.46
			match state:
				&"complete":
					draw_circle(c, r, Color(0.30, 0.62, 0.32))
					draw_circle(c, r, Color(0.5, 0.9, 0.55)); draw_circle(c, r - 3.0, Color(0.18, 0.42, 0.20))
					draw_line(c + Vector2(-r * 0.4, 0), c + Vector2(-r * 0.05, r * 0.4), Color.WHITE, 4.0, true)
					draw_line(c + Vector2(-r * 0.05, r * 0.4), c + Vector2(r * 0.5, -r * 0.4), Color.WHITE, 4.0, true)
				&"current":
					draw_circle(c, r, UiKit.GOLD_DEEP)
					draw_circle(c, r - 3.0, UiKit.GOLD)
					draw_colored_polygon(PackedVector2Array([
						c + Vector2(-r * 0.3, -r * 0.45), c + Vector2(r * 0.5, 0), c + Vector2(-r * 0.3, r * 0.45),
					]), Color(0.2, 0.14, 0.02))
				_:
					draw_circle(c, r, Color(0.22, 0.23, 0.30))
					draw_circle(c, r - 3.0, Color(0.16, 0.17, 0.23))
					draw_arc(c + Vector2(0, -r * 0.15), r * 0.42, PI, TAU, 14, Color(0.7, 0.73, 0.82), 4.0, true)
					draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.15), Vector2(r * 0.9, r * 0.7)), Color(0.7, 0.73, 0.82))


# ======================================================================
#  Kinetic (inertial) vertical scroll — makes the map feel native on touch
# ======================================================================
class KineticScroll extends ScrollContainer:
	var top_inset := 0.0
	var bottom_inset := 0.0
	var _vel := 0.0            # px/sec, sign matches scroll_vertical delta
	var _dragging := false
	var _target := -1.0        # >=0 while an auto-scroll animation is running

	func _ready() -> void:
		set_process(true)
		var vb := get_v_scroll_bar()
		if vb != null:
			vb.modulate.a = 0.0   # keep the range, hide the bar (reference has none)
		gui_input.connect(_on_gui_input)

	func set_scroll_target(y: int) -> void:
		_target = float(y)
		_vel = 0.0

	## Layer inertia on top of ScrollContainer's built-in touch drag: the base
	## class still does the 1:1 finger tracking + deadzone (so a drag that
	## starts on a level node still scrolls); we only sample the fling velocity
	## here and keep it rolling after release.
	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			if event.pressed:
				_dragging = true
				_vel = 0.0
				_target = -1.0
			else:
				_dragging = false
		elif event is InputEventScreenDrag:
			_target = -1.0
			_vel = lerpf(_vel, -event.relative.y * 56.0, 0.5)

	func _process(delta: float) -> void:
		var maxs := 0
		if get_child_count() > 0:
			maxs = int(maxf((get_child(0) as Control).size.y - size.y, 0.0))
		if _target >= 0.0:
			var nxt: float = lerpf(float(scroll_vertical), _target, clampf(delta * 9.0, 0.0, 1.0))
			scroll_vertical = int(round(nxt))
			if absf(nxt - _target) < 1.0:
				scroll_vertical = int(_target)
				_target = -1.0
			return
		if _dragging or absf(_vel) < 6.0:
			return
		scroll_vertical += int(round(_vel * delta))
		if scroll_vertical <= 0 or scroll_vertical >= maxs:
			_vel = 0.0
		_vel *= 0.90


# ======================================================================
#  Parallax world backdrop (unchanged behaviour, kept for atmosphere)
# ======================================================================
class MapEnvironment extends Control:
	var _t := 0.0
	var gesture_inset := 0.0
	var _islands: Array = []

	const _HUES := [
		Color(0.95, 0.30, 0.42), Color(1.0, 0.62, 0.24), Color(1.0, 0.85, 0.30),
		Color(0.36, 0.82, 0.52), Color(0.34, 0.62, 1.0), Color(0.64, 0.40, 0.96),
	]

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		set_process(true)
		var rng := RandomNumberGenerator.new()
		rng.seed = 71042
		for i in 6:
			_islands.append({
				"x": rng.randf(), "y": rng.randf(),
				"r": rng.randf_range(30.0, 58.0),
				"spd": rng.randf_range(0.5, 1.0),
				"ph": rng.randf() * TAU,
				"hue": rng.randi_range(0, 5),
			})

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x < 1.0:
			return
		var bg := AssetLibrary.tex(&"env_map_landmarks")
		if bg != null:
			var bw: float = float(bg.get_width())
			var bh: float = float(bg.get_height())
			var k: float = maxf(s.x / bw, s.y / bh)
			var dw := bw * k
			var dh := bh * k
			draw_texture_rect(bg, Rect2((s.x - dw) * 0.5, (s.y - dh) * 0.5, dw, dh), false)
			draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.05, 0.12, 0.42))
		else:
			_v_grad(Rect2(Vector2.ZERO, s), Color(0.11, 0.14, 0.30), Color(0.16, 0.11, 0.26), Color(0.05, 0.05, 0.12))
		for i in 16:
			var fx: float = fposmod(float(i) * 97.0 + _t * 6.0, s.x)
			var fy: float = s.y * (0.2 + 0.6 * fposmod(float(i) * 0.137, 1.0)) + sin(_t + float(i)) * 12.0
			var tw: float = 0.5 + 0.5 * sin(_t * 2.0 + float(i))
			draw_circle(Vector2(fx, fy), 2.4, Color(0.95, 0.9, 0.7, 0.45 * tw))
		if gesture_inset > 0.0:
			draw_rect(Rect2(0, s.y - gesture_inset - 8.0, s.x, gesture_inset + 8.0), Color(0.05, 0.05, 0.12, 0.5))

	func _v_grad(rect: Rect2, top: Color, mid: Color, bottom: Color) -> void:
		var bands := 24
		var bh := rect.size.y / float(bands)
		for i in bands:
			var t := float(i) / float(bands - 1)
			var col := top.lerp(mid, t / 0.5) if t < 0.5 else mid.lerp(bottom, (t - 0.5) / 0.5)
			draw_rect(Rect2(rect.position + Vector2(0, bh * i), Vector2(rect.size.x, bh + 1.0)), col)
