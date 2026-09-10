class_name HUD
extends Control
## Mobile-first gameplay HUD, built entirely in code so the layout stays
## anchor-driven and scales to any portrait resolution. Three top pills
## (MOVES / TARGET / COINS), a Fever meter, a bottom booster tray, and
## animated win/lose + settings overlays. The board renders beneath this
## layer; only the top/bottom strips and popups intercept touch.

signal booster_pressed(booster_id: StringName)
signal next_level_pressed()
signal retry_pressed()
signal map_pressed()
## Win-panel rewarded-ad "double your coins" — app.gd runs the ad + grant.
signal double_coins_requested()
signal pause_pressed()
signal resume_pressed()
## In-level booster shop opened from the HUD (app.gd freezes the board).
signal shop_pressed()
## Player pressed USE in the in-level shop — app.gd routes it through the
## existing booster pipeline (arm / instant fire -> CombatDirector).
signal shop_use_booster(booster_id: StringName)
## The in-level shop was dismissed (with or without a USE) — app.gd unfreezes
## the board.
signal shop_closed()
## "Need More Moves?" outcome — app.gd adds the moves to the live level.
signal continue_bought(moves_added: int)
signal continue_declined()

var _level_label: LevelBadge
var _score_label: UiKit.GlyphNum       # 2026-09-06: supplied gold digit glyphs
var _moves_value: UiKit.GlyphNum
var _moves_pill: Control
var _objective_row: HBoxContainer
## 2026-09-07 gameplay top-section rebuild — the individual artist-supplied
## PNGs (assets/topbar/, `tbn_*`): crown-shield MOVES / SCORE badges, the
## dynamically assembled GOAL panel (left cap + procedural middle + right cap
## + GOAL header, per Goal Parts/goal part instructions..txt), the FEVER bar
## + crown, and the SCORE shield's live star row.
var _tb_moves_zone            # HUD.StatBadge (supplied MOVES badge art + GlyphNum)
var _tb_goal_zone: Control    # dynamically assembled GOAL panel
var _tb_score_zone            # HUD.StatBadge (supplied SCORE badge art + GlyphNum)
var _tb_row1: Control
var _tb_row2: Control
var _goal_mid: Panel          # procedural rounded-blue middle (grows with objective count)
var _goal_left: TextureRect   # fixed decorative left end cap (tbn_goal_left)
var _goal_right: TextureRect  # fixed decorative right end cap (tbn_goal_right)
var _goal_header: TextureRect # GOAL header, centred above the assembly (tbn_goal_top)
## Fixed inner content window inside `_goal_mid`. Its rect is derived ONLY
## from the panel geometry (never from the objectives), and `clip_contents`
## is on, so the objective chip row can never paint past the panel border,
## the screen edge, or up behind the GOAL header — regardless of objective
## count / type / label length.
var _goal_content_clip: Control
var _tb_stars: Array = []
var _star_scores: Array = []
var _objective_chips: Array[Node] = []
## Tracks each objective's complete/incomplete state across calls to
## set_objectives() (called every move) so a fresh completion can fire an
## "OBJECTIVE COMPLETE" toast exactly once, not every subsequent move.
## Size mismatch = a new level's objectives just loaded, so no toasts fire.
var _prev_obj_complete: Array = []
var _coins_label: Label
var _fever_bar                 # UiKit.FeverBarArt (supplied art) or legacy FeverArt
var _fever_label: Label
var _power_meters: PowerMeters
var _boss_bar: BossBar
var _fever_wrap: Control
var _booster_buttons: Dictionary = {}
var _booster_badges: Dictionary = {}
var _booster_slots: Dictionary = {}      # id -> Control (for scale/armed FX)
var _booster_counts: Dictionary = {}     # id -> int (last known)
var _armed_booster: StringName = &""
var _hint_label: Label
var _end_panel: UiKit.GoldFramePanel
var _end_center: CenterContainer
var _end_title: Label
var _end_stars: StarRow
var _end_body: Label
var _end_button: Button
var _end_map_button: Button
var _end_double_button: Button
var _end_confetti: CPUParticles2D
var _settings_dialog: SettingsPanel
## Instantiated via load() (not the BoosterShop / ExtraMovesPrompt class_name)
## so hud.gd carries no compile-time dependency on them — those overlays pull
## in UiKit which pulls in HUD, and a typed reference here would close that
## into a class-resolution cycle.
var _booster_shop            # BoosterShop
var _moves_prompt            # ExtraMovesPrompt
var _pause_center: CenterContainer
var _pause_panel: UiKit.GoldFramePanel
var _scrim: ColorRect
var _displayed_coins: int = 0
var _fever_running := false
var _fever_pulse: Tween
var _fx: SpriteFX
var _end_crown: TextureRect

## Order + identity of the in-level booster tray. Icons are code-drawn
## (IconDraw) — no emoji (Android dropped the legacy emoji font).
const _BOOSTER_ORDER: Array[StringName] = [
	&"bomb", &"lightning", &"freeze", &"rainbow", &"shuffle", &"extra_moves",
]
const _BOOSTER_TINT := {
	&"bomb": Color(0.85, 0.22, 0.28), &"lightning": Color(0.98, 0.72, 0.14),
	&"freeze": Color(0.28, 0.66, 0.96), &"rainbow": Color(0.62, 0.34, 0.94),
	&"shuffle": Color(0.2, 0.7, 0.55), &"extra_moves": Color(0.3, 0.6, 0.95),
}

## Screen-edge insets (notch / status bar / gesture bar) in viewport units,
## resolved from DisplayServer.get_display_safe_area(). Everything at the
## top/bottom of the HUD is pushed in by these so nothing is ever clipped.
var _safe_top := 0.0
var _safe_bottom := 0.0
var _top_margin: MarginContainer
var _top_col: VBoxContainer
var _bottom_col: VBoxContainer

## The booster-tray column is anchored to the screen bottom and END-aligns
## its content, so it needs to be at least as tall as that content. The
## actual space the board must avoid is `playfield_bottom()` (measured from
## the real tray contents), which is smaller.
const TRAY_COL_HEIGHT := 380.0
## Height (viewport units) the tray content occupies inside that column:
## hint line + separator + tray panel (margins + one 214-tall chip row).
const TRAY_CONTENT_HEIGHT := 300.0
## Some Android gesture-nav devices report a full-height safe area (no bottom
## inset) yet still overlay a gesture pill — keep at least this much clear.
const MIN_BOTTOM_CLEARANCE := 56.0
## Height (viewport units) of the character combat arena band that sits
## BETWEEN the match-3 board and the booster tray (Phase C). The board is
## fitted above it so the three characters have a real stage and never
## overlap the board.
const ARENA_HEIGHT := 360.0

## Y (viewport units) below which the playfield may start — just under the
## top HUD column. app.gd fits the board between this and `playfield_bottom`.
func playfield_top() -> float:
	var top := maxf(_safe_top, VisualTheme.STATUS_BAR_MIN) + 24.0
	var col_h := 264.0
	if _top_col != null:
		var m := _top_col.get_combined_minimum_size().y
		if m > 40.0:
			col_h = m
	return top + col_h + 40.0

## Vertical space the booster tray reserves at the very bottom (screen edge
## up to the top of the tray's contents).
func tray_reserve() -> float:
	return maxf(_safe_bottom, MIN_BOTTOM_CLEARANCE) + 12.0 + TRAY_CONTENT_HEIGHT

## Space (viewport units) to keep clear at the bottom of the playfield —
## now the tray reservation PLUS the character combat arena, so the board
## stops above the arena and never overlaps the characters.
func playfield_bottom() -> float:
	return tray_reserve() + ARENA_HEIGHT

## The combat arena band, in viewport units. `y` = arena top (just below the
## board), `y + h` = arena floor (just above the tray). app.gd stands Jamie /
## the enemy / Jasmine on this floor.
func arena_floor_y() -> float:
	return get_viewport_rect().size.y - tray_reserve()

func arena_top_y() -> float:
	return arena_floor_y() - ARENA_HEIGHT

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resolve_safe_area()
	_build_top_bar()
	_build_fever_meter()
	_build_booster_bar()
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.55)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)
	_build_end_panel()
	_settings_dialog = SettingsPanel.new()
	add_child(_settings_dialog)
	# In-level booster shop + "Need More Moves?" — self-contained overlays
	# (own scrim), like SettingsPanel. app.gd drives open/close and freezes
	# the board while either is up.
	_booster_shop = load("res://scripts/ui/booster_shop.gd").new()
	add_child(_booster_shop)
	_booster_shop.use_requested.connect(func(id): shop_use_booster.emit(id))
	_booster_shop.closed.connect(func(): shop_closed.emit())
	_moves_prompt = load("res://scripts/ui/extra_moves_prompt.gd").new()
	add_child(_moves_prompt)
	_moves_prompt.bought.connect(func(m): continue_bought.emit(m))
	_moves_prompt.gave_up.connect(func(): continue_declined.emit())
	_build_pause_panel()
	_fx = SpriteFX.new()
	_fx.z_index = 300
	add_child(_fx)
	_track_size()
	get_viewport().size_changed.connect(_track_size)

