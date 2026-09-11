class_name AssetLibrary
extends Node
## Central texture registry for the prepared Color Clash art set (assets 1-74).
##
## The API is STATIC (`AssetLibrary.tex(id)`, `.gem(id)`, `.power(id)`, ...) with
## a process-lifetime cache, so any renderer can pull sprites without depending
## on autoload initialisation order. A missing texture returns null and the
## caller keeps its existing procedural draw, so an asset gap degrades
## gracefully instead of hard-failing.
##
## Also registered as the `Assets` autoload purely so a one-line coverage report
## prints at boot (see `_ready`).

const _PATHS := {
	# --- 1-6  main game gems -------------------------------------------------
	&"gem_red": "res://assets/gems/red.png",
	&"gem_blue": "res://assets/gems/blue.png",
	&"gem_green": "res://assets/gems/green.png",
	&"gem_yellow": "res://assets/gems/yellow.png",
	&"gem_purple": "res://assets/gems/purple.png",
	&"gem_orange": "res://assets/gems/orange.png",

	# --- 7-12  power-up objects -------------------------------------------------
	&"power_bomb": "res://assets/powers/bomb.png",
	&"power_lightning": "res://assets/powers/lightning.png",
	&"power_freeze": "res://assets/powers/freeze.png",
	&"power_chain": "res://assets/powers/chain.png",
	&"power_rainbow": "res://assets/powers/rainbow.png",
	&"power_combo_core": "res://assets/powers/combo_core.png",

	# --- 13-18  obstacles -------------------------------------------------------
	&"obstacle_ice_block": "res://assets/obstacles/ice_block.png",
	&"obstacle_frozen_gem": "res://assets/obstacles/frozen_gem.png",
	&"obstacle_lock": "res://assets/obstacles/lock.png",
	&"obstacle_stone_block": "res://assets/obstacles/stone_block.png",
	&"obstacle_time_bomb": "res://assets/obstacles/time_bomb.png",
	&"obstacle_time_bomb_fuse": "res://assets/obstacles/time_bomb_fuse.png",

	# --- 19-30  vfx source assets --------------------------------------------
	&"vfx_explosion_core": "res://assets/vfx/explosion_core.png",
	&"vfx_shockwave_ring": "res://assets/vfx/shockwave_ring.png",
	&"vfx_lightning_arc": "res://assets/vfx/lightning_arc.png",
	&"vfx_fire_burst": "res://assets/vfx/fire_burst.png",
	&"vfx_ice_burst": "res://assets/vfx/ice_burst.png",
	&"vfx_energy_burst": "res://assets/vfx/energy_burst.png",
	&"vfx_rainbow_burst": "res://assets/vfx/rainbow_burst.png",
	&"vfx_chain_energy_burst": "res://assets/vfx/chain_energy_burst.png",
	&"vfx_crystal_shards": "res://assets/vfx/crystal_shards.png",
	&"vfx_debris_pieces": "res://assets/vfx/debris_pieces.png",
	&"vfx_glow_orb": "res://assets/vfx/glow_orb.png",
	&"vfx_energy_trail_head": "res://assets/vfx/energy_trail_head.png",

	# --- 31-39  rewards / economy -----------------------------------------------
	&"eco_gold_coin": "res://assets/economy/gold_coin.png",
	&"eco_coin_stack": "res://assets/economy/coin_stack.png",
	&"eco_reward_chest": "res://assets/economy/reward_chest.png",
	&"eco_premium_chest": "res://assets/economy/premium_chest.png",
	&"eco_booster_chest": "res://assets/economy/booster_chest.png",
	&"eco_star": "res://assets/economy/star.png",
	&"eco_trophy": "res://assets/economy/trophy.png",
	&"eco_reward_crystal": "res://assets/economy/reward_crystal.png",
	&"eco_coin_burst": "res://assets/economy/coin_burst.png",

	# --- 40-48  level map assets ----------------------------------------------
	&"map_level_node": "res://assets/map/level_node.png",
	&"map_completed_node": "res://assets/map/completed_node.png",
	&"map_current_node": "res://assets/map/current_node.png",
	&"map_locked_node": "res://assets/map/locked_node.png",
	&"map_star_123": "res://assets/map/star_123.png",
	&"map_milestone_chest": "res://assets/map/milestone_chest.png",
	&"map_gate": "res://assets/map/map_gate.png",
	&"map_portal": "res://assets/map/portal.png",
	&"map_destination_structure": "res://assets/map/destination_structure.png",

	# --- 49-57  ui elements --------------------------------------------------
	&"ui_coin_icon": "res://assets/ui/coin_icon.png",
	&"ui_booster_container": "res://assets/ui/booster_container.png",
	&"ui_power_energy_container": "res://assets/ui/power_energy_container.png",
	&"ui_fever_crystal": "res://assets/ui/fever_crystal.png",
	&"ui_fever_meter_frame": "res://assets/ui/fever_meter_frame.png",
	&"ui_setting_gear": "res://assets/ui/setting_gear.png",
	&"ui_play_button": "res://assets/ui/play_button.png",
	&"ui_level_badge": "res://assets/ui/level_badge.png",
	&"ui_crown_trophy": "res://assets/ui/crown_trophy.png",

	# --- 58-67  background world / environment (full-screen opaque scenes) ---
	&"env_main_background": "res://assets/env/main_background.png",
	&"env_floating_islands": "res://assets/env/floating_islands.png",
	&"env_crystal_formations": "res://assets/env/crystal_formations.png",
	&"env_energy_crystals": "res://assets/env/energy_crystals.png",
	&"env_floating_particles": "res://assets/env/floating_particles.png",
	&"env_large_structures": "res://assets/env/large_structures.png",
	&"env_clouds_mists": "res://assets/env/clouds_mists.png",
	&"env_aurora_energy_bands": "res://assets/env/aurora_energy_bands.png",
	&"env_map_landmarks": "res://assets/env/map_landmarks.png",
	&"env_world_landmark": "res://assets/env/world_landmark.png",

	# --- 68-74  celebration / level complete --------------------------------
	&"cel_victory_crown": "res://assets/celebration/victory_crown.png",
	&"cel_confetti_pieces": "res://assets/celebration/confetti_pieces.png",
	&"cel_star_burst": "res://assets/celebration/star_burst.png",
	&"cel_firework_burst": "res://assets/celebration/firework_burst.png",
	&"cel_treasure_explosion": "res://assets/celebration/treasure_explosion.png",
	&"cel_level_complete_portal": "res://assets/celebration/level_complete_portal.png",
	&"cel_fever_activation_emblem": "res://assets/celebration/fever_activation_emblem.png",
}

