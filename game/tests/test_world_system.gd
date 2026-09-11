extends TestCase
## The 10-island system (2026-09-08 correction pass): data-driven catalogue,
## the five reusable visual templates + their cycle to level 100, the
## bounded/recycled vertical level map, world-local level identity vs authored
## campaign level vs visual part, alternating zig-zag positioning, the shared
## SEA CLIP background, the fantasy Back button, and the MainIslandScreen /
## InternalLevelMap navigation. Per-island unlock RULES live in
## test_island_progress.gd.

func _root() -> Node:
	return Engine.get_main_loop().root

func _ip():
	return _root().get_node("IslandProgress")

# ------------------------------------------------------- 1. world config --

func test_catalogue_has_ten_well_formed_worlds() -> void:
	check_eq("10 worlds", WorldCatalog.count(), 10)
	var seen_orders := {}
	for i in WorldCatalog.count():
		var w: Dictionary = WorldCatalog.worlds()[i]
		check("world %d has an id" % i, String(w.get("id", "")).length() > 0)
		check("world %d has a display name" % i, String(w.get("display_name", "")).length() > 0)
		var o := int(w.get("order", -1))
		check("world %d order in 1..10" % i, o >= 1 and o <= 10)
		seen_orders[o] = true
	check_eq("orders 1..10 all present and unique", seen_orders.size(), 10)

func test_expected_world_ids_and_names_in_order() -> void:
	var want := [
		["evergreen_kingdom", "Evergreen Kingdom"], ["emberfall_isle", "Emberfall Isle"],
		["golden_oasis", "Golden Oasis"], ["mystic_crystal_grove", "Mystic Crystal Grove"],
		["celestial_haven", "Celestial Haven"], ["pirates_paradise", "Pirate’s Paradise"],
		["whispering_wilds", "Whispering Wilds"], ["crystal_skylands", "Crystal Skylands"],
		["frostcrown_isle", "Frostcrown Isle"], ["haunted_shadowlands", "Haunted Shadowlands"],
	]
	for i in want.size():
		var w := WorldCatalog.world_by_order(i + 1)
		check_eq("order %d id" % (i + 1), String(w.get("id", "")), want[i][0])
		check_eq("order %d name" % (i + 1), String(w.get("display_name", "")), want[i][1])

# ---------------------------------------- 2 & 3. all 10 worlds, 5 parts --

func test_every_world_has_main_art_and_exactly_five_parts() -> void:
	for w in WorldCatalog.worlds():
		var id := StringName(String(w.get("id", "")))
		var main_path := String(w.get("main_asset", ""))
		check("%s main asset exists" % id, ResourceLoader.exists(main_path))
		var parts := WorldCatalog.part_paths(id)
		check_eq("%s has exactly 5 parts" % id, parts.size(), 5)
		for p in parts:
			check("%s part exists: %s" % [id, p], ResourceLoader.exists(String(p)))

func test_board_and_sea_clip_assets_exist() -> void:
	check("level board asset exists", ResourceLoader.exists(WorldCatalog.board_asset_path()))
	var sea := WorldCatalog.sea_clip_path()
	check("sea clip is a Theora .ogv", sea.ends_with(".ogv"))
	check("sea clip asset exists", ResourceLoader.exists(sea))

# ------------------------------------------- 4 & 14. template cycle to 100 --

func test_part_index_cycles_every_five_levels_through_100() -> void:
	var want := 0
	for n in range(1, 121):
		check_eq("level %d -> part %d" % [n, want], WorldCatalog.part_index(n), want)
		want = (want + 1) % 5
	check_eq("level 100 -> part 4", WorldCatalog.part_index(100), 4)

func test_part_texture_follows_the_cycle_not_the_level_number() -> void:
	var id := WorldCatalog.world_id_at(0)
	var t1 := WorldCatalog.part_texture(id, 1)
	check("level 1 has a part texture", t1 != null)
	check("level 6 reuses level 1's template", WorldCatalog.part_texture(id, 6) == t1)
	check("level 11 reuses level 1's template", WorldCatalog.part_texture(id, 11) == t1)
	check("level 96 reuses level 1's template", WorldCatalog.part_texture(id, 96) == t1)
	check("level 2 uses a different template", WorldCatalog.part_texture(id, 2) != t1)

# -------------------- 13. world-local id vs authored campaign id --

func test_authored_level_id_is_separate_from_world_local_id() -> void:
	var id := WorldCatalog.world_id_at(0)
	var a1 := WorldCatalog.authored_level_id(id, 1)
	check("world-local 1 resolves to a real authored level", GameData.levels.get_level(a1) != null)
	# every slot up to 100 is playable (authored pool is cycled) — no fake levels
	for n in [10, 25, 55, 99, 100]:
		var aid := WorldCatalog.authored_level_id(id, n)
		check("world-local %d resolves to a real authored level" % n,
			aid != -1 and GameData.levels.get_level(aid) != null)
	check("authored pool for island 1 is non-empty", WorldCatalog._authored_pool(id).size() > 0)

