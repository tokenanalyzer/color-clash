class_name DailyRewardsScreen
extends Control
## The 7-day daily-reward calendar. Streak maths still lives in the pure
## DailyRewards class; this screen owns the SaveService keys and grants the
## reward through Economy/Boosters exactly as before.
##
## 2026-09-06 UI asset integration: chrome is the artist-supplied artwork
## (assets/ui_kit/daily_rewards_elements.png, sliced via AssetLibrary.ui_slice
## — source PNG untouched). The gold frame is shown at nearly the full
## portrait width (~10px each side), aspect-locked, never stretched; the
## DAILY REWARDS ribbon, red ✕, day tiles (baked "DAY N"), reward icons,
## value pills (baked numbers), BOOST pill and green CLAIM button are all
## supplied slices. Only the "come back tomorrow" status line is live text
## (the supplied bar bakes a fixed "Day 5" and can't carry an arbitrary
## day). Every piece falls back to the previous procedural draw if missing.
##
## Value-pill ↔ reward-day mapping (matches DailyRewards.TABLE 1:1):
##   day 1→100  day 2→150  day 3→BOOST  day 4→250  day 5→BOOST  day 6→400  day 7→600
## Reward-icon mapping: coin days use the crown coin, day 3 the crystal
## (the sheet's crossed-swords icon has the green tick composited over it in
## the source and is NOT cleanly separable), day 5 the rainbow swirl, day 7
## the second crown.

signal closed()

const KEY_LAST := "daily_last_claim_day"
const KEY_STREAK := "daily_streak"

var _tiles: Array[DayTile] = []
var _claim_btn: Control
var _claim_press: Callable = Callable()
var _status: Label
var _state: Dictionary = {}
var _panel: UiKit.AssetFramePanel
var _scrim: ColorRect

## Does the player have a daily reward waiting right now? (for the menu badge)
static func has_claimable() -> bool:
	var last := SaveService.get_int(KEY_LAST, -1)
	var streak := SaveService.get_int(KEY_STREAK, 0)
	return DailyRewards.claim_state(DailyRewards.today(), last, streak)["claimable"]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := Backdrop.new()
	bg.accent = VisualTheme.STAR
	bg.scene_id = &"env_energy_crystals"
	add_child(bg)

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.42)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_panel = UiKit.AssetFramePanel.new(&"dr_frame", 10.0, 30.0)
	add_child(_panel)
	_panel.set_banner(&"dr_title", 0.72)
	_panel.set_close_x(&"dr_close_x", func():
		Audio.play(&"button_tap")
		closed.emit())
	# Reference match: the 4+3 grid + status + CLAIM are distributed down the
	# panel (grid near the top, CLAIM near the bottom) instead of crammed up
	# top. The frame slice is more elongated than the ref mock, so a little
	# breathing room top and bottom keeps it from reading as top-heavy.
	_panel.set_content_top(0.015)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.content().add_child(col)
	if AssetLibrary.ui_slice(&"dr_title") == null:
		col.add_child(VisualTheme.label("DAILY REWARDS", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD))

	# The dr_frame slice is more elongated than the reference mock, so the
	# whole grid + status + CLAIM block is vertically centred between two
	# equal expanding spacers — a clean, spacious calendar instead of a
	# top-crammed grid with a stranded button far below it.
	var lead := Control.new()
	lead.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(lead)

	# --- 4 + 3 day grid — both rows the SAME card size, each row centred.
	# Every tile is registered with the panel's aspect-fit pass at the same
	# wfrac/aspect, so all 7 come out identical (ref: DAY 1-4 span the
	# interior, DAY 5-7 are a centred group of three the same size). wfrac
	# is kept small enough that 4 cards + gaps never collide.
	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 24)
	col.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 24)
	col.add_child(row2)
	for day in range(1, 8):
		var tile := DayTile.new()
		tile.day = day
		tile.reward = DailyRewards.reward_for_day(day)
		UiKit.tag_aspect_fit(tile, 0.66, 0.205)
		(row1 if day <= 4 else row2).add_child(tile)
		_tiles.append(tile)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)

	_status = VisualTheme.label("", VisualTheme.FS_HEADING, VisualTheme.TEXT, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 44)
	col.add_child(gap2)

	_claim_btn = _build_claim_button()
	col.add_child(_claim_btn)

	var trail := Control.new()
	trail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(trail)

	_track_size()
	get_viewport().size_changed.connect(_track_size)
	refresh()

