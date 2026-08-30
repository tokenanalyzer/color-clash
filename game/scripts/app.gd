extends Node2D
## Color Clash application entry point and top-level game controller.
## Owns level flow (load -> play -> win/lose -> next) and wires the board
## view to the HUD and session-scoped systems (combo, fever, objectives,
## economy). Board/HUD are built entirely in code — see board_view.gd and
## hud.gd — so there is no hand-authored scene file to keep in sync.

const BOARD_TOP_MARGIN := 220.0
const BOARD_BOTTOM_MARGIN := 170.0

var _board: BoardView
var _hud: HUD
var _board_layer: Node2D

var _current_level: LevelConfig
var _moves_left: int = 0
var _score: int = 0
var _combo := ComboSystem.new()
var _fever: FeverSystem
var _objectives: ObjectiveTracker

func _ready() -> void:
	randomize()
	_fever = FeverSystem.new(GameData.fever_config)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = HUD.new()
	canvas.add_child(_hud)
	_hud.booster_pressed.connect(_on_booster_pressed)
	_hud.next_level_pressed.connect(_on_next_level_pressed)
	_hud.retry_pressed.connect(_on_retry_pressed)

	_board_layer = Node2D.new()
	_board_layer.position = Vector2(0, BOARD_TOP_MARGIN)
	add_child(_board_layer)

	var start_id: int = SaveService.get_int("current_level", GameData.levels.first_level_id())
	if not GameData.levels.has_level(start_id):
		start_id = GameData.levels.first_level_id()
	_start_level(start_id)

func _board_rect() -> Rect2:
	var vp_size := get_viewport().get_visible_rect().size
	var height := vp_size.y - BOARD_TOP_MARGIN - BOARD_BOTTOM_MARGIN
	return Rect2(Vector2.ZERO, Vector2(vp_size.x, height))

func _start_level(level_id: int) -> void:
	_current_level = GameData.levels.get_level(level_id)
	if _current_level == null:
		return
	SaveService.set_int("current_level", level_id)
	SaveService.save()

	_score = 0
	_moves_left = _current_level.move_limit
	_combo.reset()
	_fever.reset()
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
	_hud.set_coins(Economy.coins)
	_hud.set_objectives(_objectives, _current_level)
	_hud.set_fever(_fever.meter, GameData.fever_config.meter_max, _fever.is_active())
	_refresh_booster_counts()

func _refresh_booster_counts() -> void:
	_hud.set_booster_counts(Boosters.counts)

func _apply_move_result(result: ChainResolver.MoveResult, counts_as_move: bool) -> void:
	var combo_mult := ScoreCalculator.combo_multiplier_for_depth(result.chain_depth)
	var fever_mult := _fever.score_multiplier()
	var gained := ScoreCalculator.compute_move_score(result, GameData.power_config, combo_mult, fever_mult)
	_score += gained
	_combo.record_move(result.chain_depth)
	_fever.register_move(result.chain_depth)
	_objectives.apply_move(result.colors_cleared, _score, result.powers_created, result.obstacles_broken)

	if counts_as_move:
		_moves_left = max(_moves_left - 1, 0)

	_hud.set_moves(_moves_left)
	_hud.set_coins(Economy.coins)
	_hud.set_objectives(_objectives, _current_level)
	_hud.set_fever(_fever.meter, GameData.fever_config.meter_max, _fever.is_active())

	if _objectives.is_complete():
		_on_level_won()
	elif _moves_left <= 0:
		_on_level_lost()

func _on_move_resolved(result: ChainResolver.MoveResult) -> void:
	_apply_move_result(result, true)

func _on_booster_resolved(result: ChainResolver.MoveResult) -> void:
	_apply_move_result(result, false)

func _on_level_won() -> void:
	Economy.grant(_current_level.reward_coins)
	var next_id := GameData.levels.next_level_id(_current_level.id)
	_hud.show_win_panel(_score, _current_level.reward_coins, next_id != -1)

func _on_level_lost() -> void:
	_hud.show_lose_panel(_score)

func _on_next_level_pressed() -> void:
	var next_id := GameData.levels.next_level_id(_current_level.id)
	_start_level(next_id if next_id != -1 else GameData.levels.first_level_id())

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
