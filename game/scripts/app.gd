extends Node2D
## Color Clash application entry point and top-level game controller.
## Owns screen flow (Map <-> Play) and, once in Play, level flow (load ->
## play -> win/lose -> next), wiring the board view to the HUD and
## session-scoped systems (combo, fever, objectives, economy, progress).
## Board/HUD/Map are built entirely in code — see board_view.gd, hud.gd,
## level_map.gd — so there is no hand-authored scene file to keep in sync.

## The playfield's top/bottom bounds are owned by the HUD (`playfield_top()`
## / `playfield_bottom()`), which measures its own built chrome and folds in
## the device safe-area — so the board fills the screen on any aspect ratio
## and never slides under the top bar or the booster tray.
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
var _menu: MainMenu
var _splash: SplashScreen

var _current_level: LevelConfig
var _moves_left: int = 0
var _score: int = 0
var _combo := ComboSystem.new()
var _fever: FeverSystem
var _objectives: ObjectiveTracker
var _was_near_fail: bool = false
var _was_fever: bool = false
var _armed_booster: StringName = &""
var _music_token: int = 0

var _backdrop: Backdrop
var _daily: DailyRewardsScreen
var _jasmine: JasmineActor              # Jasmine's dynamic battlefield presence
var _jamie_rig: JamieRig               # Jamie's combat presence (Phase C)
var _enemy_actor: EnemyActor           # active villain in the combat arena
var _power_fired_this_move := false
var _story_scene: StoryScene
var _intro_video: IntroVideoScreen
var _combat: CombatDirector
var _level_ended := false
var _inventory: InventoryScreen

## Debug-only rolling FPS sampler — printed to the Android log so on-device
## performance can be verified without a profiler build. Stripped in release.
var _fps_accum := 0.0
var _fps_min := 999.0
var _fps_frames := 0

func _ready() -> void:
	randomize()
	_fever = FeverSystem.new(GameData.fever_config)
	if OS.is_debug_build():
		set_process(true)

	_backdrop = Backdrop.new()
	_backdrop.scene_id = &"env_main_background"
	add_child(_backdrop)

	var game_canvas := CanvasLayer.new()
	game_canvas.layer = 0
	add_child(game_canvas)
	_hud = HUD.new()
	game_canvas.add_child(_hud)
	get_viewport().size_changed.connect(_relayout_board)
	_hud.booster_pressed.connect(_on_booster_pressed)
	_hud.next_level_pressed.connect(_on_next_level_pressed)
	_hud.retry_pressed.connect(_on_retry_pressed)
	_hud.map_pressed.connect(_on_map_pressed)
	_hud.pause_pressed.connect(_on_pause_pressed)
	_hud.resume_pressed.connect(_on_resume_pressed)
	_hud.shop_pressed.connect(_on_shop_pressed)
	_hud.shop_closed.connect(_on_shop_closed)
	_hud.shop_use_booster.connect(_on_shop_use_booster)
	_hud.continue_bought.connect(_on_continue_bought)
	_hud.continue_declined.connect(_on_continue_declined)

	_board_layer = Node2D.new()
	_board_layer.position = Vector2(0, _hud.playfield_top())
	add_child(_board_layer)

	# --- Character combat arena (Phase C): a dedicated band between the board
	# and the booster tray holding three real characters, drawn back-to-front
	# Jasmine -> enemy -> Jamie so Jamie reads on top during a dash. ---

	# Jasmine — battlefield support. Her pose/expression tracks the real
	# story/gameplay state (captured, scared, worried, hopeful, cheering,
	# victory, rescued, ...) via Cast.jasmine_state() — never one
	# permanently-happy portrait. See _set_jasmine_state().
	_jasmine = JasmineActor.new()
	game_canvas.add_child(_jasmine)

	# The active villain — chapter minor villain on normal stages, the boss
	# on every 10th. Flinches / knocks back when Jamie's rig lands a hit.
	_enemy_actor = EnemyActor.new()
	game_canvas.add_child(_enemy_actor)

	# Jamie — the combat lead. Renders the clean supplied portrait at
	# gameplay scale and animates it through real windup -> lunge ->
	# projectile -> impact -> recover phases. Presentation only;
	# CombatDirector still owns every number.
	_jamie_rig = JamieRig.new()
	game_canvas.add_child(_jamie_rig)
	_jamie_rig.enemy_reaction.connect(_on_jamie_enemy_reaction)
	_jamie_rig.shake_requested.connect(func(mag: float):
		if _board != null:
			ScreenShake.apply(_board, mag, 0.3))
	_relayout_arena()

	var map_canvas := CanvasLayer.new()
	map_canvas.layer = 10
	add_child(map_canvas)
	_map = LevelMap.new()
	map_canvas.add_child(_map)
	_map.level_selected.connect(_on_level_selected_from_map)
	_map.home_pressed.connect(_on_home_pressed)

	var menu_canvas := CanvasLayer.new()
	menu_canvas.layer = 20
	add_child(menu_canvas)
	_menu = MainMenu.new()
	menu_canvas.add_child(_menu)
	_menu.play_pressed.connect(_on_menu_play_pressed)
	_menu.daily_pressed.connect(_on_daily_pressed)
	_menu.inventory_pressed.connect(func(): _inventory.open())

	var daily_canvas := CanvasLayer.new()
	daily_canvas.layer = 30
	add_child(daily_canvas)
	_daily = DailyRewardsScreen.new()
	daily_canvas.add_child(_daily)
	_daily.closed.connect(_on_daily_closed)
	_daily.visible = false

	var inv_canvas := CanvasLayer.new()
	inv_canvas.layer = 35
	add_child(inv_canvas)
	_inventory = InventoryScreen.new()
	inv_canvas.add_child(_inventory)
	_inventory.closed.connect(func(): _menu.refresh())

	var story_canvas := CanvasLayer.new()
	story_canvas.layer = 90
	add_child(story_canvas)
	_story_scene = StoryScene.new()
	story_canvas.add_child(_story_scene)
	_intro_video = IntroVideoScreen.new()
	_intro_video.visible = false
	story_canvas.add_child(_intro_video)

	var splash_canvas := CanvasLayer.new()
	splash_canvas.layer = 100
	add_child(splash_canvas)
	_splash = SplashScreen.new()
	splash_canvas.add_child(_splash)
	_splash.finished.connect(_on_splash_finished)

	_hud.visible = false
	_board_layer.visible = false
	_jasmine.visible = false
	_jamie_rig.visible = false
	_enemy_actor.visible = false
	_map.visible = false
	_menu.visible = true
	_menu.modulate.a = 1.0