## A Control parented to a CanvasLayer is not auto-resized to the viewport,
## so anchor presets (BOTTOM_WIDE, CENTER, ...) collapse unless we set the
## rect ourselves. Keep it pinned to the visible viewport.
func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	_resolve_safe_area()
	if _top_margin != null:
		_top_margin.add_theme_constant_override("margin_top", int(maxf(_safe_top, VisualTheme.STATUS_BAR_MIN) + 24.0))
	if _bottom_col != null:
		_bottom_col.offset_top = -TRAY_COL_HEIGHT
		_bottom_col.offset_bottom = -int(maxf(_safe_bottom, MIN_BOTTOM_CLEARANCE) + 12.0)
	# Full-rect overlay children (Settings / booster shop / continue prompt) are
	# constructed BEFORE this first runs, while HUD itself is still zero-sized
	# (a Control parented to a CanvasLayer starts at (0,0) — see the note
	# above). Their own _track_size() already ran once against that zero-sized
	# parent, baking in wrong FULL_RECT offsets that double up once HUD grows
	# to the real viewport size — on a real device this pushed the "NEED MORE
	# MOVES?" panel and the booster shop off the right edge. Re-run each
	# child's _track_size() now that HUD has its true size, and again on every
	# future resize (this function already runs on size_changed).
	for overlay in [_settings_dialog, _booster_shop, _moves_prompt]:
		if overlay != null and overlay.has_method("_track_size"):
			overlay._track_size()
	_layout_topbar()

func _resolve_safe_area() -> void:
	var vp := get_viewport_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.y <= 0 or safe.size.y <= 0:
		return
	var sy := vp.y / float(win.y)
	_safe_top = maxf(float(safe.position.y) * sy, 0.0)
	_safe_bottom = maxf(float(win.y - (safe.position.y + safe.size.y)) * sy, 0.0)

# ------------------------------------------------------------- top bar --

func _icon_button(kind: StringName, size: int = 46) -> Button:
	# frosted-glass disc (shared UiKit style)
	return UiKit.icon_button(kind, size)

func _pill(child: Control, min_w: float = 0.0) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.glass(22, true))
	pc.custom_minimum_size = Vector2(min_w, 0)
	pc.add_child(child)
	return pc

func _build_top_bar() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", int(maxf(_safe_top, VisualTheme.STATUS_BAR_MIN) + 24.0))
	_top_margin = margin
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.clip_contents = false
	_top_col = col
	margin.add_child(col)

	# 2026-09-07: rebuilt against the supplied gameplay reference + individual
	# tbn_* PNGs. Falls back to the fully procedural bar if the art is absent.
	var have_tb := AssetLibrary.ui_texture(&"tbn_moves") != null
	if not have_tb:
		_build_top_bar_legacy(col)
		return

	# --- row 1: pause (far left) · LEVEL badge (DEAD CENTRE) · coins(+) /
	# cart / gear (far right). A plain Control positioned by maths in
	# _layout_topbar() — an HBox can't screen-centre the LEVEL badge because
	# the right-hand cluster is much heavier than the lone pause button.
	var row1 := Control.new()
	row1.clip_contents = false
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tb_row1 = row1
	col.add_child(row1)

	var pause_btn := _tb_circle_btn(&"tbn_pause", &"pause")
	pause_btn.set_meta("r1", "pause")
	pause_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		pause_pressed.emit())
	row1.add_child(pause_btn)

	_level_label = LevelBadge.new()
	# the crowned-shield art is drawn ~2x oversize and overhangs up/down so it
	# interleaves with row 2 exactly like the reference.
	_level_label.custom_minimum_size = Vector2(0, 100)
	_level_label.clip_contents = false
	row1.add_child(_level_label)

	# coin readout — dark pill (coin icon + gold count) with the supplied
	# green "+" disc overhanging its right end (opens the shop; existing flow).
	# No coin-icon / pill art was supplied, so those keep their current look.
	var coin_holder := Control.new()
	coin_holder.custom_minimum_size = Vector2(214, 66)
	coin_holder.set_meta("r1", "coins")
	coin_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_pill := PanelContainer.new()
	coin_pill.add_theme_stylebox_override("panel", UiKit.glass(24, true))
	coin_pill.set_anchors_preset(Control.PRESET_FULL_RECT)
	coin_pill.offset_right = -26.0
	var coin_box := HBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 8)
	coin_box.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_pill.add_child(coin_box)
	var coin_icon := GemIcon.new()
	coin_icon.kind = &"coin"
	coin_icon.custom_minimum_size = Vector2(34, 34)
	coin_box.add_child(coin_icon)
	_coins_label = VisualTheme.label("0", VisualTheme.FS_LABEL, VisualTheme.TEXT_GOLD)
	coin_box.add_child(_coins_label)
	coin_holder.add_child(coin_pill)
	var add_btn := UiKit.asset_button(AssetLibrary.ui_texture(&"tbn_add"))
	if add_btn != null:
		add_btn.custom_minimum_size = Vector2(56, 56)
		add_btn.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		add_btn.offset_left = -56.0
		add_btn.offset_top = -28.0
		add_btn.offset_right = 0.0
		add_btn.offset_bottom = 28.0
		add_btn.pressed.connect(func():
			Audio.play(&"button_tap")
			shop_pressed.emit())
		coin_holder.add_child(add_btn)
	row1.add_child(coin_holder)

	var shop_btn := _tb_circle_btn(&"tbn_cart", &"bag")
	shop_btn.set_meta("r1", "cart")
	shop_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		shop_pressed.emit())
	row1.add_child(shop_btn)

	var gear := _tb_circle_btn(&"tbn_gear", &"gear")
	gear.set_meta("r1", "gear")
	gear.pressed.connect(func():
		Audio.play(&"button_tap")
		_show_settings(true))
	row1.add_child(gear)

	# --- row 2: MOVES badge | GOAL panel | SCORE badge --------------------
	# A plain Control — the three pieces are positioned by maths in
	# _layout_topbar(): the supplied crown-shield badges are TALLER than the
	# Goal panel and their crowns / ribbons overhang, which an HBox can't
	# express. Reference-driven vertical hierarchy.
	var row2 := Control.new()
	row2.clip_contents = false
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tb_row2 = row2
	col.add_child(row2)

	_tb_moves_zone = StatBadge.new(&"tbn_moves")
	row2.add_child(_tb_moves_zone)
	_moves_value = _tb_moves_zone.num
	_moves_value.digit_h = 54.0

	_tb_goal_zone = _build_goal_zone()
	row2.add_child(_tb_goal_zone)

	_tb_score_zone = StatBadge.new(&"tbn_score")
	row2.add_child(_tb_score_zone)
	_score_label = _tb_score_zone.num
	_score_label.digit_h = 44.0

	# Live star row on the SCORE shield (reflective only — StarRating still
	# owns the award). Small, tucked at the base of the shield so the badge
	# still reads as the supplied art (the reference shows no star row).
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.add_theme_constant_override("separation", 4)
	star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var st := TextureRect.new()
		st.texture = AssetLibrary.tex(&"eco_star")
		st.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		st.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		st.custom_minimum_size = Vector2(22, 22)
		st.modulate = Color(1, 1, 1, 0.26)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_row.add_child(st)
		_tb_stars.append(st)
	star_row.set_meta("is_star_row", true)
	_tb_score_zone.add_child(star_row)

	# a dedicated gap so the FEVER section (added next by _build_fever_meter)
	# has clear breathing room from the stat row.
	var fever_gap := Control.new()
	fever_gap.custom_minimum_size = Vector2(0, 4)
	fever_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fever_gap)

	_layout_topbar()

## The GOAL panel, assembled dynamically per
## `Downloads/New Assets/Goal Parts/goal part instructions..txt`:
##   [ left cap ] [ dynamic middle — one blue chip per objective ] [ right cap ]
## with the GOAL header centred above the whole assembly. The three supplied
## PNGs (tbn_goal_left / _right / _top) are used undistorted (aspect-fit);
## only `_goal_mid` — a procedural rounded-blue panel, exactly as the txt
## specifies — expands with the objective count. Nothing is flattened,
## redrawn or stretched.
func _build_goal_zone() -> Control:
	var z := Control.new()
	z.clip_contents = false
	z.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_goal_mid = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.106, 0.325, 0.78)
	sb.set_corner_radius_all(18)
	sb.border_color = Color(0.93, 0.70, 0.24)
	sb.set_border_width_all(6)
	sb.shadow_size = 0
	_goal_mid.add_theme_stylebox_override("panel", sb)
	_goal_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z.add_child(_goal_mid)

	_goal_left = _goal_cap(&"tbn_goal_left")
	z.add_child(_goal_left)
	_goal_right = _goal_cap(&"tbn_goal_right")
	z.add_child(_goal_right)

	# Fixed, panel-derived clip window; the chip row lives inside it and is
	# centred there. _layout_topbar() sizes/places this to a rect strictly
	# inside `_goal_mid`'s gold border.
	_goal_content_clip = Control.new()
	_goal_content_clip.clip_contents = true
	_goal_content_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z.add_child(_goal_content_clip)

	_objective_row = HBoxContainer.new()
	_objective_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_objective_row.add_theme_constant_override("separation", 12)
	_objective_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal_content_clip.add_child(_objective_row)

	_goal_header = TextureRect.new()
	_goal_header.texture = AssetLibrary.ui_texture(&"tbn_goal_top")
	_goal_header.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_goal_header.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_goal_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z.add_child(_goal_header)
	return z

func _goal_cap(tex_id: StringName) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = AssetLibrary.ui_texture(tex_id)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## Circle button from the supplied disc art, or the old glass disc.
func _tb_circle_btn(tex_id: StringName, fallback_glyph: StringName) -> BaseButton:
	var tex := AssetLibrary.ui_texture(tex_id)
	if tex != null:
		var b := UiKit.asset_button(tex)
		b.custom_minimum_size = Vector2(76, 76)
		return b
	return _icon_button(fallback_glyph, 72)