## Reserved paths for art the user will supply later (branding, character
## poses). NOT part of the 74-asset audit — `tex()` checks these after
## `_PATHS` and still returns null until the file exists, so every renderer
## keeps its code-drawn fallback. Drop the final PNG at the path and it is
## picked up with zero code change.
const _OPTIONAL := {
	&"brand_wordmark": "res://assets/branding/wordmark.png",
	&"brand_logo": "res://assets/branding/company_logo.png",
	&"brand_splash": "res://assets/branding/splash.png",
	&"char_idle": "res://assets/character/idle.png",
	&"char_wave": "res://assets/character/wave.png",
	&"char_cheer": "res://assets/character/cheer.png",
	&"char_hype": "res://assets/character/hype.png",
	&"char_point": "res://assets/character/point.png",
	&"char_power_up": "res://assets/character/power_up.png",
	&"char_worried": "res://assets/character/worried.png",
	&"char_victory": "res://assets/character/victory.png",
	&"char_sad": "res://assets/character/sad.png",
}

## Campaign island art (user-supplied, 2026-09-03). Three PNGs per island:
##   *_hero   — full island scene + name banner (gameplay backdrop / intro)
##   *_stages — 5x2 sheet of the 10 stage dioramas (sliced via AtlasTexture,
##              the source PNG is never modified — see IslandModel.stage_face)
##   *_map    — the assembled island map scene used as the map section bg
## These DO resolve to real files and ARE verified — by test_island_assets.gd,
## not the 74-asset test — so they live in their own registry.
const _ISLAND_ART := {
	&"island1_hero": "res://assets/islands/island1_sunlit_falls_hero.png",
	&"island1_stages": "res://assets/islands/island1_sunlit_falls_stages.png",
	&"island1_map": "res://assets/islands/island1_sunlit_falls_map.png",
	&"island2_hero": "res://assets/islands/island2_frosthaven_hero.png",
	&"island2_stages": "res://assets/islands/island2_frosthaven_stages.png",
	&"island2_map": "res://assets/islands/island2_frosthaven_map.png",
	&"island3_hero": "res://assets/islands/island3_volcania_hero.png",
	&"island3_stages": "res://assets/islands/island3_volcania_stages.png",
	&"island3_map": "res://assets/islands/island3_volcania_map.png",
	&"island4_hero": "res://assets/islands/island4_sandoria_hero.png",
	&"island4_stages": "res://assets/islands/island4_sandoria_stages.png",
	&"island4_map": "res://assets/islands/island4_sandoria_map.png",
	&"island5_hero": "res://assets/islands/island5_aurora_reach_hero.png",
	&"island5_stages": "res://assets/islands/island5_aurora_reach_stages.png",
	&"island5_map": "res://assets/islands/island5_aurora_reach_map.png",
}