func _process(delta: float) -> void:
	# debug FPS sampler only (set_process is off in release builds)
	_fps_accum += delta
	_fps_frames += 1
	var fps := Engine.get_frames_per_second()
	if fps > 0.0 and fps < _fps_min:
		_fps_min = fps
	if _fps_accum >= 2.0:
		print("[FPS] avg~%.0f  min_2s=%.0f" % [float(_fps_frames) / _fps_accum, _fps_min])
		_fps_accum = 0.0
		_fps_frames = 0
		_fps_min = 999.0

func _board_rect() -> Rect2:
	var vp_size := get_viewport().get_visible_rect().size
	# The playable band is whatever's left between the top HUD column and the
	# booster tray — the HUD is the single source of truth for both so the
	# board fills the screen on any aspect ratio instead of leaving dead bands.
	var top := _hud.playfield_top()
	var bottom := _hud.playfield_bottom()
	var height := maxf(vp_size.y - top - bottom, vp_size.x * 0.6)
	return Rect2(Vector2.ZERO, Vector2(vp_size.x, height))

## Reposition the board layer + re-fit the board when the viewport/orientation
## changes (portrait aspect-ratio adaptation).
func _relayout_board() -> void:
	_board_layer.position = Vector2(0, _hud.playfield_top())
	if _board != null and _current_level != null:
		_board.refit(_board_rect())
	_relayout_arena()

## Lay the three characters out in the HUD's combat-arena band: Jamie on the
## left, the villain on the right (facing each other), Jasmine set back
## between them. All stand on `arena_floor_y()`; nothing overlaps the board.
func _relayout_arena() -> void:
	if _hud == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var floor_y := _hud.arena_floor_y()
	var band := _hud.ARENA_HEIGHT
	var jamie_h := band * 0.88
	var enemy_h := band * 0.86
	var jas_h := band * 0.66

	var enemy_torso := Vector2(vp.x * 0.80, floor_y - enemy_h * 0.55)
	if _enemy_actor != null:
		enemy_torso = _enemy_actor.configure(_current_level.id if _current_level != null else 1,
			vp.x - 12.0, floor_y, enemy_h)

	if _jamie_rig != null:
		# Jamie's portrait has his flaming sword right at the frame's left
		# edge, so keep a small left margin.
		_jamie_rig.configure(vp.x * 0.02 + 8.0, floor_y, jamie_h, enemy_torso)

	if _jasmine != null:
		# set back + between the two fighters, feet a touch higher than the
		# floor so she reads as further upstage; her exact x drifts with her
		# current state (see JasmineActor._BIAS).
		_jasmine.configure(vp.x * 0.44, floor_y - band * 0.06, jas_h, vp.x * 0.5)

# --------------------------------------------------------- screen flow --

func _on_splash_finished() -> void:
	# SplashScreen frees itself; the menu is already the visible screen.
	Music.play_ambient(&"music_menu_theme")