## One deliberate reference-driven layout pass for the whole top section.
## Everything is derived from `inner` (the top bar's usable width) and a
## single badge height `bh`; no piecemeal nudging.
func _layout_topbar() -> void:
	if _tb_moves_zone == null or not is_instance_valid(_tb_moves_zone):
		return
	var vp := get_viewport_rect().size
	var inner: float = maxf(vp.x - 44.0, 320.0)

	# --- row 1: pause far-left, LEVEL badge DEAD CENTRE, coins/cart/gear
	# far-right. Positioned by maths so the LEVEL badge always lands on the
	# screen centre regardless of how heavy the right-hand cluster is.
	if _tb_row1 != null:
		var r1h := 96.0
		_tb_row1.custom_minimum_size = Vector2(inner, r1h)
		var btn := 76.0
		var gap := 12.0
		for c in _tb_row1.get_children():
			if not (c is Control):
				continue
			var tagm := String((c as Control).get_meta("r1", ""))
			match tagm:
				"pause":
					(c as Control).position = Vector2(0.0, (r1h - btn) * 0.5)
					(c as Control).size = Vector2(btn, btn)
				"gear":
					(c as Control).position = Vector2(inner - btn, (r1h - btn) * 0.5)
					(c as Control).size = Vector2(btn, btn)
				"cart":
					(c as Control).position = Vector2(inner - btn * 2.0 - gap, (r1h - btn) * 0.5)
					(c as Control).size = Vector2(btn, btn)
				"coins":
					var ch := (c as Control)
					var cw: float = ch.custom_minimum_size.x
					ch.position = Vector2(inner - btn * 2.0 - gap * 2.0 - cw, (r1h - ch.custom_minimum_size.y) * 0.5)
					ch.size = Vector2(cw, ch.custom_minimum_size.y)
		if _level_label != null:
			var lw: float = clampf(inner * 0.42, 200.0, 320.0)
			_level_label.position = Vector2(inner * 0.5 - lw * 0.5, 0.0)
			_level_label.size = Vector2(lw, r1h)

	# MOVES / SCORE crown-shield badges sit left / right, TALLER than the GOAL
	# panel; their crowns rise toward row 1 and their shields drop below the
	# GOAL panel — the reference stack. Decorative art is only ever aspect-fit.
	var bh: float = clampf(inner * 0.205, 165.0, 232.0)
	var m_aspect: float = _tb_moves_zone.art_aspect()
	var s_aspect: float = _tb_score_zone.art_aspect()
	var bw_m: float = bh * m_aspect
	var bw_s: float = bh * s_aspect
	# The GOAL zone is EXACTLY centred: the same margin on both sides (the
	# larger of the two badge widths), so a tiny MOVES/SCORE art-aspect
	# difference can never drift the panel off centre.
	var goal_margin: float = maxf(bw_m, bw_s)
	var goal_x0: float = goal_margin
	var goal_x1: float = inner - goal_margin
	var goal_w: float = maxf(goal_x1 - goal_x0, 340.0)
	var gh: float = clampf(goal_w * 0.185, 96.0, 150.0)
	# GOAL panel body centred on the badges' blue shield field, pulled up so
	# the "GOAL" header interleaves with the LEVEL badge above (reference),
	# leaving no dead band between row 1 and row 2.
	var shield_cy: float = bh * 0.52
	var goal_top: float = shield_cy - gh * 0.5

	# the badges overhang the box downward (transparent art tail); reserving
	# only ~0.82·bh kills the empty gap before the FEVER bar.
	_tb_row2.custom_minimum_size = Vector2(inner, bh * 0.82)
	_tb_moves_zone.position = Vector2(0.0, 0.0)
	_tb_moves_zone.size = Vector2(bw_m, bh)
	_tb_score_zone.position = Vector2(inner - bw_s, 0.0)
	_tb_score_zone.size = Vector2(bw_s, bh)
	_tb_goal_zone.position = Vector2(goal_x0, 0.0)
	_tb_goal_zone.size = Vector2(goal_w, bh)

	# MOVES / SCORE number on the blue shield field (below the baked label)
	if _moves_value != null:
		_moves_value.digit_h = bh * 0.24
		_moves_value.position = Vector2(bw_m * 0.5, bh * 0.70)
	if _score_label != null:
		_score_label.digit_h = bh * 0.22
		_score_label.position = Vector2(bw_s * 0.5, bh * 0.665)
	for c in _tb_score_zone.get_children():
		if c is HBoxContainer and c.has_meta("is_star_row"):
			var sr := c as HBoxContainer
			var ss: float = bh * 0.082
			sr.add_theme_constant_override("separation", int(ss * 0.3))
			for st in sr.get_children():
				(st as Control).custom_minimum_size = Vector2(ss, ss)
			var srw: float = ss * 3.0 + ss * 0.6
			sr.position = Vector2(bw_s * 0.5 - srw * 0.5, bh * 0.83)

	# --- GOAL assembly (Goal Parts txt) — caps fixed, middle dynamic -------
	var cap_h: float = gh
	var cap_w_l: float = cap_h * 1.14
	var cap_w_r: float = cap_h * 1.14
	if _goal_left != null and _goal_left.texture != null and _goal_left.texture.get_height() > 0:
		cap_w_l = cap_h * float(_goal_left.texture.get_width()) / float(_goal_left.texture.get_height())
	if _goal_right != null and _goal_right.texture != null and _goal_right.texture.get_height() > 0:
		cap_w_r = cap_h * float(_goal_right.texture.get_width()) / float(_goal_right.texture.get_height())
	if _goal_left != null:
		_goal_left.position = Vector2(0.0, goal_top)
		_goal_left.size = Vector2(cap_w_l, cap_h)
	if _goal_right != null:
		_goal_right.position = Vector2(goal_w - cap_w_r, goal_top)
		_goal_right.size = Vector2(cap_w_r, cap_h)
	if _goal_mid != null:
		# the middle spans right under the caps (their opaque gold frame hides
		# its rounded corners → a clean join) and matches their height so the
		# gold rail reads as continuous, exactly like the reference.
		var mx0: float = cap_w_l * 0.24
		var mx1: float = goal_w - cap_w_r * 0.24
		_goal_mid.position = Vector2(mx0, goal_top)
		_goal_mid.size = Vector2(maxf(mx1 - mx0, 40.0), cap_h)
	if _goal_header != null and _goal_header.texture != null and _goal_header.texture.get_height() > 0:
		var ha: float = float(_goal_header.texture.get_width()) / float(_goal_header.texture.get_height())
		var hw: float = clampf(goal_w * 0.52, 220.0, 560.0)
		var hh: float = hw / ha
		# the "GOAL" header sits ABOVE the panel — centred on the whole
		# assembly, only its bottom decorative lip dips into the panel's top
		# gold border, well clear of the objective chips below.
		_goal_header.position = Vector2(goal_w * 0.5 - hw * 0.5, goal_top - hh * 0.78)
		_goal_header.size = Vector2(hw, hh)
	# --- UI FIX #1 (revised 2026-09-10): the objective chips live in a FIXED
	# inner content rectangle inside `_goal_mid`. That rect is a pure function
	# of the panel geometry (screen width + badge art) — it does NOT depend on
	# the objectives — so it never moves between stages. The chip row fills
	# that rect and centres its chips inside it natively (H via the HBox's
	# CENTER alignment, V via SHRINK_CENTER on each chip). If the row's
	# natural size exceeds the rect it is scaled down uniformly ABOUT THE RECT
	# CENTRE, so it shrinks in place instead of drifting. `_goal_content_clip`
	# has clip_contents on, so even a pathological case can't paint past the
	# panel border, the screen edge, or up behind the GOAL header. The GOAL
	# panel art itself is never stretched.
	if _objective_row != null and _goal_mid != null and _goal_content_clip != null:
		var pad_x := 16.0
		var pad_y := 12.0
		var rect_w: float = maxf(_goal_mid.size.x - pad_x * 2.0, 30.0)
		var rect_h: float = maxf(_goal_mid.size.y - pad_y * 2.0, 20.0)
		_goal_content_clip.position = Vector2(_goal_mid.position.x + pad_x, _goal_mid.position.y + pad_y)
		_goal_content_clip.size = Vector2(rect_w, rect_h)

		# the row fills the fixed rect; the HBox centres the chip block inside
		# it, and each chip keeps its natural size (no stretch) centred on the
		# row's vertical axis.
		for ch in _objective_row.get_children():
			if ch is Control:
				(ch as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				(ch as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_objective_row.position = Vector2.ZERO
		_objective_row.size = Vector2(rect_w, rect_h)
		_objective_row.queue_sort()

		var cmin: Vector2 = _objective_row.get_combined_minimum_size()
		var sc := 1.0
		if cmin.x > 1.0 and cmin.y > 1.0:
			sc = clampf(minf(rect_w / cmin.x, rect_h / cmin.y), 0.30, 1.0)
		_objective_row.pivot_offset = Vector2(rect_w, rect_h) * 0.5
		_objective_row.scale = Vector2(sc, sc)

	# --- FEVER — clear breathing room + the supplied bar's true aspect -----
	if _fever_wrap != null:
		_fever_wrap.custom_minimum_size = Vector2(0, clampf(inner / 6.56 + 6.0, 78.0, 205.0))
	if is_instance_valid(_top_col):
		_top_col.add_theme_constant_override("separation", 4)
	_moves_pill = _tb_moves_zone

## The pre-2026-09-06 procedural top bar — kept as the fallback when the
## supplied topbar sheet is unavailable.
func _build_top_bar_legacy(col: VBoxContainer) -> void:
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	col.add_child(row1)
	var pause_btn := _icon_button(&"pause", 68)
	pause_btn.pressed.connect(func(): Audio.play(&"button_tap"); pause_pressed.emit())
	row1.add_child(pause_btn)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 1)
	_level_label = LevelBadge.new()
	_level_label.custom_minimum_size = Vector2(0, 46)
	title_box.add_child(_level_label)
	var score_cap := VisualTheme.label("SCORE", VisualTheme.FS_CAPTION, VisualTheme.TEXT_DIM, 0)
	score_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(score_cap)
	_score_label = UiKit.GlyphNum.new()
	_score_label.digit_h = 36.0
	title_box.add_child(_score_label)
	row1.add_child(title_box)
	var shop_btn := UiKit.icon_button(&"bag", 68)
	shop_btn.pressed.connect(func(): Audio.play(&"button_tap"); shop_pressed.emit())
	row1.add_child(shop_btn)
	var gear := _icon_button(&"gear", 68)
	gear.pressed.connect(func(): Audio.play(&"button_tap"); _show_settings(true))
	row1.add_child(gear)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	col.add_child(row2)
	var moves_box := VBoxContainer.new()
	moves_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var moves_cap := VisualTheme.label("MOVES", VisualTheme.FS_CAPTION, VisualTheme.TEXT_DIM, 0)
	moves_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_box.add_child(moves_cap)
	_moves_value = UiKit.GlyphNum.new()
	_moves_value.digit_h = 48.0
	moves_box.add_child(_moves_value)
	_moves_pill = _pill(moves_box, 120)
	row2.add_child(_moves_pill)
	var tgt_box := VBoxContainer.new()
	tgt_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tgt_cap := VisualTheme.label("GOAL", VisualTheme.FS_CAPTION, VisualTheme.TEXT_DIM, 0)
	tgt_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tgt_box.add_child(tgt_cap)
	_objective_row = HBoxContainer.new()
	_objective_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_objective_row.add_theme_constant_override("separation", 12)
	tgt_box.add_child(_objective_row)
	var tgt_pill := _pill(tgt_box)
	tgt_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(tgt_pill)
	var coin_box := HBoxContainer.new()
	coin_box.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_box.add_theme_constant_override("separation", 8)
	var coin_icon := GemIcon.new()
	coin_icon.kind = &"coin"
	coin_icon.custom_minimum_size = Vector2(32, 32)
	coin_box.add_child(coin_icon)
	_coins_label = VisualTheme.label("0", VisualTheme.FS_LABEL, VisualTheme.TEXT_GOLD)
	coin_box.add_child(_coins_label)
	row2.add_child(_pill(coin_box, 104))

# ------------------------------------------------------------ fever --

func _build_fever_meter() -> void:
	_fever_wrap = Control.new()
	_fever_wrap.custom_minimum_size = Vector2(0, 66)
	_fever_wrap.clip_contents = false
	_top_col.add_child(_fever_wrap)

	# 2026-09-07: the supplied FEVER bar art (tbn_fever_bar + tbn_fever_crown)
	# with a gold fill clipped to `ratio`. Same `ratio`/`active`/`flash`/
	# `mult_text` surface as the old procedural FeverArt, so set_fever() /
	# flash_fever() are untouched. Falls back to the legacy FeverArt.
	if AssetLibrary.ui_texture(&"tbn_fever_bar") != null:
		_fever_bar = UiKit.FeverBarArt.new()
	else:
		_fever_bar = FeverArt.new()
	_fever_bar.mult_text = "x%.1f" % GameData.fever_config.score_multiplier
	_fever_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fever_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fever_wrap.add_child(_fever_bar)

	# "FEVER" caption — the supplied bar art has it baked in, so this live
	# label is kept only so set_fever()'s _fever_label writes stay valid; it
	# is shown only under the legacy FeverArt path.
	_fever_label = VisualTheme.label("FEVER", VisualTheme.FS_CAPTION, VisualTheme.TEXT_GOLD, 4)
	_fever_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_fever_label.offset_left = 46
	_fever_label.offset_top = 1
	_fever_label.offset_bottom = 21
	_fever_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fever_label.visible = _fever_bar is FeverArt
	_fever_wrap.add_child(_fever_label)

	# --- combat: Jamie power meters. The boss HP bar node is kept in the
	# tree for API compat but is NEVER shown (2026-09-07: minor-villain
	# health bar removed — finale stages are won by objectives). ---
	var pm_gap := Control.new()
	pm_gap.custom_minimum_size = Vector2(0, 6)
	pm_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_col.add_child(pm_gap)
	_power_meters = PowerMeters.new()
	_power_meters.custom_minimum_size = Vector2(0, 46)
	_top_col.add_child(_power_meters)
	_boss_bar = BossBar.new()
	_boss_bar.visible = false
	_top_col.add_child(_boss_bar)

# ------------------------------------------------------------ combat --

## 2026-09-07: no-op. The minor-villain health bar was removed from the
## gameplay design; a chapter finale is won by completing its objectives.
func begin_boss(_boss_name: String, _face: Texture2D, _is_final: bool) -> void:
	_boss_bar.visible = false

func end_boss() -> void:
	_boss_bar.visible = false

## No-op — kept so any older caller still links.
func set_boss_hp(_hp: int, _hp_max: int) -> void:
	pass

func boss_defeat_anim() -> void:
	_boss_bar.play_defeat()

func boss_hit(kind: StringName) -> void:
	_boss_bar.play_hit(kind)

func boss_taunt() -> void:
	_boss_bar.play_taunt()

func set_power_meters(meters: Dictionary) -> void:
	_power_meters.set_meters(meters)

func flash_power(power: StringName) -> void:
	_power_meters.flash_power(power)

func _bar_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(13)
	return sb

# ---------------------------------------------------------- boosters --

func _build_booster_bar() -> void:
	# Anchored directly (not via a MarginContainer) so it has a real rect on
	# a Control that's parented to a CanvasLayer.
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = -TRAY_COL_HEIGHT
	col.offset_bottom = -int(maxf(_safe_bottom, MIN_BOTTOM_CLEARANCE) + 12.0)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 6)
	_bottom_col = col
	add_child(col)

	_hint_label = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT_GOLD, 5)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(0, 38)
	col.add_child(_hint_label)

	var tray := PanelContainer.new()
	var tray_sb := UiKit.glass(30, true)
	tray_sb.bg_color = Color(0.08, 0.10, 0.19, 0.72)
	tray_sb.content_margin_left = 14
	tray_sb.content_margin_right = 14
	tray_sb.content_margin_top = 14
	tray_sb.content_margin_bottom = 16
	tray_sb.shadow_size = 22
	tray.add_theme_stylebox_override("panel", tray_sb)
	col.add_child(tray)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	tray.add_child(row)

	for id in _BOOSTER_ORDER:
		var tint: Color = _BOOSTER_TINT[id]
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(150, 214)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.pivot_offset = slot.custom_minimum_size * 0.5

		var chip := BoosterChip.new()
		chip.tint = tint
		chip.booster_id = id
		var bdef: Dictionary = GameData.boosters.get(id, {})
		chip.title = String(bdef.get("label", String(id))).to_upper()
		chip.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(chip)

		var btn := Button.new()
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(s, empty)
		btn.pressed.connect(func():
			Audio.play(&"button_tap")
			booster_pressed.emit(id)
		)
		slot.add_child(btn)

		var badge := VisualTheme.label("0", VisualTheme.FS_LABEL, VisualTheme.TEXT, 4)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -46
		badge.offset_right = -2
		badge.offset_top = -8
		badge.custom_minimum_size = Vector2(44, 44)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_stylebox_override("normal", VisualTheme.panel(Color(0.04, 0.05, 0.10, 0.98), 22, VisualTheme.PANEL_BORDER_BRIGHT, 2))
		slot.add_child(badge)

		row.add_child(slot)
		_booster_buttons[id] = btn
		_booster_badges[id] = badge
		_booster_slots[id] = slot
		_booster_counts[id] = 0

