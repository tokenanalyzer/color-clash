extends TestCase
## 2026-09-06 UI asset integration. The artist-supplied UI sheets in
## assets/ui_kit/ load, and every region declared in data/ui_atlas.json
## slices into a valid AtlasTexture that lies fully inside its source sheet —
## so a crop can never show a neighbouring element. The source PNGs are
## never modified (AtlasTexture only references a sub-rect).

const _ATLAS_PATH := "res://data/ui_atlas.json"

func _atlas() -> Dictionary:
	return JsonLoader.load_json(_ATLAS_PATH)

func test_sheets_and_button_textures_all_load() -> void:
	var d := _atlas()
	for sid in d.get("sheets", {}).keys():
		var path: String = d["sheets"][sid]
		check("sheet '%s' resolves (%s)" % [sid, path], ResourceLoader.exists(path))
	for tid in d.get("textures", {}).keys():
		check("button texture '%s' resolves" % tid, AssetLibrary.ui_texture(StringName(tid)) != null)

func test_every_region_slices_and_stays_inside_its_sheet() -> void:
	var d := _atlas()
	var regions: Dictionary = d.get("regions", {})
	check("atlas declares regions", regions.size() >= 30)
	for rid in regions.keys():
		var r: Dictionary = regions[rid]
		var sheet := AssetLibrary._ui_sheet(String(r.get("sheet", "")))
		check("region '%s' sheet present" % rid, sheet != null)
		if sheet == null:
			continue
		var t := AssetLibrary.ui_slice(StringName(rid))
		check("region '%s' -> AtlasTexture" % rid, t is AtlasTexture)
		if not (t is AtlasTexture):
			continue
		var reg: Rect2 = (t as AtlasTexture).region
		var sw := float(sheet.get_width())
		var sh := float(sheet.get_height())
		var inside := reg.position.x >= 0.0 and reg.position.y >= 0.0 \
			and reg.end.x <= sw + 0.5 and reg.end.y <= sh + 0.5 \
			and reg.size.x >= 8.0 and reg.size.y >= 8.0
		check("region '%s' fully inside %dx%d sheet" % [rid, int(sw), int(sh)], inside, "region=%s" % reg)
		check("region '%s' filter_clip set (no bleed)" % rid, (t as AtlasTexture).filter_clip)

func test_frame_regions_expose_a_content_safe_area() -> void:
	for fid in ["settings_frame", "dr_frame"]:
		var s := AssetLibrary.ui_safe(StringName(fid))
		check("%s safe-area has 4 sides" % fid, s.has("left") and s.has("top") and s.has("right") and s.has("bottom"))
		check("%s insets are a sane fraction" % fid,
			s["left"] > 0.0 and s["left"] < 0.3 and s["top"] > 0.0 and s["top"] < 0.3)
		check("%s aspect is portrait-ish" % fid, AssetLibrary.ui_aspect(StringName(fid)) > 0.4 and AssetLibrary.ui_aspect(StringName(fid)) < 1.0)

func test_slider_tracks_declare_horizontal_nine_patch() -> void:
	for sid in ["settings_slider_fill", "settings_slider_bg"]:
		var n := AssetLibrary.ui_nine(StringName(sid))
		check("%s has 4 nine-patch margins" % sid, n.size() == 4)
		check("%s stretches horizontally only" % sid, int(n[0]) > 0 and int(n[2]) > 0 and int(n[1]) == 0 and int(n[3]) == 0)

func test_missing_region_returns_null_not_an_error() -> void:
	check("unknown region -> null", AssetLibrary.ui_slice(&"no_such_region_xyz") == null)
	check("unknown texture -> null", AssetLibrary.ui_texture(&"no_such_texture_xyz") == null)

func test_asset_widget_availability_flags_are_true_with_the_sheet_present() -> void:
	check("AssetToggle available", UiKit.AssetToggle.available())
	check("AssetSlider available", UiKit.AssetSlider.available())

func test_daily_value_pills_match_the_reward_table() -> void:
	# The sheet's baked value pills (100/150/250/400/600) must line up with
	# the coin days in DailyRewards.TABLE, or a day would show the wrong
	# number. Booster days (3, 5) carry no coin pill.
	var coin_day_to_pill := {1: 100, 2: 150, 4: 250, 6: 400, 7: 600}
	for day in coin_day_to_pill.keys():
		var reward: Dictionary = DailyRewards.reward_for_day(day)
		check_eq("day %d coins == its pill art" % day, int(reward.get("coins", 0)), coin_day_to_pill[day])
		check("day %d pill slice exists" % day, AssetLibrary.ui_slice(StringName("dr_pill_%d" % coin_day_to_pill[day])) != null)
	for booster_day in [3, 5]:
		check("day %d is a booster day (BOOST pill)" % booster_day,
			(DailyRewards.reward_for_day(booster_day).get("boosters", {}) as Dictionary).size() > 0)