func _on_menu_play_pressed() -> void:
	_menu.refresh()
	await _fade_out(_menu, TRANSITION_DURATION)
	_map.refresh()
	await _fade_in(_map, TRANSITION_DURATION)

func _on_home_pressed() -> void:
	await _fade_out(_map, TRANSITION_DURATION)
	_menu.refresh()
	await _fade_in(_menu, TRANSITION_DURATION)
	Music.play_ambient(&"music_menu_theme")

func _on_daily_pressed() -> void:
	_daily.refresh()
	await _fade_in(_daily, TRANSITION_DURATION)
	_daily.play_entrance()

func _on_daily_closed() -> void:
	await _fade_out(_daily, TRANSITION_DURATION)
	_menu.refresh()

func _on_map_pressed() -> void:
	await _go_to_map()

func _on_level_selected_from_map(level_id: int) -> void:
	await _go_to_level(level_id)

func _go_to_map() -> void:
	Music.stop_ambient()
	await _fade_out_game(TRANSITION_DURATION)
	_map.refresh()
	await _fade_in(_map, TRANSITION_DURATION)
	Music.play_ambient(&"music_menu_theme")

func _go_to_level(level_id: int) -> void:
	await _fade_out(_map, TRANSITION_DURATION)
	Music.stop_ambient()
	await _play_pre_level_story(level_id)
	_start_level(level_id)
	await _fade_in_game(TRANSITION_DURATION)

## Story beats that belong BEFORE a stage: the opening kidnapping cinematic
## (once, on the very first campaign stage), a chapter card on the first
## stage of an island, and any boss-intro beat. Each is played at most once
## (Story records it via SaveService).
func _play_pre_level_story(level_id: int) -> void:
	var ids: Array = GameData.levels.ordered_ids
	var first_id: int = ids[0] if not ids.is_empty() else -1
	if level_id == first_id:
		await _play_campaign_intro()
	if IslandModel.island_index_for_level(level_id) >= 0 \
			and level_id == IslandModel.level_ids_for_island(IslandModel.island_index_for_level(level_id))[0]:
		await _play_beat(Story.beat_for(Story.island_start_trigger(IslandModel.island_index_for_level(level_id))))
	await _play_beat(Story.beat_for(Story.stage_start_trigger(level_id)))

## The real intro video (2026-09-05) replaces the old code-driven "opening"
## StoryScene beat — same one-time-only contract (Story.mark_seen), same
## trigger. Falls back to the original StoryScene beat if the transcoded
## video asset isn't present (e.g. a future export target without it), so
## there's never a blank/broken screen and never two competing intros.
func _play_campaign_intro() -> void:
	if not Story.has_pending("campaign_start"):
		return
	if IntroVideoScreen.asset_available():
		_intro_video.play()
		await _intro_video.finished
		Story.mark_seen("opening")
	else:
		await _play_beat(Story.beat_for("campaign_start"))

## Plays a story beat overlay and blocks until it is dismissed. No-op for {}.
func _play_beat(beat: Dictionary) -> void:
	if beat.is_empty() or _story_scene == null:
		return
	_story_scene.play(beat)
	await _story_scene.finished
	Story.mark_seen(String(beat.get("id", "")))

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
	_jasmine.visible = false
	_jamie_rig.visible = false
	_enemy_actor.visible = false

