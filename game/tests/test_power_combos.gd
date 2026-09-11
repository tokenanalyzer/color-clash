extends TestCase
## 2026-09-05 depth pass: power+power combos must have a DISTINCT identity
## per pairing (name, blended tint, both powers' own sounds layered), not
## just a generic "everything amplified" combo — see board_view.gd's
## _combo_pair/_combo_tint/_combo_label and data/power_combos.json.

func _fake_activation(power_id: StringName) -> Dictionary:
	return {"pos": Vector2i.ZERO, "power_id": power_id}

func test_combo_pair_picks_first_two_distinct_power_ids() -> void:
	var activated := [_fake_activation(&"bomb"), _fake_activation(&"lightning"), _fake_activation(&"bomb")]
	var pair := BoardView._combo_pair(activated)
	check_eq("pair size", pair.size(), 2)
	check("first id is bomb", pair[0] == &"bomb")
	check("second id is lightning", pair[1] == &"lightning")

func test_combo_pair_same_power_three_times_reads_as_self_pair() -> void:
	var activated := [_fake_activation(&"rainbow"), _fake_activation(&"rainbow"), _fake_activation(&"rainbow")]
	var pair := BoardView._combo_pair(activated)
	check_eq("pair size", pair.size(), 2)
	check("both slots are rainbow", pair[0] == &"rainbow" and pair[1] == &"rainbow")

func test_every_power_pair_has_a_distinct_label() -> void:
	# Every unordered pair among the 5 real powers must resolve to a real
	# label from data/power_combos.json, not the generic fallback — and no
	# two DIFFERENT pairs should collapse onto the same label (that would
	# defeat the point of a per-pair identity).
	var powers: Array[StringName] = [&"bomb", &"lightning", &"freeze", &"chain", &"rainbow"]
	var board_view := BoardView.new()
	var seen_labels := {}
	for i in powers.size():
		for j in range(i, powers.size()):
			var label := board_view._combo_label(powers[i], powers[j])
			check("pair %s+%s has a real label, not the generic fallback" % [powers[i], powers[j]],
				label != "POWER COMBO!")
			check("label '%s' is unique to this pair" % label, not seen_labels.has(label))
			seen_labels[label] = true
	board_view.free()

func test_combo_label_is_order_independent() -> void:
	var board_view := BoardView.new()
	var a := board_view._combo_label(&"bomb", &"lightning")
	var b := board_view._combo_label(&"lightning", &"bomb")
	check_eq("same label regardless of pair order", a, b)
	board_view.free()

func test_combo_tint_blends_both_powers_and_is_symmetric() -> void:
	var board_view := BoardView.new()
	var t_ab := board_view._combo_tint(&"bomb", &"freeze")
	var t_ba := board_view._combo_tint(&"freeze", &"bomb")
	check("combo tint is symmetric", t_ab.is_equal_approx(t_ba))
	var bomb_tint: Color = BoardView._POW_FX_TINT[&"bomb"]
	var t_same := board_view._combo_tint(&"bomb", &"bomb")
	check("same-power combo tint equals that power's own tint", t_same.is_equal_approx(bomb_tint))
	board_view.free()
