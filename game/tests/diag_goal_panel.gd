extends SceneTree
## DEBUG GOAL-panel containment probe (manual dev tool — NOT in test_runner.gd).
##
## Drives the REAL HUD through every objective type and combination and
## asserts, for each one, that:
##   1. the GOAL panel outer rect (_tb_goal_zone) never moves;
##   2. the fixed inner content rect (_goal_content_clip) never moves and
##      stays inside _goal_mid;
##   3. every objective chip's on-screen AABB (scale included) stays fully
##      inside _goal_mid's gold border — never off the panel, off screen,
##      above the panel, or clipped.
##
##   godot4 --headless --path game --script res://tests/diag_goal_panel.gd
##
## Exit 0 = all objective sets contained; exit 1 = at least one drifted.

const VP := Vector2i(1080, 2377)
const EPS := 1.5          # px tolerance for the "inside the panel" check

var _hud
var _fails: Array = []
var _first_zone_rect := Rect2()
var _first_clip_rect := Rect2()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await _frames(3)
	if not OS.is_debug_build():
		push_warning("diag_goal_panel: not a debug build — no-op."); quit(0); return

	var svp := SubViewport.new()
	svp.size = VP
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(svp)

	var hud_script := load("res://scripts/ui/hud.gd")
	_hud = hud_script.new()
	svp.add_child(_hud)
	await _frames(8)

	# ---- the objective sets to probe -----------------------------------
	var cases: Array = []
	# every single type, short label
	cases.append(["clear_color x1", [{"type": "clear_color", "color": "red", "target": 20}]])
	cases.append(["reach_score x1", [{"type": "reach_score", "target": 4000}]])
	cases.append(["create_powers x1", [{"type": "create_powers", "power": "any", "target": 5}]])
	cases.append(["break_obstacles any", [{"type": "break_obstacles", "obstacle": "any", "target": 3}]])
	cases.append(["break_obstacles long id", [{"type": "break_obstacles", "obstacle": "shadow_barrier", "target": 2}]])
	cases.append(["deliver x1", [{"type": "deliver", "target": 1}]])
	# long numeric labels (reach_score progress renders the full score)
	cases.append(["reach_score huge", [{"type": "reach_score", "target": 25500}]])
	# 2-objective mixes
	cases.append(["clear_color + deliver", [
		{"type": "clear_color", "color": "blue", "target": 38},
		{"type": "deliver", "target": 2}]])
	cases.append(["break + create_powers", [
		{"type": "break_obstacles", "obstacle": "cursed_stone", "target": 3},
		{"type": "create_powers", "power": "any", "target": 6}]])
	# 3-objective mixes — the actual Levels 20..50 shapes
	cases.append(["score + deliver + color", [
		{"type": "reach_score", "target": 22000},
		{"type": "deliver", "target": 1},
		{"type": "clear_color", "color": "red", "target": 43}]])
	cases.append(["break + color + powers", [
		{"type": "break_obstacles", "obstacle": "shadow_barrier", "target": 2},
		{"type": "clear_color", "color": "red", "target": 58},
		{"type": "create_powers", "power": "any", "target": 6}]])
	cases.append(["deliver x3 + powers + break", [
		{"type": "deliver", "target": 3},
		{"type": "create_powers", "power": "any", "target": 6},
		{"type": "break_obstacles", "obstacle": "shadow_barrier", "target": 2}]])
	# a deliberately overfull 4-objective set (not in data — proves the
	# scale-to-fit path keeps everything inside)
	cases.append(["4 objectives (overfull)", [
		{"type": "reach_score", "target": 25500},
		{"type": "deliver", "target": 3},
		{"type": "clear_color", "color": "purple", "target": 60},
		{"type": "break_obstacles", "obstacle": "shadow_barrier", "target": 2}]])

	# also run EVERY authored level 20..50 exactly as shipped
	var gd := get_root().get_node("GameData")
	for lid in range(20, 51):
		var lv = gd.levels.get_level(lid)
		if lv != null:
			cases.append(["authored L%d" % lid, lv.objectives.duplicate(true)])

	print("==== GOAL PANEL CONTAINMENT PROBE — %d objective sets ====" % cases.size())

	var probed := 0
	for case in cases:
		var name: String = case[0]
		var objs: Array = case[1]
		await _probe(name, objs)
		probed += 1

	print("\n================ SUMMARY ================")
	print("objective sets probed : %d" % probed)
	print("GOAL outer rect        : %s  (fixed across all sets: %s)" % [str(_first_zone_rect), "YES" if _fails_for("ZONE_MOVED") == 0 else "NO"])
	print("inner content rect     : %s  (fixed across all sets: %s)" % [str(_first_clip_rect), "YES" if _fails_for("CLIP_MOVED") == 0 else "NO"])
	print("containment failures   : %d" % _fails.size())
	for f in _fails:
		print("  FAIL [%s] %s" % [f["code"], f["msg"]])
	print("========================================")
	quit(1 if _fails.size() > 0 else 0)

