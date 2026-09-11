extends SceneTree
## DEBUG view-layer stall probe (manual dev tool — NOT in tests/test_runner.gd).
##
## The model-level BoardDiagnosticBot proves BoardModel + ChainResolver never
## deadlock. This harness boots the REAL BoardView node and drives its REAL
## _play_move() coroutine so it can catch a stall that only exists in the
## animation layer: an `await <tween>.finished` on a tween that already
## finished, which parks the coroutine forever and leaves `_locked_input`
## true -> the board silently stops accepting moves ("colours stop
## combining", "stuck during play").
##
## Reproduction knob: a real device that dips below ~15 FPS during a cascade
## makes a sub-frame tween finish *inside* an earlier `await create_timer()`.
## Pass `--fixed-fps <n>` on the Godot command line to simulate that frame
## rate deterministically:
##
##   # control (fast frames) — expect NO hang:
##   godot4 --headless --path game --script res://tests/diag_board_view.gd
##
##   # repro (slow frames) — expect a hang to be reported:
##   godot4 --headless --fixed-fps 15 --path game --script res://tests/diag_board_view.gd -- --fever
##
## Flags:  --fever   force FeverSystem-style fast cascades (_cascade_scale)
##         --levels=20,30,44,47,48   which authored levels to probe
##         --moves=40                moves per level
##         --seed=12345             base seed

const _BOT := preload("res://scripts/debug/board_diagnostic_bot.gd")
const HANG_FRAME_BUDGET := 900      # frames to wait for _locked_input to clear
const HANG_WALL_MS := 20000         # ... or this much wall time, whichever first

var _args := {}
var _resolved_count := 0

