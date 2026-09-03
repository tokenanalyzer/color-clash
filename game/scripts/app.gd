extends Node2D
## Color Clash application entry point and top-level game controller.
## Owns screen flow (Map <-> Play) and, once in Play, level flow (load ->
## play -> win/lose -> next), wiring the board view to the HUD and
## session-scoped systems (combo, fever, objectives, economy, progress).
## Board/HUD/Map are built entirely in code — see board_view.gd, hud.gd,
## level_map.gd — so there is no hand-authored scene file to keep in sync.

## Sized to clear the top HUD panel (nav/score + moves/level/coins + goal
## chips + fever bar) and the bottom booster tray at their current heights
## — see hud.gd. Board layout is fully dynamic (BoardView._fit_layout), so
## these just need to leave it enough room; they don't need to be exact.
const BOARD_TOP_MARGIN := 330.0
const BOARD_BOTTOM_MARGIN := 210.0
## Moves-remaining threshold (with the objective still incomplete) at which
## the music eases into a "tension" mix — a subtle nudge, not a punishment.
const NEAR_FAIL_MOVES := 3
## How long a big-chain "high" music state holds before smoothly settling
## back down if no further move keeps it there (feedback detail #9).
const HIGH_STATE_COOLDOWN := 2.0
const TRANSITION_DURATION := 0.35

var _board: BoardView
var _hud: HUD
var _board_layer: Node2D
var _map: LevelMap

var _current_level: LevelConfig
var _moves_left: int = 0
var _score: int = 0
var _combo := ComboSystem.new()
var _fever: FeverSystem
var _objectives: ObjectiveTracker
var _was_near_fail: bool = false
var _music_token: int = 0

func _ready() -> void:
	randomize()
	_fever = FeverSystem.new(GameData.fever_config)

	var game_canvas := CanvasLayer.new()
	game_canvas.layer = 0
	add_child(game_canvas)
	_hud = HUD.new()
	game_canvas.add_child(_hud)
	_hud.booster_pressed.connect(_on_booster_pressed)
	_hud.next_level_pressed.connect(_on_next_level_pressed)
	_hud.retry_pressed.connect(_on_retry_pressed)
	_hud.map_pressed.connect(_on_map_pressed)

	_board_layer = Node2D.new()
	_board_layer.position = Vector2(0, BOARD_TOP_MARGIN)
	add_child(_board_layer)

	var map_canvas := CanvasLayer.new()
	map_canvas.layer = 10
	add_child(map_canvas)
	_map = LevelMap.new()
	map_canvas.add_child(_map)
	_map.level_selected.connect(_on_level_selected_from_map)

	_hud.visible = false
	_board_layer.visible = false
	_map.visible = true
	_map.modulate.a = 1.0

func _board_rect() -> Rect2:
	var vp_size := get_viewport().get_visible_rect().size
	var height := vp_size.y - BOARD_TOP_MARGIN - BOARD_BOTTOM_MARGIN
	return Rect2(Vector2.ZERO, Vector2(vp_size.x, height))

# --------------------------------------------------------- screen flow --

func _on_map_pressed() -> void:
	await _go_to_map()

func _on_level_selected_from_map(level_id: int) -> void:
	await _go_to_level(level_id)

func _go_to_map() -> void:
	await _fade_out_game(TRANSITION_DURATION)
	_map.refresh()
	await _fade_in(_map, TRANSITION_DURATION)

func _go_to_level(level_id: int) -> void:
	await _fade_out(_map, TRANSITION_DURATION)
	_start_level(level_id)
	await _fade_in_game(TRANSITION_DURATION)

func _fade_out(node: CanvasItem, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 0.0, duration)
	await tween.finished
	node.visible = false

func _fade_in(node: CanvasItem, duration: float) -> void:
	node.modulate.a = 0.0
	node.visible = true
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration)
	await tween.finished

func _fade_out_game(duration: float) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_hud, "modulate:a", 0.0, duration)
	tween.tween_property(_board_layer, "modulate:a", 0.0, duration)
	await tween.finished
	_hud.visible = false
	_board_layer.visible = false

func _fade_in_game(duration: float) -> void:
	_hud.modulate.a = 0.0
	_board_layer.modulate.a = 0.0
	_hud.visible = true
	_board_layer.visible = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_hud, "modulate:a", 1.0, duration)
	tween.tween_property(_board_layer, "modulate:a", 1.0, duration)
	await tween.finished

# -------------------------------------------------------- level session --

func _start_level(level_id: int) -> void:
	_current_level = GameData.levels.get_level(level_id)
	if _current_level == null:
		return

	_score = 0
	_moves_left = _current_level.move_limit
	_combo.reset()
	_fever.reset()
	_was_near_fail = false
	_music_token += 1
	_objectives = ObjectiveTracker.new(_current_level.objectives)

	if _board != null:
		_board.queue_free()
	_board = BoardView.new()
	_board_layer.add_child(_board)
	var rainbow_chance := float(GameData.power_config.get_definition(&"rainbow").get("refill_spawn_chance", 0.0))
	_board.setup(_current_level, GameData.colors, GameData.power_config, rainbow_chance, randi(), _board_rect())
	_board.move_resolved.connect(_on_move_resolved)
	_board.booster_resolved.connect(_on_booster_resolved)

	_hud.hide_end_panel()
	_hud.set_level_info(_current_level)
	_hud.set_moves(_moves_left)
	_hud.set_score(_score)
	_hud.set_coins(Economy.coins)
	_hud.set_objectives(_objectives, _current_level)
	_hud.set_fever(_fever.meter, GameData.fever_config.meter_max, _fever.is_active())
	_refresh_booster_counts()

	Music.start()
	Music.set_state(_compute_music_state(0), true)