## Story / cast art (user-supplied, "Jamie, Jasmine & Jinn" — 2026-09-03).
## Transparent character portraits + pose/enemy/scene atlases. Sliced via
## AtlasTexture in scripts/story/cast.gd + enemy_model.gd — source PNGs are
## never modified. Verified by test_story_assets.gd (own registry).
const _STORY_ART := {
	&"story_jamie_portrait": "res://assets/story/jamie_portrait.png",
	&"story_jasmine_portrait": "res://assets/story/jasmine_portrait.png",
	&"story_jinn_portrait": "res://assets/story/jinn_portrait.png",
	&"story_jasmine_poses": "res://assets/story/jasmine_poses_8.png",
	# Checkerboard-keyed copy of the same 4x2 pose grid (jasmine_poses_8.png
	# is RGB with the same baked-grey-checker bug as enemies_and_bosses.png —
	# see tools/keyed_sprites/key_jasmine_poses.py). Original untouched.
	&"story_jasmine_poses_keyed": "res://assets/story/jasmine_poses_8_keyed.png",
	&"story_cast_atlas": "res://assets/story/cast_atlas_transparent.png",
	&"story_scenes": "res://assets/story/story_scenes_transparent.png",
	&"story_enemies": "res://assets/story/enemies_and_bosses.png",
	# Checkerboard-keyed copy of the enemy row (tools/keyed_sprites/key_enemies.py):
	# the shipped enemies_and_bosses.png is RGB with a baked light-grey checker,
	# so the in-arena enemy actor slices this alpha version instead. Same art,
	# original PNG untouched.
	&"story_enemies_keyed": "res://assets/story/enemies_keyed.png",
	&"story_jamie_actions": "res://assets/story/jamie_actions_ref.png",
	&"story_jinn_actions": "res://assets/story/jinn_actions_ref.png",
	&"story_jasmine_expr": "res://assets/story/jasmine_expressions_ref.png",
	# Dedicated single-character art for 5 enemies (2026-09-05 polish pass),
	# replacing their shared-sheet slice — see enemy_model.gd::enemy_face()
	# and data/enemies.json's `art` field. Jinn keeps his own established
	# portrait above, untouched.
	&"story_villain_stone_golem": "res://assets/story/villains/stone_golem.png",
	&"story_villain_ice_wraith": "res://assets/story/villains/ice_wraith.png",
	&"story_villain_dark_knight": "res://assets/story/villains/dark_knight.png",
	&"story_villain_poison_beast": "res://assets/story/villains/poison_beast.png",
	&"story_villain_chaos_sorcerer": "res://assets/story/villains/chaos_sorcerer.png",
}

## User-supplied UI art sheets (2026-09-06 UI asset integration). The two
## PNGs are byte-identical copies of the artist's sheets and are never
## modified — `ui_slice(id)` returns an AtlasTexture over the sub-rect named
## in `data/ui_atlas.json` (source PNG untouched), `ui_texture(id)` returns a
## whole supplied button PNG, `ui_safe(id)` the frame content inset. Same
## graceful-null contract as `tex()`: a missing sheet/region returns null and
## the screen keeps its previous look.
const _UI_ATLAS_PATH := "res://data/ui_atlas.json"

