class_name EnemyModel
extends RefCounted
## Data-driven enemy roster for the "Jamie, Jasmine & Jinn" campaign
## (data/enemies.json). Pure accessors + AtlasTexture slices of the labelled
## 10-enemy row on assets/story/enemies_and_bosses.png (source PNG untouched).
## Adds NO save state — boss results still flow through ProgressService /
## Economy / Boosters.

const BOSS_EVERY := 10

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}
static var _atlas_cache: Dictionary = {}

static func _ensure() -> void:
	if not _data.is_empty():
		return
	_data = JsonLoader.load_json("res://data/enemies.json")
	for e in _data.get("enemies", []):
		_by_id[String(e["id"])] = e

static func enemy_def(id: StringName) -> Dictionary:
	_ensure()
	return _by_id.get(String(id), {})

static func all_enemy_ids() -> Array:
	_ensure()
	var out: Array = []
	for e in _data.get("enemies", []):
		out.append(StringName(String(e["id"])))
	return out

static func _island_entry(island_idx: int) -> Dictionary:
	_ensure()
	for isl in _data.get("islands", []):
		if int(isl.get("index", -1)) == island_idx:
			return isl
	return {}

static func roster_for_island(island_idx: int) -> Array:
	var out: Array = []
	for id in _island_entry(island_idx).get("roster", []):
		out.append(StringName(String(id)))
	return out

## True on every 10th campaign stage.
static func is_boss_stage(level_id: int) -> bool:
	return level_id > 0 and level_id % BOSS_EVERY == 0

## The boss id for a boss stage — an enemy id, or &"jinn" for stage 50.
## &"" when `level_id` is not a boss stage.
static func boss_for_stage(level_id: int) -> StringName:
	if not is_boss_stage(level_id):
		return &""
	var island_idx := (level_id - 1) / BOSS_EVERY
	return StringName(String(_island_entry(island_idx).get("boss", "")))

## Which enemy "guards" a normal stage — deterministic pick from the
## island's roster so a stage always shows the same foe.
static func enemy_for_stage(level_id: int) -> StringName:
	if is_boss_stage(level_id):
		return boss_for_stage(level_id)
	var island_idx := (level_id - 1) / BOSS_EVERY
	var roster := roster_for_island(island_idx)
	if roster.is_empty():
		return &""
	return roster[(level_id - 1) % roster.size()]

static func base_hp(tier: StringName) -> int:
	_ensure()
	return int(_data.get("base_hp", {}).get(String(tier), 3))

## Boss HP for a stage — base HP for the boss's tier, scaled up a little by
## which island it is so later chapters hit harder.
static func boss_hp(level_id: int) -> int:
	var bid := boss_for_stage(level_id)
	if bid == &"":
		return 0
	if bid == &"jinn":
		return base_hp(&"final_boss")
	var tier := StringName(String(enemy_def(bid).get("tier", "mini_boss")))
	var island_idx := (level_id - 1) / BOSS_EVERY
	return base_hp(tier) + island_idx * 3

## AtlasTexture for a labelled enemy on the 10-wide top row of the enemy
## sheet. null for &"jinn" (use Cast.portrait) or a missing sheet.
static func enemy_face(id: StringName) -> Texture2D:
	if id == &"jinn":
		return Cast.portrait(Cast.WHO_JINN)
	_ensure()
	var def := enemy_def(id)
	if def.is_empty():
		return null
	var cell := int(def.get("cell", 0))
	var key := "en_%d" % cell
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var sheet := AssetLibrary.tex(&"story_enemies")
	var result: Texture2D = null
	if sheet != null:
		var w := float(sheet.get_width())
		var h := float(sheet.get_height())
		var cw := w / 10.0
		var at := AtlasTexture.new()
		at.atlas = sheet
		# the labelled row sits just under the title; its art band is roughly
		# y 6%..26% of the sheet.
		at.region = Rect2(cell * cw + cw * 0.06, h * 0.055, cw * 0.88, h * 0.205)
		at.filter_clip = true
		result = at
	_atlas_cache[key] = result
	return result
