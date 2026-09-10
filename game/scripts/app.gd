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
var _islands: MainIslandScreen          # PLAY -> 10-world selection (over SEA CLIP)
var _worldmap: InternalLevelMap         # one world's infinite zig-zag level map
var _sea_clip: SeaClipBackground        # the single shared fixed ocean video
var _active_world_id: StringName = &""  # island whose map launched the level
var _active_local_level: int = 1        # world-local level number being played
# Arena/combat villain context for the CURRENT level — resolved in
# _start_level() from (_active_world_id, _active_local_level), NOT from the
# cycled authored level id. -1 island index = flat authored-campaign pick
# (the _debug_start_authored_level path).
var _arena_island_index: int = -1
var _arena_is_finale: bool = false
var _arena_is_first: bool = false
var _menu: MainMenu
var _splash: SplashScreen
var _studio_splash: StudioSplash        # Rectangle Studio branding — first screen
var _warm_done := false                 # background game warm-up complete
var _headless := DisplayServer.get_name() == "headless"

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
## Phase D — set when a booster (targeted themed hit, or an instant Shuffle /
## +Moves gesture) has already driven Jamie's rig for the move in flight, so
## `_on_jamie_attack` doesn't chain a redundant generic sword swing behind
## it. Cleared at the top of every real match in `_on_move_resolved`.
var _booster_anim_this_move := false
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

	# --- The Rectangle Studio branding splash is the VERY FIRST Godot frame,
	# built + playing before the heavy game build below. This is what
	# collapses the OS launch screen (Android 12+ shows the app icon on its
	# window background — platform-controlled, can't be removed without a
	# gradle build) to its minimum: it dismisses the instant Godot draws this
	# frame, instead of the crown-on-#fbfdff sitting there for the whole
	# ~1-2s build. The rest of the game is built ONE frame later, under the
	# splash. There is NO Godot-created logo/white screen — boot_splash has
	# show_image=false and its bg_color is the splash's own near-white.
	var studio_canvas := CanvasLayer.new()
	studio_canvas.layer = 110
	add_child(studio_canvas)
	_studio_splash = StudioSplash.new()
	studio_canvas.add_child(_studio_splash)
	_studio_splash.finished.connect(_on_studio_splash_finished)
	_studio_splash.play()
	print("[startup] app._ready at %.0f ms since boot -> branding splash on screen" % (Time.get_ticks_msec()))

	# The poster/loading screen NODE is cheap — create it now so it's ready the
	# instant the branding animation ends. It stays idle+hidden until begin().
	# Its heavy siblings (HUD/board/menu/islands/...) are built LATER, UNDER
	# this poster (which is exactly what a loading screen is for), so the
	# branding animation plays with nothing competing for the main thread.
	var splash_canvas := CanvasLayer.new()
	splash_canvas.layer = 100
	add_child(splash_canvas)
	_splash = SplashScreen.new()
	# The poster holds visible until BOTH background warm-up AND the game build
	# are done; if both were already done at hand-off it just runs a short beat.
	_splash.loading_ready = func() -> bool: return _warm_done and _hud != null
	splash_canvas.add_child(_splash)
	_splash.finished.connect(_on_splash_finished)

	# Headless (tests/smokes): no branding video to protect and the smokes
	# expect a ready app, so build synchronously right now. On-device the
	# heavy build is deferred to _on_studio_splash_finished (under the poster)
	# so the branding animation plays uninterrupted.
	if _headless:
		await _build_game()

	# Lightweight background warm-up (data + key textures) begins IMMEDIATELY,
	# in parallel with the branding animation — never blocks it.
	_warm_up_game()

## One build chunk boundary: yields a frame on-device (keeps the branding
## animation responsive) but is a no-op when headless.
func _build_yield() -> void:
	if not _headless:
		await get_tree().process_frame

