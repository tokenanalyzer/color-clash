class_name DailyRewardsScreen
extends Control
## The 7-day daily-reward calendar, reference-matched: a gold-framed
## frosted-glass dialog with a banner title, a 4+3 day grid whose tiles read
## claimed / current / upcoming / locked at a glance, and a large CLAIM
## button with a claim animation. Streak maths still lives in the pure
## DailyRewards class; this screen owns the SaveService keys and grants the
## reward through Economy/Boosters exactly as before.

signal closed()

const KEY_LAST := "daily_last_claim_day"
const KEY_STREAK := "daily_streak"

var _tiles: Array[DayTile] = []
var _claim_btn: Button
var _status: Label
var _state: Dictionary = {}
var _frame: UiKit.GoldFramePanel
var _scrim: ColorRect

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
	bg.scene_id = &"env_energy_crystals"
	add_child(bg)

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.42)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_frame = UiKit.GoldFramePanel.new(20)
	_frame.set_accent(VisualTheme.STAR)
	_frame.custom_minimum_size = Vector2(600, 0)
	center.add_child(_frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	_frame.content().add_child(col)

	# --- ribbon banner title, hung over the frame's top edge (reference
	# match, 2026-09-05) — a proper pointed-tail ribbon instead of a plain
	# pill, poking above the panel like a ceremonial plaque + close X ------
	var title_row := Control.new()
	title_row.custom_minimum_size = Vector2(0, 40)
	col.add_child(title_row)

	var banner := RibbonBanner.new()
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 0.0
	banner.anchor_bottom = 0.0
	banner.offset_left = -170
	banner.offset_right = 170
	banner.offset_top = -34
	banner.offset_bottom = 30
	title_row.add_child(banner)
	var title := VisualTheme.label("DAILY REWARDS", VisualTheme.FS_TITLE, Color(1, 1, 1))
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(title)

	var x_btn := UiKit.icon_button(&"close", 52)
	x_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x_btn.position = Vector2(4, -30)
	x_btn.z_index = 5
	var xsb := UiKit.button_face(UiKit.RED_FACE, UiKit.RED_DEEP, 26)
	xsb.content_margin_left = 0; xsb.content_margin_right = 0
	xsb.content_margin_top = 0; xsb.content_margin_bottom = 0
	x_btn.add_theme_stylebox_override("normal", xsb)
	x_btn.add_theme_stylebox_override("hover", xsb)
	x_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		closed.emit()
	)
	title_row.add_child(x_btn)

	# --- 4 + 3 day grid ------------------------------------------
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(grid)
	for day in range(1, 8):
		var tile := DayTile.new()
		tile.day = day
		tile.reward = DailyRewards.reward_for_day(day)
		tile.custom_minimum_size = Vector2(128, 142)
		grid.add_child(tile)
		_tiles.append(tile)

	_status = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT_DIM, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)

	_claim_btn = UiKit.button("CLAIM", &"primary", VisualTheme.FS_HEADING)
	_claim_btn.custom_minimum_size = Vector2(0, 80)
	_claim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_claim_btn.pressed.connect(_on_claim)
	col.add_child(_claim_btn)

	refresh()

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp

## Called by app.gd when the screen becomes visible — play the entrance.
func play_entrance() -> void:
	if _frame != null:
		UiKit.pop_in(_frame)

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
		elif tile.day == claimed_through + 1:
			st = &"upcoming"
		tile.set_state(st)

	if _state["claimable"]:
		_status.text = "Day %d reward is ready!" % int(_state["day"])
		_claim_btn.disabled = false
		_claim_btn.modulate.a = 1.0
	else:
		_status.text = "Come back tomorrow for Day %d!" % clampi(claimed_through + 1, 1, 7)
		_claim_btn.disabled = true
		_claim_btn.modulate.a = 0.5

func _on_claim() -> void:
	if not _state.get("claimable", false):
		return
	Audio.play(&"button_tap")
	var day := int(_state["day"])
	var reward: Dictionary = DailyRewards.reward_for_day(day)

	# claim-burst on the current tile
	for tile in _tiles:
		if tile.day == day:
			tile.play_claim_burst()

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