func _initialize() -> void:
	await process_frame
	await process_frame

	if not OS.is_debug_build():
		push_warning("diag_board_view: not a debug build — no-op.")
		quit(0); return

	_args = _parse_args()
	var fever: bool = _args.has("fever")
	var moves: int = int(_args.get("moves", 40))
	var base_seed: int = int(_args.get("seed", 12345))
	var level_ids: Array = []
	for s in String(_args.get("levels", "20,30,44,47,48")).split(",", false):
		level_ids.append(int(s))

	var gd := get_root().get_node("GameData")
	var bv_script := load("res://scripts/board/board_view.gd")
	var root_node := Node2D.new()
	get_root().add_child(root_node)

	print("==== VIEW-LAYER STALL PROBE ====")
	print("fixed fps        : %s" % (str(Engine.max_fps) if Engine.max_fps > 0 else "uncapped (pass --fixed-fps N to throttle)"))
	print("force fever       : %s" % fever)
	print("levels            : %s   moves/level: %d   base seed: %d" % [str(level_ids), moves, base_seed])
	print("frame time (avg)  : measuring...")

	var hangs: Array = []
	var total_moves := 0
	var worst_unlock_frames := 0

	for lid in level_ids:
		var level = gd.levels.get_level(lid)
		if level == null:
			continue
		var seed: int = base_seed + lid * 1000
		var bv = bv_script.new()
		root_node.add_child(bv)
		var rainbow_chance := float(gd.power_config.get_definition(&"rainbow").get("refill_spawn_chance", 0.0))
		bv.setup(level, gd.colors, gd.power_config, rainbow_chance, seed, Rect2(Vector2.ZERO, Vector2(1080, 1500)))
		_resolved_count = 0
		bv.move_resolved.connect(func(_r): _resolved_count += 1)
		if fever:
			bv.set_fever(true)

		# a lightweight move picker that queries bv.board (the real model)
		var picker = _BOT.new()
		picker.configure(level, seed, {"power_config": gd.power_config, "logical_level_id": lid})
		# point the picker at the SAME board instance the view is animating
		picker.board = bv.board

		var level_hung := false
		for mi in moves:
			if bv.board == null:
				break
			var plan: Dictionary = picker._pick_move()
			if plan.is_empty():
				break
			var path: Array = plan["path"]
			var kind: String = plan["kind"]

			var resolved_before := _resolved_count
			var t_wall := Time.get_ticks_msec()

			# fire the REAL coroutine (do not await it — we watch _locked_input)
			if kind == "power_tap":
				bv._play_power_tap(path[0])
			else:
				bv._play_move(_typed(path))

			# wait for the move to fully settle: _locked_input back to false
			# AND the move_resolved signal seen.
			var frames := 0
			while frames < HANG_FRAME_BUDGET:
				await process_frame
				frames += 1
				if not bv._locked_input and _resolved_count > resolved_before:
					break
				if Time.get_ticks_msec() - t_wall > HANG_WALL_MS:
					break
			worst_unlock_frames = maxi(worst_unlock_frames, frames)
			total_moves += 1

			var stuck: bool = bv._locked_input or _resolved_count == resolved_before
			if stuck:
				# If BoardView has been hand-instrumented with a `_diag_await`
				# breadcrumb var (see the diagnostic write-up), surface the
				# exact await site the coroutine parked on.
				if "_diag_await" in bv and String(bv._diag_await) != "":
					print("  >>> coroutine parked at await site: %s" % String(bv._diag_await))
				var rep := {
					"level_id": lid,
					"level_name": level.level_name,
					"seed": seed,
					"move_index": mi + 1,
					"move_kind": kind,
					"selected_move": _p2a(path),
					"board_w": bv.board.width, "board_h": bv.board.height,
					"cascade_scale": bv._cascade_scale,
					"fever_active": bv.fever_active,
					"locked_input_stuck": bv._locked_input,
					"move_resolved_emitted": _resolved_count > resolved_before,
					"frames_waited": frames,
					"wall_ms": Time.get_ticks_msec() - t_wall,
					"board": picker.serialize_board(),
				}
				hangs.append(rep)
				print(_format_hang(rep))
				level_hung = true
				break

		bv.queue_free()
		await process_frame
		if level_hung:
			# one hang is proof enough; keep probing other levels for breadth
			pass

	print("\n================ VIEW-LAYER PROBE SUMMARY ================")
	print("moves driven through the real BoardView : %d" % total_moves)
	print("worst frames-to-unlock (non-hung)       : %d" % worst_unlock_frames)
	print("hangs detected                          : %d" % hangs.size())
	if hangs.is_empty():
		print("result: NO view-layer stall at this frame rate.")
		if Engine.max_fps <= 0:
			print("        (frames were uncapped — re-run with `--fixed-fps 15` to")
			print("         simulate a mid-range device during a cascade.)")
	else:
		print("result: STALL REPRODUCED — _play_move()'s coroutine never")
		print("        cleared _locked_input. Offending await chain lives in")
		print("        BoardView._animate_result() / _animate_powers_formed().")
		for h in hangs:
			print("  level %d seed %d  move %d (%s)  cascade_scale=%.2f fever=%s  waited %d frames / %d ms"
				% [h["level_id"], h["seed"], h["move_index"], h["move_kind"],
				   h["cascade_scale"], h["fever_active"], h["frames_waited"], h["wall_ms"]])
	print("========================================================")
	quit(1 if hangs.size() > 0 else 0)

# --- helpers ---------------------------------------------------------------

func _typed(a: Array) -> Array:
	var out: Array[Vector2i] = []
	out.assign(a)
	return out

func _format_hang(h: Dictionary) -> String:
	var s := "\n############ VIEW-LAYER STALL ############\n"
	s += "level             : %d  (\"%s\")   seed %d\n" % [h["level_id"], h["level_name"], h["seed"]]
	s += "move index        : %d   kind=%s   path=%s\n" % [h["move_index"], h["move_kind"], str(h["selected_move"])]
	s += "board             : %d x %d\n" % [h["board_w"], h["board_h"]]
	s += "cascade_scale     : %.3f   fever_active=%s\n" % [h["cascade_scale"], h["fever_active"]]
	s += "_locked_input     : %s  (true => coroutine never reached the unlock line)\n" % h["locked_input_stuck"]
	s += "move_resolved     : %s  (false => _play_move() never got past its await)\n" % h["move_resolved_emitted"]
	s += "waited             : %d frames / %d ms before giving up\n" % [h["frames_waited"], h["wall_ms"]]
	s += "board at stall     :\n%s\n" % h["board"]
	s += "#########################################\n"
	return s

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var t := a.lstrip("-")
		if t.contains("="):
			var kv := t.split("=", true, 1)
			out[kv[0]] = kv[1]
		else:
			out[t] = true
	return out

static func _p2a(path: Array) -> Array:
	var out: Array = []
	for p in path:
		out.append([p.x, p.y])
	return out