static var _ui_atlas: Dictionary = {}
static var _ui_slice_cache: Dictionary = {}
static var _ui_sheet_cache: Dictionary = {}

static func _ui_atlas_data() -> Dictionary:
	if _ui_atlas.is_empty():
		_ui_atlas = JsonLoader.load_json(_UI_ATLAS_PATH)
	return _ui_atlas

static func _ui_sheet(sheet_id: String) -> Texture2D:
	if _ui_sheet_cache.has(sheet_id):
		return _ui_sheet_cache[sheet_id]
	var path: String = _ui_atlas_data().get("sheets", {}).get(sheet_id, "")
	var t: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			t = res
	_ui_sheet_cache[sheet_id] = t
	return t

## AtlasTexture for one named region of a supplied UI sheet, or null. Cached
## for the process lifetime. `filter_clip` is set so bilinear sampling can
## never pull a neighbouring element's pixels into the crop.
static func ui_slice(id: StringName) -> Texture2D:
	if _ui_slice_cache.has(id):
		return _ui_slice_cache[id]
	var r: Dictionary = _ui_atlas_data().get("regions", {}).get(String(id), {})
	var out: Texture2D = null
	if not r.is_empty():
		var sheet := _ui_sheet(String(r.get("sheet", "")))
		var rect: Array = r.get("rect", [])
		if sheet != null and rect.size() == 4:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(rect[0], rect[1], rect[2], rect[3])
			at.filter_clip = true
			out = at
	_ui_slice_cache[id] = out
	return out

## NinePatch patch margins [l, t, r, b] for a region that declares them
## (the stretchable slider tracks), else an empty array.
static func ui_nine(id: StringName) -> Array:
	return _ui_atlas_data().get("regions", {}).get(String(id), {}).get("nine", [])

## Whole supplied button PNG (btn_settings / btn_inventory / btn_daily_reward).
static func ui_texture(id: StringName) -> Texture2D:
	if _ui_slice_cache.has(id):
		return _ui_slice_cache[id]
	var path: String = _ui_atlas_data().get("textures", {}).get(String(id), "")
	var t: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			t = res
	_ui_slice_cache[id] = t
	return t

## Content-area inset for a frame region, as fractions of the DISPLAYED
## frame rect: {left, top, right, bottom}. Screens inset their content
## MarginContainer by these so nothing overlaps the decorative gold border.
## Falls back to a mild uniform inset when the region declares no `safe`.
static func ui_safe(id: StringName) -> Dictionary:
	var r: Dictionary = _ui_atlas_data().get("regions", {}).get(String(id), {})
	var rect: Array = r.get("rect", [])
	var safe: Array = r.get("safe", [])
	if rect.size() == 4 and safe.size() == 4 and float(rect[2]) > 0.0 and float(rect[3]) > 0.0:
		return {
			"left": float(safe[0]) / float(rect[2]),
			"top": float(safe[1]) / float(rect[3]),
			"right": float(safe[2]) / float(rect[2]),
			"bottom": float(safe[3]) / float(rect[3]),
		}
	return {"left": 0.09, "top": 0.06, "right": 0.09, "bottom": 0.06}

## The fraction of a frame slice's half-width that is transparent glow/AA
## outside the solid decorative border. AssetFramePanel over-sizes the frame
## by this so the *visible* gold border lands at the requested side margin
## (not the artwork's transparent bounding box). 0 when undeclared.
static func ui_bleed(id: StringName) -> float:
	return float(_ui_atlas_data().get("regions", {}).get(String(id), {}).get("bleed", 0.0))

## Aspect ratio (w / h) of a supplied region, or 1.0 if unknown.
static func ui_aspect(id: StringName) -> float:
	var rect: Array = _ui_atlas_data().get("regions", {}).get(String(id), {}).get("rect", [])
	if rect.size() == 4 and float(rect[3]) > 0.0:
		return float(rect[2]) / float(rect[3])
	return 1.0