func _fade_in_game(duration: float) -> void:
	_hud.modulate.a = 0.0
	_board_layer.modulate.a = 0.0
	_hud.visible = true
	_board_layer.visible = true
	_jasmine.modulate.a = 0.0
	_jasmine.visible = true
	_jamie_rig.modulate.a = 0.0
	_jamie_rig.visible = true
	_enemy_actor.modulate.a = 0.0
	_enemy_actor.visible = true
	_relayout_arena()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_hud, "modulate:a", 1.0, duration)
	tween.tween_property(_board_layer, "modulate:a", 1.0, duration)
	tween.tween_property(_jasmine, "modulate:a", 1.0, duration)
	tween.tween_property(_jamie_rig, "modulate:a", 1.0, duration)
	tween.tween_property(_enemy_actor, "modulate:a", 1.0, duration)
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
	_was_fever = false
	_armed_booster = &""
	_backdrop.set_accent_target(VisualTheme.ACCENT, 0.2)
	_backdrop.set_scene_for_level(_current_level.id)
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
	_board.booster_committed.connect(_on_booster_committed)
	_board.booster_disarmed.connect(func(): _hud.set_booster_armed(&""))
	_board.board_shuffled.connect(func(): GameEvents.publish_type(EngineEvent.BOARD_SHUFFLED, {}))
	_hud.set_booster_armed(&"")

	_hud.hide_end_panel()
	_hud.set_level_info(_current_level)
	_hud.set_moves(_moves_left)
	_hud.set_coins(Economy.coins)
	_hud.set_score(_score)
	_hud.set_objectives(_objectives, _current_level)
	_hud.set_fever(_fever.meter, GameData.fever_config.meter_max, _fever.is_active())
	_refresh_booster_counts()

	# --- character combat: Jamie powers always; a boss on every 10th stage ---
	_level_ended = false
	_moves_since_boss_hit = 0
	_combat = CombatDirector.new(_current_level.id)
	_combat.meters_changed.connect(_hud.set_power_meters)
	_combat.power_fired.connect(_on_power_fired)
	_combat.jamie_attack.connect(_on_jamie_attack)
	_combat.boss_damaged.connect(func(_amt, hp, mx): _hud.set_boss_hp(hp, mx))
	_combat.boss_defeated.connect(_on_boss_defeated)
	_combat.boss_attacked.connect(_on_boss_attacked)
	_hud.set_power_meters(_combat.powers.meter)
	if _combat.is_boss:
		_hud.begin_boss(_combat.boss_name, _combat.boss_face(), _combat.is_final_boss())
	else:
		_hud.end_boss()

	# Continuous real gameplay track (2026-09-05) replaces the old sparse
	# synth loop. play_ambient() no-ops if it's already playing (retry /
	# next-level keep the same music going, never restarting mid-track).
	Music.play_ambient(&"music_gameplay_theme")

	_relayout_arena()
	if _jasmine != null:
		# Danger reads on her face before a single move is made: the final
		# boss stage IS the moment she's held captive; other boss stages are
		# just tense; normal stages she's rooting for Jamie.
		if _combat != null and _combat.is_final_boss():
			_jasmine.set_state(&"captured", false)
		elif _combat != null and _combat.is_boss:
			_jasmine.set_state(&"scared", false)
		else:
			_jasmine.set_state(&"determined", false)
	if _jamie_rig != null:
		_jamie_rig.reset_to_idle()
	GameEvents.publish_type(EngineEvent.LEVEL_STARTED, {
		"level_id": _current_level.id,
		"name": _current_level.level_name,
	})
	_publish_session_state(0, false)

## Villain reaction (2026-09-05): a visible weakened tint that deepens as
## the stage's objectives progress, so completing them reads as "wearing the
## villain down" rather than being purely a board-side checklist. Independent
## of EnemyActor.play_hit()'s transient white flash.
func _update_villain_weakened_tint() -> void:
	if _enemy_actor == null or _objectives == null or _objectives.objectives.is_empty():
		return
	var total_progress := 0.0
	var total_target := 0.0
	for i in _objectives.objectives.size():
		total_progress += float(_objectives.progress[i])
		total_target += float(_objectives.target_for(i))
	if total_target > 0.0:
		_enemy_actor.set_weakened(total_progress / total_target)

func _refresh_booster_counts() -> void:
	_hud.set_booster_counts(Boosters.counts)

## Publishes the session-level events (score / moves / combo / fever /
## objective progress) that the per-move translator can't know about because
## they depend on running session state, not just one MoveResult. Consumers
## get one coherent snapshot after every move and at level start.
func _publish_session_state(score_gained: int = 0, fever_just_activated: bool = false) -> void:
	GameEvents.publish_type(EngineEvent.SCORE_CHANGED, {"score": _score, "gained": score_gained})
	GameEvents.publish_type(EngineEvent.MOVES_CHANGED, {
		"moves_left": _moves_left, "move_limit": _current_level.move_limit,
	})
	GameEvents.publish_type(EngineEvent.COMBO_CHANGED, {
		"combo": _combo.last_combo, "best": _combo.best_combo,
	})
	GameEvents.publish_type(EngineEvent.FEVER_CHANGED, {
		"meter": _fever.meter, "meter_max": GameData.fever_config.meter_max,
		"active": _fever.is_active(), "just_activated": fever_just_activated,
	})
	if _objectives != null:
		for i in _current_level.objectives.size():
			var obj: Dictionary = _current_level.objectives[i]
			var tgt := _objectives.target_for(i)
			GameEvents.publish_type(EngineEvent.OBJECTIVE_PROGRESS, {
				"index": i, "value": _objectives.progress[i], "target": tgt,
				"type": String(obj.get("type", "")),
				"complete": _objectives.progress[i] >= tgt,
			})