func test_authored_pool_respects_a_declared_campaign_span() -> void:
	# islands 1-5 declare a 10-level band; islands 6-10 fall back to the whole
	# authored campaign. Either way every slot is playable.
	var band := WorldCatalog._authored_pool(WorldCatalog.world_id_at(0))
	check("island 1 band is 10 authored levels", band.size() == 10)
	var full := WorldCatalog._authored_pool(WorldCatalog.world_id_at(9))
	check("island 10 falls back to the whole authored campaign",
		full.size() == GameData.levels.ordered_ids.size())

# ------------------------------------- 7. alternating left/right zig-zag --

func test_positions_alternate_left_right_by_level_index() -> void:
	check_eq("level 1 -> LEFT", WorldCatalog.zigzag_side(1), -1)
	check_eq("level 2 -> RIGHT", WorldCatalog.zigzag_side(2), 1)
	for n in range(1, 100):
		check("level %d side alternates" % n, WorldCatalog.is_left(n) == (n % 2 == 1))
		check("level %d != level %d side" % [n, n + 1],
			WorldCatalog.zigzag_side(n) != WorldCatalog.zigzag_side(n + 1))

# --------------------------------- 8. dynamic level board + number node --

func test_island_level_node_renders_the_dynamic_local_number() -> void:
	var n := IslandLevelNode.new()
	_root().add_child(n)
	var part := WorldCatalog.part_texture(WorldCatalog.world_id_at(0), 3)
	n.assign(3, part, &"unlocked", 0, true, Vector2(300, 300))
	check_eq("board number shows the world-local level", n._num.text, "3")
	check("island part texture assigned (not merged with board)", n._part.texture == part)
	check("reusable board texture is a separate child", n._board.texture == WorldCatalog.board_texture())
	var box_w := n.size.x
	n.assign(100, part, &"completed", 3, true, Vector2(300, 300))
	check_eq("recycled node shows its new number", n._num.text, "100")
	check("board stays the same size regardless of digit count", is_equal_approx(n.size.x, box_w))
	n.assign(47, part, &"locked", 0, false, Vector2(300, 300))
	check_eq("locked node still shows its number (dimmed)", n._num.text, "47")
	check("non-routable node is not routable", not n.routable)
	check("passive node never eats input itself", n.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	n.queue_free()

# ------------------------------ 11. SEA CLIP single shared background --

func test_sea_clip_background_is_single_and_headless_safe() -> void:
	var bg := SeaClipBackground.new()
	_root().add_child(bg)
	bg.ensure_playing()
	bg.pause()
	bg.ensure_playing()
	var video_players := 0
	for c in bg.get_children():
		if c is VideoStreamPlayer:
			video_players += 1
	check("at most one VideoStreamPlayer inside the shared background", video_players <= 1)
	check("still a valid node after play/pause cycling", is_instance_valid(bg))
	bg.queue_free()

# ------------------------- 20 & 21. fantasy Back button --

func test_back_button_arrow_points_left_and_is_large_with_a_label() -> void:
	var b := UiKit.back_button()
	_root().add_child(b)
	check("back button is comfortably tappable", b.custom_minimum_size.x >= 150 and b.custom_minimum_size.y >= 72)
	var found_left_chevron := false
	var found_label := false
	var stack: Array = [b]
	while not stack.is_empty():
		var node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
			if c is Label and String((c as Label).text).to_upper() == "BACK":
				found_label = true
			if c.get("glyph") == &"chevron_left":
				found_left_chevron = true
	check("back button uses the LEFT-pointing (mirrored) chevron", found_left_chevron)
	check("back button has a readable BACK label", found_label)
	b.queue_free()

# ---------------- 12 & 13. Main Island <-> Internal Map navigation --

func test_main_island_screen_selects_an_unlocked_island_only() -> void:
	var ip = _ip()
	ip.reset()
	var scr := MainIslandScreen.new()
	_root().add_child(scr)
	scr.size = Vector2(720, 1280)
	scr._relayout()
	var got := {"id": &""}
	scr.world_selected.connect(func(wid): got["id"] = wid)
	check_eq("one card per island", scr._cards.size(), 10)

	# island 1 (card 0) is unlocked -> tapping selects it
	var c0 = scr._cards[0]
	scr._try_tap_at(c0.position + c0.size * 0.5)
	check_eq("tapping the unlocked island 1 selects it", got["id"], c0.world_id)

	# a locked island (card 4) -> tapping does NOT select it
	got["id"] = &""
	var c4 = scr._cards[4]
	scr._try_tap_at(c4.position + c4.size * 0.5)
	check_eq("tapping a LOCKED island selects nothing", got["id"], &"")

	var backed := {"hit": false}
	scr.back_pressed.connect(func(): backed["hit"] = true)
	scr.back_pressed.emit()
	check("back_pressed is wired", backed["hit"])
	scr.queue_free()

func test_main_island_screen_scrolls_on_drag_without_selecting() -> void:
	var scr := MainIslandScreen.new()
	_root().add_child(scr)
	scr.size = Vector2(720, 1280)
	scr._relayout()
	check("10 island cards make a scrollable list", scr._max_scroll > 0.0)
	var picked := {"n": 0}
	scr.world_selected.connect(func(_w): picked["n"] += 1)

	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = Vector2(360, 400)
	scr._handle_drag_input(down)
	for i in 5:
		var drag := InputEventScreenDrag.new()
		drag.position = Vector2(360, 400 - (i + 1) * 80)
		drag.relative = Vector2(0, -80)
		scr._handle_drag_input(drag)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = Vector2(360, 0)
	scr._handle_drag_input(up)

	check("dragging scrolled the island list", scr._scroll_y > 50.0)
	check("scroll stays within bounds", scr._scroll_y <= scr._max_scroll + 1.0)
	check_eq("a drag never selects an island", picked["n"], 0)
	scr.queue_free()

func test_internal_level_map_opens_a_world_and_reuses_one_scroller() -> void:
	var m := InternalLevelMap.new()
	_root().add_child(m)
	var w1 := WorldCatalog.world_id_at(0)
	m.open(w1)
	check_eq("world stored", m.world_id, w1)
	check("LOCKED banner hidden for the always-open island 1", not m._locked_banner.visible)
	var scroller_before := m._scroller
	m.open(WorldCatalog.world_id_at(1))
	check("same scroller instance reused between islands", m._scroller == scroller_before)
	m.queue_free()

# ----------------------------- 14-16. level click routing + far scroll --

func test_scroller_routes_unlocked_levels_and_blocks_the_rest() -> void:
	var ip = _ip()
	ip.reset()
	var w1 := WorldCatalog.world_id_at(0)
	var s := InfiniteLevelScroller.new()
	_root().add_child(s)
	s.setup(w1)
	check_eq("pool is exactly POOL_SIZE nodes", s.live_node_count(), InfiniteLevelScroller.POOL_SIZE)

	var chosen := {"wid": &"", "n": -1}
	var inert := {"n": -1}
	s.level_chosen.connect(func(wid, n): chosen["wid"] = wid; chosen["n"] = n)
	s.inert_level_tapped.connect(func(n): inert["n"] = n)

	s._on_node_clicked(1)   # island 1 level 1 is always unlocked
	check_eq("tapping level 1 routes (world, 1)", chosen["n"], 1)
	check_eq("routed world id is island 1", chosen["wid"], w1)

	s._on_node_clicked(42)  # locked -> inert
	check_eq("tapping a locked level is inert", inert["n"], 42)

	# Far scroll to the end of the island: the pool never grows.
	for local in [1, 25, 50, 99, 100]:
		s.debug_scroll_to_local_level(local)
		check_eq("still POOL_SIZE nodes after scrolling to %d" % local,
			s.live_node_count(), InfiniteLevelScroller.POOL_SIZE)
		check("no more visible nodes than the pool at %d" % local,
			s.visible_node_count() <= InfiniteLevelScroller.POOL_SIZE)
	# nothing past level 100 is ever mounted
	s.debug_scroll_to_local_level(100)
	for idx in s.visible_indices():
		check("visible index never exceeds level 100", idx <= 100)
	s.queue_free()

func test_a_drag_that_starts_on_an_island_is_not_a_level_tap() -> void:
	var s := InfiniteLevelScroller.new()
	_root().add_child(s)
	s.size = Vector2(720, 1280)
	s.setup(WorldCatalog.world_id_at(0))
	var fired := {"n": 0}
	s.level_chosen.connect(func(_wid, _n): fired["n"] += 1)
	s.inert_level_tapped.connect(func(_n): fired["n"] += 1)

	var target := Vector2(360, 300)
	for node in s._nodes:
		if node.visible:
			target = node.position + node.hit_rect().size * 0.5
			break

	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = target
	s._gui_input(down)
	var drag := InputEventScreenDrag.new()
	drag.position = target + Vector2(0, -140)
	drag.relative = Vector2(0, -140)
	s._gui_input(drag)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = target + Vector2(0, -140)
	s._gui_input(up)
	check_eq("drag from an island routed nothing", fired["n"], 0)
	s.queue_free()

func test_scroller_shows_contiguous_ascending_levels() -> void:
	var s := InfiniteLevelScroller.new()
	_root().add_child(s)
	s.setup(WorldCatalog.world_id_at(0))
	s.debug_scroll_to_local_level(60)
	var idxs := s.visible_indices()
	check("some levels visible around 60", idxs.size() >= 1)
	for i in range(1, idxs.size()):
		check("visible levels are contiguous", idxs[i] == idxs[i - 1] + 1)
	s.queue_free()