## Real recorded music tracks (2026-09-05 polish pass) — the first sampled
## audio in the project; everything else is still synthesized at runtime
## (see music_director.gd). `music_gameplay_theme` (the louder, more
## rhythmically consistent of the 2 supplied tracks) is the continuous
## in-level background music, replacing the old sparse synth loop;
## `music_menu_theme` (the more dynamic/atmospheric one) plays on the main
## menu. `audio()` below loads these; `tex()`/_PATHS above stay texture-only.
const _AUDIO_TRACKS := {
	&"music_gameplay_theme": "res://assets/audio/gameplay_theme.mp3",
	&"music_menu_theme": "res://assets/audio/menu_theme.mp3",
}

## Ordered full-screen environment scenes cycled through the campaign so each
## band of levels reads as its own "world". Index by (level-1) / band size.
const ENV_WORLD_CYCLE: Array[StringName] = [
	&"env_main_background",
	&"env_floating_islands",
	&"env_energy_crystals",
	&"env_large_structures",
	&"env_clouds_mists",
	&"env_floating_particles",
]

static var _cache: Dictionary = {}

## Texture for a logical id, or null if the file is absent / failed to load.
static func tex(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var t: Texture2D = null
	var path: String = _PATHS.get(id, _ISLAND_ART.get(id, _STORY_ART.get(id, _OPTIONAL.get(id, ""))))
	if path != "" and ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			t = res
	_cache[id] = t
	return t

static func has(id: StringName) -> bool:
	return tex(id) != null

static var _audio_cache: Dictionary = {}

## AudioStream for a real recorded track id (_AUDIO_TRACKS), or null if
## absent — same graceful-degradation contract as tex().
static func audio(id: StringName) -> AudioStream:
	if _audio_cache.has(id):
		return _audio_cache[id]
	var s: AudioStream = null
	var path: String = _AUDIO_TRACKS.get(id, "")
	if path != "" and ResourceLoader.exists(path):
		var res := load(path)
		if res is AudioStream:
			s = res
	_audio_cache[id] = s
	return s

## Island art registry helpers — kw is one of "hero" | "stages" | "map".
static func island_art(one_based_island: int, kw: String) -> Texture2D:
	return tex(StringName("island%d_%s" % [one_based_island, kw]))

## {present:[], missing:[], total:int} over the 15 island-art ids.
static func island_art_audit() -> Dictionary:
	return _audit_over(_ISLAND_ART)

## {present:[], missing:[], total:int} over the story/cast art ids.
static func story_art_audit() -> Dictionary:
	return _audit_over(_STORY_ART)

static func _audit_over(reg: Dictionary) -> Dictionary:
	var present: Array[StringName] = []
	var missing: Array[StringName] = []
	for id in reg:
		if has(id):
			present.append(id)
		else:
			missing.append(id)
	return {"present": present, "missing": missing, "total": reg.size()}

## Convenience: gem texture for a colour id (&"red" -> gem_red).
static func gem(color_id: StringName) -> Texture2D:
	return tex(StringName("gem_" + String(color_id)))

## Convenience: power object texture for a power id (&"bomb" -> power_bomb).
static func power(power_id: StringName) -> Texture2D:
	return tex(StringName("power_" + String(power_id)))

## Full-screen scene for a 1-based campaign level id.
static func world_for_level(level_id: int, band: int = 10) -> Texture2D:
	return tex(ENV_WORLD_CYCLE[world_index_for_level(level_id, band)])

static func world_index_for_level(level_id: int, band: int = 10) -> int:
	return int(max(level_id - 1, 0) / max(band, 1)) % ENV_WORLD_CYCLE.size()

## Every id that resolves to a real texture / every id that does not. Used by
## the asset-presence test and a one-line boot log.
static func audit() -> Dictionary:
	var present: Array[StringName] = []
	var missing: Array[StringName] = []
	for id in _PATHS:
		if has(id):
			present.append(id)
		else:
			missing.append(id)
	return {"present": present, "missing": missing, "total": _PATHS.size()}

func _ready() -> void:
	# NB: the old boot-time 74-texture presence audit LOADED every texture —
	# several seconds of cold decode that stalled the Rectangle Studio splash.
	# It was a diagnostic only (test_assets.gd calls audit() directly), so it
	# is no longer run at startup. Textures load lazily on first tex() use.
	pass