func _apply_move_result(result: ChainResolver.MoveResult, counts_as_move: bool) -> void:
	var combo_mult := ScoreCalculator.combo_multiplier_for_depth(result.chain_depth)
	var fever_mult := _fever.score_multiplier()
	var gained := ScoreCalculator.compute_move_score(result, GameData.power_config, combo_mult, fever_mult)
	_score += gained
	_combo.record_move(result.chain_depth)
	var fever_activated := _fever.register_move(result.chain_depth)
	_objectives.apply_move(result.colors_cleared, _score, result.powers_created, result.obstacles_broken)
	_update_villain_weakened_tint()

	if counts_as_move:
		_moves_left = max(_moves_left - 1 - result.move_penalty, 0)

	_hud.set_moves(_moves_left)
	_hud.set_coins(Economy.coins)
	_hud.set_score(_score)
	_hud.set_objectives(_objectives, _current_level)
	_hud.set_fever(_fever.meter, GameData.fever_config.meter_max, _fever.is_active())

	# --- Fever spectacle: drive the board aura, backdrop tint, HUD flash and
	# an ignition burst off the real FeverSystem state transition ---
	var fever_now := _fever.is_active()
	if fever_now != _was_fever:
		_was_fever = fever_now
		_board.set_fever(fever_now)
		_backdrop.set_accent_target(VisualTheme.FEVER_HOT if fever_now else VisualTheme.ACCENT)
		if fever_now:
			_hud.flash_fever()
			_board.play_fever_burst()
			# Jamie's multi-power ultimate cinematic (short, non-blocking).
			if _jamie_rig != null:
				_jamie_rig.play(&"fever_ultimate")
			if _jasmine != null:
				_jasmine.set_state(&"cheering")

	if fever_activated:
		Audio.play(&"fever_activate")
		Haptics.strong(90)

	if not result.timebomb_explosions.is_empty():
		Audio.play(&"tension_pulse")

	var near_fail := _moves_left <= NEAR_FAIL_MOVES and not _objectives.is_complete()
	if near_fail and not _was_near_fail:
		Audio.play(&"tension_pulse")
		if _jasmine != null:
			_jasmine.set_state(&"worried")
	_was_near_fail = near_fail

	# --- typed event stream for this move (additive — the direct
	# board_view -> app signal wiring above is untouched) ---
	var move_kind := "match" if counts_as_move else "booster"
	GameEvents.publish_all(MoveEventTranslator.events_for_move(result, {"kind": move_kind}))
	_publish_session_state(gained, fever_activated)

	# --- match-3 -> character combat: turn this move into Jamie attack
	# energy + boss damage. boss_defeated fires _on_boss_defeated -> win. ---
	_power_fired_this_move = false
	if _combat != null:
		_combat.feed_move(result, result.chain_depth, result.cleared_cells.size(), counts_as_move, _moves_left)
	if _combat != null and _combat.is_boss and counts_as_move:
		_update_boss_pressure()
	# A move that broke an obstacle but didn't otherwise trigger Jamie's rig
	# (no power fired, no big plain hit) still gets a small villain flinch —
	# obstacle/objective progress should read as "hurting" the villain too,
	# not just plain matches. is_busy() guards against double-flinching a
	# move that already triggered a jamie_rig reaction through another path.
	if _enemy_actor != null and not result.obstacles_broken.is_empty() \
			and not _power_fired_this_move and (_jamie_rig == null or not _jamie_rig.is_busy()):
		_enemy_actor.play_hit(&"hit")

	_update_music_state(result.chain_depth, result.cleared_cells.size())

	if _level_ended:
		return
	if _objectives.is_complete():
		if _combat != null and _combat.is_boss:
			_check_boss_win_or_flourish()
		else:
			_on_level_won()
	elif _moves_left <= 0:
		_offer_more_moves_or_lose()

## Boss-stage pressure (2026-09-05): a boss stage isn't just a normal level
## with a health bar — every BOSS_PRESSURE_MOVES real moves while the boss
## is still alive, it counter-attacks the board with a temporary obstacle
## (reuses the ordinary ice-family plumbing; never strands the player — see
## BoardView.boss_obstruct_random_cell). A flat per-move cadence rather than
## "moves without damage": CombatDirector's base attack damage is never
## zero, so a no-damage trigger would in practice never fire.
const BOSS_PRESSURE_MOVES := 4
var _moves_since_boss_hit := 0

func _update_boss_pressure() -> void:
	if _combat.boss_hp <= 0:
		_moves_since_boss_hit = 0
		return
	_moves_since_boss_hit += 1
	if _moves_since_boss_hit < BOSS_PRESSURE_MOVES:
		return
	_moves_since_boss_hit = 0
	if _board != null and _board.boss_obstruct_random_cell(&"ice", 2):
		Audio.play(&"tension_pulse")
		Haptics.strong(60)
		if _jasmine != null:
			_jasmine.set_state(&"worried")

## Boss stages require BOTH the boss defeated (hp 0) AND the stage's own
## objectives complete — previously either one alone ended the level, which
## meant a boss fight could be skipped entirely by just hitting a score/color
## goal. Called both right when the boss dies (objectives may already be
## done) and from the objectives-complete check (boss may already be dead).
func _check_boss_win_or_flourish() -> void:
	if _level_ended:
		return
	if _combat == null or not _combat.is_boss or _combat.boss_hp > 0:
		return
	if _objectives == null or not _objectives.is_complete():
		return
	if _jamie_rig != null:
		_jamie_rig.play(&"victory")
	if _jasmine != null:
		_jasmine.set_state(&"rescued" if _combat.is_final_boss() else &"victory")
	_on_level_won()

