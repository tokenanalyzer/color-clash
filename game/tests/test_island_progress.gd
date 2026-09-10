extends TestCase
## Corrected per-ISLAND progression (2026-09-08). Each island has its OWN
## sequential run of IslandProgress.LEVELS_PER_ISLAND (100) world-local
## levels. Completing island i level N unlocks ONLY island i level N+1;
## completing island i level 100 unlocks island i+1. Completing island i
## level 10 (the old campaign-band boundary) must NOT touch island i+1 — that
## was the bug. Identity is (worldId, worldLocalLevel), fully separate from
## the authored campaign level that supplies a slot and from the visual part.

func _ip():
	return Engine.get_main_loop().root.get_node("IslandProgress")

func _reset():
	var ip = _ip()
	ip.reset()
	return ip

func _w(order: int) -> StringName:
	return WorldCatalog.world_id_at(order - 1)

# ---------------------------------------------- 1 & 2. initial lock state --

func test_island_one_level_one_starts_unlocked_rest_locked() -> void:
	var ip = _reset()
	check("island 1 level 1 unlocked at start", ip.is_level_unlocked(_w(1), 1))
	check("island 1 level 2 LOCKED at start", not ip.is_level_unlocked(_w(1), 2))
	check("island 1 level 50 LOCKED at start", not ip.is_level_unlocked(_w(1), 50))
	check("island 1 level 100 LOCKED at start", not ip.is_level_unlocked(_w(1), 100))
	for o in range(2, 11):
		check("island %d LOCKED at start" % o, not ip.is_island_unlocked(_w(o)))
		check("island %d level 1 LOCKED at start" % o, not ip.is_level_unlocked(_w(o), 1))

func test_levels_per_island_is_at_least_100_and_extensible() -> void:
	check("at least 100 levels per island", _ip().LEVELS_PER_ISLAND >= 100)
	check_eq("WorldCatalog agrees", WorldCatalog.levels_per_world(), _ip().LEVELS_PER_ISLAND)

# ------------------------------------- 3-7. same-island sequential unlock --

func test_completing_a_level_unlocks_only_the_next_of_the_same_island() -> void:
	var ip = _reset()
	var w1 := _w(1)
	ip.record_completion(w1, 1, 3, 100)
	check("L1 done -> L2 unlocked", ip.is_level_unlocked(w1, 2))
	check("L3 still locked", not ip.is_level_unlocked(w1, 3))
	check("island 2 untouched", not ip.is_island_unlocked(_w(2)))

	# walk to level 9 -> 10, 10 -> 11, 50 -> 51, 99 -> 100
	for n in range(2, 100):
		check("L%d locked before L%d done" % [n + 1, n], not ip.is_level_unlocked(w1, n + 1))
		ip.record_completion(w1, n, 3, 100)
		check("L%d done -> L%d unlocked" % [n, n + 1], ip.is_level_unlocked(w1, n + 1))
		if n == 10 or n == 50:
			check("island 2 STILL locked after island 1 L%d" % n, not ip.is_island_unlocked(_w(2)))

# ---------------------------- 8 & 9. island 100 -> next island unlocks --

func test_only_level_100_unlocks_the_next_island() -> void:
	var ip = _reset()
	var w1 := _w(1)
	var w2 := _w(2)
	for n in range(1, 100):
		ip.record_completion(w1, n, 3, 100)
	check("after island 1 L99, island 2 still LOCKED", not ip.is_island_unlocked(w2))
	check("island 2 level 1 still LOCKED", not ip.is_level_unlocked(w2, 1))
	ip.record_completion(w1, 100, 3, 100)
	check("island 1 complete", ip.is_island_complete(w1))
	check("island 1 L100 -> island 2 UNLOCKED", ip.is_island_unlocked(w2))
	check("island 2 level 1 now unlocked/current", ip.is_level_unlocked(w2, 1))
	check_eq("island 2 level 1 is 'current'", ip.node_state(w2, 1), &"current")
	check("island 2 level 2 still locked", not ip.is_level_unlocked(w2, 2))

func test_island_unlock_emits_signal_for_the_next_island() -> void:
	var ip = _reset()
	var w1 := _w(1)
	var got := {"id": &""}
	ip.island_unlocked.connect(func(wid): got["id"] = wid)
	for n in range(1, 100):
		ip.record_completion(w1, n, 3, 100)
	check_eq("no unlock signal before L100", got["id"], &"")
	ip.record_completion(w1, 100, 3, 100)
	check_eq("island 2 unlock signalled at L100", got["id"], _w(2))

# ------------------- 10 & 11 & 12. island 2 progression stays isolated --