## Called by the controller so the tray can show which booster is armed
## and prompt the player. Pass &"" to clear.
func set_booster_armed(id: StringName) -> void:
	_armed_booster = id
	for bid in _booster_slots.keys():
		var slot: Control = _booster_slots[bid]
		var chip = slot.get_child(0)
		chip.armed = (bid == id)
		chip.queue_redraw()
		var t := slot.create_tween()
		t.tween_property(slot, "scale", Vector2(1.12, 1.12) if bid == id else Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)
	if id == &"":
		_hint_label.text = ""
	else:
		var def: Dictionary = GameData.boosters.get(id, {})
		_hint_label.text = "Tap the board — %s" % String(def.get("help", "")).to_lower()
		_pulse(_hint_label, 1.06)

func flash_booster(id: StringName) -> void:
	if not _booster_slots.has(id):
		return
	var slot: Control = _booster_slots[id]
	var t := slot.create_tween()
	t.tween_property(slot, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_BACK)
	t.tween_property(slot, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC)

# --------------------------------------------------------- overlays --

func _build_end_panel() -> void:
	_end_center = CenterContainer.new()
	_end_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_center.visible = false
	add_child(_end_center)

	# Gold-framed chrome (2026-09-05 UI pass) — same dialog family as
	# Settings/Inventory/BoosterShop/DailyRewards, replacing a hand-rolled
	# glass stylebox that was the odd one out.
	_end_panel = UiKit.GoldFramePanel.new(20)
	_end_panel.custom_minimum_size = Vector2(560, 460)
	_end_center.add_child(_end_panel)

	_end_confetti = CPUParticles2D.new()
	_end_confetti.emitting = false
	_end_confetti.one_shot = true
	_end_confetti.amount = 70
	_end_confetti.lifetime = 1.6
	_end_confetti.explosiveness = 0.85
	_end_confetti.direction = Vector2.DOWN
	_end_confetti.spread = 180.0
	_end_confetti.gravity = Vector2(0, 420)
	_end_confetti.initial_velocity_min = 220.0
	_end_confetti.initial_velocity_max = 460.0
	_end_confetti.scale_amount_min = 3.0
	_end_confetti.scale_amount_max = 6.0
	_end_confetti.angular_velocity_min = -720.0
	_end_confetti.angular_velocity_max = 720.0
	_end_confetti.position = Vector2(220, 30)
	_end_panel.content().add_child(_end_confetti)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_end_panel.content().add_child(vbox)

	_end_crown = TextureRect.new()
	_end_crown.texture = AssetLibrary.tex(&"cel_victory_crown")
	_end_crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_end_crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_end_crown.custom_minimum_size = Vector2(0, 130)
	_end_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_crown.visible = _end_crown.texture != null
	vbox.add_child(_end_crown)

	_end_title = VisualTheme.label("LEVEL COMPLETE!", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_title)

	_end_stars = StarRow.new()
	_end_stars.custom_minimum_size = Vector2(240, 72)
	vbox.add_child(_end_stars)

	_end_body = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT)
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_body)

	_end_button = _cta_button("CONTINUE", &"primary")
	_end_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_end_button)

	# Optional rewarded "double your coins" on the WIN panel — only shown
	# when an ad backend is available. Grant happens in app.gd on the ad's
	# earned callback; declining/failure keeps the base reward.
	_end_double_button = _cta_button("▶  DOUBLE COINS", &"secondary")
	_end_double_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_double_button.visible = false
	_end_double_button.pressed.connect(func():
		Audio.play(&"button_tap")
		_end_double_button.disabled = true
		_end_double_button.modulate.a = 0.5
		double_coins_requested.emit()
	)
	vbox.add_child(_end_double_button)

	_end_map_button = _cta_button("LEVEL MAP", &"tertiary")
	_end_map_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_map_button.pressed.connect(func():
		Audio.play(&"button_tap")
		map_pressed.emit()
	)
	vbox.add_child(_end_map_button)