## `chain_depth` (1 = plain match, 2 = one power created+detonated, 3+ = a
## real multi-stage cascade — see chain_resolver.gd) drives base/active/high;
## `cleared_count` (how many cells this move actually cleared) can also
## promote to "high" on its own, since a Lightning bolt sweeping a whole row
## or a big Bomb blast is a genuinely big moment even at a shallow chain depth.
func _compute_music_state(chain_depth: int, cleared_count: int = 0) -> StringName:
	if _fever.is_active():
		return &"fever"
	# boss stages get their own dark, driving mix (Jinn = the biggest)
	if _combat != null and _combat.is_boss:
		return &"final_boss" if _combat.is_final_boss() else &"boss"
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

# ----------------------------------------------------- character combat --

## CombatDirector's base attack for a move. Powers/combos are handled by
## `_on_power_fired` (which sets `_power_fired_this_move`); this drives Jamie's
## rig only for a plain match with no power, and only when the match was
## sizeable — so ordinary matching stays snappy and un-busy.
func _on_jamie_attack(kind: StringName, damage: int, big: bool) -> void:
	if _board == null:
		return
	if kind == &"ultimate":
		ScreenShake.apply(_board, 22.0, 0.5)
		Haptics.strong(120)
		_board.play_fever_burst()
		Audio.play(&"power_up", 1.0)
	elif big:
		ScreenShake.apply(_board, 12.0, 0.34)
		Haptics.strong(80)
	elif damage >= 4:
		ScreenShake.apply(_board, 5.0, 0.18)
	if _jamie_rig != null and not _power_fired_this_move and kind == &"basic" and damage >= 3:
		_jamie_rig.play(&"attack_sword")

func _on_power_fired(power: StringName, combo: StringName) -> void:
	_power_fired_this_move = true
	var id := combo if combo != &"" else power
	_hud.flash_power(id)
	match String(id):
		"fire_sword": Audio.play(&"sword_attack")
		"lightning_hand", "lightning_dash": Audio.play(&"lightning")
		"lightning_boots", "dash_slash": Audio.play(&"lightning", 0.4)
		"lightning_sword": Audio.play(&"sword_attack", 0.9)
		"ultimate": Audio.play(&"power_up", 1.0)
	if _jamie_rig != null:
		_jamie_rig.play(_rig_action_for_power(id))
	# Reserve the cheer for the genuinely special moment (Ultimate) — routine
	# power fires leave her current state (e.g. scared in a boss fight) alone.
	if _jasmine != null and String(id) == "ultimate":
		_jasmine.set_state(&"cheering")

## Power / combo id -> Jamie rig action (data/jamie_actions.json).
func _rig_action_for_power(id: StringName) -> StringName:
	match String(id):
		"fire_sword": return &"attack_sword"
		"lightning_hand": return &"attack_lightning"
		"lightning_boots": return &"attack_dash"
		"lightning_sword": return &"attack_blast"
		"dash_slash": return &"attack_dash"
		"lightning_dash": return &"attack_blast"
		"ultimate": return &"fever_ultimate"
	return &"attack_sword"

func _on_boss_attacked() -> void:
	if _board != null:
		ScreenShake.apply(_board, 14.0, 0.4)
	Haptics.strong(90)
	Audio.play(&"boss_impact")
	if _jamie_rig != null:
		_jamie_rig.play(&"hurt")
	if _combat != null and _combat.is_final_boss():
		_hud.boss_taunt()
	if _jasmine != null:
		_jasmine.set_state(&"scared")

func _on_boss_defeated() -> void:
	if _level_ended:
		return
	_hud.boss_defeat_anim()
	Audio.play(&"boss_impact", 1.0)
	if _board != null:
		ScreenShake.apply(_board, 18.0, 0.5)
	if _enemy_actor != null:
		_enemy_actor.play_defeat()
	# Only the actual chapter win (Jamie's victory pose, Jasmine
	# rescued/cheering) plays here if the stage's other objectives are
	# ALREADY done too — otherwise the board stays live (CombatDirector
	# no-ops further boss damage once hp is 0) until they are, and
	# _check_boss_win_or_flourish() fires the same flourish from
	# _apply_move_result once they complete.
	_check_boss_win_or_flourish()