func _probe(name: String, objs: Array) -> void:
	var lc := LevelConfig.from_dict({
		"id": 999, "name": name, "width": 9, "height": 10,
		"colors": ["red", "blue", "yellow", "green", "purple", "orange"],
		"starting_moves": 25, "objectives": objs, "obstacles": [], "specials": [],
	})
	var tracker := ObjectiveTracker.new(lc.objectives)
	# drive progress to worst-case label widths (full numbers shown)
	for i in tracker.progress.size():
		tracker.progress[i] = tracker.target_for(i)
	_hud.set_objectives(tracker, lc)
	await _frames(4)   # let _layout_topbar.call_deferred() settle

	var zone: Control = _hud._tb_goal_zone
	var mid: Control = _hud._goal_mid
	var clip: Control = _hud._goal_content_clip
	if zone == null or mid == null or clip == null:
		_fails.append({"code": "NO_NODES", "msg": "%s: goal nodes missing" % name})
		return

	var zone_rect := zone.get_global_rect()
	var clip_rect := clip.get_global_rect()
	var mid_rect := mid.get_global_rect()

	if _first_zone_rect.size == Vector2.ZERO:
		_first_zone_rect = zone_rect
		_first_clip_rect = clip_rect
	else:
		if not _rects_match(zone_rect, _first_zone_rect, 0.5):
			_fails.append({"code": "ZONE_MOVED", "msg": "%s: GOAL outer rect moved %s -> %s" % [name, str(_first_zone_rect), str(zone_rect)]})
		if not _rects_match(clip_rect, _first_clip_rect, 0.5):
			_fails.append({"code": "CLIP_MOVED", "msg": "%s: inner content rect moved %s -> %s" % [name, str(_first_clip_rect), str(clip_rect)]})

	# inner rect must sit inside the panel art
	if not _rect_contains(mid_rect, clip_rect, EPS):
		_fails.append({"code": "CLIP_OUTSIDE_PANEL", "msg": "%s: content rect %s not inside _goal_mid %s" % [name, str(clip_rect), str(mid_rect)]})

	# every chip's transformed AABB must be inside the panel
	var n: int = _hud._objective_chips.size()
	for ci in n:
		var chip: Control = _hud._objective_chips[ci]
		if chip == null or not is_instance_valid(chip):
			continue
		var aabb := _global_aabb(chip)
		if not _rect_contains(mid_rect, aabb, EPS):
			_fails.append({"code": "CHIP_OUT_OF_PANEL",
				"msg": "%s: chip %d/%d AABB %s escapes _goal_mid %s (dx_left=%.1f dx_right=%.1f dy_top=%.1f dy_bot=%.1f)"
				% [name, ci + 1, n, str(aabb), str(mid_rect),
				   aabb.position.x - mid_rect.position.x,
				   (mid_rect.position.x + mid_rect.size.x) - (aabb.position.x + aabb.size.x),
				   aabb.position.y - mid_rect.position.y,
				   (mid_rect.position.y + mid_rect.size.y) - (aabb.position.y + aabb.size.y)]})
	print("  %-26s chips=%d  zone=(%.0f,%.0f %0.fx%0.f)  panel=(%.0f,%.0f %0.fx%0.f)  %s"
		% [name, n, zone_rect.position.x, zone_rect.position.y, zone_rect.size.x, zone_rect.size.y,
		   mid_rect.position.x, mid_rect.position.y, mid_rect.size.x, mid_rect.size.y,
		   "OK" if _fails_for_case(name) == 0 else "*** FAIL ***"])

# --- geometry helpers ---------------------------------------------------

## Global axis-aligned bounding box of a Control including every ancestor
## transform (rotation/scale included) — get_global_rect() ignores scale.
func _global_aabb(c: Control) -> Rect2:
	var xf := c.get_global_transform()
	var s := c.size
	var pts := [xf * Vector2(0, 0), xf * Vector2(s.x, 0), xf * Vector2(s.x, s.y), xf * Vector2(0, s.y)]
	var mn := Vector2(pts[0])
	var mx := Vector2(pts[0])
	for p in pts:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	return Rect2(mn, mx - mn)

func _rect_contains(outer: Rect2, inner: Rect2, eps: float) -> bool:
	return inner.position.x >= outer.position.x - eps \
		and inner.position.y >= outer.position.y - eps \
		and inner.position.x + inner.size.x <= outer.position.x + outer.size.x + eps \
		and inner.position.y + inner.size.y <= outer.position.y + outer.size.y + eps

func _rects_match(a: Rect2, b: Rect2, eps: float) -> bool:
	return absf(a.position.x - b.position.x) <= eps and absf(a.position.y - b.position.y) <= eps \
		and absf(a.size.x - b.size.x) <= eps and absf(a.size.y - b.size.y) <= eps

func _fails_for(code: String) -> int:
	var n := 0
	for f in _fails:
		if f["code"] == code:
			n += 1
	return n

func _fails_for_case(name: String) -> int:
	var n := 0
	for f in _fails:
		if String(f["msg"]).begins_with(name + ":"):
			n += 1
	return n