## Builds the full game (screens, board, characters, wiring) one frame AFTER
## the Rectangle Studio splash is already on screen, YIELDING between groups so
## the branding animation stays responsive throughout instead of freezing on a
## single long build hitch.
func _build_game() -> void:
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
	_hud.double_coins_requested.connect(_on_double_coins_requested)
	await _build_yield()

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
	await _build_yield()

	# --- Island navigation (2026-09-08): PLAY -> MainIslandScreen (10 worlds
	# over the shared SEA CLIP video) -> InternalLevelMap (infinite recycled
	# zig-zag level map) -> existing gameplay. The video lives on its own
	# layer BEHIND both island screens so it stays fixed while they scroll and
	# is never duplicated between them. ---
	var sea_canvas := CanvasLayer.new()
	sea_canvas.layer = 8
	add_child(sea_canvas)
	_sea_clip = SeaClipBackground.new()
	_sea_clip.visible = false
	sea_canvas.add_child(_sea_clip)

	var map_canvas := CanvasLayer.new()
	map_canvas.layer = 10
	add_child(map_canvas)
	_islands = MainIslandScreen.new()
	map_canvas.add_child(_islands)
	_islands.world_selected.connect(_on_world_selected)
	_islands.back_pressed.connect(_on_islands_back)
	_worldmap = InternalLevelMap.new()
	map_canvas.add_child(_worldmap)
	_worldmap.level_selected.connect(_on_level_selected_from_map)
	_worldmap.back_pressed.connect(_on_worldmap_back)
	await _build_yield()

	var menu_canvas := CanvasLayer.new()
	menu_canvas.layer = 20
	add_child(menu_canvas)
	_menu = MainMenu.new()
	menu_canvas.add_child(_menu)
	_menu.play_pressed.connect(_on_menu_play_pressed)
	_menu.daily_pressed.connect(_on_daily_pressed)
	_menu.inventory_pressed.connect(func(): _inventory.open())
	await _build_yield()

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
	await _build_yield()

	var story_canvas := CanvasLayer.new()
	story_canvas.layer = 90
	add_child(story_canvas)
	_story_scene = StoryScene.new()
	story_canvas.add_child(_story_scene)
	_intro_video = IntroVideoScreen.new()
	_intro_video.visible = false
	story_canvas.add_child(_intro_video)
	# (_splash / the poster/loading screen is created in _ready, before this
	# heavy build, so it can be shown the instant the branding animation ends.)

	_hud.visible = false
	_board_layer.visible = false
	_jasmine.visible = false
	_jamie_rig.visible = false
	_enemy_actor.visible = false
	_islands.visible = false
	_worldmap.visible = false
	_menu.visible = true
	_menu.modulate.a = 1.0

## GENTLE background preload that runs during the Rectangle Studio branding
## animation — ONE small texture per frame so it never janks the video.
## Deliberately does NOT touch the big island artwork: that is loaded when
## _build_game() creates MainIslandScreen (under the poster, where a hitch is
## expected). The poster's gate is `_warm_done AND _hud != null`, so both this
## and the heavy build must complete before the poster fades to the menu.
func _warm_up_game() -> void:
	var small: Array[StringName] = [
		&"env_floating_particles", &"brand_splash",           # menu + poster
		&"gem_red", &"gem_blue", &"gem_green", &"gem_yellow", &"gem_purple", &"gem_orange",
		&"power_bomb", &"power_lightning", &"power_freeze", &"power_rainbow",
	]
	for id in small:
		AssetLibrary.tex(id)
		await get_tree().process_frame
	WorldCatalog.board_texture()
	SeaClipBackground._video_available()
	_warm_done = true
	print("[startup] background warm-up complete")
	# menu music is started by _on_splash_finished, not during the branding beat

## The Rectangle Studio animation has played out -> hand off to the EXISTING
## poster/loading screen. No black/white frame: StudioSplash's ground and the
## poster's ground are both painted, and we cross with a short fade.
func _on_studio_splash_finished() -> void:
	# Branding animation has played out (uninterrupted — nothing was competing
	# for the main thread). Hand off to the EXISTING poster/loading screen and
	# build the heavy game UNDER it. The poster's loading_ready gate
	# (warm_done AND _hud built) keeps it up until the game is actually ready,
	# then it fades to the menu on its own.
	if _warm_done and _hud != null:
		# The game is already fully built + warmed (fast device / headless) —
		# the poster/loading screen is NOT needed. Straight to the menu, no
		# unnecessary loading delay.
		print("[startup] branding done, game already ready -> menu (poster skipped)")
		await _fade_out(_studio_splash, 0.25)
		_on_splash_finished()
		return
	# Show the EXISTING poster/loading screen and build the heavy game UNDER
	# it (that is what a loading screen is for). Its loading_ready gate
	# (warm_done AND _hud built) keeps it up until the game is ready, then it
	# fades to the menu on its own.
	print("[startup] branding done -> poster/loading (building game under it)")
	_splash.begin()
	await _fade_out(_studio_splash, 0.3)
	if _hud == null:
		await _build_game()
		print("[startup] game built at %.0f ms since boot (under poster)" % Time.get_ticks_msec())

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
			vp.x - 12.0, floor_y, enemy_h,
			_arena_island_index, _arena_is_finale, _arena_is_first)

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
	print("[startup] poster/loading done -> menu")
	Music.play_ambient(&"music_menu_theme")