## Jamie's rig reports a landed hit — drive the boss reaction (boss stages)
## from it. Damage numbers were already applied by CombatDirector; this is
## pure presentation and cannot desync them.
func _on_jamie_enemy_reaction(kind: StringName, _pos: Vector2) -> void:
	if kind == &"none":
		return
	if _enemy_actor != null:
		_enemy_actor.play_hit(kind)
	if _combat != null and _combat.is_boss and _combat.boss_hp > 0:
		_hud.boss_hit(kind)

func _on_level_won() -> void:
	if _level_ended:
		return
	_level_ended = true
	var first_clear := not Progress.is_completed(_current_level.id)
	Economy.grant(_current_level.reward_coins)
	# Per-level score thresholds are the primary star rule; StarRating falls
	# back to move-efficiency when a level defines no `star_scores`.
	var stars := StarRating.stars_for_score(_score, _current_level.star_scores, _moves_left, _current_level.move_limit)
	Progress.record_completion(_current_level.id, stars, _score)
	var next_id := GameData.levels.next_level_id(_current_level.id)
	GameEvents.publish_type(EngineEvent.LEVEL_COMPLETED, {
		"level_id": _current_level.id, "score": _score, "stars": stars,
	})
	Music.fade_out_and_stop(0.7)
	Music.stop_ambient(0.7)
	Audio.play(&"level_complete")
	if _combat != null and _combat.is_boss:
		Audio.play(&"boss_impact", 1.0)
		if not _combat.is_final_boss():
			var isl := IslandModel.island_index_for_level(_current_level.id)
			if isl >= 0:
				UiKit.show_toast(_hud, "CHAPTER COMPLETE — %s" % IslandModel.island_name(isl).to_upper(), VisualTheme.STAR)
	Haptics.strong(60)
	if _board != null:
		_board.set_fever(false)
		_board.play_win_flourish()
	_backdrop.set_accent_target(VisualTheme.ACCENT)
	# Boss wins already set a more specific state (rescued / victory) in
	# _on_boss_defeated before calling this — only a plain stage clear needs
	# it here.
	if _jasmine != null and (_combat == null or not _combat.is_boss):
		_jasmine.set_state(&"cheering")

	# Boss stage (every 10th) — grant the boss's equipment drop + a shard,
	# then let the story beat (stage_complete:N) carry the chapter transition.
	if first_clear and _combat != null and _combat.is_boss:
		var new_equip := Inventory.grant_boss_reward(_current_level.id)
		if new_equip != "":
			UiKit.show_toast(_hud, "NEW EQUIPMENT — %s" % new_equip.to_upper(), VisualTheme.GEM)

	# Every 5th level is a "chest" node on the map — the first time it's
	# cleared, open a milestone chest before the normal summary.
	if first_clear and _current_level.id % 5 == 0:
		await _present_milestone_chest()

	# Story beat that belongs AFTER a stage (boss defeat, chapter close,
	# finale) — plays once, before the win summary.
	await _play_beat(Story.beat_for(Story.stage_complete_trigger(_current_level.id)))

	_hud.show_win_panel(_score, _current_level.reward_coins, next_id != -1, stars)

func _present_milestone_chest() -> void:
	var bonus_coins := _current_level.reward_coins * 2
	var pool: Array[StringName] = [&"bomb", &"lightning", &"rainbow"]
	var bid: StringName = pool[(_current_level.id / 5) % pool.size()]
	var rewards := [
		{"type": "coins", "amount": bonus_coins},
		{"type": "booster", "id": bid, "amount": 1},
	]
	var popup := RewardPopup.present(_hud, rewards, {"title": "Milestone Chest!", "chest": "booster"})
	await popup.claimed
	Economy.grant(bonus_coins)
	Boosters.add(bid, 1)
	_hud.set_coins(Economy.coins)
	_refresh_booster_counts()

## Out of moves with the objective unfinished — offer the "Need More Moves?"
## continue before failing. The board is frozen; NOTHING about the level
## state (board, objectives, enemy/boss HP, Jamie meters) changes while the
## prompt is up, and buying resumes the SAME level — `_start_level` is never
## re-run.
func _offer_more_moves_or_lose() -> void:
	if _level_ended:
		return
	if _board != null:
		_board.disarm_booster()
		_board.set_input_locked(true)
	_armed_booster = &""
	_hud.set_booster_armed(&"")
	Music.set_state(&"tension")
	_hud.open_moves_prompt()

func _on_continue_bought(moves_added: int) -> void:
	if _level_ended:
		return
	_moves_left += moves_added
	_hud.set_moves(_moves_left)
	_hud.set_coins(Economy.coins)
	if _board != null:
		_board.set_input_locked(false)
	Music.set_state(_compute_music_state(0))
	_was_near_fail = false
	_publish_session_state()

func _on_continue_declined() -> void:
	if _level_ended:
		return
	_on_level_lost()

# ------------------------------------------------ in-level booster shop --