## Thin wrapper over the shared UiKit.button() (2026-09-05 UI pass) — this
## used to be a bespoke hand-rolled stylebox parallel to UiKit's, now it's
## the same button family as every other screen, just at the HUD's own CTA
## size.
func _cta_button(text: String, kind: StringName) -> Button:
	var b := UiKit.button(text, kind, VisualTheme.FS_BUTTON)
	b.custom_minimum_size = Vector2(300, 74)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

## The in-level Settings dialog is now the shared SettingsPanel (built in
## _ready), so the menu and the HUD show one design.
func _show_settings(v: bool) -> void:
	if v:
		_settings_dialog.open()
	else:
		_settings_dialog.close()

func _refresh_scrim() -> void:
	_scrim.visible = _end_center.visible or _pause_center.visible

func _build_pause_panel() -> void:
	_pause_center = CenterContainer.new()
	_pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_center.visible = false
	_pause_center.z_index = 190
	add_child(_pause_center)

	_pause_panel = UiKit.GoldFramePanel.new(18)
	_pause_panel.custom_minimum_size = Vector2(480, 470)
	_pause_center.add_child(_pause_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_pause_panel.content().add_child(vbox)

	var title := VisualTheme.label("PAUSED", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var resume := _cta_button("Resume", &"primary")
	resume.pressed.connect(func():
		Audio.play(&"button_tap")
		show_pause_panel(false)
		resume_pressed.emit()
	)
	vbox.add_child(resume)

	var restart := _cta_button("Restart", &"danger")
	restart.pressed.connect(func():
		Audio.play(&"button_tap")
		show_pause_panel(false)
		retry_pressed.emit()
	)
	vbox.add_child(restart)

	var settings := _cta_button("Settings", &"tertiary")
	settings.pressed.connect(func():
		Audio.play(&"button_tap")
		_show_settings(true)
	)
	vbox.add_child(settings)

	var to_map := _cta_button("Quit to Map", &"secondary")
	to_map.pressed.connect(func():
		Audio.play(&"button_tap")
		show_pause_panel(false)
		map_pressed.emit()
	)
	vbox.add_child(to_map)

func show_pause_panel(v: bool) -> void:
	if v:
		_pause_center.visible = true
		_refresh_scrim()
		UiKit.pop_in(_pause_panel)
	else:
		var t := UiKit.pop_out(_pause_panel)
		await t.finished
		_pause_center.visible = false
		_refresh_scrim()

# ----------------------------------------------- in-level shop / continue --

func open_shop(focus_id: StringName = &"") -> void:
	_booster_shop.open(focus_id)

func close_shop() -> void:
	if _booster_shop.is_open():
		_booster_shop.close()

func open_moves_prompt() -> void:
	_moves_prompt.open()

## True while any blocking overlay is up (end panel, pause, settings, shop,
## or the continue prompt) — app.gd uses this to gate the shop button.
func any_modal_open() -> bool:
	return _end_center.visible or _pause_center.visible \
		or (_settings_dialog != null and _settings_dialog.visible) \
		or (_booster_shop != null and _booster_shop.is_open()) \
		or (_moves_prompt != null and _moves_prompt.is_open())

# ----------------------------------------------------------- updates --

func set_level_info(level: LevelConfig) -> void:
	_level_label.text = level.level_name.to_upper()
	_star_scores = level.star_scores if level != null else []
	set_booster_armed(&"")
	_prev_obj_complete = []  # fresh level: no "objective complete" toasts from stale state
	_update_score_stars(_shown_score)

## Override the LEVEL badge to show the ISLAND-local level number (call after
## set_level_info). The badge itself renders only the digits.
func set_level_number(n: int) -> void:
	_level_label.text = "LEVEL %d" % n

var _shown_score := 0
func set_score(v: int) -> void:
	if v == _shown_score:
		_score_label.text = _fmt(v)
		_update_score_stars(v)
		return
	var from := _shown_score
	_shown_score = v
	var t := create_tween()
	t.tween_method(func(x: float): _score_label.text = _fmt(int(round(x))), float(from), float(v), 0.35)
	_update_score_stars(v)

## Live-light the SCORE crest's 3 stars from the running score against the
## level's star_scores thresholds (purely reflective — the authoritative
## star award still happens at level end in StarRating).
func _update_score_stars(score: int) -> void:
	if _tb_stars.is_empty():
		return
	for i in _tb_stars.size():
		var earned := i < _star_scores.size() and score >= int(_star_scores[i])
		(_tb_stars[i] as TextureRect).modulate = Color(1, 1, 1, 1) if earned else Color(1, 1, 1, 0.28)

func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

func set_moves(remaining: int) -> void:
	var r := maxi(remaining, 0)
	_moves_value.text = str(r)
	_moves_value.warn = r <= 3
	_pulse(_moves_pill)

func set_coins(amount: int) -> void:
	if amount == _displayed_coins:
		_coins_label.text = str(amount)
		return
	var from := _displayed_coins
	_displayed_coins = amount
	var t := create_tween()
	t.tween_method(func(v: float): _coins_label.text = str(int(round(v))), float(from), float(amount), 0.4)

func set_objectives(tracker: ObjectiveTracker, level: LevelConfig) -> void:
	var is_new_level := _prev_obj_complete.size() != level.objectives.size()
	var new_complete: Array = []
	for c in _objective_chips:
		c.queue_free()
	_objective_chips.clear()
	for i in level.objectives.size():
		var obj: Dictionary = level.objectives[i]
		var done: int = tracker.progress[i]
		var tgt: int = maxi(tracker.target_for(i), 1)
		var complete := done >= tgt
		new_complete.append(complete)
		if complete and not is_new_level and not bool(_prev_obj_complete[i]):
			UiKit.show_toast(self, "OBJECTIVE COMPLETE", VisualTheme.GOOD)

		# One objective chip: a compact horizontal blue pill (icon + count).
		# Kept small on purpose so multiple chips always fit INSIDE the supplied
		# GOAL panel art (_layout_topbar then scales the whole row to guarantee
		# containment). No per-goal progress bar, matching the reference.
		var card := PanelContainer.new()
		# keep each chip at its natural size and centred in the row — the row
		# fills a fixed rect, so FILL flags here would stretch chips wide.
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.03, 0.09, 0.30, 0.62)
		csb.set_corner_radius_all(12)
		csb.border_color = VisualTheme.GOOD if complete else Color(0.42, 0.60, 0.98, 0.7)
		csb.set_border_width_all(2)
		csb.content_margin_left = 9
		csb.content_margin_right = 10
		csb.content_margin_top = 5
		csb.content_margin_bottom = 5
		csb.shadow_size = 0
		card.add_theme_stylebox_override("panel", csb)

		var rowb := HBoxContainer.new()
		rowb.alignment = BoxContainer.ALIGNMENT_CENTER
		rowb.add_theme_constant_override("separation", 6)
		card.add_child(rowb)
		var icon := GemIcon.new()
		icon.custom_minimum_size = Vector2(30, 30)
		_style_obj_icon(icon, obj)
		rowb.add_child(icon)
		var txt := VisualTheme.label("%d/%d" % [mini(done, tgt), tgt], VisualTheme.FS_BODY,
			VisualTheme.GOOD if complete else Color(0.97, 0.98, 1.0))
		rowb.add_child(txt)

		_objective_row.add_child(card)
		_objective_chips.append(card)
	_prev_obj_complete = new_complete
	# re-fit the objective row into the GOAL panel art once the HBox has
	# sized itself to the new chips.
	if _tb_goal_zone != null:
		_layout_topbar.call_deferred()

func _obj_bar_color(obj: Dictionary) -> Color:
	match String(obj.get("type", "")):
		"clear_color":
			return _color_for(String(obj.get("color", "red"))).lightened(0.1)
		"reach_score":
			return VisualTheme.STAR
		"create_powers":
			return Color(1.0, 0.7, 0.3)
		"break_obstacles":
			return Color(0.7, 0.75, 0.82)
		"deliver":
			return Color(1.0, 0.55, 0.75)
		_:
			return VisualTheme.ACCENT

func _style_obj_icon(icon: GemIcon, obj: Dictionary) -> void:
	match String(obj.get("type", "")):
		"clear_color":
			icon.kind = &"gem"
			icon.tint = _color_for(String(obj.get("color", "red")))
		"reach_score":
			icon.kind = &"score"
		"create_powers":
			icon.kind = &"power"
		"break_obstacles":
			icon.kind = &"obstacle"
		"deliver":
			icon.kind = &"crystal"
			icon.tint = Color(1.0, 0.6, 0.78)
		_:
			icon.kind = &"gem"

func _color_for(id: String) -> Color:
	if GameData.colors != null and GameData.colors.has(StringName(id)):
		return GameData.colors.get_def(StringName(id)).base_color
	return Color(0.9, 0.3, 0.4)

func set_fever(meter: float, meter_max: float, active: bool) -> void:
	var target: float = 1.0 if active else clampf(meter / maxf(meter_max, 1.0), 0.0, 1.0)
	var t := create_tween()
	t.tween_property(_fever_bar, "ratio", target, 0.3).set_trans(Tween.TRANS_CUBIC)
	_fever_bar.active = active
	_fever_label.text = "FEVER!" if active else "FEVER"
	_fever_label.add_theme_color_override("font_color", Color(1, 1, 1) if active else VisualTheme.TEXT_DIM)
	if active != _fever_running:
		_fever_running = active
		if _fever_pulse != null and _fever_pulse.is_valid():
			_fever_pulse.kill()
		if active:
			_fever_bar.ratio = 1.0
			_fever_wrap.pivot_offset = _fever_wrap.size * 0.5
			_fever_pulse = create_tween().set_loops()
			_fever_pulse.tween_property(_fever_wrap, "scale", Vector2(1.04, 1.12), 0.34).set_trans(Tween.TRANS_SINE)
			_fever_pulse.tween_property(_fever_wrap, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_SINE)
		else:
			_fever_wrap.scale = Vector2.ONE
	elif active:
		_fever_bar.ratio = 1.0

## A one-off wallop the instant Fever ignites: the meter flares white and
## the whole strip kicks.
func flash_fever() -> void:
	_fever_wrap.pivot_offset = _fever_wrap.size * 0.5
	_fever_bar.flash = 1.0
	var t := create_tween()
	t.tween_property(_fever_wrap, "scale", Vector2(1.25, 1.4), 0.12).set_trans(Tween.TRANS_BACK)
	t.tween_property(_fever_wrap, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC)
	t.parallel().tween_property(_fever_bar, "flash", 0.0, 0.5)

func set_booster_counts(counts: Dictionary) -> void:
	for id in _booster_badges.keys():
		var n := int(counts.get(id, 0))
		var prev := int(_booster_counts.get(id, 0))
		_booster_counts[id] = n
		_booster_badges[id].text = str(n)
		var slot: Control = _booster_slots[id]
		slot.modulate.a = 1.0 if n > 0 else 0.42
		var chip = slot.get_child(0)
		chip.enabled = n > 0
		chip.queue_redraw()
		if n > prev:
			flash_booster(id)

var _win_reward_coins := 0

func show_win_panel(score: int, reward_coins: int, has_next_level: bool, stars: int) -> void:
	_win_reward_coins = reward_coins
	_end_title.text = "LEVEL COMPLETE!"
	_end_body.text = "Score  %s\n+%d coins" % [_fmt(score), reward_coins]
	_end_button.text = "NEXT LEVEL" if has_next_level else "BACK TO MAP"
	_end_map_button.visible = true
	if _end_double_button != null:
		_end_double_button.visible = Ads.available and Ads.double_win_coins_enabled() and reward_coins > 0
		_end_double_button.disabled = false
		_end_double_button.modulate.a = 1.0
		_end_double_button.text = "▶  DOUBLE COINS  (+%d)" % reward_coins
	if _end_crown != null:
		_end_crown.visible = _end_crown.texture != null
	_rewire(_end_button, func(): next_level_pressed.emit())
	_end_center.visible = true
	_refresh_scrim()
	UiKit.pop_in(_end_panel)
	_end_stars.play(stars)
	_end_confetti.restart()
	_end_confetti.emitting = true
	# prepared celebration bursts over the panel
	if _fx != null:
		var cc := size * Vector2(0.5, 0.42)
		_fx.play_hold(&"cel_firework_burst", cc, size.x * 0.8, Color(1, 1, 1), 0.8, true, 0.3)
		_fx.play(&"cel_confetti_pieces", cc, size.x * 0.95, Color(1, 1, 1), 1.1, false, 0.4, 2.4)
		if stars >= 3:
			_fx.play(&"cel_star_burst", cc, size.x * 0.7, Color(1, 1, 1), 0.7, true, 0.6)

## Called by app.gd after a rewarded "double coins" ad is EARNED — reflects
## the extra grant on the panel. Idempotent-safe: the button is already
## disabled by its own press handler.
func mark_win_coins_doubled() -> void:
	if _end_double_button != null:
		_end_double_button.text = "COINS DOUBLED  ✓"
		_end_double_button.disabled = true
		_end_double_button.modulate.a = 0.6
	_end_body.text = _end_body.text.replace(
		"+%d coins" % _win_reward_coins, "+%d coins  (x2!)" % (_win_reward_coins * 2))

func show_lose_panel(score: int) -> void:
	_end_title.text = "SO CLOSE!"
	_end_body.text = "Score  %s\nTry again — you've got this!" % _fmt(score)
	_end_button.text = "TRY AGAIN"
	_end_map_button.visible = true
	if _end_double_button != null:
		_end_double_button.visible = false
	_rewire(_end_button, func(): retry_pressed.emit())
	_end_center.visible = true
	_refresh_scrim()
	UiKit.pop_in(_end_panel)
	_end_stars.play(0)

func hide_end_panel() -> void:
	if not _end_center.visible:
		return
	var t := UiKit.pop_out(_end_panel)
	await t.finished
	_end_center.visible = false
	_refresh_scrim()

func _rewire(btn: Button, fn: Callable) -> void:
	for c in btn.pressed.get_connections():
		btn.pressed.disconnect(c["callable"])
	btn.pressed.connect(func():
		Audio.play(&"button_tap")
		fn.call()
	)

# ------------------------------------------------------------ anims --

func _pulse(node: Control, amount: float = 1.08) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2(amount, amount), 0.09).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)