func _on_menu_play_pressed() -> void:
	_menu.refresh()
	await _fade_out(_menu, TRANSITION_DURATION)
	_sea_clip.visible = true
	_sea_clip.ensure_playing()
	_islands.refresh()
	await _fade_in(_islands, TRANSITION_DURATION)

## MainIslandScreen -> a world's internal level map (SEA CLIP keeps running).
func _on_world_selected(world_id: StringName) -> void:
	_active_world_id = world_id
	_sea_clip.ensure_playing()
	_worldmap.open(world_id)
	await _fade_out(_islands, TRANSITION_DURATION)
	await _fade_in(_worldmap, TRANSITION_DURATION)

## Back from a world's internal map -> the 10-world selection screen.
func _on_worldmap_back() -> void:
	_sea_clip.ensure_playing()
	_islands.refresh()
	await _fade_out(_worldmap, TRANSITION_DURATION)
	await _fade_in(_islands, TRANSITION_DURATION)

## Back from the world selection screen -> the main menu (stop the video).
func _on_islands_back() -> void:
	await _fade_out(_islands, TRANSITION_DURATION)
	_sea_clip.visible = false
	_sea_clip.pause()
	_menu.refresh()
	await _fade_in(_menu, TRANSITION_DURATION)
	Music.play_ambient(&"music_menu_theme")

## Legacy hook kept for the in-level map buttons (see _go_to_map).
func _on_home_pressed() -> void:
	await _on_islands_back()

func _on_daily_pressed() -> void:
	_daily.refresh()
	await _fade_in(_daily, TRANSITION_DURATION)
	_daily.play_entrance()

func _on_daily_closed() -> void:
	await _fade_out(_daily, TRANSITION_DURATION)
	_menu.refresh()

func _on_map_pressed() -> void:
	_maybe_transition_ad("to_map")
	await _go_to_map()

func _on_level_selected_from_map(world_id: StringName, local_level: int) -> void:
	await _go_to_level(world_id, local_level)

## Return from an in-level "Quit to Map" / no-next-level to the internal level
## map of the ISLAND that was being played (falls back to world 1). The SEA
## CLIP video resumes behind it.
func _go_to_map() -> void:
	Music.stop_ambient()
	var wid := _active_world_id
	if wid == &"":
		wid = WorldCatalog.world_id_at(0)
	_active_world_id = wid
	await _fade_out_game(TRANSITION_DURATION)
	_sea_clip.visible = true
	_sea_clip.ensure_playing()
	_worldmap.open(wid)
	await _fade_in(_worldmap, TRANSITION_DURATION)
	Music.play_ambient(&"music_menu_theme")

## Enter a world-local level. `(world_id, local_level)` is the progression
## identity; `WorldCatalog.authored_level_id` resolves which authored
## LevelConfig actually supplies the board/objectives/etc. for this slot.
func _go_to_level(world_id: StringName, local_level: int) -> void:
	_active_world_id = world_id
	_active_local_level = local_level
	var authored_id := WorldCatalog.authored_level_id(world_id, local_level)
	if _worldmap.visible:
		await _fade_out(_worldmap, TRANSITION_DURATION)
	if _islands.visible:
		await _fade_out(_islands, TRANSITION_DURATION)
	_sea_clip.visible = false
	_sea_clip.pause()
	Music.stop_ambient()
	await _play_pre_level_story(authored_id)
	_start_level(authored_id)
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

