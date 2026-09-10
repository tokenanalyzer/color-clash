extends TestCase
## 2026-09-07 gameplay overhaul — the escort ("Love Crystal" / relic) object.
## A special holds no colour, is never selectable, is never destroyed by a
## clear, falls with gravity like a piece, and is DELIVERED (removed +
## reported) the moment it reaches the bottom row. Model + resolver +
## objective, all headless.

const _COLORS: Array[StringName] = [&"red", &"blue", &"yellow"]

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 12345
	return r

# ---------------------------------------------------------------- model --

func test_relic_cell_is_inert_to_selection_and_holds_no_piece() -> void:
	var b := BoardModel.new(5, 6, 3)
	b.set_special(Vector2i(2, 1), &"relic")
	var c := b.get_cell(Vector2i(2, 1))
	check("relic cell reports a special", c.has_special())
	check("relic cell holds no colour piece", c.is_empty())
	check("relic cell is NOT selectable for a connection", not c.is_selectable())
	check("has_movable_content() is true (gravity must carry it)", c.has_movable_content())

func test_generate_and_refill_never_overwrite_a_relic() -> void:
	var b := BoardModel.new(5, 6, 3)
	b.set_special(Vector2i(2, 1), &"relic")
	b.generate(_rng(), _COLORS)
	check("generate() left the relic intact", b.get_cell(Vector2i(2, 1)).has_special())
	check("generate() put no colour under the relic", b.get_cell(Vector2i(2, 1)).is_empty())
	b.get_cell(Vector2i(0, 0)).clear_piece()   # open a top cell
	b.refill(_rng(), _COLORS)
	check("refill() left the relic intact", b.get_cell(Vector2i(2, 1)).has_special())

func test_connection_routes_around_a_relic() -> void:
	var b := BoardModel.new(5, 6, 3)
	b.generate(_rng(), _COLORS)
	b.set_special(Vector2i(2, 2), &"relic")
	var grp := b.find_connected_group(Vector2i(2, 2))
	check("find_connected_group on a relic returns nothing", grp.is_empty())
	# a group next to the relic never swallows it
	for x in b.width:
		for y in b.height:
			if Vector2i(x, y) == Vector2i(2, 2):
				continue
			check("no connected group ever contains the relic cell",
				not b.find_connected_group(Vector2i(x, y)).has(Vector2i(2, 2)))

func test_gravity_carries_a_relic_down_when_the_cell_below_clears() -> void:
	var b := BoardModel.new(3, 6, 3)
	b.generate(_rng(), _COLORS)
	b.set_special(Vector2i(1, 2), &"relic")
	# clear everything below the relic in its column
	for y in range(3, 6):
		b.get_cell(Vector2i(1, y)).clear_piece()
	var moves := b.apply_gravity()
	check("the relic left row 2", not b.get_cell(Vector2i(1, 2)).has_special())
	check("the relic reached the bottom row and was DELIVERED",
		not b.get_cell(Vector2i(1, 5)).has_special())
	var delivered := 0
	var delivered_from := Vector2i(-1, -1)
	for m: Dictionary in moves:
		if m.get("delivered", false):
			delivered += 1
			delivered_from = m["from"]
	check_eq("gravity reported exactly one delivery", delivered, 1)
	check_eq("delivery is reported at the bottom row", delivered_from, Vector2i(1, 5))

func test_relic_that_only_falls_partway_is_not_delivered_yet() -> void:
	var b := BoardModel.new(3, 7, 3)
	b.generate(_rng(), _COLORS)
	b.set_special(Vector2i(1, 1), &"relic")
	b.get_cell(Vector2i(1, 3)).clear_piece()   # one gap under the relic
	b.apply_gravity()
	var still_there := b.get_cell(Vector2i(1, 2)).has_special()
	check("the relic dropped one row but is still on the board", still_there)
	check("bottom row is still empty of the relic", not b.get_cell(Vector2i(1, 6)).has_special())

# ------------------------------------------------------------- resolver --

func test_move_result_reports_specials_delivered() -> void:
	var pc := GameData.power_config
	var b := BoardModel.new(3, 6, 3)
	for x in b.width:
		for y in b.height:
			b.get_cell(Vector2i(x, y)).color_id = &"blue"
	# relic at (1,1) with a red trio filling the rest of its column below it,
	# so clearing that trio drains the whole column and the crystal drops out.
	b.set_special(Vector2i(1, 1), &"relic")
	b.get_cell(Vector2i(1, 2)).color_id = &"red"
	b.get_cell(Vector2i(1, 3)).color_id = &"red"
	b.get_cell(Vector2i(1, 4)).color_id = &"red"
	b.get_cell(Vector2i(1, 5)).clear_piece()   # nothing under the trio
	var res := ChainResolver.resolve_move(b, [Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4)], pc, _rng(), _COLORS, 0.0)
	check("move was valid", res.valid)
	check_eq("one Love Crystal was delivered by the move", res.specials_delivered.size(), 1)
	check("the board no longer carries the relic", b.special_positions().is_empty())

# ------------------------------------------------------------ objective --

func test_deliver_objective_counts_deliveries() -> void:
	var tracker := ObjectiveTracker.new([{"type": "deliver", "special": "relic", "target": 2}])
	tracker.apply_move({}, 0, [], [], 1)
	check("one delivery -> not complete", not tracker.is_complete())
	check_eq("progress tracks deliveries", tracker.progress[0], 1)
	tracker.apply_move({}, 0, [], [], 1)
	check("second delivery completes the escort objective", tracker.is_complete())

func test_deliver_objective_mixed_with_a_colour_goal() -> void:
	var tracker := ObjectiveTracker.new([
		{"type": "deliver", "special": "relic", "target": 1},
		{"type": "clear_color", "color": "red", "target": 5},
	])
	tracker.apply_move({&"red": 5}, 0, [], [], 0)
	check("colour done but crystal not delivered -> incomplete", not tracker.is_complete())
	tracker.apply_move({}, 0, [], [], 1)
	check("both goals met -> complete", tracker.is_complete())