## Booster shop opened from the HUD. Freeze the board (existing pause path)
## so no move is consumed and no board / objective / enemy / boss / power
## state changes while the shop is open.
func _on_shop_pressed(focus_id: StringName = &"") -> void:
	if _current_level == null or _level_ended or _board == null:
		return
	if _hud.any_modal_open():
		return
	_board.disarm_booster()
	_board.set_input_locked(true)
	_armed_booster = &""
	_hud.set_booster_armed(&"")
	Music.set_state(&"tension")
	_hud.open_shop(focus_id)

func _on_shop_closed() -> void:
	if _board != null and not _level_ended:
		_board.set_input_locked(false)
	if not _level_ended and _current_level != null:
		Music.set_state(_compute_music_state(0))

## USE pressed in the shop — route straight into the existing booster
## pipeline so the real board -> CombatDirector -> Jamie/boss chain runs
## (targeted boosters arm for a board tap, instant ones fire now).
func _on_shop_use_booster(booster_id: StringName) -> void:
	if _board == null or _level_ended:
		return
	_board.set_input_locked(false)
	_refresh_booster_counts()
	_on_booster_pressed(booster_id)

func _on_level_lost() -> void:
	if _level_ended:
		return
	_level_ended = true
	_hud.show_lose_panel(_score)
	Audio.play(&"level_failed")
	GameEvents.publish_type(EngineEvent.LEVEL_FAILED, {
		"level_id": _current_level.id, "score": _score,
	})
	if _jasmine != null:
		_jasmine.set_state(&"crying")

func _on_next_level_pressed() -> void:
	var next_id := GameData.levels.next_level_id(_current_level.id)
	if next_id != -1 and Progress.is_unlocked(next_id):
		_hud.hide_end_panel()
		await _play_pre_level_story(next_id)
		_start_level(next_id)
	else:
		await _go_to_map()

func _on_retry_pressed() -> void:
	_start_level(_current_level.id)

func _on_pause_pressed() -> void:
	if _board != null:
		_board.disarm_booster()
		_board.set_input_locked(true)
	_armed_booster = &""
	Music.set_state(&"tension")
	_hud.show_pause_panel(true)

func _on_resume_pressed() -> void:
	if _board != null:
		_board.set_input_locked(false)
	Music.set_state(_compute_music_state(0))

## Booster tapped in the tray. Targeted boosters (Bomb / Lightning / Freeze
## / Rainbow) ARM — the player then taps a jewel and the charge is spent on
## `booster_committed`. Instant boosters (Shuffle / +Moves) fire now.
func _on_booster_pressed(booster_id: StringName) -> void:
	if _board == null:
		return
	# Toggle off if this one is already armed.
	if _board.is_booster_armed() and _armed_booster == booster_id:
		_board.disarm_booster()
		_armed_booster = &""
		return
	# Tapping a booster you own zero of used to be a silent dead end — now it
	# opens the shop straight to that booster's buy-confirm dialog, so
	# "I want this one" is a single tap instead of tap-tray-then-find-it.
	if Boosters.get_count(booster_id) <= 0:
		_on_shop_pressed(booster_id)
		return

	var def: Dictionary = GameData.boosters.get(booster_id, {})
	if bool(def.get("instant", false)):
		if not Boosters.use(booster_id):
			return
		_refresh_booster_counts()
		_hud.flash_booster(booster_id)
		GameEvents.publish_type(EngineEvent.BOOSTER_USED, {"booster_id": booster_id, "targeted": false})
		match String(def.get("effect", "")):
			"shuffle_board":
				_board.request_shuffle()
			"add_moves":
				_moves_left += int(def.get("value", 5))
				_hud.set_moves(_moves_left)
				_publish_session_state()
		return

	# Targeted: arm it.
	_armed_booster = booster_id
	_board.arm_booster(booster_id, StringName(String(def.get("power", booster_id))))
	_hud.set_booster_armed(booster_id)

func _on_booster_committed(booster_id: StringName) -> void:
	Boosters.use(booster_id)
	_armed_booster = &""
	_refresh_booster_counts()
	_hud.set_booster_armed(&"")
	_hud.flash_booster(booster_id)
	GameEvents.publish_type(EngineEvent.BOOSTER_USED, {"booster_id": booster_id, "targeted": true})
	if _jamie_rig != null:
		_jamie_rig.play(_rig_action_for_booster(booster_id))

## Booster id -> the Jamie attack it reads as (Bomb -> Jamie detonates a
## bomb, Rainbow -> a mega blast, ...). Its board effect still resolves
## through ChainResolver / CombatDirector exactly as before.
func _rig_action_for_booster(booster_id: StringName) -> StringName:
	match String(booster_id):
		"bomb": return &"attack_bomb"
		"lightning": return &"attack_lightning"
		"freeze": return &"attack_freeze"
		"rainbow": return &"attack_rainbow"
	return &"attack_blast"