## `use_island_context` true (the normal island-map flow) resolves the arena
## villain / chapter-finale from the REAL progression position
## (_active_world_id, _active_local_level). false (the _debug_start_authored_
## level path) keeps the flat authored-campaign pick so the campaign-id
## smokes/tests stay meaningful.
func _start_level(level_id: int, use_island_context: bool = true) -> void:
	_current_level = GameData.levels.get_level(level_id)
	if _current_level == null:
		return

	if use_island_context and _active_world_id != &"":
		_arena_island_index = int(WorldCatalog.world(_active_world_id).get("order", 1)) - 1
		_arena_is_finale = _active_local_level >= IslandProgress.LEVELS_PER_ISLAND
		_arena_is_first = _active_local_level == 1
	else:
		_arena_island_index = -1
		_arena_is_finale = false
		_arena_is_first = false

	_score = 0
	_moves_left = _current_level.move_limit
	_combo.reset()
	_fever.reset()
	_was_near_fail = false
	_was_fever = false
	_armed_booster = &""
	_backdrop.set_accent_target(VisualTheme.ACCENT, 0.2)
	_backdrop.set_scene_for_level(_current_level.id, _current_level.env)
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
	# The HUD LEVEL badge shows the world-local level (Island 1 Level 47), not
	# the authored campaign id that happens to supply this slot's board.
	_hud.set_level_number(_active_local_level)
	_hud.set_moves(_moves_left)
	_hud.set_coins(Economy.coins)
	_hud.set_score(_score)
	_hud.set_objectives(_objectives, _current_level)
	_hud.set_fever(_fever.meter, GameData.fever_config.meter_max, _fever.is_active())
	_refresh_booster_counts()

	# --- character combat: Jamie powers drive the arena on every stage. The
	# chapter villain is presentation only (2026-09-07: no health bar, no
	# boss-HP win gate). `is_boss` = "chapter finale" (every 10th stage). ---
	_level_ended = false
	_combat = CombatDirector.new(_current_level.id, _arena_island_index, _arena_is_finale)
	_combat.meters_changed.connect(_hud.set_power_meters)
	_combat.power_fired.connect(_on_power_fired)
	_combat.jamie_attack.connect(_on_jamie_attack)
	_hud.set_power_meters(_combat.powers.meter)
	_hud.end_boss()   # the HUD boss HP bar is never shown any more

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
	var _obj_before: Array = _objectives.progress.duplicate()
	_objectives.apply_move(result.colors_cleared, _score, result.powers_created, result.obstacles_broken, result.specials_delivered.size())
	# One soft "goal advanced" chime per move — a non-score objective that
	# ticked forward but isn't finished yet. (Score creep alone doesn't ping.)
	if not _objectives.is_complete():
		for i in _objectives.progress.size():
			if _objectives.progress[i] > _obj_before[i] \
					and String(_objectives.objectives[i].get("type", "")) != "reach_score":
				Audio.play(&"objective_progress", clampf(float(_objectives.progress[i]) / maxf(float(_objectives.target_for(i)), 1.0), 0.0, 1.0))
				break
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

	# --- turn this move into Jamie attack energy + power fires (arena
	# presentation only; the win is decided purely by objectives). ---
	_power_fired_this_move = false
	if _combat != null:
		_combat.feed_move(result, result.chain_depth, result.cleared_cells.size(), counts_as_move, _moves_left)
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
			_win_finale_stage()
		else:
			_on_level_won()
	elif _moves_left <= 0:
		_offer_more_moves_or_lose()

## Chapter-finale stage (every 10th) cleared: the villain is driven off with
## the full defeat presentation (screen flourish, arena defeat pose, Jasmine
## rescued/victory), then the normal win flow runs. No HP was ever involved —
## completing the stage's objectives is the whole victory condition.
func _win_finale_stage() -> void:
	if _level_ended:
		return
	_hud.boss_defeat_anim()
	Audio.play(&"boss_impact", 1.0)
	if _board != null:
		ScreenShake.apply(_board, 18.0, 0.5)
	if _enemy_actor != null:
		_enemy_actor.play_defeat()
	if _jamie_rig != null:
		_jamie_rig.play(&"victory")
	if _jasmine != null:
		_jasmine.set_state(&"rescued" if (_combat != null and _combat.is_final_boss()) else &"victory")
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
	_booster_anim_this_move = false
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
	if _jamie_rig != null and not _power_fired_this_move and not _booster_anim_this_move \
			and kind == &"basic" and damage >= 3:
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

