class_name ScoreCalculator
extends RefCounted
## Turns a resolved move's raw stats into a score. Centralizing the formula
## keeps balancing changes in one place and makes scoring independently
## testable from board/animation code.

static func compute_move_score(move_result: ChainResolver.MoveResult, power_config: PowerConfig, combo_multiplier: float, fever_multiplier: float) -> int:
	var total := 0.0
	for event in move_result.score_events:
		total += float(event["cells"]) * float(power_config.base_points_per_piece) + float(event["power_bonus"])
	total *= combo_multiplier
	total *= fever_multiplier
	return int(round(total))

## Combo multiplier grows with how many waves cascaded in a single move.
static func combo_multiplier_for_depth(chain_depth: int, step: float = 0.35) -> float:
	return 1.0 + float(max(chain_depth - 1, 0)) * step