## One booster tray chip: glossy rounded face in its tint, a code-drawn
## IconDraw glyph, a name plate, an armed glow-pulse, and a lock overlay
## when empty.
class BoosterChip extends Control:
	var tint: Color = Color(0.5, 0.5, 0.5)
	var booster_id: StringName = &"bomb"
	var title: String = ""
	var armed := false
	var enabled := true
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if armed:
			queue_redraw()

	## Power boosters sit in the sci-fi "power energy" capsule (#51); the
	## utility ones (shuffle / +moves) in the general booster container (#50).
	const _POWER_IDS := [&"bomb", &"lightning", &"freeze", &"rainbow", &"chain"]

	func _draw() -> void:
		var rr := 22.0
		var rect := Rect2(Vector2(4, 4), size - Vector2(8, 8))

		var frame_id := &"ui_power_energy_container" if booster_id in _POWER_IDS else &"ui_booster_container"
		var frame := AssetLibrary.tex(frame_id)

		if armed:
			var p := 0.5 + 0.5 * sin(_t * 8.0)
			for k in 3:
				_round(rect.grow(3.0 + 5.0 * p + k * 5.0), rr + 6,
					Color(tint.r, tint.g, tint.b, (0.34 - k * 0.09) * (0.5 + 0.5 * p)))

		if frame != null:
			# capsule art fills the chip (aspect kept), plus a per-power tinted
			# wash so each slot still reads at a glance. "changing energy level":
			# the capsule brightens when the booster is armed, dims when empty.
			var fw: float = float(frame.get_width())
			var fh: float = float(frame.get_height())
			var scale_k: float = maxf(rect.size.x / fw, rect.size.y / fh)
			var dw := fw * scale_k
			var dh := fh * scale_k
			var fr := Rect2(rect.position + (rect.size - Vector2(dw, dh)) * 0.5, Vector2(dw, dh))
			var lvl := 1.0 if armed else (0.9 if enabled else 0.5)
			draw_texture_rect(frame, fr, false, Color(lvl, lvl, lvl, 1.0))
			if enabled:
				_round(rect.grow(-6.0), rr - 4, Color(tint.r, tint.g, tint.b, 0.16 + (0.18 if armed else 0.0)))
			if armed:
				_round_outline(rect, rr, Color(1, 1, 1, 0.85), 3.0)
		else:
			# drop shadow + tinted body fallback (no container art)
			_round(Rect2(rect.position + Vector2(0, 6), rect.size), rr, Color(0, 0, 0, 0.35))
			_round(rect, rr, tint.darkened(0.34))
			_round(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.52)), rr, tint.lightened(0.10))
			_round(rect.grow(-3.0), rr - 3, tint.darkened(0.10))
			if armed:
				_round_outline(rect, rr, Color(1, 1, 1, 0.85), 3.0)
			draw_line(rect.position + Vector2(14, 6), rect.position + Vector2(rect.size.x - 14, 6),
				Color(1, 1, 1, 0.30), 3.0, true)

		# the booster's own object: prepared power art (#7-11) for the power
		# boosters, vector glyph for shuffle / +moves.
		var icon_c := Vector2(size.x * 0.5, size.y * 0.44)
		var pow_tex := AssetLibrary.power(booster_id)
		if pow_tex != null:
			var s := minf(size.x, size.y) * 0.66
			var m: float = maxf(float(pow_tex.get_width()), float(pow_tex.get_height()))
			var w := s * pow_tex.get_width() / m
			var h := s * pow_tex.get_height() / m
			draw_texture_rect(pow_tex, Rect2(icon_c - Vector2(w, h) * 0.5, Vector2(w, h)), false)
		else:
			IconDraw.draw_icon(self, booster_id, icon_c, minf(size.x, size.y) * 0.6, _t)

		# name plate — a darkened strip along the bottom so the label always
		# reads over the tinted face, clear of the chip's lower edge.
		if title != "":
			var strip_h := clampf(size.y * 0.22, 24.0, 40.0)
			_round(Rect2(rect.position + Vector2(6, rect.size.y - strip_h - 4), Vector2(rect.size.x - 12, strip_h)),
				10.0, Color(0, 0, 0, 0.36))
			var font := ThemeDB.fallback_font
			var fs := VisualTheme.FS_MICRO
			var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			var tp := Vector2(size.x * 0.5 - tw * 0.5, rect.position.y + rect.size.y - strip_h * 0.5 - 4.0 + fs * 0.34)
			draw_string_outline(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
			draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.96))

		if not enabled:
			# Owning zero of this booster is no longer a dead end (tapping it
			# opens the shop straight to its buy dialog — see
			# app.gd::_on_booster_pressed) — a gold "+" reads as "tap to buy"
			# instead of a padlock's "this is off-limits".
			_round(rect, rr, Color(0.03, 0.04, 0.08, 0.5))
			var lc := Vector2(size.x * 0.5, size.y * 0.42)
			var pr: float = size.x * 0.15
			draw_circle(lc, pr, Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.85))
			draw_arc(lc, pr, 0, TAU, 20, Color(1, 1, 1, 0.9), 2.0, true)
			draw_line(lc + Vector2(-pr * 0.5, 0), lc + Vector2(pr * 0.5, 0), Color(0.16, 0.1, 0.02), 4.0, true)
			draw_line(lc + Vector2(0, -pr * 0.5), lc + Vector2(0, pr * 0.5), Color(0.16, 0.1, 0.02), 4.0, true)

	func _round(r: Rect2, radius: float, col: Color) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, radius, 5)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.position + r.size * 0.5)
		draw_colored_polygon(moved, col)

	func _round_outline(r: Rect2, radius: float, col: Color, w: float) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, radius, 6)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.position + r.size * 0.5)
		moved.append(moved[0])
		draw_polyline(moved, col, w, true)


