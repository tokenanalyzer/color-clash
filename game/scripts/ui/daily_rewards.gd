class_name DailyRewardsScreen
extends Control
## The 7-day daily-reward calendar. Streak maths lives in the pure
## DailyRewards class; this screen owns the SaveService keys
## (`daily_last_claim_day`, `daily_streak`), the layout, and granting the
## reward through Economy/Boosters when the player claims.

signal closed()

const KEY_LAST := "daily_last_claim_day"
const KEY_STREAK := "daily_streak"

var _tiles: Array[DayTile] = []
var _claim_btn: Button
var _status: Label
var _state: Dictionary = {}

## Does the player have a daily reward waiting right now? (for the menu badge)
static func has_claimable() -> bool:
	var last := SaveService.get_int(KEY_LAST, -1)
	var streak := SaveService.get_int(KEY_STREAK, 0)
	return DailyRewards.claim_state(DailyRewards.today(), last, streak)["claimable"]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	var bg := Backdrop.new()
	bg.accent = VisualTheme.STAR
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 20)
	center.add_child(col)

	var title := VisualTheme.label("DAILY REWARDS", 34, VisualTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)
	for day in range(1, 8):
		var tile := DayTile.new()
		tile.day = day
		tile.reward = DailyRewards.reward_for_day(day)
		tile.custom_minimum_size = Vector2(108, 118)
		grid.add_child(tile)
		_tiles.append(tile)

	_status = VisualTheme.label("", 18, VisualTheme.TEXT_DIM, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)

	_claim_btn = _button("Claim", VisualTheme.GOOD)
	_claim_btn.pressed.connect(_on_claim)
	col.add_child(_claim_btn)

	var close := _button("Back", VisualTheme.ACCENT)
	close.pressed.connect(func():
		Audio.play(&"button_tap")
		closed.emit()
	)
	col.add_child(close)

	refresh()

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp

func _button(text: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 56)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", VisualTheme.TEXT)
	b.add_theme_stylebox_override("normal", VisualTheme.button_face(tint.darkened(0.1)))
	b.add_theme_stylebox_override("hover", VisualTheme.button_face(tint))
	b.add_theme_stylebox_override("pressed", VisualTheme.button_face(tint.darkened(0.3)))
	b.focus_mode = Control.FOCUS_NONE
	return b

func refresh() -> void:
	var last := SaveService.get_int(KEY_LAST, -1)
	var streak := SaveService.get_int(KEY_STREAK, 0)
	_state = DailyRewards.claim_state(DailyRewards.today(), last, streak)
	var claimed_through: int = 0 if _state.get("reset", false) else clampi(streak, 0, 7)
	for tile in _tiles:
		var st := &"future"
		if _state["claimable"] and tile.day == int(_state["day"]):
			st = &"current"
		elif tile.day <= claimed_through:
			st = &"claimed"
		tile.set_state(st)

	if _state["claimable"]:
		_status.text = "Day %d reward is ready!" % int(_state["day"])
		_claim_btn.disabled = false
		_claim_btn.modulate.a = 1.0
	else:
		_status.text = "Come back tomorrow for Day %d." % clampi(claimed_through + 1, 1, 7)
		_claim_btn.disabled = true
		_claim_btn.modulate.a = 0.5

func _on_claim() -> void:
	if not _state.get("claimable", false):
		return
	Audio.play(&"button_tap")
	var day := int(_state["day"])
	var reward: Dictionary = DailyRewards.reward_for_day(day)

	SaveService.set_int(KEY_LAST, DailyRewards.today())
	SaveService.set_int(KEY_STREAK, DailyRewards.streak_after_claim(day))
	SaveService.save()

	var popup_rewards: Array = []
	var coins := int(reward.get("coins", 0))
	if coins > 0:
		Economy.grant(coins)
		popup_rewards.append({"type": "coins", "amount": coins})
	for id in (reward.get("boosters", {}) as Dictionary).keys():
		var qty := int(reward["boosters"][id])
		Boosters.add(StringName(String(id)), qty)
		popup_rewards.append({"type": "booster", "id": StringName(String(id)), "amount": qty})

	refresh()
	RewardPopup.present(self, popup_rewards, {"title": "Day %d Reward" % day})


## One day cell in the calendar.
class DayTile extends Control:
	var day := 1
	var reward: Dictionary = {}
	var state: StringName = &"future"
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(s: StringName) -> void:
		state = s
		set_process(s == &"current")
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var big := day == 7
		var body := VisualTheme.PANEL_RAISED
		var border := VisualTheme.PANEL_BORDER
		match state:
			&"claimed":
				body = Color(0.10, 0.16, 0.12, 0.95)
				border = Color(0.4, 0.8, 0.5, 0.5)
			&"current":
				var p := 0.5 + 0.5 * sin(_t * 6.0)
				body = Color(0.16, 0.15, 0.10, 0.98)
				border = VisualTheme.STAR.lerp(Color(1, 1, 1), p)
				VisualTheme.draw_glow(self, r.size * 0.5, r.size.x * 0.7, Color(1, 0.85, 0.3, 0.25 + 0.15 * p), 4)
		_round_rect(r, 16.0, body)
		var rp := ShapeDrawUtils.rounded_rect_points(r.size, 16.0, 5)
		var moved := PackedVector2Array()
		for pt in rp:
			moved.append(pt + r.size * 0.5)
		moved.append(moved[0])
		draw_polyline(moved, border, 2.0, true)

		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(8, 22), "DAY %d" % day, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			VisualTheme.STAR if big else VisualTheme.TEXT_DIM)

		var c := Vector2(r.size.x * 0.5, r.size.y * 0.56)
		var boosters: Dictionary = reward.get("boosters", {})
		if boosters.size() > 0:
			var hex := ShapeDrawUtils.regular_polygon(6, 22.0, PI / 6.0, c)
			draw_colored_polygon(hex, Color(0.42, 0.28, 0.62))
			var bid := StringName(String(boosters.keys()[0]))
			IconDraw.draw_icon(self, bid, c, 30.0)
		else:
			draw_circle(c, 18.0, VisualTheme.COIN)
			draw_circle(c, 13.0, VisualTheme.COIN.lightened(0.25))
		var amt := int(reward.get("coins", 0))
		var lbl := ("+%d" % amt) if amt > 0 else "BOOST"
		var ls := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_string(font, Vector2(c.x - ls.x * 0.5, r.size.y - 12), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, VisualTheme.TEXT)

		if state == &"claimed":
			draw_line(Vector2(r.size.x * 0.3, r.size.y * 0.5), Vector2(r.size.x * 0.45, r.size.y * 0.62),
				Color(0.5, 0.95, 0.6), 4.0)
			draw_line(Vector2(r.size.x * 0.45, r.size.y * 0.62), Vector2(r.size.x * 0.72, r.size.y * 0.32),
				Color(0.5, 0.95, 0.6), 4.0)

	func _round_rect(rect: Rect2, radius: float, color: Color) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(rect.size, radius, 5)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + rect.position + rect.size * 0.5)
		draw_colored_polygon(moved, color)