## Jamie's rig reports a landed hit — drive the villain flinch from it. Pure
## presentation; no HP is tracked any more.
func _on_jamie_enemy_reaction(kind: StringName, _pos: Vector2) -> void:
	if kind == &"none":
		return
	if _enemy_actor != null:
		_enemy_actor.play_hit(kind)

func _on_level_won() -> void:
	if _level_ended:
		return
	_level_ended = true
	# Progression identity is (island, world-local level) — recorded in
	# IslandProgress. Completing island i level N unlocks only island i level
	# N+1; completing island i level 100 unlocks island i+1. The campaign
	# `Progress` autoload is still dual-written for the authored level so the
	# older story/backdrop views stay coherent, but the island map never reads
	# it.
	var first_clear := not IslandProgress.is_level_completed(_active_world_id, _active_local_level)
	Economy.grant(_current_level.reward_coins)
	# Per-level score thresholds are the primary star rule; StarRating falls
	# back to move-efficiency when a level defines no `star_scores`.
	var stars := StarRating.stars_for_score(_score, _current_level.star_scores, _moves_left, _current_level.move_limit)
	IslandProgress.record_completion(_active_world_id, _active_local_level, stars, _score)
	Progress.record_completion(_current_level.id, stars, _score)
	var has_next := _active_local_level < IslandProgress.LEVELS_PER_ISLAND
	GameEvents.publish_type(EngineEvent.LEVEL_COMPLETED, {
		"level_id": _current_level.id, "world_id": String(_active_world_id),
		"local_level": _active_local_level, "score": _score, "stars": stars,
	})
	Music.fade_out_and_stop(0.7)
	Music.stop_ambient(0.7)
	Audio.play(&"level_complete")
	if _combat != null and _combat.is_boss:
		Audio.play(&"boss_impact", 1.0)
	# Clearing an island's final level (100) unlocks the next island — call it
	# out (IslandProgress has already emitted island_unlocked).
	if _active_local_level >= IslandProgress.LEVELS_PER_ISLAND:
		UiKit.show_toast(_hud, "ISLAND COMPLETE — %s" %
			String(WorldCatalog.world(_active_world_id).get("display_name", "")).to_upper(), VisualTheme.STAR)
	Haptics.strong(60)
	if _board != null:
		_board.set_fever(false)
		_board.play_win_flourish()
	_backdrop.set_accent_target(VisualTheme.ACCENT)
	# Finale wins already set a more specific state (rescued / victory) in
	# _win_finale_stage before calling this — only a plain stage clear needs
	# it here.
	if _jasmine != null and (_combat == null or not _combat.is_boss):
		_jasmine.set_state(&"cheering")

	# Non-finale stage clear: dismiss the chapter's minor villain so beating
	# the level visibly drives it off. Finale stages already played
	# play_defeat() in _win_finale_stage; a retreat here would double it.
	if _enemy_actor != null and (_combat == null or not _combat.is_boss):
		_enemy_actor.play_retreat()

	# Boss stage (every 10th) — grant the boss's equipment drop + a shard,
	# then let the story beat (stage_complete:N) carry the chapter transition.
	if first_clear and _combat != null and _combat.is_boss:
		var new_equip := Inventory.grant_boss_reward(_current_level.id)
		if new_equip != "":
			UiKit.show_toast(_hud, "NEW EQUIPMENT — %s" % new_equip.to_upper(), VisualTheme.GEM)

	# Every 5th world-local level is a "chest" milestone — the first time it's
	# cleared, open a milestone chest before the normal summary.
	if first_clear and _active_local_level % 5 == 0:
		await _present_milestone_chest()

	# Story beat that belongs AFTER a stage (boss defeat, chapter close,
	# finale) — plays once, before the win summary.
	await _play_beat(Story.beat_for(Story.stage_complete_trigger(_current_level.id)))

	_hud.show_win_panel(_score, _current_level.reward_coins, has_next, stars)

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