## Code-drawn chrome glyph (pause / gear) — avoids missing font glyphs.
class MiniIcon extends Control:
	var kind: StringName = &"pause"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.26
		if kind == &"gear":
			var tex := AssetLibrary.tex(&"ui_setting_gear")
			if tex != null:
				var s := minf(size.x, size.y) * 0.92
				var m: float = maxf(float(tex.get_width()), float(tex.get_height()))
				var w := s * tex.get_width() / m
				var h := s * tex.get_height() / m
				draw_texture_rect(tex, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false)
				return
		match kind:
			&"pause":
				var w := r * 0.5
				draw_rect(Rect2(c + Vector2(-r, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
				draw_rect(Rect2(c + Vector2(r - w, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
			&"gear":
				draw_arc(c, r, 0, TAU, 24, VisualTheme.TEXT, maxf(r * 0.42, 2.0), true)
				for i in 8:
					var a := TAU * float(i) / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * r * 0.9,
						c + Vector2(cos(a), sin(a)) * r * 1.5, VisualTheme.TEXT, maxf(r * 0.3, 2.0), true)
				draw_circle(c, r * 0.4, VisualTheme.PANEL_RAISED)
			_:
				draw_circle(c, r, VisualTheme.TEXT)


## Small code-drawn gem / icon used in the coin pill and objective chips.
class GemIcon extends Control:
	var kind: StringName = &"gem" # gem | coin | score | power | obstacle
	var tint: Color = Color(0.9, 0.3, 0.4)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Logical icon -> prepared UI/economy sprite. Falls back to the vector draw.
	## `gem` stays the code-drawn TINTED hex (used by colour-clear objective
	## chips, which must show the target colour). `crystal` is the currency icon.
	const _SPRITE := {
		&"coin": &"ui_coin_icon", &"score": &"eco_star", &"crystal": &"eco_reward_crystal",
		&"trophy": &"eco_trophy", &"star": &"eco_star",
	}

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		if _SPRITE.has(kind):
			var tex := AssetLibrary.tex(_SPRITE[kind])
			if tex != null:
				var s := minf(size.x, size.y)
				var m: float = maxf(float(tex.get_width()), float(tex.get_height()))
				var w := s * tex.get_width() / m
				var h := s * tex.get_height() / m
				draw_texture_rect(tex, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false)
				return
		match kind:
			&"coin":
				draw_circle(c, r, VisualTheme.COIN)
				draw_circle(c, r * 0.72, VisualTheme.COIN.lightened(0.25))
				draw_arc(c, r, 0, TAU, 20, VisualTheme.COIN.darkened(0.3), 2.0, true)
			&"score":
				draw_colored_polygon(ShapeDrawUtils.star_points(c, r), VisualTheme.STAR)
			&"power":
				var hex := ShapeDrawUtils.regular_polygon(6, r, PI / 6.0, c)
				draw_colored_polygon(hex, Color(1, 0.85, 0.3))
				draw_line(c + Vector2(-r * 0.2, -r * 0.5), c + Vector2(r * 0.1, r * 0.05), Color(0.1, 0.1, 0.12), 3.0)
				draw_line(c + Vector2(r * 0.1, r * 0.05), c + Vector2(-r * 0.1, r * 0.5), Color(0.1, 0.1, 0.12), 3.0)
			&"obstacle":
				draw_colored_polygon(ShapeDrawUtils.regular_polygon(6, r, PI / 6.0, c), Color(0.5, 0.55, 0.62))
				draw_arc(c, r * 0.9, 0, TAU, 18, Color(0.2, 0.22, 0.26), 2.0, true)
			_:
				var g := ShapeDrawUtils.regular_polygon(6, r, PI / 6.0, c)
				draw_polygon(g, ShapeDrawUtils.vertical_shade(g, tint.lightened(0.3), tint.darkened(0.35)))
				draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.22, Color(1, 1, 1, 0.6))


## Three stars that pop in one-by-one on a win.
class StarRow extends Control:
	var _earned := 0
	var _shown := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func play(earned: int) -> void:
		_earned = earned
		_shown = 0.0
		set_process(true)
		var t := create_tween()
		t.tween_method(func(v: float): _shown = v; queue_redraw(), 0.0, 3.0, 0.9)
		t.tween_callback(func(): set_process(false))

	func _draw() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		var spacing := 78.0
		var tex := AssetLibrary.tex(&"eco_star")
		for i in 3:
			var center := Vector2(cx + float(i - 1) * spacing, cy)
			var filled := float(i) < _shown and i < _earned
			var grow: float = clampf(_shown - float(i), 0.0, 1.0)
			var r := 26.0 * (0.4 + 0.6 * grow) if float(i) < _shown else 22.0
			if not (float(i) < _shown):
				grow = 1.0
				r = 22.0
			if tex != null:
				var d := r * 2.4
				var col := Color(1, 1, 1) if filled else Color(0.3, 0.32, 0.4, 0.85)
				draw_texture_rect(tex, Rect2(center - Vector2(d, d) * 0.5, Vector2(d, d)), false, col)
				continue
			draw_colored_polygon(ShapeDrawUtils.star_points(center, r + 3.0), Color(0, 0, 0, 0.35))
			var pcol := VisualTheme.STAR if filled else Color(0.24, 0.25, 0.32)
			draw_colored_polygon(ShapeDrawUtils.star_points(center, r), pcol)
			if filled:
				draw_colored_polygon(ShapeDrawUtils.star_points(center, r * 0.5), VisualTheme.STAR.lightened(0.4))


## The full golden Fever bar (reference §13): an ornate gold double frame
## with a crown emblem on the left, a golden energy fill with premium glow
## and a moving sheen, the Fever Crystal (#52) riding the fill edge, and the
## x1.5 reward in a gold badge on the right. Fully code-drawn so it stays one
## node and one draw pass — cheap on gl_compatibility.
class FeverArt extends Control:
	var ratio := 0.0: set = _set_ratio
	var active := false: set = _set_active
	var flash := 0.0: set = _set_flash
	var mult_text := "x1.5"
	var _t := 0.0

	func _set_ratio(v: float) -> void: ratio = clampf(v, 0.0, 1.0); queue_redraw()
	func _set_active(v: bool) -> void: active = v; queue_redraw()
	func _set_flash(v: float) -> void: flash = v; queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if active or flash > 0.001 or ratio > 0.0:
			queue_redraw()

	func _draw() -> void:
		var h := size.y
		var w := size.x
		var badge_r := h * 0.36
		var crown_w := h * 0.82

		# --- track geometry: leave room for the crown (left) + badge (right) ---
		var track := Rect2(crown_w * 0.78, h * 0.30, w - crown_w * 0.78 - badge_r * 2.6 - 8.0, h * 0.44)
		var cr := track.size.y * 0.5

		var gold := UiKit.GOLD if not active else Color(1.0, 0.62, 0.2)
		var gold_deep := UiKit.GOLD_DEEP

		# outer glow when charged / active
		if ratio > 0.02 or active:
			var ga: float = (0.10 + 0.22 * ratio) * (1.4 if active else 1.0)
			_capsule(track.grow(9.0), cr + 9.0, Color(gold.r, gold.g, gold.b, ga))

		# dark well + gold double frame
		_capsule(track.grow(4.0), cr + 4.0, Color(gold_deep.r, gold_deep.g, gold_deep.b, 0.95))
		_capsule(track, cr, Color(0.05, 0.04, 0.02, 0.96))

		# golden energy fill
		var fill_w := track.size.x * ratio
		if fill_w > cr:
			var f := Rect2(track.position, Vector2(fill_w, track.size.y))
			var base := Color(1.0, 0.66, 0.12) if not active else Color(1.0, 0.44, 0.18)
			if flash > 0.0:
				base = base.lerp(Color(1, 1, 1), flash)
			_capsule(f, cr, base)
			# bright top third + a travelling sheen
			_capsule(Rect2(f.position + Vector2(0, 2), Vector2(f.size.x, f.size.y * 0.4)), cr, Color(1, 0.92, 0.6, 0.5))
			var sheen_x := track.position.x + fposmod(_t * 130.0, maxf(fill_w, 1.0))
			draw_line(Vector2(sheen_x, f.position.y + 2), Vector2(sheen_x, f.position.y + f.size.y - 2),
				Color(1, 1, 1, active and 0.5 or 0.3), 6.0)

		# gold frame lines (outer heavy + inner hairline)
		_capsule_outline(track, cr, Color(gold.r, gold.g, gold.b, 0.95), 3.0)
		_capsule_outline(track.grow(-3.0), cr - 3.0, Color(UiKit.GOLD_LITE.r, UiKit.GOLD_LITE.g, UiKit.GOLD_LITE.b, 0.55), 1.5)

		# --- crown emblem on the left ---
		var crown_c := Vector2(crown_w * 0.5, h * 0.52)
		var crown_tex := AssetLibrary.tex(&"ui_crown_trophy")
		if crown_tex != null:
			var cw := crown_w
			var ch := cw * float(crown_tex.get_height()) / float(crown_tex.get_width())
			draw_texture_rect(crown_tex, Rect2(crown_c - Vector2(cw, ch) * 0.5, Vector2(cw, ch)), false)
		else:
			var cw2 := crown_w * 0.5
			var pts := PackedVector2Array([
				crown_c + Vector2(-cw2, 8), crown_c + Vector2(-cw2, -4), crown_c + Vector2(-cw2 * 0.4, 4),
				crown_c + Vector2(0, -10), crown_c + Vector2(cw2 * 0.4, 4), crown_c + Vector2(cw2, -4), crown_c + Vector2(cw2, 8),
			])
			draw_colored_polygon(pts, gold)
			draw_polyline(pts, gold_deep, 1.5, true)

		# --- Fever Crystal (#52) on the fill edge ---
		var edge_x := track.position.x + clampf(fill_w, cr, track.size.x - cr)
		var cy := track.position.y + track.size.y * 0.5
		var crystal := AssetLibrary.tex(&"ui_fever_crystal")
		if crystal != null and ratio > 0.03:
			var cs := h * (0.92 if active else 0.7)
			if active:
				cs *= 1.0 + 0.08 * sin(_t * 8.0)
			var m: float = maxf(float(crystal.get_width()), float(crystal.get_height()))
			if active:
				VisualTheme.draw_glow(self, Vector2(edge_x, cy), cs, Color(1.0, 0.5, 0.2, 0.5), 4)
			draw_texture_rect(crystal, Rect2(Vector2(edge_x - cs * crystal.get_width() / m * 0.5,
				cy - cs * crystal.get_height() / m * 0.5),
				Vector2(cs * crystal.get_width() / m, cs * crystal.get_height() / m)), false)

		# --- x1.5 gold badge on the right ---
		var badge_c := Vector2(w - badge_r - 12.0, h * 0.52)
		var bpulse := (0.9 + 0.1 * sin(_t * 7.0)) if active else 1.0
		draw_circle(badge_c, badge_r + 3.0, Color(gold_deep.r, gold_deep.g, gold_deep.b, 0.95))
		draw_circle(badge_c, badge_r * bpulse, gold)
		draw_circle(badge_c, badge_r * 0.72 * bpulse, Color(1.0, 0.9, 0.55))
		var font := ThemeDB.fallback_font
		var bfs := int(badge_r * 0.9)
		var bs := font.get_string_size(mult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs)
		draw_string_outline(font, badge_c - bs * 0.5 + Vector2(0, bs.y * 0.32), mult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, 4, Color(0.3, 0.16, 0.0, 0.9))
		draw_string(font, badge_c - bs * 0.5 + Vector2(0, bs.y * 0.32), mult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, Color(0.28, 0.14, 0.0))

		if flash > 0.0:
			_capsule(track, cr, Color(1, 1, 1, 0.45 * flash))

	func _capsule_outline(r: Rect2, radius: float, col: Color, wd: float) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, minf(radius, r.size.y * 0.5), 6)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.position + r.size * 0.5)
		moved.append(moved[0])
		draw_polyline(moved, col, wd, true)

	func _capsule(r: Rect2, radius: float, col: Color) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, minf(radius, r.size.y * 0.5), 5)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.position + r.size * 0.5)
		draw_colored_polygon(moved, col)