## One day cell in the calendar. States: claimed | current | upcoming | future.
class DayTile extends Control:
	var day := 1
	var reward: Dictionary = {}
	var state: StringName = &"future"
	var _t := 0.0
	var _burst := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(s: StringName) -> void:
		state = s
		set_process(s == &"current" or _burst > 0.0)
		queue_redraw()

	func play_claim_burst() -> void:
		_burst = 1.0
		set_process(true)
		var t := create_tween()
		t.tween_method(func(v): _burst = v; queue_redraw(), 1.0, 0.0, 0.7)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var big := day == 7
		var body := UiKit.GLASS_BG_DEEP
		var border := UiKit.GLASS_BORDER
		match state:
			&"claimed":
				# Same neutral charcoal as every other tile (reference match,
				# 2026-09-05) — the big check overlay alone signals "claimed",
				# no separate green-tinted background needed.
				body = Color(0.07, 0.08, 0.15, 0.7)
				border = Color(0.4, 0.7, 0.5, 0.35)
			&"current":
				var p := 0.5 + 0.5 * sin(_t * 6.0)
				body = Color(0.17, 0.15, 0.08, 0.95)
				border = VisualTheme.STAR.lerp(Color(1, 1, 1), p)
				VisualTheme.draw_glow(self, r.size * 0.5, r.size.x * 0.75, Color(1, 0.85, 0.3, 0.22 + 0.16 * p), 4)
			&"upcoming":
				body = Color(0.10, 0.12, 0.22, 0.82)
				border = Color(0.7, 0.8, 1.0, 0.4)
			_:
				body = Color(0.07, 0.08, 0.15, 0.7)
				border = Color(1, 1, 1, 0.10)
		_round_rect(r, 16.0, body)
		# Day 7 "hero" treatment (2026-09-05 UI pass) — the streak payoff gets
		# a gold outline of its own regardless of claim state, not just a
		# bigger coin icon, so it visually reads as the grand prize.
		if big and state != &"current":
			border = border.lerp(UiKit.GOLD, 0.6)
		var rp := ShapeDrawUtils.rounded_rect_points(r.size, 16.0, 5)
		var moved := PackedVector2Array()
		for pt in rp:
			moved.append(pt + r.size * 0.5)
		moved.append(moved[0])
		draw_polyline(moved, border, 3.0 if (state == &"current" or big) else 2.0, true)

		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(11, 25), "DAY %d" % day, HORIZONTAL_ALIGNMENT_LEFT, -1, VisualTheme.FS_MICRO,
			VisualTheme.STAR if (big or state == &"current") else VisualTheme.TEXT_DIM)

		var c := Vector2(r.size.x * 0.5, r.size.y * 0.55)
		var dim := state == &"future"
		var mod := Color(1, 1, 1, 0.4) if dim else Color(1, 1, 1)
		var boosters: Dictionary = reward.get("boosters", {})
		if boosters.size() > 0:
			var bid := StringName(String(boosters.keys()[0]))
			var ptex := AssetLibrary.power(bid)
			if ptex != null:
				var d := 54.0
				var m: float = maxf(float(ptex.get_width()), float(ptex.get_height()))
				draw_texture_rect(ptex, Rect2(c - Vector2(d * ptex.get_width() / m, d * ptex.get_height() / m) * 0.5,
					Vector2(d * ptex.get_width() / m, d * ptex.get_height() / m)), false, mod)
			else:
				IconDraw.draw_icon(self, bid, c, 40.0)
		else:
			var coin_tex := AssetLibrary.tex(&"eco_coin_stack" if big else &"eco_gold_coin")
			if coin_tex != null:
				var d := 60.0 if big else 48.0
				var m: float = maxf(float(coin_tex.get_width()), float(coin_tex.get_height()))
				draw_texture_rect(coin_tex, Rect2(c - Vector2(d * coin_tex.get_width() / m, d * coin_tex.get_height() / m) * 0.5,
					Vector2(d * coin_tex.get_width() / m, d * coin_tex.get_height() / m)), false, mod)
			else:
				draw_circle(c, 21.0, VisualTheme.COIN)

		var amt := int(reward.get("coins", 0))
		var lbl := ("%d" % amt) if amt > 0 else "BOOST"
		var lfs := VisualTheme.FS_CAPTION
		var ls := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs)
		draw_string_outline(font, Vector2(c.x - ls.x * 0.5, r.size.y - 13), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, 4, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(c.x - ls.x * 0.5, r.size.y - 13), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, VisualTheme.TEXT if not dim else VisualTheme.TEXT_DIM)

		if state == &"claimed":
			# Bigger green check overlapping the reward icon (reference match,
			# 2026-09-05) — reads as "claimed" at a glance instead of a small
			# corner badge that's easy to miss.
			var bc := Vector2(r.size.x - 22.0, r.size.y * 0.55 - 18.0)
			draw_circle(bc, 17.0, Color(0.14, 0.4, 0.18))
			draw_circle(bc, 17.0, Color(0.4, 0.85, 0.5, 0.92))
			draw_circle(bc, 13.0, Color(0.16, 0.46, 0.22))
			draw_line(bc + Vector2(-6, 0), bc + Vector2(-1, 5), Color.WHITE, 3.5, true)
			draw_line(bc + Vector2(-1, 5), bc + Vector2(7, -6), Color.WHITE, 3.5, true)

		if _burst > 0.0:
			var rad := (1.0 - _burst) * r.size.x * 0.9
			draw_arc(r.size * 0.5, rad, 0, TAU, 28, Color(1, 0.9, 0.4, _burst), 4.0, true)
			VisualTheme.draw_glow(self, r.size * 0.5, rad * 0.7, Color(1, 0.85, 0.3, _burst * 0.5), 4)

	func _round_rect(rect: Rect2, radius: float, color: Color) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(rect.size, radius, 5)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + rect.position + rect.size * 0.5)
		draw_colored_polygon(moved, color)


## A pointed-tail ribbon banner (reference match, 2026-09-05) — a purple
## body with a V-notch cut into each end and small folded "tail" triangles,
## gold-bordered, standing in for the plain pill title used previously.
class RibbonBanner extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
		# flared tails beyond each edge, reading as a hanging ribbon's ends
		var tail_l := PackedVector2Array([Vector2(0, 0), Vector2(0, h), Vector2(-16, h * 0.5)])
		var tail_r := PackedVector2Array([Vector2(w, 0), Vector2(w, h), Vector2(w + 16, h * 0.5)])
		draw_colored_polygon(tail_l, UiKit.PURPLE_DEEP)
		draw_colored_polygon(tail_r, UiKit.PURPLE_DEEP)
		draw_colored_polygon(body, UiKit.PURPLE_FACE)
		var closed := body.duplicate()
		closed.append(closed[0])
		draw_polyline(closed, UiKit.GOLD, 3.0, true)
		draw_polyline(PackedVector2Array([tail_l[0], tail_l[2], tail_l[1]]), UiKit.GOLD_DEEP, 2.5, true)
		draw_polyline(PackedVector2Array([tail_r[0], tail_r[2], tail_r[1]]), UiKit.GOLD_DEEP, 2.5, true)