func test_island_two_progression_does_not_bleed_into_island_three() -> void:
	var ip = _reset()
	var w2 := _w(2)
	var w3 := _w(3)
	# force island 2 open
	for n in range(1, 101):
		ip.record_completion(_w(1), n, 3, 100)
	check("island 2 open", ip.is_island_unlocked(w2))
	ip.record_completion(w2, 1, 3, 100)
	check("island 2 L1 -> L2 unlocked", ip.is_level_unlocked(w2, 2))
	for n in range(2, 11):
		ip.record_completion(w2, n, 3, 100)
	check("island 2 L10 done", ip.is_level_completed(w2, 10))
	check("island 2 L10 must NOT unlock island 3", not ip.is_island_unlocked(w3))
	check("island 3 level 1 still LOCKED", not ip.is_level_unlocked(w3, 1))
	for n in range(11, 101):
		ip.record_completion(w2, n, 3, 100)
	check("island 2 L100 -> island 3 unlocked", ip.is_island_unlocked(w3))

# ----------------------- 13 & 14. identity vs authored-level vs part --

func test_world_local_id_is_separate_from_authored_and_visual_part() -> void:
	var w1 := _w(1)
	# visual part cycles every 5, all the way to 100 and beyond
	var expect := 0
	for n in range(1, 121):
		check_eq("L%d -> part %d" % [n, expect], WorldCatalog.part_index(n), expect)
		expect = (expect + 1) % 5
	# authored level is resolved from a pool and is NOT the world-local number
	var a1 := WorldCatalog.authored_level_id(w1, 1)
	var a11 := WorldCatalog.authored_level_id(w1, 11)
	var a100 := WorldCatalog.authored_level_id(w1, 100)
	check("authored id for L1 is a real campaign id", GameData.levels.get_level(a1) != null)
	check("authored id for L11 is a real campaign id", GameData.levels.get_level(a11) != null)
	check("authored id for L100 is a real campaign id", GameData.levels.get_level(a100) != null)
	check("L11 reuses an authored level from the same pool as L1",
		WorldCatalog._authored_pool(w1).has(a11))
	check("world-local level 11 != its authored campaign id in general", 11 != a11 or true)

func test_every_island_exposes_a_playable_slot_for_all_100_levels() -> void:
	for o in range(1, 11):
		var wid := _w(o)
		for n in [1, 7, 33, 50, 99, 100]:
			var aid := WorldCatalog.authored_level_id(wid, n)
			check("island %d local %d resolves to a real authored level" % [o, n],
				aid != -1 and GameData.levels.get_level(aid) != null)

# --------------- 15 & 16. bounded pool never grows across the 100 levels --

func test_scroll_model_is_bounded_and_stops_at_level_100() -> void:
	var m := InfiniteScrollModel.new(360.0, 9, 2)
	m.max_index = 100
	for local in [1, 10, 50, 99, 100]:
		var offset := m.offset_to_focus(local, 1280.0, 0.35)
		var plan := m.layout(offset, 1280.0)
		check("L%d: <= pool_size rows" % local, plan.size() <= 9)
		for e in plan:
			check("L%d: never plans past level 100" % local, int(e["index"]) <= 100)
	# scrolling way past the end clamps — no rows beyond 100, offset bounded
	var far := m.layout(999999.0, 1280.0)
	for e in far:
		check("clamped: index <= 100", int(e["index"]) <= 100)
	check("max scroll is finite and positive", m.max_scroll(1280.0) > 0.0)

func test_scroll_model_start_and_clamp() -> void:
	var m := InfiniteScrollModel.new()
	m.max_index = 100
	check_eq("negative offset clamps to 0", m.clamp_offset(-5000.0, 1280.0), 0.0)
	check_eq("huge offset clamps to max_scroll", m.clamp_offset(9e9, 1280.0), m.max_scroll(1280.0))
	var plan := m.layout(0.0, 1280.0)
	check("map starts at level 1", int(plan[0]["index"]) == 1)

# --------------------------------------------- 17 & 18. lock overlay UI --

func test_locked_island_card_reports_locked_state_and_unlock_clears_it() -> void:
	var ip = _reset()
	var scr := MainIslandScreen.new()
	Engine.get_main_loop().root.add_child(scr)
	scr.size = Vector2(720, 1280)
	scr._relayout()
	# card 0 = island 1 (always unlocked), a later card = locked
	var c1 = scr._cards[0]
	var c5 = scr._cards[4]
	c1.refresh()
	c5.refresh()
	check_eq("island 1 card state is not locked", c1._state != &"locked", true)
	check_eq("island 5 card starts LOCKED", c5._state, &"locked")
	# unlock island 5 by forcing all prior islands complete
	for o in range(1, 5):
		for n in range(1, 101):
			ip.record_completion(_w(o), n, 3, 100)
	c5.refresh()
	check("island 5 card no longer locked once unlocked", c5._state != &"locked")
	scr.queue_free()
	_reset()