func _refresh_booster_counts() -> void:
	_hud.set_booster_counts(Boosters.counts)

func _apply_move_result(result: ChainResolver.MoveResult, counts_as_move: bool) -> void:
	var combo_mult := ScoreCalculator.combo_multiplier_for_depth(result.chain_depth)
	var fever_mult := _fever.score_multiplier()
	var gained := ScoreCalculator.compute_move_score(result, GameData.power_config, combo_mult, fever_mult)
	_score += gained
	_combo.record_move(result.chain_depth)
	var fever_activated := _fever.register_move(result.chain_depth)
	_objectives.apply_move(result.colors_cleared, _score, result.powers_created, result.obstacles_broken)

	if counts_as_move:
		_moves_left = max(_moves_left - 1, 0)

	_hud.set_moves(_moves_left)
	_hud.set_score(_score)
	_hud.set_coins(Economy.coins)
	_hud.set_objectives(_objectives, _current_level)
	_hud.set_fever(_fever.meter, GameData.fever_config.meter_max, _fever.is_active())

	if fever_activated:
		Audio.play(&"fever_activate")
		Haptics.strong(90)

	var near_fail := _moves_left <= NEAR_FAIL_MOVES and not _objectives.is_complete()
	if near_fail and not _was_near_fail:
		Audio.play(&"tension_pulse")
	_was_near_fail = near_fail

	_update_music_state(result.chain_depth, result.cleared_cells.size())

	if _objectives.is_complete():
		_on_level_won()
	elif _moves_left <= 0:
		_on_level_lost()

## `chain_depth` (1 = plain match, 2 = one power created+detonated, 3+ = a
## real multi-stage cascade — see chain_resolver.gd) drives base/active/high;
## `cleared_count` (how many cells this move actually cleared) can also
## promote to "high" on its own, since a Lightning bolt sweeping a whole row
## or a big Bomb blast is a genuinely big moment even at a shallow chain depth.
func _compute_music_state(chain_depth: int, cleared_count: int = 0) -> StringName:
	if _fever.is_active():
		return &"fever"
	if _moves_left <= NEAR_FAIL_MOVES and not _objectives.is_complete():
		return &"tension"
	if chain_depth >= 4 or cleared_count >= 10:
		return &"high"
	if chain_depth >= 2:
		return &"active"
	return &"base"

## Crossfades music to reflect this move's energy, then — for a big-clear
## "high" spike only — smoothly settles back down after a short hold if no
## later move keeps the intensity up (feedback detail #9: resolve tension
## when the chain ends, don't cut it abruptly).
func _update_music_state(chain_depth: int, cleared_count: int = 0) -> void:
	_music_token += 1
	var token := _music_token
	var state := _compute_music_state(chain_depth, cleared_count)
	Music.set_state(state)
	if state == &"high":
		await get_tree().create_timer(HIGH_STATE_COOLDOWN).timeout
		if token == _music_token:
			Music.set_state(_compute_music_state(0))

func _on_move_resolved(result: ChainResolver.MoveResult) -> void:
	_apply_move_result(result, true)

func _on_booster_resolved(result: ChainResolver.MoveResult) -> void:
	_apply_move_result(result, false)

func _on_level_won() -> void:
	Economy.grant(_current_level.reward_coins)
	var stars := StarRating.stars_for(_moves_left, _current_level.move_limit)
	Progress.record_completion(_current_level.id, stars, _score)
	var next_id := GameData.levels.next_level_id(_current_level.id)
	_hud.show_win_panel(_score, _current_level.reward_coins, next_id != -1, stars)
	Music.fade_out_and_stop(0.7)
	Audio.play(&"level_complete")
	Haptics.strong(60)

func _on_level_lost() -> void:
	_hud.show_lose_panel(_score)
	Audio.play(&"level_failed")

func _on_next_level_pressed() -> void:
	var next_id := GameData.levels.next_level_id(_current_level.id)
	if next_id != -1 and Progress.is_unlocked(next_id):
		_start_level(next_id)
	else:
		await _go_to_map()

func _on_retry_pressed() -> void:
	_start_level(_current_level.id)

func _on_booster_pressed(booster_id: StringName) -> void:
	if not Boosters.use(booster_id):
		if not Boosters.purchase(booster_id):
			return
		Boosters.use(booster_id)
	_refresh_booster_counts()
	_hud.set_coins(Economy.coins)

	var def: Dictionary = GameData.boosters.get(booster_id, {})
	match String(def.get("effect", "")):
		"clear_random_cluster":
			_board.apply_power_booster(&"bomb")
		"clear_line":
			_board.apply_power_booster(&"lightning")
		"clear_color":
			_board.apply_power_booster(&"rainbow")
		"shuffle_board":
			_board.request_shuffle()
		"add_moves":
			_moves_left += int(def.get("value", 5))
			_hud.set_moves(_moves_left)
		_:
			pass
