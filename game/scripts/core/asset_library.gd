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
	var path: String = _PATHS.get(id, _OPTIONAL.get(id, ""))
	if path != "" and ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			t = res
	_cache[id] = t
	return t

static func has(id: StringName) -> bool:
	return tex(id) != null

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
	var a := audit()
	if a["missing"].is_empty():
		print("[Assets] %d/%d textures loaded" % [a["present"].size(), a["total"]])
	else:
		push_warning("[Assets] missing %d textures: %s" % [a["missing"].size(), a["missing"]])
