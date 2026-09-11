class_name MoveEventTranslator
extends RefCounted
## Translates one resolved move (ChainResolver.MoveResult) into an ordered
## list of typed EngineEvents. Pure and deterministic: it only re-shapes
## data the resolver already produced — it does NOT re-run any game logic,
## touch the board, or use an RNG. This is the seam that lets the existing,
## fully-tested ChainResolver stay exactly as it is while the presentation
## layers move onto a clean event stream.
##
## Mapping (MoveResult field -> events):
##   wave_cells[0] / score_events[0] .... MATCH_FOUND (+ GEM_REMOVED)
##   wave_cells[i>0] / score_events[i] ... CASCADE_STEP (+ POWER_ACTIVATED
##                                         when that wave is a detonation,
##                                         + GEM_REMOVED)
##   powers_created ..................... POWER_CREATED (formed = powers_formed)
##   obstacles_broken .................. OBSTACLE_CLEARED
##   frozen_cells ...................... GEM_FROZEN
##   timebomb_explosions .............. TIMEBOMB_EXPLODED
##   gravity_moves ..................... GRAVITY_APPLIED
##   refilled_cells ................... BOARD_REFILLED
##   chain_depth / powers_formed ...... CASCADE_FINISHED
##
## Not yet emitted: OBSTACLE_DAMAGED (partial ice/lock hits). MoveResult does
## not currently carry partial-hit data; adding it means a new additive field
## on ChainResolver, deferred to Phase 2 so the tested resolver is untouched.

## `ctx` optionally carries move-level context the resolver doesn't know:
##   path        Array[Vector2i]  the player's drawn connection
##   kind        String           "match" | "power_tap" | "booster" | "auto"
##   group_size  int              size of the connected group / path
##   color       StringName       the match's target colour
static func events_for_move(result, ctx: Dictionary = {}) -> Array[EngineEvent]:
	var out: Array[EngineEvent] = []
	if result == null or not result.valid:
		return out

	var path: Array = ctx.get("path", [])
	var kind: String = String(ctx.get("kind", "match"))
	out.append(EngineEvent.make(EngineEvent.MOVE_STARTED, {"path": path, "kind": kind}))
	out.append(EngineEvent.make(EngineEvent.CASCADE_STARTED, {}))

	var wave_cells: Array = result.wave_cells
	var score_events: Array = result.score_events
	# Wave 0 is a plain initial clear (resolve_move) UNLESS it already carries a
	# power_id — a power tap / booster detonation has no separate initial clear,
	# its first wave IS the detonation. Detect that and emit the right shape.
	var wave0_is_detonation: bool = score_events.size() > 0 and (score_events[0].has("power_id") or score_events[0].get("timebomb", false))
	for i in wave_cells.size():
		var cells: Array = wave_cells[i]
		var se: Dictionary = score_events[i] if i < score_events.size() else {}
		var new_count: int = int(se.get("cells", cells.size()))
		if i == 0 and not wave0_is_detonation:
			out.append(EngineEvent.make(EngineEvent.MATCH_FOUND, {
				"size": int(ctx.get("group_size", cells.size())),
				"cell_count": cells.size(),
				"color": ctx.get("color", &""),
			}))
			if cells.size() > 0:
				out.append(EngineEvent.make(EngineEvent.GEM_REMOVED, {"count": cells.size(), "wave": 0}))
		else:
			if se.has("power_id"):
				out.append(EngineEvent.make(EngineEvent.POWER_ACTIVATED, {
					"power_id": se.get("power_id"),
					"pos": se.get("power_pos", Vector2i.ZERO),
					"wave": i,
					"bonus": int(se.get("power_bonus", 0)),
				}))
			out.append(EngineEvent.make(EngineEvent.CASCADE_STEP, {
				"wave": i,
				"cell_count": new_count,
				"power_bonus": int(se.get("power_bonus", 0)),
			}))
			if new_count > 0:
				out.append(EngineEvent.make(EngineEvent.GEM_REMOVED, {"count": new_count, "wave": i}))

	for pc in result.powers_created:
		out.append(EngineEvent.make(EngineEvent.POWER_CREATED, {
			"power_id": pc.get("power_id"),
			"pos": pc.get("pos", Vector2i.ZERO),
			"formed": result.powers_formed,
		}))

	for ob in result.obstacles_broken:
		out.append(EngineEvent.make(EngineEvent.OBSTACLE_CLEARED, {
			"obstacle_id": ob.get("obstacle_id"),
			"pos": ob.get("pos", Vector2i.ZERO),
		}))

	for fz in result.frozen_cells:
		out.append(EngineEvent.make(EngineEvent.GEM_FROZEN, {"pos": fz}))

	for tb in result.timebomb_explosions:
		out.append(EngineEvent.make(EngineEvent.TIMEBOMB_EXPLODED, {
			"pos": tb,
			"move_penalty": ChainResolver.TIMEBOMB_MOVE_PENALTY,
		}))

	if not result.gravity_moves.is_empty():
		out.append(EngineEvent.make(EngineEvent.GRAVITY_APPLIED, {"count": result.gravity_moves.size()}))
	if not result.refilled_cells.is_empty():
		out.append(EngineEvent.make(EngineEvent.BOARD_REFILLED, {"count": result.refilled_cells.size()}))

	out.append(EngineEvent.make(EngineEvent.CASCADE_FINISHED, {
		"chain_depth": result.chain_depth,
		"powers_formed": result.powers_formed,
		"secondary_triggers": result.secondary_triggers,
		"total_cleared": result.cleared_cells.size(),
	}))
	return out