## Green CLAIM button — supplied art when present, else the old primary
## button. Returns the node to add; the click wiring is the same either way.
func _build_claim_button() -> Control:
	var b := UiKit.asset_button_fw(AssetLibrary.ui_slice(&"dr_btn_claim"), 0.58)
	if b != null:
		b.pressed.connect(_on_claim)
		_claim_press = func(disabled: bool):
			b.disabled = disabled
			b.modulate.a = 0.5 if disabled else 1.0
		return b
	var pb := UiKit.button("CLAIM", &"primary", VisualTheme.FS_HEADING)
	pb.custom_minimum_size = Vector2(0, 80)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.pressed.connect(_on_claim)
	_claim_press = func(disabled: bool):
		pb.disabled = disabled
		pb.modulate.a = 0.5 if disabled else 1.0
	return pb

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	if _panel != null:
		_panel.layout(vp)

## Called by app.gd when the screen becomes visible — play the entrance.
func play_entrance() -> void:
	if _panel != null:
		_track_size()
		UiKit.pop_in(_panel.visual())

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
		if _claim_press.is_valid():
			_claim_press.call(false)
	else:
		_status.text = "Come back tomorrow for Day %d!" % clampi(claimed_through + 1, 1, 7)
		if _claim_press.is_valid():
			_claim_press.call(true)

func _on_claim() -> void:
	if not _state.get("claimable", false):
		return
	Audio.play(&"button_tap")
	var day := int(_state["day"])
	var reward: Dictionary = DailyRewards.reward_for_day(day)

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


