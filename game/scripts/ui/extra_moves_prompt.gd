class_name ExtraMovesPrompt
extends Control
## The "NEED MORE MOVES?" continue modal, shown by app.gd when the player
## runs out of moves with the objective still incomplete. Buying adds moves
## straight to the RUNNING level — the board, objectives, enemy HP, boss HP
## and Jamie's power meters are all left exactly as they were (app.gd never
## re-runs `_start_level`). Declining falls through to the normal loss.
##
## Tiers + prices come from GameData.continue_offers (data/economy.json);
## coins are spent through the existing Economy / SaveService. No new state.
##
##   signals:
##     bought(moves_added: int) — coins already spent; add these moves + resume
##     gave_up()                — no purchase; proceed to the loss screen

signal bought(moves_added: int)
signal gave_up()

var _scrim: ColorRect
var _panel: UiKit.GoldFramePanel
var _tier_box: VBoxContainer
var _coins_label: Label
var _ad_btn: Button
var _ad_pending := false
var _is_open := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 205
	visible = false
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.62)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Gold-framed chrome (2026-09-05 UI pass) — same dialog family as every
	# other modal, replacing a hand-rolled stylebox that was the odd one out.
	_panel = UiKit.GoldFramePanel.new(22)
	_panel.custom_minimum_size = Vector2(520, 560)
	center.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.content().add_child(v)

	var title := VisualTheme.label("NEED MORE MOVES?", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var sub := VisualTheme.label("Keep this board — top up and play on.", VisualTheme.FS_BODY, VisualTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var coin_row := HBoxContainer.new()
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_theme_constant_override("separation", 8)
	v.add_child(coin_row)
	var ci := HUD.GemIcon.new()
	ci.kind = &"coin"
	ci.custom_minimum_size = Vector2(30, 30)
	coin_row.add_child(ci)
	_coins_label = VisualTheme.label("0", VisualTheme.FS_LABEL, VisualTheme.TEXT_GOLD)
	coin_row.add_child(_coins_label)

	_tier_box = VBoxContainer.new()
	_tier_box.add_theme_constant_override("separation", 10)
	v.add_child(_tier_box)

	# Rewarded-ad continue: only appears when an ad backend is actually
	# available. Grants the reward ONLY on the ad-completion callback; if the
	# ad is unavailable / fails / is dismissed early, nothing is granted and
	# the coin tiers above still work. See AdsService.
	_ad_btn = UiKit.button("", &"secondary", VisualTheme.FS_BODY)
	_ad_btn.custom_minimum_size = Vector2(420, 72)
	_ad_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ad_btn.visible = false
	_ad_btn.pressed.connect(_on_watch_ad)
	v.add_child(_ad_btn)

	var give_up := UiKit.button("GIVE UP", &"tertiary", VisualTheme.FS_MICRO)
	give_up.custom_minimum_size = Vector2(300, 60)
	give_up.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	give_up.pressed.connect(func(): Audio.play(&"button_tap"); _decline())
	v.add_child(give_up)

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	_rebuild()
	_scrim.modulate.a = 0.0
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 1.0, 0.16)
	UiKit.pop_in(_panel)

func _rebuild() -> void:
	_coins_label.text = str(Economy.coins)
	for c in _tier_box.get_children():
		c.queue_free()
	for t in GameData.continue_offers.tiers():
		_tier_box.add_child(_tier_button(t))
	_refresh_ad_button()

func _refresh_ad_button() -> void:
	if _ad_btn == null:
		return
	var has_ads: bool = Ads.available and not _ad_pending
	_ad_btn.visible = Ads.available
	_ad_btn.disabled = not has_ads
	_ad_btn.modulate.a = 1.0 if has_ads else 0.5
	_ad_btn.text = ("LOADING AD…" if _ad_pending
		else "▶  WATCH AD   +%d MOVES  (FREE)" % Ads.reward_continue_moves())

## Rewarded continue. The +moves are emitted ONLY when the ad's single
## terminal result says earned=true. `_ad_pending` blocks a second tap and
## a duplicate grant; any non-earned outcome just re-enables the button so
## the coin tiers above still work.
func _on_watch_ad() -> void:
	if _ad_pending or not Ads.available:
		return
	Audio.play(&"button_tap")
	_ad_pending = true
	_refresh_ad_button()
	if not Ads.rewarded_result.is_connected(_on_ad_result):
		Ads.rewarded_result.connect(_on_ad_result)
	Ads.show_rewarded("continue_moves")

func _on_ad_result(placement: String, earned: bool) -> void:
	if placement != "continue_moves" or not _ad_pending:
		return
	Ads.rewarded_result.disconnect(_on_ad_result)
	_ad_pending = false
	if earned:
		Audio.play(&"power_up", 0.7)
		_close()
		bought.emit(Ads.reward_continue_moves())
	elif _is_open:
		_refresh_ad_button()

## Label and price get their own columns (2026-09-05 UI pass) — previously
## one run-on string with no visual hierarchy between what you're buying
## and what it costs.
func _tier_button(t: Dictionary) -> Button:
	var id: StringName = t["id"]
	var cost := int(t["cost"])
	var afford := Economy.can_afford(cost)
	var after := maxi(Economy.coins - cost, 0)
	var b := UiKit.button("", &"primary" if afford else &"tertiary", VisualTheme.FS_BODY)
	b.custom_minimum_size = Vector2(420, 78)
	b.disabled = not afford
	b.modulate.a = 1.0 if afford else 0.45
	b.pressed.connect(func(): _buy(id))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22; row.offset_right = -22
	row.offset_top = 6; row.offset_bottom = -6
	row.add_theme_constant_override("separation", 10)
	b.add_child(row)

	var label := VisualTheme.label(String(t["label"]).to_upper(), VisualTheme.FS_BODY, Color(1, 1, 1))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var price_col := VBoxContainer.new()
	price_col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(price_col)
	var price_lbl := VisualTheme.label("%d ¢" % cost, VisualTheme.FS_HEADING, Color(1, 1, 1))
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_col.add_child(price_lbl)
	var after_lbl := VisualTheme.label("→ %d" % after, VisualTheme.FS_MICRO, Color(1, 1, 1, 0.75), 0)
	after_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_col.add_child(after_lbl)

	return b

## Spend + report the moves to add. app.gd adds them to the live level and
## resumes — it does NOT restart the stage.
func _buy(id: StringName) -> void:
	var moves := GameData.continue_offers.purchase(id)   # Economy.spend + persist
	if moves <= 0:
		_rebuild()   # not affordable after all — just refresh
		return
	Audio.play(&"power_up", 0.7)
	_close()
	bought.emit(moves)

func _decline() -> void:
	_close()
	gave_up.emit()

func _close() -> void:
	_is_open = false
	var t := UiKit.pop_out(_panel)
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 0.0, 0.16)
	await t.finished
	visible = false
