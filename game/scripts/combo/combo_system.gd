class_name ComboSystem
extends RefCounted
## Tracks combo statistics across a level session. "Combo" is the chain
## depth of a single resolved move — how many power waves cascaded from it.

var last_combo: int = 0
var best_combo: int = 0
var total_chain_moves: int = 0 # moves where more than one wave triggered

func record_move(chain_depth: int) -> void:
	last_combo = chain_depth
	best_combo = max(best_combo, chain_depth)
	if chain_depth > 1:
		total_chain_moves += 1

func reset() -> void:
	last_combo = 0
	best_combo = 0
	total_chain_moves = 0