## The "LEVEL n" tag: the prepared Level Badge (#56, crowned shield) drawn
## undistorted as an emblem, with the level text set across it. Plain gold
## label if the art is missing.
class LevelBadge extends Control:
	var text := "LEVEL 1": set = _set_text

	func _set_text(v: String) -> void:
		text = v
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		# 2026-09-07: prefer the supplied standalone Level Badge PNG.
		var tex := AssetLibrary.ui_texture(&"tbn_level")
		if tex == null:
			tex = AssetLibrary.tex(&"ui_level_badge")
		if tex == null:
			var fs0 := VisualTheme.FS_LABEL
			var ts0 := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs0)
			draw_string_outline(font, Vector2((size.x - ts0.x) * 0.5, size.y * 0.5 + fs0 * 0.34), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs0, 4, VisualTheme.OUTLINE)
			draw_string(font, Vector2((size.x - ts0.x) * 0.5, size.y * 0.5 + fs0 * 0.34), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs0, VisualTheme.TEXT_GOLD)
			return
		# badge fit to the row height (aspect kept), centred; crown / ribbons
		# overhang the row (clip_contents is off on the row) so the LEVEL badge
		# reads as large as MOVES / SCORE and interleaves with row 2.
		var bh := size.y * 2.15
		var bw := bh * float(tex.get_width()) / float(tex.get_height())
		var bx := (size.x - bw) * 0.5
		draw_texture_rect(tex, Rect2(Vector2(bx, (size.y - bh) * 0.5), Vector2(bw, bh)), false)
		# level number on the blue shield field, gold like the reference
		var digits := ""
		for ch in text:
			if ch >= "0" and ch <= "9":
				digits += ch
		var label := digits if digits != "" else text
		var fs := int(bh * 0.21)
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var pos := Vector2(size.x * 0.5 - ts.x * 0.5, size.y * 0.5 + bh * 0.16 + fs * 0.34)
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.20, 0.09, 0.0, 0.92))
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, VisualTheme.TEXT_GOLD)


## A crowned MOVES / SCORE badge rendered from the supplied standalone art
## (tbn_moves / tbn_score), undistorted (aspect-fit), with the live value
## drawn on the blue shield field via a UiKit.GlyphNum (the supplied gold
## digit glyphs). `HUD._layout_topbar()` positions `num` and the star row.
class StatBadge extends Control:
	var _tex_id: StringName
	var _bg: TextureRect
	var num: UiKit.GlyphNum
	var _aspect := 1.09

	func _init(tex_id: StringName) -> void:
		_tex_id = tex_id

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = false
		_bg = TextureRect.new()
		_bg.texture = AssetLibrary.ui_texture(_tex_id)
		_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg)
		if _bg.texture != null and _bg.texture.get_height() > 0:
			_aspect = float(_bg.texture.get_width()) / float(_bg.texture.get_height())
		num = UiKit.GlyphNum.new()
		add_child(num)

	func art_aspect() -> float:
		return _aspect
