class_name IslandLevelNode
extends Control
## ONE pooled visual on the internal level map = supplied island-part PNG
## + the shared reusable wooden LEVEL BOARD PNG + a dynamically-rendered
## level number + a lightweight lock/current/completed state overlay.
##
## Passive: it does NO input handling itself (mouse_filter IGNORE). The owning
## InfiniteLevelScroller owns all touch — it distinguishes a drag from a tap
## and, on a genuine tap, hit-tests the pooled nodes and routes the one that
## was hit. That keeps a fling that starts on an island from ever being
## mistaken for a level tap.
##
## The board and number are CHILD nodes positioned relative to this control,
## so they travel with the island automatically as the pool recycles. The
## island artwork is only ever aspect-fit — never stretched, recoloured,
## rotated, cropped or merged with the board. Nothing about a node's identity
## lives in the object: `assign()` rewrites everything, so the same node can
## be Level 3 now and Level 128 after a recycle.

## Board width as a fraction of the drawn island-part width (kept small so it
## never covers the island's detail, and constant so it never grows with the
## digit count — see instruction §14).
const BOARD_W_FRAC := 0.40
const BOARD_MAX_W := 208.0

var local_level: int = 0
var state: StringName = &"locked"          # locked | unlocked | current | completed
var stars: int = 0
var routable: bool = false                  # false -> tap is inert (locked)

var _part: TextureRect
var _board: TextureRect
var _num: Label
var _part_aspect: float = 1.0               # h / w of the current part texture
var _pulse_t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

	_part = TextureRect.new()
	_part.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_part.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_part)

	_board = TextureRect.new()
	_board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_board.texture = WorldCatalog.board_texture()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)

	_num = Label.new()
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_num.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
	_num.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02))
	_num.add_theme_constant_override("outline_size", 6)
	add_child(_num)

	set_process(false)

## Rewrite this pooled node to represent a different logical level. `part_tex`
## is the caller-resolved (cycled) template; `box` is the node's on-screen
## size in px. Cheap enough to call every frame while dragging.
func assign(p_local_level: int, part_tex: Texture2D,
		p_state: StringName, p_stars: int, p_routable: bool, box: Vector2) -> void:
	local_level = p_local_level
	state = p_state
	stars = p_stars
	routable = p_routable

	if _part.texture != part_tex:
		_part.texture = part_tex
	if part_tex != null and part_tex.get_width() > 0:
		_part_aspect = float(part_tex.get_height()) / float(part_tex.get_width())
	custom_minimum_size = box
	size = box
	_num.text = str(p_local_level)
	set_process(p_state == &"current")
	_relayout_children()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout_children()

func _relayout_children() -> void:
	if _part == null or _board == null or _num == null:
		return
	var w := size.x
	var part_h: float = w * _part_aspect
	_part.position = Vector2.ZERO
	_part.size = Vector2(w, part_h)

	var bw: float = minf(w * BOARD_W_FRAC, BOARD_MAX_W)
	var b_aspect := 0.62
	if _board.texture != null and _board.texture.get_width() > 0:
		b_aspect = float(_board.texture.get_height()) / float(_board.texture.get_width())
	var bh: float = bw * b_aspect
	# Board hangs off the lower third of the island so both stay readable.
	var bx: float = (w - bw) * 0.5
	var by: float = part_h * 0.60
	_board.position = Vector2(bx, by)
	_board.size = Vector2(bw, bh)

	# Number label is inset slightly into the board so a 3-digit value still
	# sits clearly on the plaque face and stays centred + attached to it.
	_num.position = Vector2(bx + bw * 0.06, by + bh * 0.04)
	_num.size = Vector2(bw * 0.88, bh * 0.92)
	var fs: int = int(clampf(bh * 0.56, 18.0, 52.0))
	# Shrink for 3+ digits so the board never has to grow (§14) — but keep it
	# readable.
	if _num.text.length() >= 3:
		fs = int(float(fs) * 0.80)
	if _num.text.length() >= 4:
		fs = int(float(fs) * 0.82)
	_num.add_theme_font_size_override("font_size", maxi(fs, 15))

## Screen-space rectangle a tap must land in to select this node — the island
## art plus its board, ignoring the node's transparent padding.
func hit_rect() -> Rect2:
	var w := size.x
	var part_h: float = w * _part_aspect
	var bw: float = minf(w * BOARD_W_FRAC, BOARD_MAX_W)
	var b_aspect := 0.62
	if _board != null and _board.texture != null and _board.texture.get_width() > 0:
		b_aspect = float(_board.texture.get_height()) / float(_board.texture.get_width())
	var bottom: float = part_h * 0.60 + bw * b_aspect
	return Rect2(global_position, Vector2(w, maxf(part_h, bottom)))

func _process(delta: float) -> void:
	_pulse_t += delta
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var part_h: float = w * _part_aspect
	var bw: float = minf(w * BOARD_W_FRAC, BOARD_MAX_W)
	var b_aspect := 0.62
	if _board.texture != null and _board.texture.get_width() > 0:
		b_aspect = float(_board.texture.get_height()) / float(_board.texture.get_width())
	var bh: float = bw * b_aspect
	var board_rect := Rect2((w - bw) * 0.5, part_h * 0.60, bw, bh)
	var board_c := board_rect.position + board_rect.size * 0.5

	match state:
		&"locked":
			# gentle darken across the island so it reads not-yet-open without
			# hiding the artwork; the number stays (dimmed) + a small padlock
			# badge in the board's corner
			_part.modulate = Color(0.72, 0.76, 0.86, 0.92)
			_num.visible = true
			_num.add_theme_color_override("font_color", Color(0.80, 0.83, 0.90, 0.85))
			var pc := board_rect.position + Vector2(board_rect.size.x * 0.86, board_rect.size.y * 0.5)
			draw_circle(pc, bh * 0.30, Color(0.06, 0.07, 0.14, 0.85))
			draw_arc(pc + Vector2(0, -bh * 0.06), bh * 0.11, PI, TAU, 12, Color(0.86, 0.89, 0.97, 0.95), 2.5, true)
			draw_rect(Rect2(pc - Vector2(bh * 0.13, bh * 0.02), Vector2(bh * 0.26, bh * 0.20)), Color(0.86, 0.89, 0.97, 0.98))
		&"current":
			_part.modulate = Color(1, 1, 1, 1)
			_num.visible = true
			_num.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
			var pulse := 0.5 + 0.5 * sin(_pulse_t * 3.0)
			draw_arc(board_c, bw * (0.62 + 0.05 * pulse), 0.0, TAU, 40,
				Color(1.0, 0.84, 0.36, 0.35 + 0.35 * pulse), 5.0, true)
		&"completed":
			_part.modulate = Color(1, 1, 1, 1)
			_num.visible = true
			_num.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
			var star_tex := AssetLibrary.tex(&"eco_star")
			for i in 3:
				var a := deg_to_rad(-124.0 + float(i) * 34.0)
				var sc := board_c + Vector2(cos(a), sin(a)) * (bw * 0.62)
				var lit: bool = i < stars
				if star_tex != null:
					var ss := bh * 0.34
					draw_texture_rect(star_tex, Rect2(sc - Vector2(ss, ss) * 0.5, Vector2(ss, ss)),
						false, Color(1, 1, 1) if lit else Color(0.34, 0.35, 0.43, 0.85))
				else:
					draw_circle(sc, bh * 0.12, Color(1.0, 0.82, 0.3) if lit else Color(0.32, 0.33, 0.4))
		_:
			_part.modulate = Color(1, 1, 1, 1)
			_num.visible = true
			_num.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
