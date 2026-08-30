class_name StarRating
extends RefCounted
## Converts a completed level's move efficiency into a 1-3 star rating.
## Deliberately objective-agnostic (works the same whether the level's goal
## was clear_color/reach_score/create_powers/break_obstacles) so it never
## needs special-casing per objective type — it only looks at how many of
## the allotted moves were left over, a fair, skill-reflecting measure
## available on every level.

## Fraction of the move limit that must remain unused to earn 2 and 3 stars.
const TWO_STAR_SPARE_FRACTION := 0.25
const THREE_STAR_SPARE_FRACTION := 0.5

static func stars_for(moves_left: int, move_limit: int) -> int:
	if move_limit <= 0:
		return 1
	var spare_fraction := float(max(moves_left, 0)) / float(move_limit)
	if spare_fraction >= THREE_STAR_SPARE_FRACTION:
		return 3
	if spare_fraction >= TWO_STAR_SPARE_FRACTION:
		return 2
	return 1
