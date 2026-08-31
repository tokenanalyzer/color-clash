class_name DailyRewards
extends RefCounted
## Pure, deterministic 7-day daily-reward streak logic. No Node, no clock of
## its own — the caller passes today's UTC day index and the last-claim
## state (both persisted through SaveService), so the streak maths is fully
## unit-testable. Rewards are soft currency + boosters only (never premium
## currency), and there is no "pay to keep your streak" hook — see
## docs/GAME_DESIGN.md and docs/SECURITY.md.

## One entry per day of the 7-day cycle. `coins` and `boosters` (id -> qty)
## are both optional; day 7 is the big finish.
const TABLE := [
	{ "day": 1, "coins": 100 },
	{ "day": 2, "coins": 150 },
	{ "day": 3, "coins": 0, "boosters": { "bomb": 1 } },
	{ "day": 4, "coins": 250 },
	{ "day": 5, "coins": 0, "boosters": { "rainbow": 1 } },
	{ "day": 6, "coins": 400 },
	{ "day": 7, "coins": 600, "boosters": { "lightning": 1, "bomb": 1 } },
]

const CYCLE := 7

## UTC day number (days since the Unix epoch) for a wall-clock time.
static func day_index(unix_time: float) -> int:
	return int(floor(unix_time / 86400.0))

static func today() -> int:
	return day_index(Time.get_unix_time_from_system())

## Given today's day index and the saved streak state, works out what the
## player can claim right now.
##   last_claim_day : day_index of the last claim, or < 0 if never claimed
##   streak         : how many days of the current cycle are already claimed
##                    (0..7); 7 means the cycle is complete
## Returns { claimable: bool, day: int (1..7), reset: bool }
##   day       : the cycle day the CLAIM button would grant (or, if not
##               claimable, the last day already claimed)
##   reset     : true if the previous streak lapsed and this claim restarts
static func claim_state(today_index: int, last_claim_day: int, streak: int) -> Dictionary:
	streak = clampi(streak, 0, CYCLE)
	if last_claim_day < 0:
		return { "claimable": true, "day": 1, "reset": false }
	if today_index <= last_claim_day:
		# Already claimed today (or the clock moved backwards) — nothing yet.
		return { "claimable": false, "day": maxi(streak, 1), "reset": false }
	if today_index == last_claim_day + 1:
		# Consecutive day: advance, wrapping a completed cycle back to day 1.
		if streak >= CYCLE:
			return { "claimable": true, "day": 1, "reset": true }
		return { "claimable": true, "day": streak + 1, "reset": false }
	# Missed one or more days — the streak lapsed.
	return { "claimable": true, "day": 1, "reset": true }

## The streak value to persist after a successful claim of `claimed_day`.
static func streak_after_claim(claimed_day: int) -> int:
	return clampi(claimed_day, 1, CYCLE)

static func reward_for_day(day: int) -> Dictionary:
	var idx := clampi(day, 1, CYCLE) - 1
	return TABLE[idx]