## One day cell in the calendar, built from the supplied tile / icon / pill
## slices. States: claimed | current | upcoming | future — the state only
## changes tint/overlay, never the artwork. Falls back to a code-drawn tile
## when the sheet is missing.
class DayTile extends Control:
	var day := 1
	var reward: Dictionary = {}
	var state: StringName = &"future"

	var _bg: TextureRect
	var _icon: TextureRect
	var _pill: Control
	var _check: TextureRect
	var _fx: _TileFx
	var _has_art := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg_tex := AssetLibrary.ui_slice(StringName("dr_tile_day%d" % clampi(day, 1, 7)))
		_has_art = bg_tex != null
		if _has_art:
			_bg = TextureRect.new()
			_bg.texture = bg_tex
			_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
			_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_bg)

			_icon = TextureRect.new()
			_icon.texture = _reward_icon()
			_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_icon)

			_pill = UiKit.asset_rect(_value_pill_id())
			if _pill != null:
				# asset_rect floors the size at the native texture width — clear
				# it so _relayout() can shrink the pill to fit inside the card.
				_pill.custom_minimum_size = Vector2.ZERO
				_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(_pill)

			_check = TextureRect.new()
			_check.texture = AssetLibrary.ui_slice(&"dr_icon_check")
			_check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_check.visible = false
			add_child(_check)

		_fx = _TileFx.new()
		_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fx)
		resized.connect(_relayout)
		_relayout()
		_apply_state()

	func _reward_icon() -> Texture2D:
		match day:
			3: return AssetLibrary.ui_slice(&"dr_icon_crystal")
			5: return AssetLibrary.ui_slice(&"dr_icon_rainbow")
			7: return AssetLibrary.ui_slice(&"dr_icon_crown_b")
			_: return AssetLibrary.ui_slice(&"dr_icon_crown_a")

	func _value_pill_id() -> StringName:
		match day:
			1: return &"dr_pill_100"
			2: return &"dr_pill_150"
			3: return &"dr_btn_boost"
			4: return &"dr_pill_250"
			5: return &"dr_btn_boost"
			6: return &"dr_pill_400"
			_: return &"dr_pill_600"

	func _relayout() -> void:
		if not _has_art:
			return
		var w := size.x
		var h := size.y
		# Proportions read off Daily Reward Panel Reference.png: baked "DAY N"
		# occupies the top ~18% of the card, the reward icon is centred at
		# ~45% height, the value pill sits at ~80%, the claimed ✓ overlaps the
		# bottom-right and spills slightly past the card edge.
		if _icon != null:
			var d := w * 0.50
			_icon.size = Vector2(d, d)
			_icon.position = Vector2((w - d) * 0.5, h * 0.21)
		if _pill != null:
			var pw := w * 0.72
			var ph := pw / 2.1
			_pill.size = Vector2(pw, ph)
			_pill.position = Vector2((w - pw) * 0.5, h * 0.78 - ph * 0.5)
		if _check != null:
			# tucked into the card's bottom-right corner, clear of the value
			# pill (matches the reference)
			var cs := w * 0.34
			_check.size = Vector2(cs, cs)
			_check.position = Vector2(w - cs * 0.88, h * 0.66)

	func set_state(s: StringName) -> void:
		state = s
		_apply_state()

	func _apply_state() -> void:
		if _fx != null:
			_fx.current = state == &"current"
			_fx.set_process(state == &"current" or _fx._burst > 0.0)
			_fx.queue_redraw()
		if not _has_art:
			queue_redraw()
			return
		var dim := state == &"future"
		modulate = Color(1, 1, 1, 0.45) if dim else Color(1, 1, 1, 1)
		if _check != null:
			_check.visible = state == &"claimed"

	func play_claim_burst() -> void:
		if _fx != null:
			_fx.play_burst()

	func _draw() -> void:
		# fallback tile (no supplied art)
		if _has_art:
			return
		var r := Rect2(Vector2.ZERO, size)
		var body := Color(0.07, 0.08, 0.15, 0.7)
		var border := Color(1, 1, 1, 0.10)
		match state:
			&"claimed": border = Color(0.4, 0.7, 0.5, 0.35)
			&"current": border = VisualTheme.STAR
			&"upcoming": border = Color(0.7, 0.8, 1.0, 0.4)
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, 16.0, 5)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.size * 0.5)
		draw_colored_polygon(moved, body)
		moved.append(moved[0])
		draw_polyline(moved, border, 2.0, true)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(10, 22), "DAY %d" % day, HORIZONTAL_ALIGNMENT_LEFT, -1, VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM)
		var amt := int(reward.get("coins", 0))
		var lbl := ("%d" % amt) if amt > 0 else "BOOST"
		draw_string(font, Vector2(10, r.size.y - 12), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, VisualTheme.FS_CAPTION, VisualTheme.TEXT)

	## Highlight/burst effects layer — a glow pulse for the "current" day and
	## a claim ring. These are transient feedback, never a redraw of the
	## supplied tile artwork.
	class _TileFx extends Control:
		var current := false
		var _burst := 0.0
		var _t := 0.0

		func _ready() -> void:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			set_process(false)

		func play_burst() -> void:
			_burst = 1.0
			set_process(true)
			var tw := create_tween()
			tw.tween_method(func(v): _burst = v; queue_redraw(), 1.0, 0.0, 0.7)

		func _process(delta: float) -> void:
			_t += delta
			queue_redraw()
			if not current and _burst <= 0.0:
				set_process(false)

		func _draw() -> void:
			if current:
				var p := 0.5 + 0.5 * sin(_t * 6.0)
				VisualTheme.draw_glow(self, size * 0.5, size.x * 0.7, Color(1, 0.85, 0.3, 0.18 + 0.14 * p), 4)
			if _burst > 0.0:
				var rad := (1.0 - _burst) * size.x * 0.9
				draw_arc(size * 0.5, rad, 0, TAU, 28, Color(1, 0.9, 0.4, _burst), 4.0, true)


## Pointed-tail ribbon banner — kept only as the fallback title when the
## supplied DAILY REWARDS ribbon slice is unavailable.
class RibbonBanner extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
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