## "Next" from the win panel advances to the NEXT LEVEL OF THE SAME ISLAND.
## After level 100 (or if the next level somehow isn't unlocked) it drops back
## to the island map — where the newly-unlocked next island is now visible.
## Interstitial at a genuine level->level / level->map transition ONLY. Never
## called during active gameplay. AdsService self-gates on the frequency
## rules (cooldown, per-session cap, tutorial guard, no back-to-back), so a
## no-op is the common case and a real ad only ever plays over the black
## transition, not the board.
func _maybe_transition_ad(placement: String) -> void:
	if not _level_ended:
		return
	Ads.maybe_show_interstitial(placement, {"levels_cleared": _total_levels_cleared()})

func _total_levels_cleared() -> int:
	var n := 0
	for i in WorldCatalog.count():
		n += IslandProgress.completed_count(WorldCatalog.world_id_at(i))
	return n

## Win-panel "▶ DOUBLE COINS" — rewarded ad. The extra coins are granted
## ONLY when the ad's single terminal result says earned=true; a failed /
## dismissed / unavailable ad grants nothing and the base reward stands.
var _double_coins_base := 0

func _on_double_coins_requested() -> void:
	if _current_level == null or not Ads.available:
		return
	if _current_level.reward_coins <= 0:
		return
	_double_coins_base = _current_level.reward_coins
	if not Ads.rewarded_result.is_connected(_on_double_coins_ad_result):
		Ads.rewarded_result.connect(_on_double_coins_ad_result)
	Ads.show_rewarded("double_win_coins")

func _on_double_coins_ad_result(placement: String, earned: bool) -> void:
	if placement != "double_win_coins" or _double_coins_base <= 0:
		return
	Ads.rewarded_result.disconnect(_on_double_coins_ad_result)
	var base_coins := _double_coins_base
	_double_coins_base = 0
	if earned:
		Economy.grant(base_coins)
		_hud.set_coins(Economy.coins)
		_hud.mark_win_coins_doubled()
		Audio.play(&"power_up", 0.8)

func _on_next_level_pressed() -> void:
	_maybe_transition_ad("next_level")
	var next_local := _active_local_level + 1
	if next_local <= IslandProgress.LEVELS_PER_ISLAND \
			and IslandProgress.is_level_unlocked(_active_world_id, next_local):
		_hud.hide_end_panel()
		_active_local_level = next_local
		var authored_id := WorldCatalog.authored_level_id(_active_world_id, next_local)
		await _play_pre_level_story(authored_id)
		_start_level(authored_id)
	else:
		await _go_to_map()

func _on_retry_pressed() -> void:
	_maybe_transition_ad("retry")
	_start_level(WorldCatalog.authored_level_id(_active_world_id, _active_local_level))

## Test / dev helper: start an authored campaign level directly, wiring the
## island slot to that level's natural (island, world-local) position so the
## win flow records progression correctly. Bypasses the island-map UI.
func _debug_start_authored_level(level_id: int) -> void:
	var isl := IslandModel.island_index_for_level(level_id)
	var pool := IslandModel.level_ids_for_island(isl)
	var pos := pool.find(level_id)
	_active_world_id = WorldCatalog.world_id_at(clampi(isl, 0, WorldCatalog.count() - 1))
	_active_local_level = (pos + 1) if pos >= 0 else 1
	# flat authored-campaign villain semantics (is_boss_stage(level_id)) — this
	# entry point deliberately plays the 1..50 campaign directly.
	_start_level(level_id, false)
	_hud.set_level_number(_active_local_level)

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
				# Phase D — the Shuffle booster now reads as Jamie doing
				# something: a battlefield sweep, not a silent board reshuffle.
				if _jamie_rig != null and not _jamie_rig.is_busy():
					_booster_anim_this_move = true
					_jamie_rig.play(&"gesture_shuffle")
			"add_moves":
				_moves_left += int(def.get("value", 5))
				_hud.set_moves(_moves_left)
				_publish_session_state()
				# Phase D — +Moves is a hopeful beat: Jamie braces for another
				# push and Jasmine takes heart.
				if _jamie_rig != null and not _jamie_rig.is_busy():
					_booster_anim_this_move = true
					_jamie_rig.play(&"brace")
				if _jasmine != null:
					_jasmine.set_state(&"cheering")
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
		_booster_anim_this_move = true
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
